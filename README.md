# flutter_rag — On-Device Transaction Search with Local RAG

An offline, on-device natural-language transaction search demo built with Flutter. It searches **5,500 synthetic Thai Baht (`THB`) transactions** over three years using a **SQL-first + Hybrid RAG** pipeline, with an optional on-device **Gemma 4 E2B** LLM mode for post-retrieval explanations and guarded action drafting.

---

## Architecture Overview

```text
User Query ("Find things I bought for camping last month, under THB 3,000, excluding food")
   │
   ▼
1. Deterministic Rule Parser (+ optional ML Kit entity fallback)  [< 1 ms]
   ├─ Hard filters: dateRange (Sep 2026), maxAmount (< 3,000 THB), exclude (food), type (purchase)
   └─ Leftover semantic intent: "camping"
   │
   ▼
2. SQLite Pre-Filter (Drift)                                      [~2–30 ms]
   ├─ Enforces exact dates, satang amounts, categories, and payees first
   └─ Emits allowlisted candidate transaction IDs + exact satang subtotals
   │
   ▼
3. Hybrid Local RAG (only when semanticQuery is present)          [~80–100 ms]
   ├─ all-MiniLM-L6-v2 (23 MB ONNX, 384-d embeddings, HNSW) + BM25 keyword search
   ├─ Reciprocal Rank Fusion (k = 5) across allowed IDs only
   └─ Two-tier cosine similarity gate (0.17 with keyword overlap, 0.43 semantic-only)
   │
   ▼
4. Optional Post-Retrieval On-Device LLM (Gemma 4 E2B + Deterministic Post-Hook)
   ├─ Explain results: 1–2 sentence grounded summary with pre-summed THB subtotal & verified [txn_...] citations
   └─ Draft transfer (`draft_transfer` tool): selects a retrieved transfer & updates the memo while a
      deterministic Dart post-hook locks the exact satang amount and recipient from SQLite
```

---

## Prerequisites

