import 'package:objectbox/objectbox.dart';
import 'lab_report.dart';

/// Flag indicating whether a biomarker value is within reference range.
///
/// Index order matters — [flagIndex] is stored as int in ObjectBox.
/// Append new values at the end to avoid breaking existing data.
enum BiomarkerFlag { normal, low, high, critical, unknown, borderline }

/// Represents a single parsed biomarker result from a lab report.
/// This is the core data unit of the app — each row in a lab report
/// becomes one BiomarkerResult.
@Entity()
class BiomarkerResult {
  @Id()
  int id;

  /// Relation to the parent lab report
  final report = ToOne<LabReport>();

  /// Canonical key from the biomarker dictionary (e.g., "tsh", "hba1c")
  @Index()
  String biomarkerKey;

  /// Human-readable display name (e.g., "Thyroid Stimulating Hormone")
  String displayName;

  /// The original test name as printed on the lab report
  String? originalName;

  /// Numerical value of the result
  double? value;

  /// String representation for non-numeric values (e.g., "Reactive", "Non-Reactive")
  String? valueText;

  /// Unit of measurement (e.g., "mg/dL", "mIU/L", "cells/cumm")
  String? unit;

  /// Lower bound of the reference range
  double? refLow;

  /// Upper bound of the reference range
  double? refHigh;

  /// Reference range as a raw string from the report (e.g., "0.4 - 4.0")
  String? refRangeRaw;

  /// Flag: normal, low, high, critical, unknown
  /// Stored as int index of BiomarkerFlag enum
  int flagIndex;

  /// LOINC code for interoperability (FHIR export)
  String? loincCode;

  /// Category grouping (e.g., "Thyroid", "CBC", "Lipid Panel")
  String? category;

  /// Date the test was performed (denormalized from LabReport for quick queries)
  @Property(type: PropertyType.date)
  @Index()
  DateTime testDate;

  /// Embedding vector for RAG (stored as float list, used with HNSW later)
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  BiomarkerResult({
    this.id = 0,
    required this.biomarkerKey,
    required this.displayName,
    this.originalName,
    this.value,
    this.valueText,
    this.unit,
    this.refLow,
    this.refHigh,
    this.refRangeRaw,
    this.flagIndex = 4, // BiomarkerFlag.unknown
    this.loincCode,
    this.category,
    required this.testDate,
    this.embedding,
  });

  /// Convenience getter for the flag enum
  BiomarkerFlag get flag => BiomarkerFlag.values[flagIndex];

  /// Convenience setter for the flag enum
  set flag(BiomarkerFlag f) => flagIndex = f.index;

  /// Compute the flag based on the value and reference range.
  ///
  /// Values within 10% of a boundary are marked [BiomarkerFlag.borderline]
  /// (rendered as amber in the UI) to alert users before they go out of range.
  void computeFlag() {
    if (value == null) {
      flagIndex = BiomarkerFlag.unknown.index;
      return;
    }

    final v = value!;

    if (refLow != null && refHigh != null) {
      if (v < refLow!) {
        flagIndex = BiomarkerFlag.low.index;
      } else if (v > refHigh!) {
        flagIndex = BiomarkerFlag.high.index;
      } else {
        // In range — check if borderline (within 10% of either boundary)
        final range = refHigh! - refLow!;
        final margin = range * 0.10;
        if (margin > 0 && (v <= refLow! + margin || v >= refHigh! - margin)) {
          flagIndex = BiomarkerFlag.borderline.index;
        } else {
          flagIndex = BiomarkerFlag.normal.index;
        }
      }
    } else if (refHigh != null) {
      // Only upper bound (e.g., Cholesterol < 200)
      if (v > refHigh!) {
        flagIndex = BiomarkerFlag.high.index;
      } else {
        final margin = refHigh! * 0.10;
        flagIndex = (margin > 0 && v >= refHigh! - margin)
            ? BiomarkerFlag.borderline.index
            : BiomarkerFlag.normal.index;
      }
    } else if (refLow != null) {
      // Only lower bound
      if (v < refLow!) {
        flagIndex = BiomarkerFlag.low.index;
      } else {
        final margin = refLow! * 0.10;
        flagIndex = (margin > 0 && v <= refLow! + margin)
            ? BiomarkerFlag.borderline.index
            : BiomarkerFlag.normal.index;
      }
    } else {
      flagIndex = BiomarkerFlag.unknown.index;
    }
  }

  /// Format the value for display
  String get formattedValue {
    if (value != null) {
      // Show integer if whole number, otherwise 2 decimal places
      return value! == value!.roundToDouble()
          ? value!.toInt().toString()
          : value!.toStringAsFixed(2);
    }
    return valueText ?? '--';
  }

  /// Format the reference range for display
  String get formattedRefRange {
    if (refLow != null && refHigh != null) {
      return '${refLow!.toStringAsFixed(1)} – ${refHigh!.toStringAsFixed(1)}';
    } else if (refHigh != null) {
      return '< ${refHigh!.toStringAsFixed(1)}';
    } else if (refLow != null) {
      return '> ${refLow!.toStringAsFixed(1)}';
    }
    return refRangeRaw ?? '--';
  }
}
