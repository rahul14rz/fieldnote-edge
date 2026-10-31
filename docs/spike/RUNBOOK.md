# How to run the Milestone 0 measurements

This runbook tells you how to produce every number in `benchmarks/results/TEMPLATE.md` on the OnePlus 11R and the MacBook Air M4, and how to fill in the go/no-go table at the end. The gates and proposed thresholds are in [ADR 0001](../decisions/0001-spike-decision-gates.md).

None of these steps have been run yet. The session that wrote them had no access to either device. If a step fails, write down the exact error and fix the step in this file.

## Before you start

You need:

- The MacBook Air M4 with Xcode, Flutter 3.47.9, Python 3.11 or later, Node.js 22, pnpm 10, and `ffmpeg`.
- Android platform tools (`adb`) on the Mac.
- The OnePlus 11R with **Developer options** and **USB debugging** turned on, connected by USB.
- About 6 GB of free space on each device for the model files.

Clone the repository and install the Node packages:

```bash
git clone https://github.com/rahul14rz/fieldnote-edge.git
cd fieldnote-edge
pnpm install
```

## Download the models

Download the files on the Mac into `benchmarks/datasets/local/models/`, which git ignores. The URLs come from the flutter_edge_ai 2.5.4 documentation. On 2026-11-01 the Hugging Face API listed all three files, and the repositories are not gated.

```bash
mkdir -p benchmarks/datasets/local/models
cd benchmarks/datasets/local/models
curl -L -o gemma-4-E2B-it.litertlm https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
curl -L -o whisper_base_30s_i8.tflite https://huggingface.co/litert-community/whisper-base/resolve/main/whisper_base_30s_i8.tflite
curl -L -o whisper-base-tokenizer.json https://huggingface.co/openai/whisper-base/resolve/main/tokenizer.json
cd -
```

The licenses are recorded in `docs/spike/findings.md`: Apache 2.0 for Gemma 4 E2B and for the Whisper LiteRT files.

## Prepare the speech recordings

1. Record each fictional script in `apps/spike/assets/prompt_set.json`, or your own fictional scripts, in each language you need: `en`, `ta`, `ml`, `hi`, `ta-en`, `ml-en`, `hi-en`. Never use a recording of a real client meeting.
2. Convert each recording to 16 kHz, mono, 16-bit PCM WAV:

   ```bash
   ffmpeg -i input.m4a -ac 1 -ar 16000 -sample_fmt s16 scripted-ta-001.wav
   ```

3. Put the WAV files in `benchmarks/datasets/local/asr/audio/`.
4. Write `benchmarks/datasets/local/asr/manifest.jsonl`, with one line per file. Use `apps/spike/examples/asr-manifest.example.jsonl` as the pattern:

   ```json
   {"id": "scripted-ta-001", "language": "ta", "audio": "asr/audio/scripted-ta-001.wav"}
   ```

5. Write `benchmarks/datasets/local/asr/references.jsonl` with the exact spoken text for each ID:

   ```json
   {"id": "scripted-ta-001", "language": "ta", "text": "..."}
   ```

Aim for at least 10 minutes of audio per language. That is a proposal, not a measured requirement.

## Run on the OnePlus 11R

### Install the spike app

1. Build and install the release build:

   ```bash
   cd apps/spike
   flutter build apk --release --target-platform android-arm64
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   cd -
   ```

2. Open **Fieldnote spike** on the phone once. The screen shows the work directory. It should be `/storage/emulated/0/Android/data/io.github.rahul14rz.fieldnote_spike/files`.
3. Copy the models and recordings into the work directory:

   ```bash
   W=/sdcard/Android/data/io.github.rahul14rz.fieldnote_spike/files
   adb shell mkdir -p $W/models $W/asr
   adb push benchmarks/datasets/local/models/. $W/models/
   adb push benchmarks/datasets/local/asr/. $W/asr/
   ```

   If `adb push` into `Android/data` fails with a permission error on Android 16, stop and record the error. The spike app would then need a file picker, which it does not have yet.

