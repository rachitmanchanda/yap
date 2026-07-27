"""Metric aggregation and stable JSON/Markdown result rendering."""

from __future__ import annotations

import difflib
import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from .metrics import (
    entity_accuracy,
    error_counts,
    exact_send,
    preserves_roman_script,
    switch_boundary_accuracy,
    tokenize,
)
from .models import ManifestItem, PipelineResult


def score_item(item: ManifestItem, pipeline: PipelineResult) -> dict[str, Any]:
    raw_edits, reference_words = error_counts(item.reference, pipeline.raw_asr)
    final_edits, _ = error_counts(item.reference, pipeline.final_text)
    raw_wer = raw_edits / reference_words if reference_words else (1.0 if raw_edits else 0.0)
    correction_burden = (
        final_edits / reference_words if reference_words else (1.0 if final_edits else 0.0)
    )
    correct_entities, entity_total = entity_accuracy(item.entities, pipeline.final_text)
    correct_switches, switch_total = switch_boundary_accuracy(
        item.reference, pipeline.final_text, item.switch_indexes
    )
    return {
        "id": item.id,
        "file": str(item.file),
        "source": item.source,
        "category": item.category,
        "noise": item.noise,
        "reference": item.reference,
        "datasetTranscript": item.dataset_transcript,
        "rawAsr": pipeline.raw_asr,
        "finalText": pipeline.final_text,
        "rawWer": raw_wer,
        "correctionBurden": correction_burden,
        "referenceWords": reference_words,
        "rawEdits": raw_edits,
        "finalEdits": final_edits,
        "sendWithoutEdit": exact_send(item.reference, pipeline.final_text),
        "romanScriptPreserved": preserves_roman_script(item.reference, pipeline.final_text),
        "entityCorrect": correct_entities,
        "entityTotal": entity_total,
        "switchCorrect": correct_switches,
        "switchTotal": switch_total,
        "asrMs": pipeline.asr_ms,
        "enhancementMs": pipeline.enhancement_ms,
        "totalMs": pipeline.total_ms,
        "asrProvider": pipeline.asr_provider,
        "enhancementProvider": pipeline.enhancement_provider,
        "enhancementError": pipeline.enhancement_error,
        "enhancementFallback": pipeline.enhancement_error is not None,
        "rawDiff": list(
            difflib.ndiff(tokenize(item.reference), tokenize(pipeline.raw_asr))
        ),
        "finalDiff": list(
            difflib.ndiff(tokenize(item.reference), tokenize(pipeline.final_text))
        ),
    }


