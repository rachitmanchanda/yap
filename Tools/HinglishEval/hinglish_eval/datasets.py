"""Licensed dataset preparation with deterministic sampling and checksum enforcement."""

from __future__ import annotations

import ast
import csv
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import tarfile
import urllib.request
from pathlib import Path
from typing import Any


ASCII_WORD = re.compile(r"[A-Za-z]+")
DEVANAGARI_WORD = re.compile(r"[\u0900-\u097f]+")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_verified(url: str, destination: Path, expected_sha256: str) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and sha256_file(destination) == expected_sha256:
        return destination
    partial = destination.with_suffix(destination.suffix + ".part")
    existing_bytes = partial.stat().st_size if partial.exists() else 0
    headers = {"User-Agent": "YAP-Hinglish-Eval/1.0"}
    if existing_bytes:
        headers["Range"] = f"bytes={existing_bytes}-"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=120) as response:
        status = getattr(response, "status", None)
        mode = "ab" if existing_bytes and status == 206 else "wb"
        with partial.open(mode) as output:
            shutil.copyfileobj(response, output)
    actual = sha256_file(partial)
    if actual != expected_sha256:
        partial.unlink(missing_ok=True)
        raise ValueError(
            f"checksum mismatch for {url}: expected {expected_sha256}, received {actual}"
        )
    partial.replace(destination)
    return destination


