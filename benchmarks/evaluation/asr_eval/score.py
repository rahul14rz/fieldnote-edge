from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass

from asr_eval.normalize import normalize

LANGUAGES = ("en", "ta", "ml", "hi", "ta-en", "ml-en", "hi-en")


@dataclass(frozen=True)
class PairScore:
    reference_words: int
    word_errors: int
    reference_chars: int
    char_errors: int


def edit_distance(reference: Sequence[str], hypothesis: Sequence[str]) -> int:
    previous = list(range(len(hypothesis) + 1))
    for i, ref_item in enumerate(reference, start=1):
        current = [i]
        for j, hyp_item in enumerate(hypothesis, start=1):
            current.append(
                min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (ref_item != hyp_item),
                )
            )
        previous = current
    return previous[-1]


def score_pair(reference: str, hypothesis: str) -> PairScore:
    ref, hyp = normalize(reference), normalize(hypothesis)
    return PairScore(
        reference_words=len(ref.split()),
        word_errors=edit_distance(ref.split(), hyp.split()),
        reference_chars=len(ref),
        char_errors=edit_distance(ref, hyp),
    )


def score_corpus(
    references: Iterable[Mapping[str, str]], hypotheses: Iterable[Mapping[str, str]]
) -> dict[str, dict[str, float | int]]:
    hypothesis_by_id = {h["id"]: h["text"] for h in hypotheses}
    references = list(references)

    missing = [r["id"] for r in references if r["id"] not in hypothesis_by_id]
    if missing:
        raise ValueError(f"no hypothesis for reference ids: {', '.join(missing)}")
    unknown = sorted({r["language"] for r in references} - set(LANGUAGES))
    if unknown:
        raise ValueError(f"unknown language codes {unknown}; expected one of {LANGUAGES}")

    totals: dict[str, list[int]] = {}
    for ref in references:
        pair = score_pair(ref["text"], hypothesis_by_id[ref["id"]])
        t = totals.setdefault(ref["language"], [0, 0, 0, 0, 0])
        t[0] += 1
        t[1] += pair.reference_words
        t[2] += pair.word_errors
        t[3] += pair.reference_chars
        t[4] += pair.char_errors

    return {
        language: {
            "utterances": n,
            "reference_words": words,
            "word_errors": word_errors,
            "wer": word_errors / words if words else 0.0,
            "reference_chars": chars,
            "char_errors": char_errors,
            "cer": char_errors / chars if chars else 0.0,
        }
        for language, (n, words, word_errors, chars, char_errors) in sorted(totals.items())
    }
