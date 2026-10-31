"""Script-aware text normalization for WER and CER.

Combining marks (Unicode category M*) are kept. In Tamil, Malayalam and
Hindi they are vowel signs, viramas and anusvaras that change the word.
Whisper's BasicTextNormalizer replaces every M* character with a space:
https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/normalizers/basic.py#L55
"""

import re
import unicodedata

NORMALIZER_ID = "fieldnote-v1"

_INVISIBLE_FORMAT_CHARS = dict.fromkeys(map(ord, "​‌‍⁠﻿"))
_WHITESPACE = re.compile(r"\s+")


def _is_separator(char: str) -> bool:
    return unicodedata.category(char)[0] in "PSZ"


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFC", text).casefold()
    text = text.translate(_INVISIBLE_FORMAT_CHARS)
    text = "".join(" " if _is_separator(c) else c for c in text)
    return _WHITESPACE.sub(" ", text).strip()
