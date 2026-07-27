import hashlib
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from hinglish_eval.datasets import (
    download_verified,
    english_ratio,
    prepare_mucs,
    ratio_band,
    safe_extract_tar,
)


class DatasetTests(unittest.TestCase):
    def test_ratio_bands(self) -> None:
        self.assertEqual(ratio_band(english_ratio("आज घर जाना है meeting बाद में")), "low")
        self.assertEqual(ratio_band(english_ratio("आज meeting cancel करना")), "medium")
        self.assertEqual(ratio_band(english_ratio("meeting cancel today अभी")), "high")

    def test_verified_download_rejects_checksum_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.txt"
            source.write_text("licensed dataset", encoding="utf-8")
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            destination = root / "cache" / "dataset.txt"
            self.assertEqual(
                download_verified(source.as_uri(), destination, digest).read_text(),
                "licensed dataset",
            )
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                download_verified(source.as_uri(), destination, "0" * 64)

    def test_verified_download_resumes_partial_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "dataset.bin"
            partial = root / "dataset.bin.part"
            partial.write_bytes(b"abc")
            response = io.BytesIO(b"def")
            response.status = 206
            digest = hashlib.sha256(b"abcdef").hexdigest()

            def open_request(request, timeout):
                self.assertEqual(request.get_header("Range"), "bytes=3-")
                return response

            with mock.patch("urllib.request.urlopen", open_request):
                download_verified("https://example.invalid/dataset", destination, digest)
            self.assertEqual(destination.read_bytes(), b"abcdef")

    def test_tar_extraction_rejects_path_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "unsafe.tar"
            with tarfile.open(archive, "w") as package:
                info = tarfile.TarInfo("../escape.txt")
                payload = b"not allowed"
                info.size = len(payload)
                package.addfile(info, io.BytesIO(payload))
            with self.assertRaisesRegex(ValueError, "unsafe archive path"):
                safe_extract_tar(archive, root / "output")

    def test_mucs_sampling_is_deterministic_and_references_stay_empty(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio = root / "audio"
            audio.mkdir()
            transcripts = []
            examples = {
                "low": "आज घर जाना है meeting बाद में",
                "medium": "आज meeting cancel करना",
                "high": "meeting cancel today अभी",
            }
            for band, text in examples.items():
                (audio / f"{band}.wav").write_bytes(b"real corpus bytes")
                transcripts.append(f"{band} {text}")
            (root / "text").write_text("\n".join(transcripts), encoding="utf-8")
            first = root / "first.json"
            second = root / "second.json"
            prepare_mucs(root, first, sample_size=3, seed=7)
            prepare_mucs(root, second, sample_size=3, seed=7)
            first_document = json.loads(first.read_text())
            second_document = json.loads(second.read_text())
            self.assertEqual(
                [row["id"] for row in first_document["items"]],
                [row["id"] for row in second_document["items"]],
            )
            self.assertTrue(all(row["reference"] == "" for row in first_document["items"]))
            self.assertEqual(
                {row["englishRatioBand"] for row in first_document["items"]},
                {"low", "medium", "high"},
            )


if __name__ == "__main__":
    unittest.main()
