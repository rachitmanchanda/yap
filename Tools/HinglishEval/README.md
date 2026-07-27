# YAP Hinglish Quality Harness

This tool measures one product: the production YAP transcription-plus-enhancement pipeline. It is not a provider or competitor leaderboard.

The speech gate uses real recordings and human-written Roman Hinglish references. A dataset's native-script transcript is useful for finding clips, but it is never automatically romanized or treated as the sendable reference. Text-to-speech and generated references are prohibited.

## Requirements

- Python 3.11 or newer (standard library only)
- `ffmpeg` for inspecting or converting corpus audio when needed
- Network access to YAP's deployed Supabase functions
- The YAP checkout's existing `SupabaseConfiguration.swift`, or:
  - `YAP_SUPABASE_URL`
  - `YAP_SUPABASE_KEY`
  - optional `YAP_ACCESS_TOKEN`

Downloaded corpora, annotations and result runs stay under ignored tool directories.

## Quick start

```bash
cd Tools/HinglishEval
chmod +x yap-eval
./yap-eval --help
python3 -m unittest discover -s tests -v
```

The five fixture rows are deliberately unlabelled. Add real recordings and references before validation:

```bash
./yap-eval validate fixtures/manifest.sample.json
./yap-eval run fixtures/manifest.sample.json
```

Validation failing on empty references or absent audio is the intended safe default.

## Prepare datasets

The registry records the exact URL, version, license, SHA-256 and cache path for every source.

```bash
# Downloads and verifies OpenSLR 104, then creates a stratified annotation queue.
./yap-eval prepare --dataset mucs-hindi-english-test --sample-size 100

# Enhancement-preservation samples from human Roman Hinglish.
./yap-eval prepare --dataset hinge --sample-size 100

# Evaluation-only normalization diagnostics.
./yap-eval prepare --dataset hinglishnorm --sample-size 100 \
  --allow-unverified-license

# License is not verified in the upstream repository; this requires an explicit override.
./yap-eval prepare --dataset l3cube-hinglid --sample-size 100 \
  --allow-unverified-license
```

Speech manifests may be JSON or CSV. In CSV, encode `entities` and `switchIndexes` as JSON arrays such as `["Rachit","Hauz Khas"]` and `[2,5]`.

MUCS rows contain the original `datasetTranscript`, an English-ratio band, and an empty `reference`. For each selected clip:

1. Listen to the recording.
2. Write what a user should be able to send, in natural Roman Hinglish.
3. Choose the product category and clean/noisy tag.
4. Add names, places and brands to `entities`.
5. Add each annotated language boundary as the zero-based index of the token on its right.
6. Run `validate`; do not bypass its Roman-reference check.

The preparer balances low, medium and high English-ratio bands deterministically. The source transcript helps stratification only. MUCS consists of technical-lecture speech, so it is a useful public seed—not a substitute for the private conversational holdout.

## Run production YAP

```bash
./yap-eval validate annotation-queue-mucs-hindi-english-test.json
./yap-eval run annotation-queue-mucs-hindi-english-test.json
```

The harness sends each audio file to the same deployed endpoints and request contract as the app:

1. `/functions/v1/transcribe` with `language_code=unknown` and `mode=translit`
2. `/functions/v1/rewrite` with `operation=enhance`

Running the harness uploads speech and text through YAP's production backend to its configured providers. Use only recordings you are authorized to process, and keep private holdout manifests and audio outside Git.

It mirrors the app's 8-second batch-transcription and 2.5-second enhancement budgets. Transcription retries only transient network, HTTP 429 and HTTP 5xx failures with deterministic backoff; enhancement does not retry and falls back to the raw transcript just like the app. One utterance failing does not erase the run.

Each run writes:

```text
results/<UTC timestamp>-<git SHA>/
├── results.json
└── report.md
```

Metadata includes the manifest checksum, full Git commit, dirty-worktree flag and timestamps. Pass `--run-id` to name a controlled rerun; an existing run directory is never overwritten.

## Metrics

- **Raw ASR WER:** word edit distance from transcription to the human Roman reference.
- **Correction burden:** word edit distance from enhanced output to that reference. This is the primary product metric.
- **Send without edit:** final output exactly matches the reference after Unicode and whitespace normalization only. Case and punctuation differences still count as edits.
- **Roman-script preservation:** output does not drift into Devanagari when the reference is Roman Hinglish.
- **Entity accuracy:** annotated names, places and brands present as contiguous token sequences.
- **Switch-boundary accuracy:** both annotated words around a Hindi/English switch are correct and adjacent.

Normalization applies Unicode NFKC, case folding and punctuation removal. It does not translate, romanize, stem or use an LLM.

Reports aggregate overall, by category, noise and source, and include deterministic diffs for the worst 20 outputs.

## Text-only enhancement regressions

```bash
./yap-eval run-text text-regressions-hinge.json
```

- **HinGE:** human-generated Hinglish is used as both input and reference to detect damage to already-natural text.
- **L3Cube-HingLID:** tagged Roman code-mixed sentences test script/code-switch preservation. Upstream licensing must be confirmed before use.
- **hinglishNorm:** input/normalized pairs are evaluation-only diagnostics because the upstream license is non-commercial ShareAlike and its normalization target is not automatically YAP's preferred product style.

Do not mix these text rows into the real-speech launch gate.

## Sources and rights

- [MUCS / OpenSLR 104](https://www.openslr.org/104/) — CC BY-SA 4.0
- [HinGE](https://huggingface.co/datasets/LingoIITGN/HinGE) — CC BY 4.0
- [L3Cube-HingLID](https://github.com/l3cube-pune/code-mixed-nlp) — upstream license review required
- [hinglishNorm](https://github.com/piyushmakhija5/hinglishNorm) — evaluation-only; upstream indicates BY-NC-SA
- IITG-HingCoS — request separately from IIT Guwahati. It is intentionally not downloadable here until the corpus is received and its terms are confirmed.

Preserve source attribution with any derived annotations. Do not commit corpus audio or private holdout recordings.

## Device/backend test plan

1. Run all unit tests.
2. Prepare MUCS and manually label five real clips across the three ratio bands.
3. Validate the manifest.
4. Run it against the deployed production endpoints.
5. Open both report files and verify raw/final outputs, timing and diffs.
6. Repeat the same manifest with the same commit. Output metrics should match unless the deployed backend changed.
7. Label 100 stratified public clips and add a separate 30–50-message private conversational holdout recorded with consent.

The automated gate remains ineligible until a speech run contains at least 100 rows whose source is `mucs-openslr-104` and 30–50 rows whose source is `private-holdout`. It then requires at least 70% send-without-edit, under 8% overall correction burden and under 5% correction burden on clean audio. Public and private sets are still reported separately; the private holdout must not be tuned against.
