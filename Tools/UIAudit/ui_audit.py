#!/usr/bin/env python3
"""Dependency-free guard against new one-off SwiftUI styling."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = (ROOT / "VoiceCardsApp", ROOT / "VoiceCardsKeyboard")
ALLOWLIST = {
    ROOT / "VoiceCardsApp/Onboarding/YapDesignSystem.swift",
    ROOT / "VoiceCardsApp/Onboarding/YapOnboardingFlowView.swift",
    ROOT / "VoiceCardsApp/Recording/WaveformView.swift",
    ROOT / "Shared/UI/YapDesignFoundation.swift",
}


@dataclass(frozen=True)
class Rule:
    name: str
    pattern: re.Pattern[str]
    guidance: str


RULES = (
    Rule(
        "fixed-font",
        re.compile(r"\.font\(\.system\(size:"),
        "Use a YapType semantic role.",
    ),
    Rule(
        "numeric-radius",
        re.compile(r"(?:cornerRadius:\s*|\.cornerRadius\()\d"),
        "Use YapRadius or a documented geometry exception.",
    ),
    Rule(
        "direct-rgb-color",
        re.compile(r"Color\(\s*red:"),
        "Use the target palette instead of a local RGB color.",
    ),
)


def violations() -> list[str]:
    findings: list[str] = []
    for source_root in SOURCE_ROOTS:
        for path in sorted(source_root.rglob("*.swift")):
            if path in ALLOWLIST:
                continue
            for line_number, line in enumerate(path.read_text().splitlines(), start=1):
                for rule in RULES:
                    # Palette declarations are the single source of truth for color values.
                    if rule.name == "direct-rgb-color" and "static let" in line:
                        continue
                    if rule.pattern.search(line):
                        relative = path.relative_to(ROOT)
                        findings.append(
                            f"{relative}:{line_number}: {rule.name}: "
                            f"{rule.guidance}\n    {line.strip()}"
                        )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return a failing status when violations exist.",
    )
    args = parser.parse_args()
    findings = violations()
    if findings:
        print("\n".join(findings))
        print(f"\nUI audit: {len(findings)} violation(s).")
        return 1 if args.strict else 0
    print("UI audit: passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
