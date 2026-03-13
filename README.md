# Koshika

![Status](https://img.shields.io/badge/Status-Active_Development-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Android%20|%20iOS%20|%20Web-blue)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.9.2-0175C2)

**Your health data lives in your cell, not the cloud.**
Koshika is an offline-first, privacy-focused Flutter application designed to extract, parse, and trend biomarker data from unstructured PDF lab reports entirely on-device.

## Features

*   **On-Device PDF Parsing:** Extracts raw text and structure from PDFs securely using `syncfusion_flutter_pdf` without sending your personal health data to the cloud.
*   **Intelligent Regex Engine:** A multi-pattern matching fallback system specifically designed to handle unstructured formats typical of Indian pathology labs (Thyrocare, SRL, Dr. Lal, etc.).
*   **Fuzzy Term Matching:** Standardizes raw lab terminology into an internal dictionary schema so that variations (e.g., "FASTING SUGAR" vs "Glucose F") align perfectly for historical tracking.
*   **Private Database:** Data is persisted in lightning-fast `ObjectBox` document stores.
*   **Beautiful Visualizations:** *(Coming Soon)* Dynamic charting with `fl_chart` to track your health trends over time.

## Platforms

- Android
- iOS
- Web (Planned)

## Architecture & Tech Stack

This project uses standard Flutter `StatefulWidget` tree passing for local state, persisting to an **ObjectBox NoSQL database** for offline persistence.

- **Frontend:** Flutter
- **Local DB:** ObjectBox
- **Extraction:** syncfusion_flutter_pdf
- **Text Analysis:** custom Multi-Regex Engine + string_similarity matching

## Project Structure

```text
lib/
├── models/             # ObjectBox Entities (Patient, LabReport, BiomarkerResult)
├── screens/            # UI Views (ReportDetails, Home, Dashboard)
├── services/           # Core Logic (PdfExtractor, LabParser, StoreOrchestrator)
└── main.dart           # App Entry Point & Navigation
assets/
└── data/               # Local JSON dictionaries mapping lab terminology
```

## Getting Started

### Prerequisites
*   Flutter SDK (Compatible with Dart `>=3.9.2`)
*   Code Editor (VS Code / Android Studio)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/priyavratuniyal/koshika.git
cd koshika
```

2. Fetch Flutter packages:
```bash
flutter pub get
```

3. Generate the ObjectBox bindings:
```bash
dart run build_runner build --delete-conflicting-outputs
```

4. Run the app:
```bash
flutter run
```

## Contributing
Pull requests are welcome! If you find a lab report format that our parser fails to scrape, please consider opening an issue or contributing a regex fallback.

## License
This project is open-source and available under standard open source provisions.
