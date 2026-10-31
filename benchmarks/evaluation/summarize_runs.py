"""Summarize apps/spike result files into the rows of benchmarks/results/TEMPLATE.md.

Usage: python3 summarize_runs.py --output summary.json results/*.json
"""

import argparse
import json
import sys
from pathlib import Path
from statistics import median


def _median(values):
    present = [v for v in values if v is not None]
    return median(present) if present else None


def _peak(values):
    present = [v for v in values if v is not None]
    return max(present) if present else None


def _llm_rows(records):
    groups = {}
    for record in records:
        for run in record["runs"]:
            if run["warmup"]:
                continue
            key = (record["device"]["label"], record["config"]["llm"]["modelId"],
                   record["model"]["requestedBackend"], run["caseId"])
            groups.setdefault(key, []).append((record, run))
    rows = []
    for (device, model, backend, case), items in sorted(groups.items()):
        runs = [r for _, r in items]
        rows.append({
            "device": device,
            "model": model,
            "backend": backend,
            "activeBackend": items[0][0]["model"]["activeBackend"],
            "promptSetVersion": items[0][0]["promptSetVersion"],
            "caseId": case,
            "runs": len(runs),
            "medianLoadMs": _median(rec["model"]["loadMs"] for rec, _ in items),
            "medianTimeToFirstTokenMs": _median(r["timeToFirstTokenMs"] for r in runs),
            "medianDecodeTokensPerSecond": _median(r["decodeTokensPerSecond"] for r in runs),
            "medianEndToEndMs": _median(r["endToEndMs"] for r in runs),
            "peakAnonymousBytes": _peak(r["memory"]["sampledMaxAnonymousBytes"] for r in runs),
            "peakFileBackedBytes": _peak(r["memory"]["sampledMaxFileBackedBytes"] for r in runs),
            "peakMaxRssBytes": _peak(r["memory"]["maxRssBytes"] for r in runs),
        })
    return rows


def _asr_rows(records):
    groups = {}
    for record in records:
        asr = record["config"]["asr"]
        for result in record["results"]:
            key = (record["device"]["label"], asr["modelId"], asr["engine"],
                   record["model"]["requestedBackend"], result["language"])
            groups.setdefault(key, []).append(result)
    return [
        {
            "device": device,
            "model": model,
            "engine": engine,
            "backend": backend,
            "language": language,
            "files": len(results),
            "audioSeconds": sum(r["audioSeconds"] for r in results),
            "realTimeFactor": sum(r["elapsedMs"] for r in results) / 1000
            / sum(r["audioSeconds"] for r in results),
            "peakAnonymousBytes": _peak(r["memory"]["sampledMaxAnonymousBytes"] for r in results),
            "peakMaxRssBytes": _peak(r["memory"]["maxRssBytes"] for r in results),
        }
        for (device, model, engine, backend, language), results in sorted(groups.items())
    ]


def summarize(records):
    return {
        "llm": _llm_rows([r for r in records if r["mode"] == "llm"]),
        "asr": _asr_rows([r for r in records if r["mode"] == "asr"]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("records", type=Path, nargs="+")
    args = parser.parse_args()
    records = [json.loads(p.read_text("utf-8")) for p in args.records if p.suffix == ".json"]
    summary = summarize(records)
    args.output.write_text(json.dumps(summary, indent=2) + "\n", "utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
