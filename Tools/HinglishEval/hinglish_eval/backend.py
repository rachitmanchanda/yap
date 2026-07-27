"""Standard-library client for the same Supabase functions used by the iOS app."""

from __future__ import annotations

import json
import mimetypes
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .models import PipelineResult


Transport = Callable[[urllib.request.Request, float], tuple[int, bytes]]


@dataclass(frozen=True)
class BackendConfiguration:
    base_url: str
    api_key: str
    access_token: str | None = None

    @classmethod
    def from_environment(cls, repository_root: Path) -> "BackendConfiguration":
        base_url = os.environ.get("YAP_SUPABASE_URL")
        api_key = os.environ.get("YAP_SUPABASE_KEY")
        configuration_file = repository_root / "Shared/Services/SupabaseConfiguration.swift"
        if (not base_url or not api_key) and configuration_file.exists():
            source = configuration_file.read_text(encoding="utf-8")
            base_url_match = re.search(r'projectURL\s*=\s*URL\(string:\s*"([^"]+)"', source)
            api_key_match = re.search(r'publishableKey\s*=\s*"([^"]+)"', source)
            base_url = base_url or (base_url_match.group(1) if base_url_match else None)
            api_key = api_key or (api_key_match.group(1) if api_key_match else None)
        if not base_url or not api_key:
            raise ValueError(
                "Set YAP_SUPABASE_URL and YAP_SUPABASE_KEY, or run from a YAP checkout "
                "containing Shared/Services/SupabaseConfiguration.swift."
            )
        return cls(base_url.rstrip("/"), api_key, os.environ.get("YAP_ACCESS_TOKEN"))


def _default_transport(request: urllib.request.Request, timeout: float) -> tuple[int, bytes]:
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.read()


class YAPBackendClient:
    def __init__(
        self,
        configuration: BackendConfiguration,
        *,
        transcription_timeout: float = 8.0,
        enhancement_timeout: float = 2.5,
        retries: int = 2,
        transport: Transport = _default_transport,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self.configuration = configuration
        self.transcription_timeout = transcription_timeout
        self.enhancement_timeout = enhancement_timeout
        self.retries = retries
        self.transport = transport
        self.sleep = sleep

    def run_pipeline(
        self, audio_file: Path, *, known_terms: list[str] | None = None
    ) -> PipelineResult:
        started = time.perf_counter()
        asr_started = time.perf_counter()
        transcript_payload = self.transcribe(audio_file, known_terms=known_terms or [])
        asr_ms = round((time.perf_counter() - asr_started) * 1000)
        raw_asr = str(transcript_payload.get("transcript", "")).strip()
        if not raw_asr:
            raise RuntimeError("transcription endpoint returned an empty transcript")

        enhancement_started = time.perf_counter()
        enhancement_error: str | None = None
        enhancement_payload: dict[str, Any] = {}
        try:
            enhancement_payload = self.enhance(raw_asr, known_terms=known_terms or [])
            final_text = str(enhancement_payload.get("text", "")).strip()
            if not final_text:
                raise RuntimeError("enhancement endpoint returned empty text")
        except RuntimeError as error:
            # The app treats enhancement as optional polish and inserts the usable raw transcript
            # when its 2.5-second budget or provider request fails.
            final_text = raw_asr
            enhancement_error = str(error)
        enhancement_ms = round((time.perf_counter() - enhancement_started) * 1000)
        return PipelineResult(
            raw_asr=raw_asr,
            final_text=final_text,
            asr_ms=asr_ms,
            enhancement_ms=enhancement_ms,
            total_ms=round((time.perf_counter() - started) * 1000),
            asr_provider=transcript_payload.get("provider"),
            enhancement_provider=enhancement_payload.get("provider"),
            enhancement_error=enhancement_error,
        )

    def transcribe(self, audio_file: Path, *, known_terms: list[str]) -> dict[str, Any]:
        boundary = f"YAP-HINGLISH-EVAL-{uuid.uuid4().hex}"
        fields = {
            "language_code": "unknown",
            "mode": "translit",
            "vocabulary": ",".join(known_terms),
        }
        chunks: list[bytes] = []
        for name, value in fields.items():
            chunks.append(
                (
                    f"--{boundary}\r\n"
                    f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                    f"{value}\r\n"
                ).encode()
            )
        content_type = mimetypes.guess_type(audio_file.name)[0] or "application/octet-stream"
        chunks.append(
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="file"; filename="{audio_file.name}"\r\n'
                f"Content-Type: {content_type}\r\n\r\n"
            ).encode()
        )
        chunks.append(audio_file.read_bytes())
        chunks.append(f"\r\n--{boundary}--\r\n".encode())
        return self._json_request(
            "transcribe",
            b"".join(chunks),
            f"multipart/form-data; boundary={boundary}",
            timeout=self.transcription_timeout,
        )

    def enhance(self, text: str, *, known_terms: list[str]) -> dict[str, Any]:
        body = json.dumps(
            {
                "operation": "enhance",
                "text": text,
                "mode": None,
                "knownTerms": known_terms,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode()
        return self._json_request(
            "rewrite",
            body,
            "application/json",
            timeout=self.enhancement_timeout,
            retries=0,
        )

    def _json_request(
        self,
        function_name: str,
        body: bytes,
        content_type: str,
        *,
        timeout: float,
        retries: int | None = None,
    ) -> dict[str, Any]:
        headers = {
            "apikey": self.configuration.api_key,
            "Authorization": f"Bearer {self.configuration.access_token or self.configuration.api_key}",
            "Content-Type": content_type,
            "Accept": "application/json",
            "User-Agent": "YAP-Hinglish-Eval/1.0",
        }
        request = urllib.request.Request(
            f"{self.configuration.base_url}/functions/v1/{function_name}",
            data=body,
            headers=headers,
            method="POST",
        )
        retry_limit = self.retries if retries is None else retries
        for attempt in range(retry_limit + 1):
            try:
                status, response_body = self.transport(request, timeout)
                if status >= 400:
                    raise urllib.error.HTTPError(
                        request.full_url, status, response_body.decode(errors="replace"), {}, None
                    )
                payload = json.loads(response_body)
                if not isinstance(payload, dict):
                    raise RuntimeError(f"{function_name} returned a non-object JSON response")
                return payload
            except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as error:
                status = getattr(error, "code", None)
                retryable = status is None or status == 429 or status >= 500
                if isinstance(error, urllib.error.HTTPError):
                    error.close()
                if attempt >= retry_limit or not retryable:
                    raise RuntimeError(f"{function_name} request failed: {error}") from error
                self.sleep(2**attempt)
            except json.JSONDecodeError as error:
                raise RuntimeError(f"{function_name} returned malformed JSON") from error
        raise AssertionError("retry loop should always return or raise")


def git_metadata(repository_root: Path) -> dict[str, Any]:
    def run(*arguments: str) -> str:
        return subprocess.run(
            ["git", *arguments],
            cwd=repository_root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    try:
        sha = run("rev-parse", "HEAD")
        dirty = bool(run("status", "--porcelain"))
    except (OSError, subprocess.CalledProcessError):
        return {"commit": None, "shortCommit": None, "dirty": None}
    return {"commit": sha, "shortCommit": sha[:12], "dirty": dirty}
