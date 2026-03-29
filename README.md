# Koshika — कोशिका

> *Your health data lives in your cell, not the cloud.*

![Status](https://img.shields.io/badge/Status-Active_Development-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue)
![License](https://img.shields.io/badge/License-MPL--2.0-blue)
![AI](https://img.shields.io/badge/AI-100%25_On--Device-purple)
![Privacy](https://img.shields.io/badge/Privacy-Zero_Cloud-teal)

<!-- TODO: Add screenshot strip (3 device frames side by side) -->
<!-- TODO: Add demo GIF (import PDF → dashboard → AI chat) -->

Koshika turns your PDF lab reports into actionable health insights — parsed, tracked, and explained by AI — entirely on your phone. No cloud. No accounts. No data leaves your device. Ever.

**[Website](https://www.koshika.life)**&ensp;·&ensp;**[Contributing](#contributing)**

---

## Why?

200+ million Indians get blood tests every year. They receive PDF reports filled with cryptic abbreviations and reference ranges they can't interpret. Every existing solution either can't parse these formats or requires uploading private health data to a server.

Unlike cloud health apps, **Koshika never uploads your data.**
Unlike PDF readers, **it actually understands your lab values.**

---

## What it does

- **Parses a wide range of Indian lab PDFs** — 4 regex patterns + fuzzy matching + OCR fallback. Works with Thyrocare, Dr. Lal, SRL, Metropolis, and more.
- **Tracks 63 biomarkers** across 10 categories with trend charts, reference gauges, and borderline detection.
- **On-device AI chat** — ask questions about your results, get citation-backed answers grounded in your actual lab values. Full RAG pipeline, entirely offline.
- **Exports to FHIR R4** — share standardized health data with any FHIR-compatible system.

---

## Quick Start

```bash
git clone https://github.com/priyavratuniyal/koshika.git
cd koshika
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Base features (parsing, trends, export) work immediately. AI chat is optional — download a model (~230 MB–1 GB) from Settings when you want it.

---

## How it Works

```mermaid
flowchart LR
    A([PDF Lab\nReport]) --> B["<b>Parse</b>\nRegex + OCR\n+ Fuzzy Match"]
    B --> C[("<b>Store</b>\nObjectBox\nLocal DB")]
    C --> D["<b>Insights</b>\nTrends · Gauges\n· FHIR Export"]
    C --> E["<b>AI Chat</b>\nRAG · LLM\n· Citations"]
```

### 1. PDF Import & Parsing

```mermaid
flowchart LR
    A([PDF]) --> B[Text Extract\nor OCR] --> C[4 Regex\nPatterns] --> D[Fuzzy\nMatch] --> E[Flag &\nStore]
```

<details>
<summary>Detailed technical diagram</summary>

```mermaid
flowchart TD
    A([Lab Report PDF]) --> B[PdfTextExtractor\nSyncfusion]
    B --> C{Page has\n≥35 chars?}
    C -->|Yes| F
    C -->|No / sparse| D[PdfPageRenderService\nrender to PNG]
    D --> E[OcrTextRecognitionService\nGoogle ML Kit]
    E --> E2[OcrRowReconstructor\ngroup by geometry]
    E2 --> F

    F[LabReportParser] --> F1[Pattern A: space-delimited]
    F --> F2[Pattern B: colon-separated]
    F --> F3[Pattern C: pipe-separated]
    F --> F4[Pattern D: loose catch-all]

    F1 & F2 & F3 & F4 --> G[RawLabRows]
    G --> H[BiomarkerDictionary\nfuzzyMatch]
    H --> H1[Exact alias lookup]
    H --> H2[Substring match]
    H --> H3["Dice coefficient (≥0.6)"]

    H1 & H2 & H3 --> I[BiomarkerResult\nvalue · unit · refRange · flag]
    I --> J[computeFlag\nnormal · borderline · low · high · critical]
    J --> K[(ObjectBox\nsaveReportWithResults)]
```

Each page is extracted digitally first; pages with sparse text fall back to OCR (render → ML Kit → row reconstruction). Raw text runs through 4 regex patterns, and matched rows are fuzzy-matched against 63 biomarker definitions. Values are parsed, reference ranges extracted, and flags computed (including 10% borderline detection).

</details>

### 2. Insights & Export

```mermaid
flowchart LR
    A[(Local DB)] --> B[Dashboard\n& Trends] --> C[Biomarker\nDetail]
    A --> D[FHIR R4\nExport]
```

<details>
<summary>Detailed technical diagram</summary>

```mermaid
flowchart TD
    G[(ObjectBox\nLocal DB)] --> D[Dashboard]
    G --> B[Biomarker Detail]
    G --> X[FHIR Export]

    D --> D1[Clinical status\nHealthy · Minor Variances\nNeeds Attention · Under Review]
    D --> D2[Attention panel\ntop 3 out-of-range]
    D --> D3[Category trend cards\n4-point sparkline · severity badge]
    D --> D4[Clinical insights\ntrending up/down detection]

    B --> B1[Interactive trend chart\nfl_chart · ref range bands\ncolor-coded dots · tooltips]
    B --> B2[Reference range gauge\nlow / normal / high zones\ncurrent value marker]
    B --> B3[Full history table\ndate · lab · value · flag]

    X --> X1[Patient resource]
    X --> X2[Observation per biomarker\nLOINC code · UCUM unit\ninterpretation code]
    X --> X3[DiagnosticReport per lab report]
    X1 & X2 & X3 --> X4([FHIR R4 Bundle\nJSON export])
```

The dashboard shows a clinical status overview, flags attention-needed biomarkers, and renders per-category trend cards with sparklines. The detail view has interactive trend charts with reference bands and a custom-painted gauge. FHIR export produces a spec-compliant R4 Bundle with LOINC codes, UCUM units, and interpretation codes.

</details>

### 3. On-Device AI Chat

```mermaid
flowchart LR
    A([Message]) --> B[Intent\nRouter] --> C[Build\nContext] --> D[LLM\nStream] --> E[Validate\n& Cite]
```

<details>
<summary>Detailed technical diagram</summary>

```mermaid
flowchart TD
    A([User Message]) --> R[QueryRouter]

    R --> S1[Stage 1: IntentPrefilter\ndeterministic regex]
    S1 -->|Emergency 17 patterns| EM([Escalate — no LLM])
    S1 -->|Off-topic| OT([Refuse — no LLM])
    S1 -->|Lab query + no data| NL([Need report first])
    S1 -->|Ambiguous| S2[Stage 2: IntentClassifier\nembed → cosine to centroids]
    S1 -->|Lab / Health| CTX

    S2 -->|Low confidence| CQ([Ask clarifying question])
    S2 -->|Resolved| CTX

    CTX[ChatContextBuilder]
    CTX -->|Embeddings loaded| SEM[Semantic: embed query\n→ HNSW top-5 search]
    CTX -->|Not loaded| KW[Keyword fallback\ncategory matching]

    SEM & KW --> P[ChatML prompt\nsystem · history · context · question]
    P --> LLM["LlmService\nstreaming via llamadart\n(4 GGUF models or BYOM)"]

    LLM --> V[OutputValidator]
    V -->|Empty / garbled| RET([Retry up to 3×])
    V -->|Hallucinated / repetitive\n/ prohibited| FB([Fallback response])
    V -->|Passed| CIT[CitationExtractor\nmap references to lab sources]
    CIT --> OUT([Response with\nsource footer])
```

Messages are routed through a two-stage classifier — regex prefilter handles emergencies, off-topic, and clear intent; ambiguous queries go to an embedding-based centroid classifier. Context is built via semantic search (bge-small-en-v1.5, 384-dim, HNSW) or keyword fallback. The LLM streams a response which is validated for hallucinations, repetition, garbled output, and prohibited diagnostic language. Valid responses get a citation footer mapping `[N]` references back to lab sources.

</details>


---

## Features in Detail

<details>
<summary>Expand</summary>

### PDF Parsing Engine
- Hybrid extraction: digital text (Syncfusion) with OCR fallback (Google ML Kit)
- 4 regex patterns: space-delimited, colon-separated, pipe-separated, loose catch-all
- Fuzzy term matching normalizes lab naming ("FASTING SUGAR" → "Glucose, Fasting")
- 63 biomarker definitions across 10 categories with LOINC codes
- Section header detection (40+ variations), multiline handling, OCR artifact cleanup

### On-Device AI
- Multi-model: SmolLM2 360M · Qwen3 0.6B · Llama 3.2 1B · Gemma 3 1B (or any GGUF)
- RAG: bge-small-en-v1.5 embeddings (384-dim) + HNSW vector index → semantic search → citation-backed responses
- Two-stage routing: deterministic regex prefilter + embedding centroid classifier
- Safety: emergency escalation (17 patterns), hallucination detection, repetition/garbled detection, off-topic refusal
- Conversation history with anaphora resolution ("is that normal?" after lab query)

### Dashboard & Trends
- Clinical status overview with severity badges (Stable, Borderline, Critical)
- Interactive trend charts with reference range bands and color-coded data points
- Reference range gauge with low/normal/high zones
- Borderline detection (within 10% of reference boundaries)

### Privacy & Export
- All processing on-device: parsing, OCR, LLM, embeddings, vector search
- FHIR R4 Bundle export with LOINC codes and UCUM units
- Full and Lite app flavors (Lite = no AI, no model downloads)
- No accounts, no telemetry, no analytics

</details>

---

## Tech Stack

<details>
<summary>Expand</summary>

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart >=3.9.2) |
| Local DB | ObjectBox 5.2 (HNSW vector indexing) |
| PDF | syncfusion_flutter_pdf |
| OCR | google_mlkit_text_recognition + pdfx |
| LLM | llamadart (llama.cpp, GGUF, ChatML) |
| Embeddings | bge-small-en-v1.5 (384-dim, HNSW) |
| Charts | fl_chart |
| Export | fhir_r4 |

</details>

---

## Project Structure

<details>
<summary>Expand</summary>

```text
lib/
├── constants/    # Prompts, templates, budgets, strings
├── models/       # 11 ObjectBox entities + data classes
├── screens/      # 8 screens
├── services/     # 23 services (PDF, AI, storage, export)
├── theme/        # Design system (typography, colors, spacing)
├── widgets/      # 10 reusable components + 6 settings widgets
├── main.dart     # App entry + routing
├── main_full.dart
└── main_lite.dart
```

</details>

---

## Roadmap

**Shipped:** PDF parsing · OCR fallback · 63 biomarkers · trend charts · borderline detection · FHIR R4 export · on-device LLM (4 models + BYOM) · semantic search · RAG with citations · two-stage intent routing · output validation · emergency detection · persistent chat · onboarding · Full/Lite flavors

**Next:**
- [ ] Health Connect integration (steps, heart rate, SpO2)
- [ ] Computed risk scores (FIB-4, eGFR, APRI)
- [ ] Anomaly detection (EWMA, personal baselines)
- [ ] Encrypted storage with biometric lock
- [ ] Web platform

---

## Contributing

Pull requests welcome. If you find a lab format the parser can't handle, open an issue with a redacted sample PDF.

```bash
npm install          # set up pre-commit formatting hook
flutter test         # run test suite
flutter analyze      # static analysis
```

Use conventional commits: `feat(scope):` · `fix(scope):` · `refactor(scope):`

---

## License

[MPL-2.0](LICENSE)
