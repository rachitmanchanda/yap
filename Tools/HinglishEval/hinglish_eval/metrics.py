"""Transparent text metrics with no language-model or romanization dependency."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Sequence


TOKEN_PATTERN = re.compile(r"[^\W_]+(?:['’][^\W_]+)*", re.UNICODE)
DEVANAGARI_PATTERN = re.compile(r"[\u0900-\u097f]")
BULLET_PATTERN = re.compile(r"^\s*[-•]\s+\S")


def normalize_text(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text).replace("’", "'").casefold()
    return " ".join(TOKEN_PATTERN.findall(normalized))


def tokenize(text: str) -> list[str]:
    normalized = normalize_text(text)
    return normalized.split() if normalized else []


@dataclass(frozen=True)
class Alignment:
    distance: int
    reference_to_hypothesis: tuple[int | None, ...]


def align(reference: Sequence[str], hypothesis: Sequence[str]) -> Alignment:
    """Return Levenshtein distance and deterministic reference-token alignment."""
    rows, columns = len(reference) + 1, len(hypothesis) + 1
    costs = [[0] * columns for _ in range(rows)]
    back = [[""] * columns for _ in range(rows)]
    for row in range(1, rows):
        costs[row][0], back[row][0] = row, "delete"
    for column in range(1, columns):
        costs[0][column], back[0][column] = column, "insert"

    priority = {"match": 0, "substitute": 1, "delete": 2, "insert": 3}
    for row in range(1, rows):
        for column in range(1, columns):
            same = reference[row - 1] == hypothesis[column - 1]
            choices = [
                (costs[row - 1][column - 1] + (0 if same else 1), "match" if same else "substitute"),
                (costs[row - 1][column] + 1, "delete"),
                (costs[row][column - 1] + 1, "insert"),
            ]
            value, operation = min(choices, key=lambda choice: (choice[0], priority[choice[1]]))
            costs[row][column], back[row][column] = value, operation

    mapping: list[int | None] = [None] * len(reference)
    row, column = len(reference), len(hypothesis)
    while row or column:
        operation = back[row][column]
        if operation in {"match", "substitute"}:
            mapping[row - 1] = column - 1
            row -= 1
            column -= 1
        elif operation == "delete":
            row -= 1
        elif operation == "insert":
            column -= 1
        else:
            break
    return Alignment(costs[-1][-1], tuple(mapping))


def error_rate(reference: str, hypothesis: str) -> float:
    edits, reference_words = error_counts(reference, hypothesis)
    if not reference_words:
        return 0.0 if edits == 0 else 1.0
    return edits / reference_words


def error_counts(reference: str, hypothesis: str) -> tuple[int, int]:
    reference_tokens = tokenize(reference)
    hypothesis_tokens = tokenize(hypothesis)
    return align(reference_tokens, hypothesis_tokens).distance, len(reference_tokens)


def exact_send(reference: str, hypothesis: str) -> bool:
    """Use only Unicode and whitespace normalization: punctuation/case edits still count."""
    def sendable(text: str) -> str:
        return " ".join(unicodedata.normalize("NFKC", text).split())

    return sendable(reference) == sendable(hypothesis)


def formatting_signature(text: str) -> tuple[str, ...]:
    """Describe paragraphs and bullet rows without scoring their wording twice."""
    normalized = unicodedata.normalize("NFKC", text).replace("\r\n", "\n").replace("\r", "\n")
    signature: list[str] = []
    pending_paragraph_break = False
    for raw_line in normalized.split("\n"):
        line = raw_line.strip()
        if not line:
            if signature:
                pending_paragraph_break = True
            continue
        if pending_paragraph_break and signature and signature[-1] != "paragraph-break":
            signature.append("paragraph-break")
        signature.append("bullet" if BULLET_PATTERN.match(line) else "prose")
        pending_paragraph_break = False
    return tuple(signature)


def formatting_decisions(reference: str, hypothesis: str) -> tuple[bool, bool, bool]:
    """Score overall structure plus list and paragraph decisions independently."""
    reference_signature = formatting_signature(reference)
    hypothesis_signature = formatting_signature(hypothesis)
    list_correct = reference_signature.count("bullet") == hypothesis_signature.count("bullet")
    paragraphs_correct = (
        reference_signature.count("paragraph-break")
        == hypothesis_signature.count("paragraph-break")
    )
    return reference_signature == hypothesis_signature, list_correct, paragraphs_correct


def preserves_roman_script(reference: str, hypothesis: str) -> bool:
    """Flag output script drift without ever transliterating the human reference."""
    return bool(DEVANAGARI_PATTERN.search(reference)) or not DEVANAGARI_PATTERN.search(hypothesis)


def entity_accuracy(entities: Sequence[str], hypothesis: str) -> tuple[int, int]:
    """Match entities as contiguous normalized token sequences."""
    hypothesis_tokens = tokenize(hypothesis)
    correct = 0
    for entity in entities:
        entity_tokens = tokenize(entity)
        if entity_tokens and any(
            hypothesis_tokens[index : index + len(entity_tokens)] == entity_tokens
            for index in range(len(hypothesis_tokens) - len(entity_tokens) + 1)
        ):
            correct += 1
    return correct, len(entities)


def switch_boundary_accuracy(
    reference: str, hypothesis: str, switch_indexes: Sequence[int]
) -> tuple[int, int]:
    """Score an annotated boundary only when its two neighboring words are correct."""
    reference_tokens = tokenize(reference)
    hypothesis_tokens = tokenize(hypothesis)
    alignment = align(reference_tokens, hypothesis_tokens)
    correct = 0
    for boundary in switch_indexes:
        left = boundary - 1
        right = boundary
        if left < 0 or right >= len(reference_tokens):
            continue
        left_hypothesis = alignment.reference_to_hypothesis[left]
        right_hypothesis = alignment.reference_to_hypothesis[right]
        if (
            left_hypothesis is not None
            and right_hypothesis is not None
            and right_hypothesis == left_hypothesis + 1
            and reference_tokens[left] == hypothesis_tokens[left_hypothesis]
            and reference_tokens[right] == hypothesis_tokens[right_hypothesis]
        ):
            correct += 1
    return correct, len(switch_indexes)
