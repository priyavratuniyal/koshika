# Koshika

![Status](https://img.shields.io/badge/Status-Active_Development-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Android%20|%20iOS-blue)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.9.2-0175C2)
![License](https://img.shields.io/badge/License-MIT-green)

**Your health data lives in your cell, not the cloud.**

Koshika is an offline-first, privacy-focused health app that extracts biomarker data from PDF lab reports, tracks trends over time, and lets you discuss your results with an on-device AI — all without a single byte leaving your phone.

---

## Why Koshika?

Indian pathology labs produce PDF reports in dozens of inconsistent formats. Most health apps either can't parse them, or require uploading to a cloud service to try.

Koshika solves this differently:

- **Parses locally.** A multi-pattern regex engine + fuzzy matching handles the formatting chaos of Thyrocare, SRL, Dr. Lal PathLabs, and others — directly on your device.
- **Understands your data.** Biomarkers are normalized to a standard dictionary, flagged against reference ranges, and tracked historically with trend charts.
- **Runs AI on-device.** Gemma 3 1B runs inference locally via MediaPipe. Ask questions about your reports and get citation-backed answers grounded in your actual lab values.
- **Never phones home.** No accounts, no telemetry, no cloud sync. Your health data stays in ObjectBox on your device.

---

## Features

### PDF Parsing
- Extracts structured data from digital PDFs using `syncfusion_flutter_pdf`
- OCR fallback for scanned/image-based pages using Google ML Kit
- Staged import progress with clear error messaging for unsupported layouts
- Fuzzy term matching normalizes lab-specific naming ("FASTING SUGAR" → "Glucose, Fasting") across 63 biomarker definitions in 10 medical categories

### On-Device AI
- **Gemma 3 1B IT** — instruction-tuned LLM running locally via `flutter_gemma` + MediaPipe
- GPU-first inference with automatic CPU fallback
- Streaming token-by-token responses
- **EmbeddingGemma 300M** — on-device embeddings for semantic search (~75 MB, 768-dim)
- **RAG pipeline** — embeds your query, searches an HNSW vector index of your lab results, injects the top-5 matches as context, and generates grounded responses with source citations `[1]`, `[2]`
- Graceful degradation — keyword search works seamlessly when the embedding model isn't loaded

### Dashboard & Trends
- Health overview with tracked biomarker count, abnormal flags, and borderline detection (within 10% of reference boundaries)
- "Attention Needed" panel for out-of-range results
- Category-level trend indicators
- Biomarker detail view with interactive `fl_chart` trend visualization, reference range gauge, and color-coded history
- Borderline flag detection reflected across the entire app

### Privacy & Export
- All processing happens on-device — parsing, AI inference, embeddings, search
- ObjectBox local database with no network dependency
- FHIR R4 Bundle export for sharing with healthcare providers
- Native share sheet integration via `share_plus`

### Onboarding
- Animated splash screen with branded fade/scale animation
- 3-screen onboarding flow (Welcome, How it Works, Privacy)
- Subsequent launches skip directly to home

---

## Architecture

| Layer | Technology |
|-------|------------|
| Frontend | Flutter (StatefulWidget) |
| Local DB | ObjectBox |
| PDF Extraction | syncfusion_flutter_pdf |
| OCR Fallback | google_mlkit_text_recognition + pdfx |
| Text Analysis | Custom multi-regex engine + string_similarity |
| On-Device LLM | flutter_gemma (Gemma 3 1B IT, MediaPipe) |
| Embeddings | EmbeddingGemma 300M (HNSW via SQLite VectorStore) |
| Charts | fl_chart |
| Export | FHIR R4 (fhir_r4 package) |

### Project Structure

```text
lib/
├── models/          # ObjectBox entities (Patient, LabReport, BiomarkerResult, ChatMessage)
├── screens/         # UI (Dashboard, Reports, Chat, Settings, BiomarkerDetail, Onboarding)
├── services/        # Core logic (PDF extraction, parsing, AI, embeddings, vector search, FHIR)
├── widgets/         # Reusable components (trend chart, gauge, flag badge, chat bubble)
└── main.dart        # App entry, theme, navigation

assets/data/         # Biomarker dictionary (63 definitions, 10 categories)
```

---

## Getting Started

### Prerequisites
- Flutter SDK (Dart >=3.9.2)
- Android device or emulator (API 26+)

### Installation

```bash
git clone https://github.com/priyavratuniyal/koshika.git
cd koshika
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Auto-format on commit (optional)

This repo uses a Husky pre-commit hook that auto-formats staged Dart files:

```bash
npm install
```

---

## Roadmap

- [x] PDF parsing with multi-pattern regex engine
- [x] OCR fallback for scanned reports
- [x] Fuzzy biomarker matching (63 definitions, 10 categories)
- [x] Dashboard with health overview and trend indicators
- [x] Biomarker detail view with trend charts and reference gauges
- [x] Borderline detection (10% margin flagging)
- [x] FHIR R4 export
- [x] On-device LLM (Gemma 3 1B IT via MediaPipe)
- [x] Semantic search with EmbeddingGemma 300M
- [x] RAG pipeline with citation-backed responses
- [x] Animated splash screen and onboarding flow
- [ ] Conversation memory (persistent chat sessions)
- [ ] Health Connect wearable integration
- [ ] Computed health risk scores (FIB-4, eGFR, APRI)
- [ ] Biomarker anomaly detection (EWMA, personal baselines)
- [ ] Nutritional and lifestyle recommendations
- [ ] LLM-assisted PDF extraction fallback
- [ ] Encrypted local storage with biometric lock
- [ ] Multi-patient profile support

---

## Known Limitations

- OCR for scanned reports is experimental — accuracy varies across lab formats
- Web platform is planned but not yet implemented
- The on-device LLM (1B parameters) is best suited for simple explanations; complex medical reasoning has limits inherent to the model size

---

## Contributing

Pull requests are welcome.

If you find a lab report format that the parser fails to handle, please open an issue with a redacted sample (remove personal information) or contribute a regex pattern.

When contributing, keep each commit focused on one logical change and use conventional commit messages (`feat:`, `fix:`, `chore:`, `refactor:`).

---

## License

[MIT](LICENSE)