- **Flutter SDK** (via [FVM](https://fvm.app/) recommended, or standard `flutter`)
- **Android Studio / Xcode** for running on a physical Android or iOS device
- `curl` (used by `./tool/download_models.sh` to fetch the 23 MB `all-MiniLM-L6-v2` ONNX model and tokenizer)

---

## Quick Start

### 1. Download the local embedding model & install dependencies

```bash
./tool/download_models.sh
fvm flutter pub get
```

This downloads `model.onnx` and `tokenizer.json` (`all-MiniLM-L6-v2`, ~23 MB) into `assets/models/minilm/`.

### 2. Run on a connected device

**Android (profile mode recommended for realistic RAG & LLM speed):**

```bash
fvm flutter run --profile -d <android-device-id>
```

**iOS (physical iPhone, iOS 16+):**

```bash
fvm flutter run --profile -d <iphone-device-id>
```

You can optionally choose the seeded fixture size (`300`, `3000`, or default `5500` rows):

```bash
fvm flutter run --profile -d <device-id> --dart-define=FIXTURE_SIZE=5500
```

> **Note:** On first launch, the app seeds the SQLite database and indexes transaction memos in the background (**memo-bearing rows are indexed first** so semantic search is ready in ~1.5 minutes on a 5,500-row fixture, or ~3 seconds on the 300-row fixture, while exact SQL search works immediately).

---

## How to Use the App

The demo reference date is fixed at **3 October 2026** (`Asia/Bangkok`, `UTC+7`), so relative phrases like `"last month"` always resolve deterministically to **September 2026** and `"last year"` to **2025**.

### 1. Standard Search (Rules + SQLite + Hybrid RAG)

Type natural-language queries in the top search bar:

- **Hybrid SQL + Meaning search:**
  - `Find things I bought for camping last month, under THB 3,000, excluding food`
  - `Find the camping gear I bought in 2025`
  - `Where did I buy a sleeping bag?`
  - `Party supplies for the housewarming`
- **Exact filter search (SQLite only):**
  - `Show my 7-Eleven payments last month`
  - `Find my Sushiro meals in 2025`
  - `Show grocery and clothing purchases under 500 baht in August 2026`
  - `What did I spend on 29 February 2024?`
- **Person-to-person transfer search:**
  - `Find family transfers whose memos mention helping with the house`
  - `Show transfers to Mom last year`
  - `Money I paid Alex back for the group trip`
  - `School fees for the kids`
- **No-match gating (returns 0 results cleanly instead of unrelated rows):**
  - `Scuba diving lessons`

### 2. Follow-Up Refinements & Filter Chips

After running a search:
- Use the **Refine** bar below the chips to adjust the active plan—for example:
  - `go back one year and include the month before it too`
  - `under 2000`
  - `sleeping bag`
- Tap any **filter chip** to edit or remove individual constraints, or tap a transaction row to view its slip and edit its memo (saving a memo re-indexes that single row immediately).

### 3. Optional On-Device LLM (`Advanced reasoning` — Gemma 4 E2B)

1. Tap the **tune icon** (top-right) to open **On-device models** and download/enable **Gemma 4 E2B** (`2.59 GB`), or toggle **Advanced reasoning** on the main screen.
2. Searching and refining still update the transaction list **immediately (`< 100 ms`)** via deterministic rules + SQLite + RAG.
3. Once results are on screen, two post-retrieval LLM actions appear in the summary bar:
   - **Explain results:** Generates a short grounded summary of the top rows using the pre-summed satang subtotal from Dart and verifies every `[txn_...]` citation chip against the shown rows.
   - **Draft transfer** *(shown when results include at least one transfer)*: Runs the `draft_transfer` tool on the retrieved transfers to pick the best source transfer and adapt its memo for October 2026, validates it through a deterministic post-hook (`validateTransferDraft` in `lib/advanced/transfer_drafter.dart`) that copies the exact satang amount and recipient from SQLite, and opens a **Draft Transfer JSON** popup displaying both:
     1. **Gemma Tool Call (`draft_transfer`)** JSON
     2. **Verified API Payload (`POST /v1/transfers/draft`)** JSON ready to submit

---

## Developer & Benchmark Switches

Run one developer workflow at a time using `--dart-define`:

| Switch | Description |
|---|---|
| `--dart-define=COMPAT_PROBE=true` | Verifies native SQLite + ONNX MiniLM + HNSW compatibility on device |
| `--dart-define=GEMMA_PROBE=true` | Runs the on-device Gemma 4 E2B probe (load, tool calls, `draft_transfer`, cancel, memory release) |
| `--dart-define=RUN_CALIBRATION=true` | Runs cosine gate and RRF `k` calibration over the fixture |
| `--dart-define=RUN_EVAL=true` | Runs the 32-query evaluation suite (add `--dart-define=EVAL_ADVANCED=true` to include Gemma planner evaluation) |
| `--dart-define=RUN_BENCH=true` | Runs 5 benchmark passes after warm-up (add `--dart-define=BENCH_ADVANCED=true` to include Advanced mode) |
| `--dart-define=FIXTURE_SIZE=300\|3000\|5500` | Selects the seeded database size (default `5500`) |

---

## Running Tests & Static Analysis

```bash
# Static analysis
fvm flutter analyze lib test

# Unit & widget test suite
fvm flutter test

# On-device integration tests
fvm flutter test integration_test -d <device-id>
```

---

## Project Structure

```text
lib/
├── core/         # Transaction model, integer satang money helpers, Bangkok timezone utilities, payee directory
├── data/         # Drift SQLite database, RAG source mapping store, deterministic 5,500-row seeded fixture generator
├── search/       # SearchPlan model, validator, SQL compiler (SearchSql), deterministic RuleParser & RuleRefiner, ML Kit fallback
├── retrieval/    # MobileRagIndex wrapper, memo-first IndexManager, SemanticRetriever (RRF k=5 + two-tier cosine gate)
├── results/      # SearchEngine, ResultPager, ResultSummary, TransactionSearchController
├── advanced/     # Gemma 4 E2B installer/runtime, grounded Explainer, TransferDrafter (draft_transfer tool + post-hook)
├── ui/           # SearchScreen, PlanChips, SummaryBar, ExplanationCard, TransferDraftCard & JSON dialog, SlipSheet, TimingPanel
└── dev/          # On-device evaluation, benchmark, calibration, and compatibility probes
```
