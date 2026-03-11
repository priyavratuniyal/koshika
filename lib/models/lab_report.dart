import 'package:objectbox/objectbox.dart';
import 'patient.dart';

/// Represents a single imported lab report PDF.
/// Each report can contain multiple biomarker results.
@Entity()
class LabReport {
  @Id()
  int id;

  /// Relation to the patient this report belongs to
  final patient = ToOne<Patient>();

  /// Name of the lab (e.g., "Thyrocare", "Dr Lal PathLabs", "SRL")
  String? labName;

  /// Date the lab test was performed
  @Property(type: PropertyType.date)
  DateTime reportDate;

  /// Local file path to the stored PDF
  String pdfPath;

  /// Original filename of the imported PDF
  String? originalFileName;

  /// When this report was imported into the app
  @Property(type: PropertyType.date)
  DateTime importedAt;

  /// Number of biomarkers successfully extracted
  int extractedCount;

  /// Total biomarkers detected (including failed parses)
  int totalDetected;

  /// Raw extracted text from the PDF (for re-parsing / debugging)
  String? rawText;

  LabReport({
    this.id = 0,
    this.labName,
    required this.reportDate,
    required this.pdfPath,
    this.originalFileName,
    DateTime? importedAt,
    this.extractedCount = 0,
    this.totalDetected = 0,
    this.rawText,
  }) : importedAt = importedAt ?? DateTime.now();
}
