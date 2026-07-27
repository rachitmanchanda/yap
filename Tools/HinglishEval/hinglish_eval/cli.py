"""Command-line entry point for preparing, validating and running YAP evaluations."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .backend import BackendConfiguration, YAPBackendClient, git_metadata
from .datasets import prepare_dataset
from .manifest import ManifestValidationError, load_manifest, validate_private_baselines
from .models import ManifestItem, PipelineResult, SUPPORTED_CATEGORIES, SUPPORTED_PROVIDERS
from .report import baseline_rows, build_report, score_item, write_report


TOOL_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = TOOL_ROOT.parents[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run_id(git: dict[str, Any]) -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{timestamp}-{git.get('shortCommit') or 'nogit'}"


def _known_terms(path: Path | None) -> list[str]:
    if not path:
        return []
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, list) or any(not isinstance(term, str) for term in document):
        raise ValueError("known-terms file must be a JSON array of strings")
    return [term.strip() for term in document if term.strip()]


def command_prepare(arguments: argparse.Namespace) -> int:
    for dataset_id in arguments.dataset:
        output, count = prepare_dataset(
            arguments.registry,
            dataset_id,
            cache_root=arguments.cache,
            output_directory=arguments.output,
            sample_size=arguments.sample_size,
            seed=arguments.seed,
            allow_unverified_license=arguments.allow_unverified_license,
        )
        print(f"prepared {count} {dataset_id} rows at {output}")
    return 0


def command_validate(arguments: argparse.Namespace) -> int:
    try:
        items = load_manifest(arguments.manifest)
        if arguments.mode == "baseline":
            validate_private_baselines(items)
    except ManifestValidationError as error:
        for message in error.errors:
            print(f"error: {message}", file=sys.stderr)
        return 1
    print(f"valid: {len(items)} human-labelled real-speech utterances ({arguments.mode} mode)")
    return 0


def _client(arguments: argparse.Namespace) -> YAPBackendClient:
    configuration = BackendConfiguration.from_environment(REPOSITORY_ROOT)
    return YAPBackendClient(
        configuration,
        transcription_timeout=arguments.transcription_timeout,
        enhancement_timeout=arguments.enhancement_timeout,
        retries=arguments.retries,
    )


def command_run(arguments: argparse.Namespace) -> int:
    try:
        items = load_manifest(arguments.manifest)
        known_terms = _known_terms(arguments.known_terms)
        client = _client(arguments)
    except (ManifestValidationError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    git = git_metadata(REPOSITORY_ROOT)
    run_id = arguments.run_id or f"{_run_id(git)}-{arguments.provider}"
    rows: list[dict[str, Any]] = []
    started = datetime.now(timezone.utc)
    for index, item in enumerate(items, start=1):
        print(f"[{index}/{len(items)}] {item.id}", flush=True)
        item_started = time.perf_counter()
        try:
            rows.append(
                score_item(
                    item,
                    client.run_pipeline(
                        item.file,
                        provider=arguments.provider,
                        known_terms=known_terms,
                    ),
                    system="yap",
                    provider=arguments.provider,
                )
            )
        except Exception as error:
            rows.append(
                {
                    "id": item.id,
                    "file": str(item.file),
                    "source": item.source,
                    "category": item.category,
                    "noise": item.noise,
                    "reference": item.reference,
                    "system": "yap",
                    "provider": arguments.provider,
                    "error": str(error),
                    "failedAfterMs": round((time.perf_counter() - item_started) * 1000),
                }
            )
    rows.extend(baseline_rows(items))
    metadata = {
        "schemaVersion": 2,
        "runId": run_id,
        "startedAt": started.isoformat(),
        "finishedAt": datetime.now(timezone.utc).isoformat(),
        "manifest": str(arguments.manifest.resolve()),
        "manifestSha256": _sha256(arguments.manifest),
        "pipeline": "production-yap-transcribe-plus-enhance",
        "provider": arguments.provider,
        "git": git,
    }
    output = arguments.output / run_id
    try:
        write_report(output, build_report(metadata, rows))
    except FileExistsError:
        print(f"error: run directory already exists: {output}", file=sys.stderr)
        return 1
    print(f"wrote {output / 'report.md'}")
    return 0 if all(not row.get("error") for row in rows) else 2


def command_baseline(arguments: argparse.Namespace) -> int:
    try:
        items = load_manifest(arguments.manifest)
        validate_private_baselines(items)
    except ManifestValidationError as error:
        for message in error.errors:
            print(f"error: {message}", file=sys.stderr)
        return 1
    git = git_metadata(REPOSITORY_ROOT)
    run_id = arguments.run_id or f"{_run_id(git)}-baselines"
    now = datetime.now(timezone.utc).isoformat()
    metadata = {
        "schemaVersion": 2,
        "runId": run_id,
        "startedAt": now,
        "finishedAt": now,
        "manifest": str(arguments.manifest.resolve()),
        "manifestSha256": _sha256(arguments.manifest),
        "pipeline": "manual-baselines-only",
        "provider": None,
        "git": git,
    }
    output = arguments.output / run_id
    try:
        write_report(output, build_report(metadata, baseline_rows(items)))
    except FileExistsError:
        print(f"error: run directory already exists: {output}", file=sys.stderr)
        return 1
    print(f"wrote {output / 'report.md'}")
    return 0


def _load_text_manifest(path: Path) -> list[dict[str, Any]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    rows = document.get("items") if isinstance(document, dict) else None
    if not isinstance(rows, list):
        raise ValueError("text manifest must contain an items array")
    errors: list[str] = []
    seen: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            errors.append(f"item {index + 1}: must be an object")
            continue
        item_id = str(row.get("id", "")).strip()
        if not item_id or item_id in seen:
            errors.append(f"item {index + 1}: id is missing or duplicated")
        seen.add(item_id)
        if not str(row.get("input", "")).strip() or not str(row.get("reference", "")).strip():
            errors.append(f"item {index + 1} ({item_id}): input and reference are required")
        if row.get("category") not in SUPPORTED_CATEGORIES:
            errors.append(f"item {index + 1} ({item_id}): unsupported category")
    if errors:
        raise ValueError("\n".join(errors))
    return sorted(rows, key=lambda row: row["id"])


def command_run_text(arguments: argparse.Namespace) -> int:
    try:
        source_rows = _load_text_manifest(arguments.manifest)
        known_terms = _known_terms(arguments.known_terms)
        client = _client(arguments)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    git = git_metadata(REPOSITORY_ROOT)
    run_id = arguments.run_id or f"{_run_id(git)}-text"
    rows: list[dict[str, Any]] = []
    started = datetime.now(timezone.utc)
    for index, row in enumerate(source_rows, start=1):
        print(f"[{index}/{len(source_rows)}] {row['id']}", flush=True)
        enhancement_started = time.perf_counter()
        try:
            enhancement_error: str | None = None
            try:
                payload = client.enhance(row["input"], known_terms=known_terms)
                final_text = str(payload["text"])
            except RuntimeError as error:
                payload = {}
                final_text = row["input"]
                enhancement_error = str(error)
            enhancement_ms = round((time.perf_counter() - enhancement_started) * 1000)
            item = ManifestItem(
                id=row["id"],
                file=arguments.manifest,
                reference=row["reference"],
                source=row.get("source", "text-regression"),
                category=row["category"],
                noise="clean",
                switch_indexes=tuple(row.get("switchIndexes", [])),
            )
            rows.append(
                score_item(
                    item,
                    PipelineResult(
                        raw_asr=row["input"],
                        final_text=final_text,
                        asr_ms=0,
                        enhancement_ms=enhancement_ms,
                        total_ms=enhancement_ms,
                        enhancement_provider=payload.get("provider"),
                        enhancement_error=enhancement_error,
                    ),
                    system="yap",
                    provider=None,
                )
            )
        except Exception as error:
            rows.append(
                {
                    "id": row["id"],
                    "source": row.get("source", "text-regression"),
                    "category": row["category"],
                    "noise": "clean",
                    "reference": row["reference"],
                    "error": str(error),
                    "failedAfterMs": round((time.perf_counter() - enhancement_started) * 1000),
                }
            )
    metadata = {
        "schemaVersion": 1,
        "runId": run_id,
        "startedAt": started.isoformat(),
        "finishedAt": datetime.now(timezone.utc).isoformat(),
        "manifest": str(arguments.manifest.resolve()),
        "manifestSha256": _sha256(arguments.manifest),
        "pipeline": "production-yap-enhance-only",
        "provider": None,
        "git": git,
    }
    output = arguments.output / run_id
    try:
        write_report(output, build_report(metadata, rows))
    except FileExistsError:
        print(f"error: run directory already exists: {output}", file=sys.stderr)
        return 1
    print(f"wrote {output / 'report.md'}")
    return 0 if all(not row.get("error") for row in rows) else 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="yap-eval",
        description="Evaluate YAP's production Hinglish pipeline using human-labelled real speech.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    prepare = subcommands.add_parser("prepare", help="download, verify and prepare licensed datasets")
    prepare.add_argument(
        "--registry", type=Path, default=TOOL_ROOT / "datasets.json"
    )
    prepare.add_argument("--dataset", action="append", required=True)
    prepare.add_argument("--cache", type=Path, default=TOOL_ROOT / ".cache")
    prepare.add_argument("--output", type=Path, default=TOOL_ROOT)
    prepare.add_argument("--sample-size", type=int, default=100)
    prepare.add_argument("--seed", type=int, default=20260727)
    prepare.add_argument("--allow-unverified-license", action="store_true")
    prepare.set_defaults(handler=command_prepare)

    validate = subcommands.add_parser("validate", help="strictly validate a speech manifest")
    validate.add_argument("manifest", type=Path)
    validate.add_argument("--mode", choices=("pipeline", "baseline"), default="pipeline")
    validate.set_defaults(handler=command_validate)

    baseline = subcommands.add_parser(
        "baseline", help="score manually captured Gboard and Apple Dictation outputs"
    )
    baseline.add_argument("manifest", type=Path)
    baseline.add_argument("--output", type=Path, default=TOOL_ROOT / "results")
    baseline.add_argument("--run-id")
    baseline.set_defaults(handler=command_baseline)

    for name, handler, help_text in (
        ("run", command_run, "run real speech through production transcription and enhancement"),
        ("run-text", command_run_text, "run a Roman-Hinglish enhancement regression manifest"),
    ):
        command = subcommands.add_parser(name, help=help_text)
        command.add_argument("manifest", type=Path)
        command.add_argument("--output", type=Path, default=TOOL_ROOT / "results")
        command.add_argument("--run-id")
        command.add_argument("--known-terms", type=Path)
        command.add_argument("--transcription-timeout", type=float, default=8.0)
        command.add_argument("--enhancement-timeout", type=float, default=2.5)
        command.add_argument("--retries", type=int, default=2)
        if name == "run":
            command.add_argument(
                "--provider",
                choices=sorted(SUPPORTED_PROVIDERS),
                default="sarvam",
                help="ASR provider; apple runs locally through Speech.framework",
            )
        command.set_defaults(handler=handler)
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        return arguments.handler(arguments)
    except KeyboardInterrupt:
        print("cancelled", file=sys.stderr)
        return 130
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
