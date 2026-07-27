import csv
import json
import tempfile
import unittest
from pathlib import Path

from hinglish_eval.manifest import ManifestValidationError, load_manifest


class ManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "real.wav").write_bytes(b"RIFF-real-recording-placeholder")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write(self, items: list[dict]) -> Path:
        path = self.root / "manifest.json"
        path.write_text(json.dumps({"items": items}), encoding="utf-8")
        return path

    def valid_row(self) -> dict:
        return {
            "id": "clip-1",
            "file": "real.wav",
            "reference": "kal Rachit ke saath meeting hai",
            "source": "human-holdout",
            "category": "work-message",
            "noise": "clean",
            "entities": ["Rachit"],
            "switchIndexes": [3],
        }

    def test_loads_valid_manifest(self) -> None:
        items = load_manifest(self.write([self.valid_row()]))
        self.assertEqual(items[0].id, "clip-1")
        self.assertEqual(items[0].entities, ("Rachit",))

    def test_loads_csv_manifest_with_json_annotation_columns(self) -> None:
        path = self.root / "manifest.csv"
        row = self.valid_row()
        row["entities"] = json.dumps(row["entities"])
        row["switchIndexes"] = json.dumps(row["switchIndexes"])
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=row.keys())
            writer.writeheader()
            writer.writerow(row)
        items = load_manifest(path)
        self.assertEqual(items[0].switch_indexes, (3,))

    def test_rejects_native_script_reference(self) -> None:
        row = self.valid_row()
        row["reference"] = "kal मीटिंग hai"
        with self.assertRaisesRegex(ManifestValidationError, "contains Devanagari"):
            load_manifest(self.write([row]))

    def test_rejects_missing_audio_and_reference(self) -> None:
        row = self.valid_row()
        row["file"] = "missing.wav"
        row["reference"] = ""
        with self.assertRaises(ManifestValidationError) as caught:
            load_manifest(self.write([row]))
        self.assertIn("reference is required", str(caught.exception))
        self.assertIn("audio file is missing", str(caught.exception))

    def test_rejects_duplicate_id_and_bad_switch(self) -> None:
        first = self.valid_row()
        second = self.valid_row()
        second["switchIndexes"] = [99]
        with self.assertRaises(ManifestValidationError) as caught:
            load_manifest(self.write([first, second]))
        self.assertIn("duplicate id", str(caught.exception))
        self.assertIn("switchIndexes", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