def safe_extract_tar(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with tarfile.open(archive) as package:
        for member in package.getmembers():
            target = (destination / member.name).resolve()
            if root not in target.parents and target != root:
                raise ValueError(f"unsafe archive path: {member.name}")
            if member.issym() or member.islnk():
                raise ValueError(f"archive links are not accepted: {member.name}")
            if not member.isfile() and not member.isdir():
                raise ValueError(f"unsupported archive member type: {member.name}")
        try:
            package.extractall(destination, filter="data")
        except TypeError:
            # Python 3.11 lacks the filter argument; every member was explicitly validated above.
            package.extractall(destination)


def english_ratio(text: str) -> float:
    english = len(ASCII_WORD.findall(text))
    hindi = len(DEVANAGARI_WORD.findall(text))
    return english / (english + hindi) if english + hindi else 0.0


def ratio_band(ratio: float) -> str:
    if ratio < 0.25:
        return "low"
    if ratio <= 0.60:
        return "medium"
    return "high"


def _read_transcript_maps(root: Path) -> dict[str, str]:
    mappings: dict[str, str] = {}
    for candidate in sorted(root.rglob("*")):
        if not candidate.is_file() or candidate.suffix.lower() not in {"", ".txt", ".text", ".trans"}:
            continue
        try:
            lines = candidate.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        parsed = 0
        local: dict[str, str] = {}
        for line in lines:
            parts = line.strip().split(maxsplit=1)
            if len(parts) == 2 and parts[0] and parts[1]:
                local[Path(parts[0]).stem] = parts[1].strip()
                parsed += 1
        if parsed >= 2:
            mappings.update(local)
    return mappings


def _read_keyed_lines(path: Path, minimum_parts: int) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split()
        if len(parts) >= minimum_parts:
            rows.append(parts)
    return rows


def _resolve_recording(root: Path, entry: str) -> Path | None:
    candidate = Path(entry)
    if candidate.is_file():
        return candidate
    relative = (root / candidate).resolve()
    if relative.is_file():
        return relative
    matches = sorted(root.rglob(candidate.name))
    return matches[0] if matches else None


def _extract_kaldi_segments(root: Path, clips_root: Path) -> list[tuple[Path, str]]:
    """Materialize utterance clips when a corpus uses Kaldi recording timestamps."""
    pairs: list[tuple[Path, str]] = []
    for segments_path in sorted(root.rglob("segments")):
        directory = segments_path.parent
        text_path = directory / "text"
        wav_scp_path = directory / "wav.scp"
        if not text_path.is_file() or not wav_scp_path.is_file():
            continue
        transcripts = {
            row[0]: " ".join(row[1:])
            for row in _read_keyed_lines(text_path, 2)
        }
        recordings = {
            row[0]: " ".join(row[1:])
            for row in _read_keyed_lines(wav_scp_path, 2)
        }
        for utterance, recording_id, start, end, *_ in _read_keyed_lines(segments_path, 4):
            transcript = transcripts.get(utterance)
            recording_entry = recordings.get(recording_id)
            if not transcript or not recording_entry:
                continue
            # Shell pipelines in wav.scp are intentionally unsupported: evaluation preparation
            # must never execute corpus-provided commands.
            if recording_entry.rstrip().endswith("|"):
                continue
            recording = _resolve_recording(root, recording_entry)
            if not recording:
                continue
            clip = clips_root / f"{utterance}.wav"
            if not clip.exists():
                clip.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(
                    [
                        "ffmpeg", "-nostdin", "-loglevel", "error", "-y",
                        "-ss", start, "-to", end, "-i", str(recording),
                        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(clip),
                    ],
                    check=True,
                )
            pairs.append((clip, transcript))
    return pairs


def prepare_mucs(
    extracted_root: Path,
    output_manifest: Path,
    *,
    sample_size: int,
    seed: int,
) -> int:
    transcripts = _read_transcript_maps(extracted_root)
    audio_extensions = {".wav", ".flac", ".mp3", ".m4a"}
    candidates: list[tuple[Path, str, str, float]] = []
    for audio in sorted(path for path in extracted_root.rglob("*") if path.suffix.lower() in audio_extensions):
        transcript = transcripts.get(audio.stem)
        if transcript:
            ratio = english_ratio(transcript)
            candidates.append((audio, transcript, ratio_band(ratio), ratio))
    if not candidates:
        clips_root = extracted_root.parent.parent / "clips" / "mucs-hindi-english-test"
        for audio, transcript in _extract_kaldi_segments(extracted_root, clips_root):
            ratio = english_ratio(transcript)
            candidates.append((audio, transcript, ratio_band(ratio), ratio))
    if not candidates:
        raise ValueError(
            "No MUCS audio/transcript pairs found. The archive layout may have changed; "
            "inspect the extracted corpus before continuing."
        )

    groups: dict[str, list[tuple[Path, str, str, float]]] = {"low": [], "medium": [], "high": []}
    for candidate in candidates:
        groups[candidate[2]].append(candidate)
    randomizer = random.Random(seed)
    selected: list[tuple[Path, str, str, float]] = []
    target_per_band = sample_size // 3
    remainder = sample_size % 3
    for index, band in enumerate(("low", "medium", "high")):
        ordered = sorted(groups[band], key=lambda candidate: str(candidate[0]))
        randomizer.shuffle(ordered)
        selected.extend(ordered[: target_per_band + (1 if index < remainder else 0)])
    if len(selected) < sample_size:
        already = {candidate[0] for candidate in selected}
        remaining = [candidate for candidate in candidates if candidate[0] not in already]
        randomizer.shuffle(remaining)
        selected.extend(remaining[: sample_size - len(selected)])

    items = []
    for audio, transcript, band, ratio in sorted(selected, key=lambda candidate: str(candidate[0])):
        items.append(
            {
                "id": f"mucs-{audio.stem}",
                "file": os.path.relpath(audio, output_manifest.parent),
                "reference": "",
                "source": "mucs-openslr-104",
                "category": "whatsapp-casual",
                "noise": "clean",
                "entities": [],
                "switchIndexes": [],
                "datasetTranscript": transcript,
                "englishRatio": round(ratio, 4),
                "englishRatioBand": band,
                "needsHumanRomanReference": True,
                "annotationNote": "Listen to the real clip and write exactly what you would send in Roman Hinglish.",
            }
        )
    output_manifest.parent.mkdir(parents=True, exist_ok=True)
    output_manifest.write_text(
        json.dumps({"schemaVersion": 1, "items": items}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return len(items)


def _text_rows(dataset_id: str, source: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if dataset_id == "hinge":
        with source.open(encoding="utf-8", newline="") as handle:
            for index, row in enumerate(csv.DictReader(handle)):
                try:
                    candidates = ast.literal_eval(row.get("Human-generated Hinglish", "[]"))
                except (SyntaxError, ValueError):
                    continue
                if isinstance(candidates, list) and candidates and isinstance(candidates[0], str):
                    text = candidates[0].strip()
                    if text:
                        rows.append({"sourceId": str(index), "input": text, "reference": text})
    elif dataset_id == "hinglishnorm":
        document = json.loads(source.read_text(encoding="utf-8"))
        for row in document:
            input_text = str(row.get("inputText", "")).strip()
            reference = str(row.get("normalizedText", "")).strip()
            if input_text and reference:
                rows.append(
                    {"sourceId": str(row.get("id", len(rows))), "input": input_text, "reference": reference}
                )
    elif dataset_id == "l3cube-hinglid":
        sentence_tokens: list[str] = []
        language_tags: list[str] = []
        sentences: list[tuple[list[str], list[str]]] = []
        for line in source.read_text(encoding="utf-8").splitlines() + [""]:
            if not line.strip():
                if sentence_tokens:
                    sentences.append((sentence_tokens, language_tags))
                    sentence_tokens, language_tags = [], []
                continue
            parts = line.split()
            if len(parts) >= 2:
                sentence_tokens.append(parts[0])
                language_tags.append(parts[-1].upper())
        for index, (tokens, tags) in enumerate(sentences):
            switches = [
                token_index
                for token_index in range(1, len(tags))
                if tags[token_index] != tags[token_index - 1]
                and tags[token_index] in {"HI", "EN"}
                and tags[token_index - 1] in {"HI", "EN"}
            ]
            text = " ".join(tokens)
            rows.append(
                {"sourceId": str(index), "input": text, "reference": text, "switchIndexes": switches}
            )
    return rows


def prepare_text_regressions(
    dataset_id: str,
    source: Path,
    output_manifest: Path,
    *,
    sample_size: int,
    seed: int,
    license_status: str,
) -> int:
    rows = _text_rows(dataset_id, source)
    randomizer = random.Random(seed)
    randomizer.shuffle(rows)
    selected = sorted(rows[:sample_size], key=lambda row: row["sourceId"])
    document = {
        "schemaVersion": 1,
        "kind": "enhancement-regression",
        "dataset": dataset_id,
        "licenseStatus": license_status,
        "items": [
            {
                "id": f"{dataset_id}-{row['sourceId']}",
                "input": row["input"],
                "reference": row["reference"],
                "source": dataset_id,
                "category": "whatsapp-casual",
                "switchIndexes": row.get("switchIndexes", []),
            }
            for row in selected
        ],
    }
    output_manifest.parent.mkdir(parents=True, exist_ok=True)
    output_manifest.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return len(selected)


def prepare_dataset(
    registry_path: Path,
    dataset_id: str,
    *,
    cache_root: Path,
    output_directory: Path,
    sample_size: int,
    seed: int,
    allow_unverified_license: bool,
) -> tuple[Path, int]:
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    entry = registry["datasets"].get(dataset_id)
    if not entry:
        raise ValueError(f"unknown dataset '{dataset_id}'")
    status = entry.get("licenseStatus", "verified")
    if status == "request-required":
        raise ValueError(f"{dataset_id} requires a separate corpus request and rights confirmation")
    if status != "verified" and not allow_unverified_license:
        raise ValueError(
            f"{dataset_id} has license status '{status}'. Review its terms, then pass "
            "--allow-unverified-license for evaluation-only use."
        )
    download_path = cache_root / entry["cachePath"]
    download_verified(entry["url"], download_path, entry["sha256"])
    if entry["kind"] == "speech":
        extracted = cache_root / "extracted" / dataset_id
        marker = extracted / f".sha256-{entry['sha256']}"
        if not marker.exists():
            if extracted.exists():
                shutil.rmtree(extracted)
            safe_extract_tar(download_path, extracted)
            marker.touch()
        output = output_directory / f"annotation-queue-{dataset_id}.json"
        count = prepare_mucs(extracted, output, sample_size=sample_size, seed=seed)
    else:
        output = output_directory / f"text-regressions-{dataset_id}.json"
        count = prepare_text_regressions(
            dataset_id,
            download_path,
            output,
            sample_size=sample_size,
            seed=seed,
            license_status=status,
        )
    return output, count