### Prepare the phone before each run

1. Close all other apps.
2. Keep the screen on while the phone is plugged in over USB:

   ```bash
   adb shell svc power stayon usb
   ```

3. Wait until the phone is cool. Check the thermal status:

   ```bash
   adb shell dumpsys thermalservice | grep -i "thermal status"
   ```

   Start a run only when the status is 0 (`NONE`). Record the value as "Thermal before".
4. Record the battery state:

   ```bash
   adb shell dumpsys battery | grep -E "level|temperature|powered"
   ```

### Measure LLM timing

1. Copy a timing config into place. Timing configs read memory only before and after each prompt:

   ```bash
   adb push apps/spike/examples/llm-gemma4-e2b-gpu-timing.json $W/spike_config.json
   ```

2. In the app, tap **Run spike_config.json**. Wait for the line that starts with `DONE wrote`.
3. Record the thermal status again as "Thermal after".
4. Wait until the thermal status is back to 0, then repeat with `llm-gemma4-e2b-cpu-timing.json`.

### Measure LLM memory

The app records `anonymousBytes` and `fileBackedBytes` from `flutter_edge_ai_diagnostics`. On Android, `anonymousPeakBytes` is always null, so the peak comes from samples. On a GPU backend, most GPU memory is outside `anonymousBytes`. Record the OS's own number as well:

1. Push the memory config:

   ```bash
   adb push apps/spike/examples/llm-gemma4-e2b-gpu-memory.json $W/spike_config.json
   ```

2. In a second terminal, start this loop before you tap **Run**. It prints the app's total PSS every two seconds:

   ```bash
   while true; do adb shell dumpsys meminfo io.github.rahul14rz.fieldnote_spike | grep -E "TOTAL PSS|TOTAL:" ; sleep 2; done | tee oneplus-meminfo.log
   ```

3. Tap **Run spike_config.json** and wait for `DONE wrote`. Stop the loop with Ctrl+C.
4. Record the largest TOTAL PSS value in `oneplus-meminfo.log` as "OS peak memory".

`dumpsys meminfo` costs CPU, so never run the loop during a timing run.

### Measure speech recognition

1. Push an ASR config:

   ```bash
   adb push apps/spike/examples/asr-whisper-base-timing.json $W/spike_config.json
   ```

2. Tap **Run spike_config.json**. The app writes `results/<runId>.json` and `results/<runId>.hypotheses.jsonl`.
3. Repeat with `asr-gemma4-audio-timing.json` for the Gemma audio arm.
4. For memory, run the same configs with `"memorySampleIntervalMs": 1000` and the `dumpsys meminfo` loop from the previous section.

The Whisper config decodes code-switched audio with the base language code (`ta-en` uses `ta`). To compare, copy it, change `decodeLanguage` for that pair to `en`, and run it again. The Gemma config uses language names instead, such as `Tamil and English`, because the model card's ASR prompt names the language.

### Copy the results to the Mac

```bash
mkdir -p benchmarks/results/raw/oneplus-11r
adb pull $W/results/. benchmarks/results/raw/oneplus-11r/
```

`benchmarks/results/raw/` is ignored by git. Commit only the filled-in Markdown and `summary.json`.

## Run on the MacBook Air M4

1. Plug in the Mac and close other apps. Record the power state:

   ```bash
   pmset -g batt
   ```

2. Build and open the app:

   ```bash
   cd apps/spike
   flutter build macos --release
   open build/macos/Build/Products/Release/fieldnote_spike.app
   cd -
   ```

3. The app shows its work directory. In the sandbox it should be `~/Library/Containers/io.github.rahul14rz.fieldnoteSpike/Data/Documents`. Copy the files there:

   ```bash
   W=~/Library/Containers/io.github.rahul14rz.fieldnoteSpike/Data/Documents
   mkdir -p "$W/models" "$W/asr"
   cp benchmarks/datasets/local/models/* "$W/models/"
   cp -R benchmarks/datasets/local/asr/. "$W/asr/"
   ```

