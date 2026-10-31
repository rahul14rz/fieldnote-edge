import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from summarize_runs import summarize

EVAL_DIR = Path(__file__).resolve().parent.parent


def llm_record(device="OnePlus 11R", backend="gpu", runs=()):
    return {
        "schemaVersion": 1,
        "runId": "r",
        "mode": "llm",
        "device": {"label": device},
        "config": {"llm": {"modelId": "gemma-4-E2B-it"}},
        "model": {"requestedBackend": backend, "activeBackend": backend, "loadMs": 900.0,
                  "memoryAfterLoad": {"anonymousBytes": 100, "fileBackedBytes": 10, "maxRssBytes": 200}},
        "promptSetVersion": "v1",
        "runs": list(runs),
    }


def run(case, rep, ttft, tps, e2e, warmup=False, anon=100, rss=200):
    return {"caseId": case, "repetition": rep, "warmup": warmup, "timeToFirstTokenMs": ttft,
            "decodeTokensPerSecond": tps, "endToEndMs": e2e, "outputTokens": 10,
            "memory": {"sampledMaxAnonymousBytes": anon, "sampledMaxFileBackedBytes": 5,
                       "anonymousPeakBytes": None, "maxRssBytes": rss, "samples": 3}}


class SummarizeLlm(unittest.TestCase):
    def test_medians_exclude_warmup_and_peaks_take_the_maximum(self):
        record = llm_record(runs=[
            run("en-short", 1, 9999, 1, 9999, warmup=True, anon=99999),
            run("en-short", 1, 300, 20, 1000, anon=150),
            run("en-short", 2, 100, 10, 800, anon=400, rss=900),
            run("en-short", 3, 200, 30, 1200, anon=120),
        ])

        [row] = summarize([record])["llm"]

        self.assertEqual(row["runs"], 3)
        self.assertEqual(row["medianTimeToFirstTokenMs"], 200)
        self.assertEqual(row["medianDecodeTokensPerSecond"], 20)
        self.assertEqual(row["medianEndToEndMs"], 1000)
        self.assertEqual(row["peakAnonymousBytes"], 400)
        self.assertEqual(row["peakMaxRssBytes"], 900)

    def test_rows_are_split_by_device_backend_and_case(self):
        records = [
            llm_record(backend="gpu", runs=[run("en-short", 1, 1, 1, 1), run("en-long", 1, 1, 1, 1)]),
            llm_record(backend="cpu", runs=[run("en-short", 1, 1, 1, 1)]),
        ]

        keys = [(r["backend"], r["caseId"]) for r in summarize(records)["llm"]]

        self.assertEqual(keys, [("cpu", "en-short"), ("gpu", "en-long"), ("gpu", "en-short")])

    def test_a_run_with_no_output_has_no_median_rather_than_zero(self):
        [row] = summarize([llm_record(runs=[run("en-short", 1, None, None, 50)])])["llm"]

        self.assertIsNone(row["medianTimeToFirstTokenMs"])


class SummarizeAsr(unittest.TestCase):
    def test_real_time_factor_is_pooled_per_language(self):
        record = {
            "schemaVersion": 1, "mode": "asr", "device": {"label": "OnePlus 11R"},
            "config": {"asr": {"modelId": "whisper-base", "engine": "whisper"}},
            "model": {"requestedBackend": "cpu", "activeBackend": None},
            "results": [
                {"id": "a", "language": "ta", "audioSeconds": 10.0, "elapsedMs": 5000.0,
                 "memory": {"sampledMaxAnonymousBytes": 7, "maxRssBytes": 8}},
                {"id": "b", "language": "ta", "audioSeconds": 30.0, "elapsedMs": 9000.0,
                 "memory": {"sampledMaxAnonymousBytes": 9, "maxRssBytes": 6}},
            ],
        }

        [row] = summarize([record])["asr"]

        self.assertEqual(row["language"], "ta")
        self.assertAlmostEqual(row["realTimeFactor"], 14 / 40)
        self.assertEqual(row["peakAnonymousBytes"], 9)


class MatchesResultsSchema(unittest.TestCase):
    """Every summary row carries exactly the fields results.schema.json requires or allows."""

    def test_rows_fit_the_schema(self):
        schema = json.loads((EVAL_DIR.parent / "results" / "results.schema.json").read_text())
        llm = llm_record(runs=[run("en-short", 1, 1, 1, 1)])
        asr = {"mode": "asr", "device": {"label": "d"}, "config": {"asr": {"modelId": "m", "engine": "whisper"}},
               "model": {"requestedBackend": "cpu", "activeBackend": None},
               "results": [{"language": "ta", "audioSeconds": 1.0, "elapsedMs": 1.0, "memory": {"sampledMaxAnonymousBytes": None, "maxRssBytes": 1}}]}
        summary = summarize([llm, asr])
        for section in ("llm", "asr"):
            item = schema["properties"][section]["items"]
            row = summary[section][0]
            self.assertLessEqual(set(item["required"]), set(row), section)
            self.assertLessEqual(set(row), set(item["properties"]), section)


class CommandLine(unittest.TestCase):
    def test_reads_result_files_and_writes_the_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "r1.json").write_text(json.dumps(llm_record(runs=[run("en-short", 1, 5, 6, 7)])))
            Path(tmp, "r1.hypotheses.jsonl").write_text('{"id": "x", "text": "ignored"}\n')
            out = Path(tmp, "summary.json")
            proc = subprocess.run(
                [sys.executable, "summarize_runs.py", "--output", str(out), str(Path(tmp, "r1.json"))],
                cwd=EVAL_DIR, capture_output=True, text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(json.loads(out.read_text())["llm"][0]["medianEndToEndMs"], 7)


if __name__ == "__main__":
    unittest.main()
