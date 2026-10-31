import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from asr_eval import score_corpus, score_pair

EVAL_DIR = Path(__file__).resolve().parent.parent


class PairScores(unittest.TestCase):
    def test_substitution_and_deletion_count_against_reference_length(self):
        result = score_pair("a b c d", "a x c")
        self.assertEqual(result.reference_words, 4)
        self.assertEqual(result.word_errors, 2)

    def test_insertions_count(self):
        self.assertEqual(score_pair("a b", "a b c").word_errors, 1)

    def test_identical_text_has_no_errors(self):
        result = score_pair("send the quote by friday", "Send the quote by Friday.")
        self.assertEqual((result.word_errors, result.char_errors), (0, 0))


class CorpusScores(unittest.TestCase):
    def test_rates_are_pooled_per_language(self):
        references = [
            {"id": "1", "language": "en", "text": "a b c d"},
            {"id": "2", "language": "en", "text": "e f"},
            {"id": "3", "language": "ta", "text": "காலை வணக்கம்"},
        ]
        hypotheses = [
            {"id": "1", "text": "a b c d"},
            {"id": "2", "text": "e"},
            {"id": "3", "text": "கலை வணக்கம்"},
        ]
        report = score_corpus(references, hypotheses)
        self.assertAlmostEqual(report["en"]["wer"], 1 / 6)
        self.assertEqual(report["en"]["utterances"], 2)
        self.assertAlmostEqual(report["ta"]["wer"], 1 / 2)

    def test_missing_hypothesis_is_rejected(self):
        with self.assertRaises(ValueError) as caught:
            score_corpus([{"id": "1", "language": "en", "text": "a"}], [])
        self.assertIn("1", str(caught.exception))

    def test_unknown_language_is_rejected(self):
        with self.assertRaises(ValueError):
            score_corpus(
                [{"id": "1", "language": "fr", "text": "a"}], [{"id": "1", "text": "a"}]
            )


class CommandLine(unittest.TestCase):
    def run_cli(self, references, hypotheses):
        with tempfile.TemporaryDirectory() as tmp:
            refs = Path(tmp, "refs.jsonl")
            hyps = Path(tmp, "hyps.jsonl")
            out = Path(tmp, "report.json")
            refs.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in references), "utf-8")
            hyps.write_text("\n".join(json.dumps(h, ensure_ascii=False) for h in hypotheses), "utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "asr_eval", "--references", str(refs),
                 "--hypotheses", str(hyps), "--output", str(out)],
                cwd=EVAL_DIR, capture_output=True, text=True,
            )
            report = json.loads(out.read_text("utf-8")) if out.exists() else None
            return proc, report

    def test_writes_a_per_language_report(self):
        proc, report = self.run_cli(
            [{"id": "1", "language": "hi-en", "text": "कल meeting है"}],
            [{"id": "1", "text": "कल meeting हैं"}],
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertAlmostEqual(report["languages"]["hi-en"]["wer"], 1 / 3)
        self.assertEqual(report["normalizer"], "fieldnote-v1")

    def test_exits_2_without_writing_when_input_is_invalid(self):
        proc, report = self.run_cli([{"id": "1", "language": "en", "text": "a"}], [])
        self.assertEqual(proc.returncode, 2)
        self.assertIsNone(report)


if __name__ == "__main__":
    unittest.main()
