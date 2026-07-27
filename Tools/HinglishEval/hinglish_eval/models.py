"""Validated value objects shared by the evaluator commands."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SUPPORTED_CATEGORIES = frozenset(
    {
        "whatsapp-casual",
        "work-message",
        "numbers-dates",
        "names-places",
        "slang",
        "pure-hindi",
        "pure-english",
    }
)
SUPPORTED_NOISE_TAGS = frozenset({"clean", "noisy"})
SUPPORTED_PROVIDERS = frozenset({"sarvam", "whisper", "apple"})
BASELINE_SYSTEMS = ("gboard", "apple-dictation")


@dataclass(frozen=True)
class ManifestItem:
    id: str
    file: Path
    reference: str
    source: str
    category: str
    noise: str
    entities: tuple[str, ...] = ()
    switch_indexes: tuple[int, ...] = ()
    baseline_gboard: str | None = None
    baseline_apple: str | None = None
    dataset_transcript: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class PipelineResult:
    raw_asr: str
    final_text: str
    asr_ms: int
    enhancement_ms: int
    total_ms: int
    asr_provider: str | None = None
    enhancement_provider: str | None = None
    enhancement_error: str | None = None
