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
from .models import BASELINE_SYSTEMS, ManifestItem, PipelineResult


def score_item(
    item: ManifestItem,
    pipeline: PipelineResult,
    *,
    system: str = "yap",
    provider: str | None = None,
) -> dict[str, Any]:
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
        "system": system,
        "provider": provider,
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
        "rawDiff": list(difflib.ndiff(tokenize(item.reference), tokenize(pipeline.raw_asr))),
        "finalDiff": list(difflib.ndiff(tokenize(item.reference), tokenize(pipeline.final_text))),
    }


def baseline_rows(items: Iterable[ManifestItem]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for item in items:
        for system, output in (
            ("gboard", item.baseline_gboard),
            ("apple-dictation", item.baseline_apple),
        ):
            if not output:
                continue
            rows.append(
                score_item(
                    item,
                    PipelineResult(output, output, 0, 0, 0, system, None),
                    system=system,
                    provider=None,
                )
            )
    return rows


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


def _grouped(rows: Iterable[dict[str, Any]], field: str) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[str(row.get(field, "unknown"))].append(row)
    return {name: _aggregate(groups[name]) for name in sorted(groups)}


def _system_name(row: dict[str, Any]) -> str:
    return f"yap-{row.get('provider') or 'unknown'}" if row.get("system") == "yap" else row["system"]


def _system_summaries(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[_system_name(row)].append(row)
    return {name: _aggregate(groups[name]) for name in sorted(groups)}


def _ship_gate(private_rows: list[dict[str, Any]]) -> dict[str, Any]:
    yap_rows = [row for row in private_rows if row.get("system") == "yap" and not row.get("error")]
    yap_ids = {row["id"] for row in yap_rows}
    matched: dict[str, list[dict[str, Any]]] = {}
    for baseline in BASELINE_SYSTEMS:
        candidates = [
            row for row in private_rows
            if row.get("system") == baseline and not row.get("error") and row["id"] in yap_ids
        ]
        if {row["id"] for row in candidates} == yap_ids:
            matched[baseline] = candidates
    eligible = bool(yap_ids) and len(matched) == len(BASELINE_SYSTEMS)
    yap_summary = _aggregate(yap_rows)
    baseline_rates = {
        name: _aggregate(rows)["sendWithoutEditRate"] for name, rows in matched.items()
    }
    best_baseline = max(baseline_rates.values()) if eligible else None
    yap_rate = yap_summary["sendWithoutEditRate"]
    return {
        "eligible": eligible,
        "passed": bool(eligible and yap_rate is not None and yap_rate > best_baseline),
        "matchedPrivateUtterances": len(yap_ids) if eligible else 0,
        "yapSendWithoutEditRate": yap_rate,
        "baselineSendWithoutEditRates": baseline_rates,
        "bestBaselineSendWithoutEditRate": best_baseline,
        "requirement": "YAP must strictly beat the best matched manual baseline on private-holdout send-without-edit.",
    }


def build_report(metadata: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    yap_rows = [row for row in rows if row.get("system", "yap") == "yap"]
    private_rows = [row for row in rows if row.get("source") == "private-holdout"]
    mucs_rows = [row for row in rows if row.get("source") == "mucs-openslr-104"]
    worst = sorted(
        [row for row in yap_rows if not row.get("error")],
        key=lambda row: (-row["correctionBurden"], row["id"]),
    )[:20]
    return {
        "metadata": metadata,
        "overall": _aggregate(yap_rows),
        "privateHoldout": {
            "systems": _system_summaries(private_rows),
            "byCategory": _grouped(
                [row for row in private_rows if row.get("system") == "yap"], "category"
            ),
        },
        "mucsRegression": {
            "systems": _system_summaries(mucs_rows),
            "byCategory": _grouped(
                [row for row in mucs_rows if row.get("system") == "yap"], "category"
            ),
        },
        "byNoise": _grouped(yap_rows, "noise"),
        "bySource": _grouped(yap_rows, "source"),
        "shipGate": _ship_gate(private_rows),
        "utterances": rows,
        "worst20": worst,
    }


def _percent(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.2f}%"


def _system_table(lines: list[str], summaries: dict[str, Any]) -> None:
    lines.extend([
        "| System | N | Send without edit | Correction burden | Raw WER | Entity accuracy | Switch accuracy |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ])
    if not summaries:
        lines.append("| No scored rows | 0 | n/a | n/a | n/a | n/a | n/a |")
    for name, summary in summaries.items():
        lines.append(
            f"| {name} | {summary['successful']} | {_percent(summary['sendWithoutEditRate'])} | "
            f"{_percent(summary['correctionBurden'])} | {_percent(summary['rawWer'])} | "
            f"{_percent(summary['entityAccuracy'])} | {_percent(summary['switchBoundaryAccuracy'])} |"
        )


def markdown(report: dict[str, Any]) -> str:
    metadata = report["metadata"]
    gate = report["shipGate"]
    lines = [
        f"# YAP Hinglish evaluation — `{metadata['runId']}`",
        "",
        f"- Git commit: `{metadata.get('git', {}).get('commit') or 'unknown'}`"
        + (" (dirty worktree)" if metadata.get("git", {}).get("dirty") else ""),
        f"- Started: {metadata['startedAt']}",
        f"- Provider: `{metadata.get('provider') or 'manual-baseline'}`",
        f"- Manifest SHA-256: `{metadata['manifestSha256']}`",
        "",
        "## Private holdout — headline",
        "",
    ]
    _system_table(lines, report["privateHoldout"]["systems"])
    lines.extend(["", "### Ship gate", ""])
    if gate["eligible"]:
        result = "PASS" if gate["passed"] else "NOT PASSED"
        lines.append(
            f"**{result}** — YAP {_percent(gate['yapSendWithoutEditRate'])}; "
            f"best matched baseline {_percent(gate['bestBaselineSendWithoutEditRate'])}."
        )
    else:
        lines.append(
            "**NOT ELIGIBLE** — every scored private-holdout clip must have manually captured "
            "`baselineGboard` and `baselineApple` outputs."
        )
    lines.extend(["", "### Private YAP by category", ""])
    _category_table(lines, report["privateHoldout"]["byCategory"])
    lines.extend(["", "## MUCS regression appendix", ""])
    _system_table(lines, report["mucsRegression"]["systems"])
    lines.extend(["", "### MUCS YAP by category", ""])
    _category_table(lines, report["mucsRegression"]["byCategory"])
    lines.extend(["", "## Worst 20 YAP final outputs", ""])
    if not report["worst20"]:
        lines.append("No successful YAP utterances.")
    for index, row in enumerate(report["worst20"], start=1):
        lines.extend([
            f"### {index}. `{row['id']}` — {_percent(row['correctionBurden'])} correction burden",
            "",
            f"- Reference: {row['reference']}",
            f"- Raw ASR: {row['rawAsr']}",
            f"- Final: {row['finalText']}",
            f"- Final diff: `{' '.join(row['finalDiff'])}`",
            "",
        ])
    failures = [row for row in report["utterances"] if row.get("error")]
    if failures:
        lines.extend(["## Failures", ""])
        lines.extend(f"- `{row['id']}`: {row['error']}" for row in failures)
        lines.append("")
    return "\n".join(lines)


def _category_table(lines: list[str], summaries: dict[str, Any]) -> None:
    lines.extend([
        "| Category | N | Send without edit | Correction burden | Raw WER |",
        "|---|---:|---:|---:|---:|",
    ])
    if not summaries:
        lines.append("| No scored rows | 0 | n/a | n/a | n/a |")
    for name, summary in summaries.items():
        lines.append(
            f"| {name} | {summary['successful']} | {_percent(summary['sendWithoutEditRate'])} | "
            f"{_percent(summary['correctionBurden'])} | {_percent(summary['rawWer'])} |"
        )


def write_report(output_directory: Path, report: dict[str, Any]) -> None:
    output_directory.mkdir(parents=True, exist_ok=False)
    (output_directory / "results.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output_directory / "report.md").write_text(markdown(report), encoding="utf-8")
