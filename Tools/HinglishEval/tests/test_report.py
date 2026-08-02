import unittest
from pathlib import Path

from hinglish_eval.models import ManifestItem, PipelineResult
from hinglish_eval.report import baseline_rows, build_report, markdown, score_item


class ReportTests(unittest.TestCase):
    def row(self, item_id: str, final: str, category: str = "whatsapp-casual"):
        item = ManifestItem(
            id=item_id,
            file=Path("clip.wav"),
            reference="kal meeting hai",
            source="private-holdout",
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
        self.assertIn("Raw WER", markdown(report))

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

    def test_private_gate_strictly_beats_matched_baselines(self) -> None:
        item = ManifestItem(
            id="private-1",
            file=Path("clip.wav"),
            reference="kal meeting hai",
            source="private-holdout",
            category="work-message",
            noise="clean",
            baseline_gboard="kal meeting he",
            baseline_apple="kal meeting hai",
        )
        yap = score_item(
            item,
            PipelineResult("kal meeting hai", "kal meeting hai", 100, 50, 150, "sarvam"),
            provider="sarvam",
        )
        report = build_report(
            {"runId": "test", "startedAt": "now", "manifestSha256": "abc", "git": {}},
            [yap, *baseline_rows([item])],
        )
        self.assertTrue(report["shipGate"]["eligible"])
        self.assertFalse(report["shipGate"]["passed"], "a tie must not pass")

        better_item = ManifestItem(
            **{
                **item.__dict__,
                "baseline_apple": "kal meeting he",
            }
        )
        better_report = build_report(
            {"runId": "test", "startedAt": "now", "manifestSha256": "abc", "git": {}},
            [
                score_item(
                    better_item,
                    PipelineResult("kal meeting hai", "kal meeting hai", 1, 1, 2, "sarvam"),
                    provider="sarvam",
                ),
                *baseline_rows([better_item]),
            ],
        )
        self.assertTrue(better_report["shipGate"]["passed"])

    def test_private_gate_rejects_partial_baseline_coverage(self) -> None:
        row = self.row("private-1", "kal meeting hai")
        report = build_report(
            {"runId": "test", "startedAt": "now", "manifestSha256": "abc", "git": {}},
            [row],
        )
        self.assertFalse(report["shipGate"]["eligible"])

    def test_private_section_precedes_mucs_appendix(self) -> None:
        report = build_report(
            {"runId": "test", "startedAt": "now", "manifestSha256": "abc", "git": {}},
            [self.row("private-1", "kal meeting hai")],
        )
        rendered = markdown(report)
        self.assertLess(
            rendered.index("Private holdout — headline"),
            rendered.index("MUCS regression appendix"),
        )


if __name__ == "__main__":
    unittest.main()
