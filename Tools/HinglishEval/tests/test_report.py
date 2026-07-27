import unittest
from pathlib import Path

from hinglish_eval.models import ManifestItem, PipelineResult
from hinglish_eval.report import build_report, markdown, score_item


class ReportTests(unittest.TestCase):
    def row(self, item_id: str, final: str, category: str = "whatsapp-casual"):
        item = ManifestItem(
            id=item_id,
            file=Path("clip.wav"),
            reference="kal meeting hai",
            source="holdout",
            category=category,
            noise="clean",
            entities=("meeting",),
            switch_indexes=(1,),
        )
        return score_item(
            item,
            PipelineResult("kal meeting he", final, 100, 50, 150, "sarvam", "deepseek"),
        )

    def test_aggregates_and_orders_worst_failures_deterministically(self) -> None:
        rows = [
            self.row("good", "kal meeting hai"),
            self.row("bad-b", "totally wrong output"),
            self.row("bad-a", "totally wrong output"),
        ]
        report = build_report(
            {
                "runId": "test",
                "startedAt": "2026-07-27T00:00:00+00:00",
                "manifestSha256": "abc",
                "git": {},
            },
            rows,
        )
        self.assertAlmostEqual(report["overall"]["sendWithoutEditRate"], 1 / 3)
        self.assertEqual([row["id"] for row in report["worst20"][:2]], ["bad-a", "bad-b"])
        self.assertFalse(report["shipGate"]["eligible"])
        self.assertIn("Raw ASR WER", markdown(report))

    def test_failure_is_counted_without_breaking_aggregation(self) -> None:
        row = self.row("good", "kal meeting hai")
        failure = {
            "id": "failed",
            "source": "holdout",
            "category": "work-message",
            "noise": "noisy",
            "reference": "reference",
            "error": "timeout",
        }
        report = build_report(
            {
                "runId": "test",
                "startedAt": "now",
                "manifestSha256": "abc",
                "git": {},
            },
            [row, failure],
        )
        self.assertEqual(report["overall"]["failed"], 1)
        self.assertEqual(report["overall"]["successful"], 1)


if __name__ == "__main__":
    unittest.main()
