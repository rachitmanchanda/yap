# YAP Hinglish Quality Harness

This tool selects the strongest ASR for YAP and measures the resulting production
transcription-plus-enhancement pipeline. Provider comparisons are internal product
evidence; manually captured keyboard baselines establish whether YAP lowers correction burden.

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
./yap-eval run fixtures/manifest.sample.json --provider sarvam
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

Speech manifests may be JSON or CSV. In CSV, encode `entities` and `switchIndexes` as JSON arrays such as `["Rachit","Hauz Khas"]` and `[2,5]`. Optional `baselineGboard` and `baselineApple` columns hold manually captured dictation output for the identical clip.

MUCS rows contain the original `datasetTranscript`, an English-ratio band, and an empty `reference`. For each selected clip:

1. Listen to the recording.
2. Write what a user should be able to send, in natural Roman Hinglish.
3. Choose the product category and clean/noisy tag.
4. Add names, places and brands to `entities`.
5. Add each annotated language boundary as the zero-based index of the token on its right.
6. Run `validate`; do not bypass its Roman-reference check.

The preparer balances low, medium and high English-ratio bands deterministically. The source transcript helps stratification only. MUCS consists of technical-lecture speech, so it is a useful public seed—not a substitute for the private conversational holdout.

## Run YAP by provider

```bash
./yap-eval validate annotation-queue-mucs-hindi-english-test.json
./yap-eval run private-holdout.json --provider sarvam
./yap-eval run private-holdout.json --provider whisper
./yap-eval run private-holdout.json --provider apple
```

The harness sends each audio file to the same deployed endpoints and request contract as the app:

1. `/functions/v1/transcribe` with the selected `provider`, `language_code=unknown` and `mode=translit`
2. `/functions/v1/rewrite` with `operation=enhance`

Sarvam and Whisper route through the same Supabase transcription function used by
the app. Missing provider fields still default to Sarvam, so the app contract remains
backward compatible. Deploy the updated function and configure its `OPENAI` (or
`OPENAI_API_KEY`) secret before running Whisper. The harness rejects a response whose
provider does not match the request, rather than silently labelling Sarvam as Whisper.

Apple Speech runs locally on macOS through `Speech.framework`, followed by the same
YAP enhancement endpoint. The helper builds with Xcode on first use and macOS may ask
for Speech Recognition permission. Because device models can differ, the manually
captured `baselineApple` output is the authoritative Apple keyboard comparison.

## Add manual Gboard and Apple baselines

For each private-holdout clip, play the same real recording into the target device,
copy the exact unedited dictation result, and populate:

```json
{
  "baselineGboard": "kal meeting he",
  "baselineApple": "kal meeting hai"
}
```

No competitor keyboard is automated. Validate and score these columns independently:

```bash
./yap-eval validate private-holdout.json --mode baseline
./yap-eval baseline private-holdout.json
```

A normal provider run automatically includes populated baseline rows in the same JSON
and Markdown table. This keeps identical references, tokenization, correction burden,
send-without-edit, entity accuracy and switch-boundary accuracy across every system.

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

The report begins with private-holdout system results, where **send without edit** and
**correction burden** are the headline metrics. MUCS appears separately as a public
regression appendix. Worst-20 diffs contain YAP outputs only.

The ship gate is eligible only when every YAP-scored private clip has both manual
baseline outputs for the exact same ID set. YAP passes only when its private-set
send-without-edit rate is strictly greater than the better of Gboard and Apple
Dictation. A tie does not pass. There is no absolute percentage gate and public MUCS
results cannot make the private gate pass.

## Text-only enhancement regressions

```bash
./yap-eval run-text text-regressions-hinge.json
```

- **HinGE:** human-generated Hinglish is used as both input and reference to detect damage to already-natural text.
- **L3Cube-HingLID:** tagged Roman code-mixed sentences test script/code-switch preservation. Upstream licensing must be confirmed before use.
- **hinglishNorm:** input/normalized pairs are evaluation-only diagnostics because the upstream license is non-commercial ShareAlike and its normalization target is not automatically YAP's preferred product style.

Do not mix these text rows into the real-speech launch gate.

Reports also score formatting structure, list decisions and paragraph decisions. These
metrics compare the shape of the final output with the human reference without counting
the same wording edits twice. Formatting scores are meaningful only when the reference
was deliberately annotated with the paragraphs and bullets the user would actually send;
never generate those references with an LLM.

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
7. Build the private conversational holdout first, recorded with consent, and manually
   capture both baseline columns.
8. Expand MUCS to 100 stratified clips as a secondary regression suite.
9. Run each provider against the unchanged manifests and compare reports by run ID and
   Git SHA.

Do not tune against the private holdout. Add or revise pipeline behavior using separate
development data, then use the private gate as the final product check.