4. Copy a config and set `deviceLabel` to `MacBook Air M4`:

   ```bash
   sed 's/OnePlus 11R/MacBook Air M4/' apps/spike/examples/llm-gemma4-e2b-gpu-timing.json > "$W/spike_config.json"
   ```

5. Record the thermal state as "Thermal before":

   ```bash
   pmset -g therm
   ```

6. Click **Run spike_config.json** and wait for `DONE wrote`. Record `pmset -g therm` again as "Thermal after".
7. For memory, macOS reports `anonymousPeakBytes`, the kernel's lifetime peak of the app's footprint, so the result file already holds the peak. To cross-check it while the app is still open after a run:

   ```bash
   footprint fieldnote_spike
   ```

   Record the peak footprint value. Activity Monitor's **Memory** column shows the same footprint while the app runs.
8. Repeat for the CPU config and the ASR configs as on the phone.
9. Copy the results:

   ```bash
   mkdir -p benchmarks/results/raw/macbook-air-m4
   cp "$W"/results/* benchmarks/results/raw/macbook-air-m4/
   ```

## Compute the numbers

1. Summarize the timing and memory results:

   ```bash
   cd benchmarks/evaluation
   python3 summarize_runs.py --output ../results/summary.json ../results/raw/*/*.json
   cd -
   ```

2. Compute WER and CER for each ASR run:

   ```bash
   cd benchmarks/evaluation
   python3 -m asr_eval --references ../datasets/local/asr/references.jsonl --hypotheses ../results/raw/oneplus-11r/<runId>.hypotheses.jsonl --output ../results/raw/oneplus-11r/<runId>.wer.json
   cd -
   ```

3. Count the LLM outputs that are valid `MeetingSummary` JSON. Pass absolute paths, because the command runs inside `packages/contracts`:

   ```bash
   pnpm --filter @fieldnote/contracts validate-outputs "$PWD"/benchmarks/results/raw/oneplus-11r/*-llm.json
   ```

4. Copy `benchmarks/results/TEMPLATE.md` to `benchmarks/results/<date>-baseline.md`. Fill in each cell from `summary.json`, the `.wer.json` files, the validator output, and your thermal and `dumpsys meminfo` notes. Convert bytes to MiB by dividing by 1,048,576. Add `wer`, `cer`, `osPeakMemoryBytes` and the thermal values to the rows in `summary.json` as well.

## Fill in the go/no-go table

First confirm or replace the thresholds in ADR 0001. Then fill in one row per language and engine, and one row per LLM configuration. Write the measured value next to each threshold. A gate without a measurement stays "not yet measured" and does not pass.

Decision values: **go on-device**, **Mac only**, **not viable on-device**.

### Speech recognition

| Language | Engine and model | WER | CER | RTF on phone | Peak PSS on phone (MiB) | Thresholds confirmed (A1 to A3) | Stability (A4) | Decision | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| en | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ta | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ml | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| hi | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ta-en | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ml-en | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| hi-en | whisper, whisper-base-30s-i8 | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| en | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ta | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ml | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| hi | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ta-en | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| ml-en | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |
| hi-en | gemmaAudio, gemma-4-E2B-it | not yet measured | not yet measured | not yet measured | not yet measured | not yet confirmed | not yet measured | | |

### Summary extraction

| Model | Device | Backend | Median end-to-end, en-long (L1) | Valid JSON share, worst case (L2) | Peak PSS in MiB (L3) | Worst thermal status (L4) | Stability (L5) | Decision | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| gemma-4-E2B-it | OnePlus 11R | gpu | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | | |
| gemma-4-E2B-it | OnePlus 11R | cpu | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | | |
| gemma-4-E2B-it | MacBook Air M4 | gpu | not yet measured | not yet measured | not yet measured | not yet measured | not yet measured | | |

When every row has a decision, Milestone 1 can start.