def _aggregate(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    rows = list(rows)
    successes = [row for row in rows if not row.get("error")]
    reference_words = sum(row["referenceWords"] for row in successes)
    raw_errors = sum(row["rawEdits"] for row in successes)
    final_errors = sum(row["finalEdits"] for row in successes)
    entity_total = sum(row["entityTotal"] for row in successes)
    switch_total = sum(row["switchTotal"] for row in successes)
    return {
        "utterances": len(rows),
        "successful": len(successes),
        "failed": len(rows) - len(successes),
        "rawWer": raw_errors / reference_words if reference_words else None,
        "correctionBurden": final_errors / reference_words if reference_words else None,
        "sendWithoutEditRate": (
            sum(bool(row["sendWithoutEdit"]) for row in successes) / len(successes)
            if successes else None
        ),
        "entityAccuracy": (
            sum(row["entityCorrect"] for row in successes) / entity_total if entity_total else None
        ),
        "switchBoundaryAccuracy": (
            sum(row["switchCorrect"] for row in successes) / switch_total if switch_total else None
        ),
        "enhancementFallbacks": sum(bool(row["enhancementFallback"]) for row in successes),
        "romanScriptPreservationRate": (
            sum(bool(row["romanScriptPreserved"]) for row in successes) / len(successes)
            if successes else None
        ),
        "meanAsrMs": (
            round(sum(row["asrMs"] for row in successes) / len(successes)) if successes else None
        ),
        "meanEnhancementMs": (
            round(sum(row["enhancementMs"] for row in successes) / len(successes))
            if successes else None
        ),
        "meanTotalMs": (
            round(sum(row["totalMs"] for row in successes) / len(successes)) if successes else None
        ),
    }


def build_report(metadata: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    def grouped(field: str) -> dict[str, Any]:
        groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for row in rows:
            groups[str(row.get(field, "unknown"))].append(row)
        return {name: _aggregate(groups[name]) for name in sorted(groups)}

    worst = sorted(
        [row for row in rows if not row.get("error")],
        key=lambda row: (-row["correctionBurden"], row["id"]),
    )[:20]
    overall = _aggregate(rows)
    clean = _aggregate(row for row in rows if row.get("noise") == "clean")
    public_count = sum(
        1 for row in rows if not row.get("error") and row.get("source") == "mucs-openslr-104"
    )
    private_count = sum(
        1 for row in rows if not row.get("error") and row.get("source") == "private-holdout"
    )
    gate_eligible = (
        metadata.get("pipeline") == "production-yap-transcribe-plus-enhance"
        and public_count >= 100
        and 30 <= private_count <= 50
    )
    thresholds_met = (
        overall["sendWithoutEditRate"] is not None
        and overall["sendWithoutEditRate"] >= 0.70
        and overall["correctionBurden"] is not None
        and overall["correctionBurden"] < 0.08
        and clean["correctionBurden"] is not None
        and clean["correctionBurden"] < 0.05
    )
    return {
        "metadata": metadata,
        "overall": overall,
        "byCategory": grouped("category"),
        "byNoise": grouped("noise"),
        "bySource": grouped("source"),
        "shipGate": {
            "eligible": gate_eligible,
            "passed": gate_eligible and thresholds_met,
            "publicMucsCount": public_count,
            "privateHoldoutCount": private_count,
            "requirements": {
                "minimumPublicMucs": 100,
                "minimumPrivateHoldout": 30,
                "maximumPrivateHoldout": 50,
                "minimumSendWithoutEditRate": 0.70,
                "maximumOverallCorrectionBurdenExclusive": 0.08,
                "maximumCleanCorrectionBurdenExclusive": 0.05,
            },
        },
        "utterances": rows,
        "worst20": worst,
    }


def _percent(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.2f}%"


def markdown(report: dict[str, Any]) -> str:
    metadata = report["metadata"]
    overall = report["overall"]
    lines = [
        f"# YAP Hinglish evaluation — `{metadata['runId']}`",
        "",
        f"- Git commit: `{metadata.get('git', {}).get('commit') or 'unknown'}`"
        + (" (dirty worktree)" if metadata.get("git", {}).get("dirty") else ""),
        f"- Started: {metadata['startedAt']}",
        f"- Manifest SHA-256: `{metadata['manifestSha256']}`",
        "",
        "## Overall",
        "",
        "| Utterances | Failed | Raw ASR WER | Correction burden | Send without edit | Roman script | Entity accuracy | Switch accuracy | Enhancement fallbacks | Mean total |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        (
            f"| {overall['utterances']} | {overall['failed']} | {_percent(overall['rawWer'])} | "
            f"{_percent(overall['correctionBurden'])} | {_percent(overall['sendWithoutEditRate'])} | "
            f"{_percent(overall['romanScriptPreservationRate'])} | "
            f"{_percent(overall['entityAccuracy'])} | {_percent(overall['switchBoundaryAccuracy'])} | "
            f"{overall['enhancementFallbacks']} | "
            f"{overall['meanTotalMs'] if overall['meanTotalMs'] is not None else 'n/a'} ms |"
        ),
        "",
        "## Ship gate",
        "",
        (
            f"**{'PASS' if report['shipGate']['passed'] else 'NOT PASSED'}**"
            if report["shipGate"]["eligible"]
            else "**NOT ELIGIBLE** — requires at least 100 `mucs-openslr-104` clips and "
            "30–50 `private-holdout` clips in a speech-pipeline run."
        ),
    ]
    for title, key in (("By category", "byCategory"), ("By noise", "byNoise"), ("By source", "bySource")):
        lines.extend(
            [
                "",
                f"## {title}",
                "",
                "| Group | N | Raw ASR WER | Correction burden | Send without edit |",
                "|---|---:|---:|---:|---:|",
            ]
        )
        for name, summary in report[key].items():
            lines.append(
                f"| {name} | {summary['successful']} | {_percent(summary['rawWer'])} | "
                f"{_percent(summary['correctionBurden'])} | {_percent(summary['sendWithoutEditRate'])} |"
            )
    lines.extend(["", "## Worst 20 final outputs", ""])
    if not report["worst20"]:
        lines.append("No successful utterances.")
    for index, row in enumerate(report["worst20"], start=1):
        lines.extend(
            [
                f"### {index}. `{row['id']}` — {_percent(row['correctionBurden'])} correction burden",
                "",
                f"- Reference: {row['reference']}",
                f"- Raw ASR: {row['rawAsr']}",
                f"- Final: {row['finalText']}",
                f"- Final diff: `{' '.join(row['finalDiff'])}`",
                "",
            ]
        )
    failures = [row for row in report["utterances"] if row.get("error")]
    if failures:
        lines.extend(["## Failures", ""])
        lines.extend(f"- `{row['id']}`: {row['error']}" for row in failures)
        lines.append("")
    return "\n".join(lines)


def write_report(output_directory: Path, report: dict[str, Any]) -> None:
    output_directory.mkdir(parents=True, exist_ok=False)
    (output_directory / "results.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output_directory / "report.md").write_text(markdown(report), encoding="utf-8")
