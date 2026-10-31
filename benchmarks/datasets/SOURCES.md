# Dataset sources

This file lists every dataset the evaluation may use, with its license and where the license was read. Licenses were checked on 2026-10-31. **unverified** means the license page could not be read from the session that wrote this file (see [findings](../../docs/spike/findings.md)), so the dataset can't be used until someone reads its license and updates this row.

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
| Google FLEURS | `en`, `ta`, `ml`, `hi` (unverified) | **unverified** | https://huggingface.co/datasets/google/fleurs could not be reached | Read speech, not conversational. |
| Mozilla Common Voice | `ta`, `ml`, `hi`, `en` (unverified) | **unverified** | https://commonvoice.mozilla.org/en/datasets could not be reached | Check the dataset terms on speaker re-identification before use. |
| AI4Bharat IndicVoices | `ta`, `ml`, `hi` (unverified) | **unverified** | https://huggingface.co/datasets/ai4bharat/IndicVoices could not be reached | Access may be gated (unverified). |
| AI4Bharat Kathbath | `ta`, `ml`, `hi` | **unverified** | https://huggingface.co/datasets/ai4bharat/kathbath could not be reached. The [Vistaar README](https://github.com/AI4Bharat/vistaar) links Kathbath downloads but states a license only for Vistaar's code and models. | Used in the Vistaar benchmark. |
| AI4Bharat Svarah | Indian-accented English | **unverified**. No license is stated in the [Svarah README](https://github.com/AI4Bharat/Svarah). | https://github.com/AI4Bharat/Svarah | The README links a Hugging Face copy that was not reachable. |
| MUCS 2021 (Hindi-English code-switching) | `hi-en` | **unverified** | https://navana-tech.github.io/MUCS2021/ could not be reached | Candidate for `hi-en`. |
| OpenSLR SLR65 (Tamil), SLR63 (Malayalam) | `ta`, `ml` | **unverified** | https://www.openslr.org/65/ and https://www.openslr.org/63/ could not be reached | Read speech. |

No public Tamil-English or Malayalam-English code-switched speech dataset was found in this check, because the places to search (Hugging Face, OpenSLR) were unreachable. Until one is found and its license is read, `ta-en` and `ml-en` rely on the scripted recordings.
