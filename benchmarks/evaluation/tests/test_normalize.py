import unicodedata
import unittest

from asr_eval import normalize, score_pair


class MatraPreservation(unittest.TestCase):
    """Vowel signs (matras) are letters of the word, not removable diacritics.

    Whisper's BasicTextNormalizer replaces every Unicode mark (category M*)
    with a space, which splits Tamil, Malayalam and Hindi words apart and
    hides real recognition errors.
    """

    def test_tamil_vowel_signs_survive(self):
        self.assertEqual(normalize("காலை வணக்கம்"), "காலை வணக்கம்")

    def test_malayalam_vowel_signs_survive(self):
        self.assertEqual(normalize("മീറ്റിംഗ് നാളെ"), "മീറ്റിംഗ് നാളെ")

    def test_hindi_vowel_signs_survive(self):
        self.assertEqual(normalize("कल मीटिंग है"), "कल मीटिंग है")

    def test_a_missing_matra_is_a_word_error(self):
        # காலை (morning) vs கலை (art): differ only by the vowel sign ா.
        result = score_pair("காலை", "கலை")
        self.assertEqual(result.word_errors, 1)
        self.assertEqual(result.char_errors, 1)

    def test_a_missing_virama_is_a_char_error(self):
        # The virama ् (U+094D, category Mn) joins consonants and must not be dropped.
        result = score_pair("क्या", "कया")
        self.assertEqual(result.char_errors, 1)


class Normalization(unittest.TestCase):
    def test_punctuation_and_case_are_removed(self):
        self.assertEqual(normalize("Hello, World!  Ok?"), "hello world ok")

    def test_canonically_equivalent_forms_score_as_equal(self):
        composed = "கொடு"
        decomposed = unicodedata.normalize("NFD", composed)
        self.assertNotEqual(composed, decomposed)
        self.assertEqual(score_pair(composed, decomposed).word_errors, 0)

    def test_zero_width_joiners_are_ignored(self):
        self.assertEqual(normalize("क‍र"), "कर")

    def test_code_switched_text_keeps_both_scripts(self):
        self.assertEqual(normalize("Budget review நாளை, OK?"), "budget review நாளை ok")


if __name__ == "__main__":
    unittest.main()
