import unittest

from hinglish_eval.metrics import (
    entity_accuracy,
    error_rate,
    exact_send,
    formatting_decisions,
    formatting_signature,
    normalize_text,
    preserves_roman_script,
    switch_boundary_accuracy,
    tokenize,
)


class MetricsTests(unittest.TestCase):
    def test_normalization_preserves_roman_hinglish_words(self) -> None:
        self.assertEqual(normalize_text("Kal aaoge, right?"), "kal aaoge right")
        self.assertEqual(tokenize("Sharma ji’s flat"), ["sharma", "ji's", "flat"])

    def test_word_error_rate_counts_edits(self) -> None:
        self.assertAlmostEqual(error_rate("kal office jaana hai", "kal office jana hai"), 0.25)
        self.assertAlmostEqual(error_rate("kal office jaana hai", "kal jaana hai"), 0.25)
        self.assertAlmostEqual(error_rate("kal jaana hai", "kal definitely jaana hai"), 1 / 3)

    def test_exact_send_only_ignores_whitespace_and_unicode_representation(self) -> None:
        self.assertTrue(exact_send("Kal  aaoge?", "Kal aaoge?"))
        self.assertFalse(exact_send("Kal aaoge?", "kal aaoge"))
        self.assertFalse(exact_send("Kal aaoge?", "Kal aaoge"))
        self.assertFalse(exact_send("Kal aaoge?", "kal aoge"))

    def test_entities_match_contiguous_tokens(self) -> None:
        self.assertEqual(
            entity_accuracy(["Rachit", "Hauz Khas", "YAP"], "rachit ko Hauz Khas mein YAP dikhaya"),
            (3, 3),
        )
        self.assertEqual(entity_accuracy(["Hauz Khas"], "Hauz mein Khas jagah"), (0, 1))

    def test_formatting_signature_tracks_bullets_and_paragraphs(self) -> None:
        text = "three things:\n- deck\n- call Ritika\n\nfinish by friday"
        self.assertEqual(
            formatting_signature(text),
            ("prose", "bullet", "bullet", "paragraph-break", "prose"),
        )

    def test_formatting_decisions_reject_false_list_and_paragraph_changes(self) -> None:
        reference = "kal teen cheezein:\n- deck\n- call Ritika"
        self.assertEqual(formatting_decisions(reference, reference), (True, True, True))
        self.assertEqual(
            formatting_decisions(reference, "kal teen cheezein: deck aur call Ritika"),
            (False, False, True),
        )
        self.assertEqual(
            formatting_decisions("kal aana\n\nphir baat karenge", "kal aana phir baat karenge"),
            (False, True, False),
        )

    def test_switch_boundary_requires_both_adjacent_words(self) -> None:
        reference = "kal meeting cancel kar do"
        self.assertEqual(switch_boundary_accuracy(reference, reference, [1, 3]), (2, 2))
        self.assertEqual(
            switch_boundary_accuracy(reference, "kal meeting postpone kar do", [1, 3]),
            (1, 2),
        )

    def test_script_preservation_detects_devanagari_drift(self) -> None:
        self.assertTrue(preserves_roman_script("kal meeting hai", "Kal meeting hai."))
        self.assertFalse(preserves_roman_script("kal meeting hai", "कल meeting hai"))


if __name__ == "__main__":
    unittest.main()
