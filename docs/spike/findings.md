# Milestone 0 findings: packages, models and licenses

Package checks were done on 2026-10-31. Model and dataset licenses on Hugging Face and ai.google.dev were checked on 2026-11-01, after the environment's network access was widened. Every claim below names the source that was read. Where a source could not be reached, the claim is marked **unverified**.

On 2026-10-31 the session could not reach huggingface.co or ai.google.dev, so those facts were first marked unverified. They were read on 2026-11-01. openslr.org, commonvoice.mozilla.org, ai4bharat.iitm.ac.in and datacollective.mozillafoundation.org were still refused on 2026-11-01.

## Package versions and compatibility

Versions come from the pub.dev API (`https://pub.dev/api/packages/<name>`). Requirements come from each package's README and pubspec in the published archive for that version.

| Package | Latest version | Published (UTC) | Dart SDK | Flutter |
| --- | --- | --- | --- | --- |
| [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) | 2.5.4 | 2026-10-28 | `>=3.12.0 <4.0.0` | `>=3.44.0` |
| [`flutter_edge_ai_litertlm`](https://pub.dev/packages/flutter_edge_ai_litertlm) | 1.19.0 | 2026-10-28 | `>=3.12.0 <4.0.0` | `>=3.44.0` |
| [`flutter_edge_ai_speech`](https://pub.dev/packages/flutter_edge_ai_speech) | 0.5.12 | 2026-10-28 | `>=3.12.0 <4.0.0` | `>=3.44.0` |
| [`flutter_edge_ai_diagnostics`](https://pub.dev/packages/flutter_edge_ai_diagnostics) | 0.5.0 | 2026-10-25 | `>=3.12.0 <4.0.0` | `>=3.44.0` |

`flutter_edge_ai_litertlm` 1.19.0 depends on `flutter_edge_ai: ^2.5.4`. `flutter_edge_ai_speech` 0.5.12 depends on `flutter_edge_ai: ^2.3.0` and `flutter_edge_ai_litertlm: ^1.13.0`. `flutter_edge_ai_diagnostics` has no dependency on the other three. `apps/spike` resolves all four at the versions in the table with Flutter 3.47.9 (Dart 3.13.7), as recorded in `apps/spike/pubspec.lock`. `flutter build apk --release --target-platform android-arm64` succeeded on Linux with Android SDK platform 36. The APK has `minSdkVersion` 30 and contains `libLiteRtLm.so`, `libLiteRtOpenClAccelerator.so`, `libLiteRtTopKOpenClSampler.so` and `libGemmaModelConstraintProvider.so` for `arm64-v8a`. A build is not a run: whether the model loads on the OnePlus 11R is not yet measured. No macOS build was possible without a Mac.

### Requirements that were already known: confirmed

- **minSdk 30 and arm64-v8a only.** Confirmed. The `flutter_edge_ai` 2.5.4 README says: "Anything backed by LiteRT — `.litertlm`, LiteRT embeddings, speech — needs `minSdk 30` and is `arm64-v8a` only." The platform-setup reference in the package adds that on API 29 "the native library fails to load at runtime — the build does not catch it." `apps/spike` sets `minSdk = 30` and `abiFilters += listOf("arm64-v8a")`.
- **Upgrade all packages together.** Confirmed. The `flutter_edge_ai` README says: "Upgrade every flutter_edge_ai package together." The `flutter_edge_ai_litertlm` README tells you to run `flutter pub upgrade`, not `flutter pub upgrade flutter_edge_ai_litertlm`.

### Requirements found during this check

- **macOS needs a 14.0 deployment target and Apple Silicon.** The platform-setup reference in `flutter_edge_ai` 2.5.4 says: "Apple Silicon (`arm64`) only" and "The deployment target must be **macOS 14.0**." `apps/spike` sets `MACOSX_DEPLOYMENT_TARGET = 14.0`. The MacBook Air M4 is Apple Silicon.
- **The model file has to be loaded with the right file type.** `installModel` defaults to `ModelFileType.task`. A `.litertlm` file has to be installed with `fileType: ModelFileType.litertlm` (`flutter_edge_ai_litertlm` README).
- **`maxTokens` sets the context window, not the reply length.** On native `.litertlm` engines, values below 1024 are raised to 1024. The reply is capped with `maxOutputTokens` (inference skill bundled with `flutter_edge_ai`).
- **Audio longer than the model window is truncated without an error.** "Each model has a fixed window — 5 s for moonshine and Parakeet, 30 s for Whisper; shorter audio is zero-padded and longer audio is silently truncated" (`flutter_edge_ai_speech` README). Meeting recordings must therefore be split. `apps/spike` splits audio into 30-second windows.
- **Speech input must be raw 16 kHz mono 16-bit PCM.** "Not a WAV file, not 44.1 or 48 kHz: nothing resamples or converts it" (speech skill bundled with `flutter_edge_ai`). Gemma audio input is the opposite: it takes a whole WAV file, 16 kHz mono, header included (inference skill).

Sources:

- https://pub.dev/packages/flutter_edge_ai/versions/2.5.4
- https://pub.dev/packages/flutter_edge_ai_litertlm/versions/1.19.0
- https://pub.dev/packages/flutter_edge_ai_speech/versions/0.5.12
- https://pub.dev/packages/flutter_edge_ai_diagnostics/versions/0.5.0
- https://github.com/DenisovAV/flutter_edge_ai at commit `e68a8d39ad9d712c73dd3aa76305a2a726e306fd` (the `main` head on 2026-10-31)

## Package licenses

| Package | License on pub.dev (2026-10-31) | License file in the published archive | License file in the source repository |
| --- | --- | --- | --- |
| `flutter_edge_ai` | `license:mit` | MIT, "Copyright (c) 2024 Sasha Denisov" | [`LICENSE`](https://github.com/DenisovAV/flutter_edge_ai/blob/main/LICENSE): MIT |
| `flutter_edge_ai_litertlm` | `license:mit` | MIT. The archive also contains a `NOTICES` file (see below). | [`packages/flutter_edge_ai_litertlm/LICENSE`](https://github.com/DenisovAV/flutter_edge_ai/blob/main/packages/flutter_edge_ai_litertlm/LICENSE): MIT |
| `flutter_edge_ai_speech` | `license:mit` | MIT | [`packages/flutter_edge_ai_speech/LICENSE`](https://github.com/DenisovAV/flutter_edge_ai/blob/main/packages/flutter_edge_ai_speech/LICENSE): MIT |
| `flutter_edge_ai_diagnostics` | `license:mit` | MIT | [`packages/flutter_edge_ai_diagnostics/LICENSE`](https://github.com/DenisovAV/flutter_edge_ai/blob/main/packages/flutter_edge_ai_diagnostics/LICENSE): MIT |

The pub.dev license tags come from the package score API (`https://pub.dev/api/packages/<name>/score`).

**About the LiteRT engine.** Your earlier research saw the license of `flutter_edge_ai_litertlm` as unknown on pub.dev. On 2026-10-31, pub.dev tags version 1.19.0 as `license:mit`. Its `LICENSE` file in the archive and in the repository is the MIT text. The archive also has a `NOTICES` file. That file repeats the MIT notice for the Dart package, then lists "LiteRT" and "LiteRT-LM" under the Apache License, Version 2.0. So the Dart code is MIT, and the native LiteRT-LM libraries that the package bundles are Apache 2.0. Both licenses permit use in this project. An app that ships the libraries has to reproduce the Apache 2.0 notice. Which version showed "unknown" earlier could not be determined.

## Model licenses

| Model | License | Source read | Status |
| --- | --- | --- | --- |
| Gemma 4 E2B (`google/gemma-4-E2B-it`) | Apache 2.0 | [Model card](https://huggingface.co/google/gemma-4-E2B-it): `license: apache-2.0`, linking [the Gemma 4 license page](https://ai.google.dev/gemma/docs/gemma_4_license), which redirects to "Apache License 2.0" at https://ai.google.dev/gemma/apache_2 | verified 2026-11-01 |
| Gemma 4 E2B LiteRT build (`litert-community/gemma-4-E2B-it-litert-lm`) | Apache 2.0 | [Hugging Face API](https://huggingface.co/api/models/litert-community/gemma-4-E2B-it-litert-lm) `cardData.license`. Not gated. Files include `gemma-4-E2B-it.litertlm` and `gemma-4-E2B-it-gpu.litertlm`. | verified 2026-11-01 |
| Gemma 4 12B (`google/gemma-4-12B-it`, `litert-community/gemma-4-12B-it-litert-lm`) | Apache 2.0 | Hugging Face API `cardData.license` for both repositories. Neither is gated. | verified 2026-11-01. See [the larger model for the Mac](#the-larger-model-for-the-mac). |
| Whisper (OpenAI checkpoints) | MIT, code and weights | [openai/whisper README](https://github.com/openai/whisper/blob/main/README.md): "Whisper's code and model weights are released under the MIT License." | verified |
| Whisper LiteRT conversions (`litert-community/whisper-tiny`, `litert-community/whisper-base`) | Apache 2.0 | Hugging Face API `cardData.license`. `whisper-base` has `whisper_base_30s_f32.tflite` and `whisper_base_30s_i8.tflite`. | verified 2026-11-01. The OpenAI README says MIT for the original weights, while the conversions are tagged Apache 2.0. Both permit this use. |
| OpenAI Whisper on Hugging Face (`openai/whisper-small`, `openai/whisper-medium`, `openai/whisper-large-v3-turbo`) | `apache-2.0`, `apache-2.0`, `mit` as tagged | Hugging Face API `cardData.license` | verified 2026-11-01. The tags differ from the GitHub README's MIT statement. This page reports both as found. |
| AI4Bharat IndicConformer | MIT | [AI4Bharat/IndicConformerASR README](https://github.com/AI4Bharat/IndicConformerASR): "IndicConformer is released under the MIT license." The Hugging Face copy `ai4bharat/indic-conformer-600m-multilingual` is also tagged `mit` and is gated (`auto`). | verified |
| AI4Bharat IndicWhisper (Vistaar) | MIT, including the fine-tuned models | [AI4Bharat/vistaar README](https://github.com/AI4Bharat/vistaar): "Vistaar is MIT-licensed. The license applies to all the fine-tuned language models" | verified (README statement) |
| Community fine-tuned Indic Whisper (`vasista22/whisper-tamil-medium`, `vasista22/whisper-hindi-medium`) | Apache 2.0 | Hugging Face API `cardData.license` | verified 2026-11-01 (tag only; the model cards were not read further) |

### The larger model for the Mac

A general-purpose Gemma 4 12B exists. The Gemma 4 E2B model card lists the family as E2B, E4B, "12B Unified", 26B A4B and 31B Dense, and `google/gemma-4-12B-it` is on Hugging Face under Apache 2.0. The card's architecture table gives the 12B model 11.95B parameters, a 256K-token context, and text, image and audio input. Its audio has no separate encoder: the card says the 12B model projects "raw image patches and audio waveforms directly into the LLM's embedding space".

`litert-community/gemma-4-12B-it-litert-lm` provides `gemma-4-12B-it.litertlm` and `gemma-4-12B-it-gpu.litertlm`, so the Mac could run it with the same LiteRT-LM engine as the phone. Whether it fits and how fast it runs on the 16 GB MacBook Air M4 is not yet measured. The 12B is the Mac candidate for Milestone 1. Gemma 4 E4B is a smaller fallback if it does not fit.

The only "Gemma 4 12B" in the flutter_edge_ai documentation is a separate Intel NPU build for Windows (`flutter_edge_ai_litertlm` 1.19.0 README). It is not relevant to the Mac.

## Which ASR models flutter_edge_ai_speech can run on the device

`flutter_edge_ai_speech` 0.5.12 runs speech-to-text through `LiteRtSttBackend`. The model family is chosen by `SttModelType`, which has three values (`flutter_edge_ai` 2.5.4, `lib/src/model_management/types/stt_model_spec.dart`): `moonshine`, `whisper` and `parakeet`. Models are LiteRT `.tflite` files plus a tokenizer.

| `SttModelType` | Languages (bundled speech skill) | Window | Required languages it can cover |
| --- | --- | --- | --- |
| `moonshine` | English | 5 s | `en` |
| `whisper` | "99, selectable, default `'en'`" | 30 s | `en`, `ta`, `ml`, `hi` as decode languages. Code-switched speech has no language code of its own. |
| `parakeet` | English. The skill gives its size as 2.35 GB, "so desktop in practice". | 5 s | `en` |

The bundled speech skill names two Whisper LiteRT files: `litert-community/whisper-tiny/.../whisper_tiny_30s_f32.tflite` and `litert-community/whisper-base/.../whisper_base_30s_i8.tflite`. It says: "Whisper tiny is weak outside English." On 2026-11-01 the Hugging Face API listed both files.

### Candidates that need conversion

These candidates are not in a format that `flutter_edge_ai_speech` loads:

- **AI4Bharat IndicConformer.** It is distributed as NVIDIA NeMo `.nemo` files, with names like `indicconformer_stt_ta_hybrid_rnnt_large.nemo`. Per-language models exist for Tamil, Malayalam and Hindi, and a 600M multilingual model covers 22 Indian languages ([IndicConformerASR README](https://github.com/AI4Bharat/IndicConformerASR)). It is not Whisper, and `SttModelType.parakeet` is the only NeMo-family type the package knows. Running it would need a `.tflite` conversion and a check that the Parakeet front end and decoder in the package match IndicConformer. Neither has been tried, so treat it as not runnable on the device today.
- **AI4Bharat IndicWhisper (Vistaar).** These are Whisper checkpoints fine-tuned per language and loaded with Hugging Face `transformers` ([vistaar README](https://github.com/AI4Bharat/vistaar)). They would need conversion to a LiteRT `.tflite` laid out like the litert-community Whisper files. The architecture matches Whisper, so the conversion path is likely the same one used for the litert-community files. That is an inference. It has not been tried.
- **Community fine-tuned Indic Whisper.** Same as IndicWhisper: conversion to `.tflite` would be needed. Unverified beyond that.

The spike can measure only the models that load today. Those are the Whisper LiteRT files and Gemma 4 audio input. A conversion would be a separate task if the gates in [ADR 0001](../decisions/0001-spike-decision-gates.md) show that stock Whisper can't meet the Tamil or Malayalam targets.

## Gemma 4 E2B audio input in this stack

The stack accepts audio input for Gemma 4 E2B:

- The `flutter_edge_ai_speech` README, under "Audio turns: the model hears the recording": "A model with an audio encoder (Gemma 4 E2B/E4B) can take the recording itself." The model is loaded with `supportAudio: true`.
- The inference skill bundled with `flutter_edge_ai` 2.5.4 says that `Message.audioBytes` takes a whole 16 kHz mono WAV file, and that "Audio input needs Gemma 4 or Gemma 3n, on Android, iOS or desktop". On the web `.litertlm` engine, an audio message throws `UnsupportedError`.

`apps/spike` has a `gemmaAudio` ASR engine for this benchmark arm. It sends each 30-second window as a WAV file with the model card's ASR prompt.

Not known:

- Speech recognition quality for Tamil, Malayalam, Hindi or code-switched speech. The model card reports one FLEURS score per model (0.09 for E2B, "lower is better"), not per language, and names no metric. That number says nothing about Tamil, Malayalam or Hindi, so this page makes no quality claim for them.

From the [Gemma 4 E2B model card](https://huggingface.co/google/gemma-4-E2B-it), read on 2026-11-01:

- "Audio supports a maximum length of 30 seconds." The spike's 30-second windows match that limit.
- The card gives an ASR prompt: "Transcribe the following speech segment in {LANGUAGE} into {LANGUAGE} text.", followed by two formatting rules. It also says to put audio after the text in the prompt. The spike uses that prompt (`apps/spike/lib/src/gemma_asr_prompt.dart`), and the LiteRT-LM engine sends Gemma 4 messages as text, then audio.
- The card lists audio as "Automatic speech recognition (ASR) and speech-to-translated-text translation across multiple languages" for E2B, E4B and 12B.

## Memory measurement

`flutter_edge_ai_diagnostics` 0.5.0 reports `anonymousBytes`, `fileBackedBytes`, `anonymousPeakBytes` and `availableBytes`. Its bundled skill explains how each field behaves on each platform:

- On Android, `anonymousPeakBytes` is always null, so peak memory has to come from sampling. Read a snapshot no faster than about once a second. Each Android snapshot reads `/proc` and costs about 150 ms on a low-end device.
- On Android, a GPU backend puts most of its memory outside `anonymousBytes`. On Adreno, most of it is counted in `fileBackedBytes`. An `anonymousBytes` figure alone makes a GPU run look cheaper than it is.
- On macOS, `anonymousBytes` is `phys_footprint` and `anonymousPeakBytes` is the kernel's lifetime high-water mark of that value. `fileBackedBytes` and `availableBytes` are null.

The spike records all available fields, plus `ProcessInfo.maxRss` from `dart:io`. The [runbook](RUNBOOK.md) adds the OS's own tools (`dumpsys meminfo` on Android, `footprint` and Activity Monitor on macOS) as a cross-check.

## Still unverified

1. Mozilla Common Voice. Since October 2025 it is distributed only through Mozilla Data Collective (per the [Hugging Face page](https://huggingface.co/datasets/mozilla-foundation/common_voice_17_0)), and that site was refused from this session.
2. OpenSLR SLR63 and SLR65. openslr.org was refused.
3. AI4Bharat Svarah. The Hugging Face copy is gated and states no license in the API, and the GitHub README states none.
4. MUCS 2021. Its site was not reached.

To check these from a cloud session, add `openslr.org`, `datacollective.mozillafoundation.org` and `navana-tech.github.io` to the environment's allowed domains. See [network access](https://code.claude.com/docs/en/cloud-environments#network-access).
