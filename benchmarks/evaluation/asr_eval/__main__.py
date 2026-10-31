import argparse
import json
import sys
from pathlib import Path

from asr_eval.normalize import NORMALIZER_ID
from asr_eval.score import score_corpus


def read_jsonl(path: Path) -> list[dict]:
    lines = path.read_text("utf-8").splitlines()
    return [json.loads(line) for line in lines if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description="Per-language WER and CER for ASR output.")
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--hypotheses", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    try:
        languages = score_corpus(read_jsonl(args.references), read_jsonl(args.hypotheses))
    except (ValueError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    report = {"normalizer": NORMALIZER_ID, "languages": languages}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
