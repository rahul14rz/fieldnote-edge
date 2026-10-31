# Dataset sources

This file lists every dataset the evaluation may use, with its license and where the license was read. Licenses were checked on 2026-10-31 and, for Hugging Face entries, again on 2026-11-01. **unverified** means the license page could not be read from the session that wrote this file (see [findings](../../docs/spike/findings.md)), so the dataset can't be used until someone reads its license and updates this row.

## Rules

- The published evaluation set contains no real client meetings or customer visits. Recordings of real meetings stay on the user's own devices. They never go into this repository or into published results.
- Meeting-style audio comes from scripted recordings that the user makes and owns (see below).
- Public speech datasets are used only for ASR word and character error rates.
- Raw audio is not committed. Put local copies under `benchmarks/datasets/local/`, which git ignores.

## Scripted recordings (planned, not recorded yet)

| Item | Owner | License | Status |
| --- | --- | --- | --- |
| Scripted meeting and visit recordings in `en`, `ta`, `ml`, `hi`, `ta-en`, `ml-en`, `hi-en`, read from fictional scripts | The user (Rahul M) | To be chosen by the owner before publishing. Every speaker must give written consent to publication. | not recorded yet |

The fictional transcripts in `apps/spike/assets/prompt_set.json` can serve as starting scripts. Record each script as 16 kHz mono 16-bit WAV, and write the reference transcript exactly as spoken.

## Public speech datasets (candidates)

| Dataset | Languages relevant here | License | Where the license was read | Notes |
| --- | --- | --- | --- | --- |
| Google FLEURS | `en` (`en_us`), `ta` (`ta_in`), `ml` (`ml_in`), `hi` (`hi_in`) | CC BY 4.0 (`cc-by-4.0`) | [Dataset card](https://huggingface.co/datasets/google/fleurs), read 2026-11-01 | Read speech, not conversational. Not gated. |
| Mozilla Common Voice | `ta`, `ml`, `hi`, `en` (unverified) | **unverified** | The [Hugging Face page](https://huggingface.co/datasets/mozilla-foundation/common_voice_17_0) says that since October 2025 the datasets are available only through Mozilla Data Collective, which this session could not reach | Read the terms on Mozilla Data Collective before use, including any rule on speaker re-identification. |
| AI4Bharat IndicVoices | `ta`, `ml`, `hi` (unverified) | CC BY 4.0 (`cc-by-4.0`) | [Hugging Face API](https://huggingface.co/api/datasets/ai4bharat/IndicVoices) `cardData.license`, read 2026-11-01 | Gated: you must accept the terms on Hugging Face. |
| AI4Bharat Kathbath | `ta`, `ml`, `hi` | CC BY 4.0 (`cc-by-4.0`) | [Hugging Face API](https://huggingface.co/api/datasets/ai4bharat/Kathbath) `cardData.license`, read 2026-11-01 | Gated. Used in the Vistaar benchmark. |
| AI4Bharat Svarah | Indian-accented English | **unverified**. No license is stated in the [Svarah README](https://github.com/AI4Bharat/Svarah), and the gated Hugging Face copy has no license tag. | https://github.com/AI4Bharat/Svarah and https://huggingface.co/api/datasets/ai4bharat/Svarah | |
| MUCS 2021 (Hindi-English code-switching) | `hi-en` | **unverified** | https://navana-tech.github.io/MUCS2021/ could not be reached | Candidate for `hi-en`. |
| OpenSLR SLR65 (Tamil), SLR63 (Malayalam) | `ta`, `ml` | **unverified** | https://www.openslr.org/65/ and https://www.openslr.org/63/ could not be reached | Read speech. |

No public Tamil-English or Malayalam-English code-switched speech dataset has been found yet. Hugging Face became reachable on 2026-11-01 but has not been searched for one, and OpenSLR is still unreachable. Until one is found and its license is read, `ta-en` and `ml-en` rely on the scripted recordings.
