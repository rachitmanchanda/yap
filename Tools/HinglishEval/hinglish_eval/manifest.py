"""Manifest loading and strict human-reference validation."""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path
from typing import Any

from .metrics import tokenize
from .models import ManifestItem, SUPPORTED_CATEGORIES, SUPPORTED_NOISE_TAGS


DEVANAGARI_PATTERN = re.compile(r"[\u0900-\u097f]")
SAFE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class ManifestValidationError(ValueError):
    def __init__(self, errors: list[str]) -> None:
        super().__init__("\n".join(errors))
        self.errors = errors


def _items_from_document(document: Any) -> list[dict[str, Any]]:
    if isinstance(document, list):
        return document
    if isinstance(document, dict) and isinstance(document.get("items"), list):
        return document["items"]
    raise ManifestValidationError(["manifest must be an array or an object containing an 'items' array"])


def load_manifest(path: Path, *, require_audio: bool = True) -> list[ManifestItem]:
    try:
        if path.suffix.casefold() == ".csv":
            with path.open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            for row in rows:
                for field in ("entities", "switchIndexes"):
                    raw = row.get(field) or ""
                    row[field] = json.loads(raw) if raw.strip() else []
        else:
            document = json.loads(path.read_text(encoding="utf-8"))
            rows = _items_from_document(document)
    except (OSError, csv.Error, json.JSONDecodeError) as error:
        raise ManifestValidationError([f"could not read manifest: {error}"]) from error
    errors: list[str] = []
    seen_ids: set[str] = set()
    items: list[ManifestItem] = []
    for index, row in enumerate(rows):
        label = f"item {index + 1}"
        if not isinstance(row, dict):
            errors.append(f"{label}: must be an object")
            continue
        item_id = str(row.get("id", "")).strip()
        reference = str(row.get("reference", "")).strip()
        source = str(row.get("source", "")).strip()
        category = str(row.get("category", "")).strip()
        noise = str(row.get("noise", "")).strip()
        file_value = str(row.get("file", "")).strip()
        entities_value = row.get("entities", [])
        switches_value = row.get("switchIndexes", [])

        if not SAFE_ID_PATTERN.fullmatch(item_id):
            errors.append(f"{label}: id must use letters, numbers, '.', '_' or '-'")
        elif item_id in seen_ids:
            errors.append(f"{label}: duplicate id '{item_id}'")
        seen_ids.add(item_id)
        if not reference:
            errors.append(f"{label} ({item_id or 'missing id'}): reference is required and must be human-written")
        elif DEVANAGARI_PATTERN.search(reference):
            errors.append(
                f"{label} ({item_id}): reference contains Devanagari; write the sendable Roman Hinglish reference manually"
            )
        if not source:
            errors.append(f"{label} ({item_id}): source is required")
        if category not in SUPPORTED_CATEGORIES:
            errors.append(f"{label} ({item_id}): unsupported category '{category}'")
        if noise not in SUPPORTED_NOISE_TAGS:
            errors.append(f"{label} ({item_id}): noise must be clean or noisy")

        resolved_file = (path.parent / file_value).resolve() if file_value else path.parent
        if require_audio and (not file_value or not resolved_file.is_file() or resolved_file.stat().st_size == 0):
            errors.append(f"{label} ({item_id}): audio file is missing or empty: {file_value or '<missing>'}")

        if not isinstance(entities_value, list) or any(
            not isinstance(entity, str) or not entity.strip() for entity in entities_value
        ):
            errors.append(f"{label} ({item_id}): entities must be an array of non-empty strings")
            entities: tuple[str, ...] = ()
        else:
            entities = tuple(entity.strip() for entity in entities_value)

        token_count = len(tokenize(reference))
        if not isinstance(switches_value, list) or any(
            not isinstance(switch, int) or isinstance(switch, bool) or switch < 1 or switch >= token_count
            for switch in switches_value
        ):
            errors.append(
                f"{label} ({item_id}): switchIndexes must be integer boundaries from 1 through {max(token_count - 1, 0)}"
            )
            switches: tuple[int, ...] = ()
        else:
            switches = tuple(switches_value)

        known_keys = {
            "id", "file", "reference", "source", "category", "noise",
            "entities", "switchIndexes", "datasetTranscript",
        }
        metadata = {key: value for key, value in row.items() if key not in known_keys}
        items.append(
            ManifestItem(
                id=item_id,
                file=resolved_file,
                reference=reference,
                source=source,
                category=category,
                noise=noise,
                entities=entities,
                switch_indexes=switches,
                dataset_transcript=row.get("datasetTranscript"),
                metadata=metadata,
            )
        )
    if errors:
        raise ManifestValidationError(errors)
    return sorted(items, key=lambda item: item.id)
