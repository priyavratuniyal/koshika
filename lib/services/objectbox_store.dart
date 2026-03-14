import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../objectbox.g.dart';
import '../models/models.dart';

/// Singleton wrapper around ObjectBox Store.
/// Initialized once at app startup, provides typed Box accessors.
class ObjectBoxStore {
  late final Store store;

  late final Box<Patient> patientBox;
  late final Box<LabReport> labReportBox;
  late final Box<BiomarkerResult> biomarkerResultBox;

  ObjectBoxStore._create(this.store) {
    patientBox = Box<Patient>(store);
    labReportBox = Box<LabReport>(store);
    biomarkerResultBox = Box<BiomarkerResult>(store);
  }

  /// Initialize the ObjectBox store. Call once during app startup.
  static Future<ObjectBoxStore> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final store = await openStore(
      directory: p.join(docsDir.path, 'koshika-db'),
    );
    return ObjectBoxStore._create(store);
  }

  /// Get or create the default patient profile.
  /// For MVP, there's one user = one patient.
  Patient getOrCreateDefaultPatient({String name = 'Me'}) {
    final patients = patientBox.getAll();
    if (patients.isNotEmpty) {
      return patients.first;
    }
    final patient = Patient(name: name);
    patientBox.put(patient);
    return patient;
  }

  /// Get all lab reports, ordered by report date (newest first)
  List<LabReport> getAllReports() {
    final query = labReportBox.query()
      ..order(LabReport_.reportDate, flags: Order.descending);
    final built = query.build();
    final results = built.find();
    built.close();
    return results;
  }

  /// Get all biomarker results for a specific report
  List<BiomarkerResult> getResultsForReport(int reportId) {
    final query = biomarkerResultBox.query(
      BiomarkerResult_.report.equals(reportId),
    ).build();
    final results = query.find();
    query.close();
    return results;
  }

  /// Get all historical values for a specific biomarker key, ordered by date
  List<BiomarkerResult> getHistoryForBiomarker(String biomarkerKey) {
    final query = biomarkerResultBox.query(
      BiomarkerResult_.biomarkerKey.equals(biomarkerKey),
    )..order(BiomarkerResult_.testDate, flags: Order.descending);
    final built = query.build();
    final results = built.find();
    built.close();
    return results;
  }

  /// Get the latest result for each unique biomarker key
  Map<String, BiomarkerResult> getLatestResults() {
    final all = biomarkerResultBox.query()
      ..order(BiomarkerResult_.testDate, flags: Order.descending);
    final built = all.build();
    final results = built.find();
    built.close();

    final latest = <String, BiomarkerResult>{};
    for (final result in results) {
      if (!latest.containsKey(result.biomarkerKey)) {
        latest[result.biomarkerKey] = result;
      }
    }
    return latest;
  }

  /// Get count of out-of-range results from the latest values
  int getOutOfRangeCount() {
    final latest = getLatestResults();
    return latest.values.where((r) =>
      r.flag == BiomarkerFlag.high ||
      r.flag == BiomarkerFlag.low ||
      r.flag == BiomarkerFlag.critical
    ).length;
  }

  /// Store a parsed lab report with its biomarker results
  void saveReportWithResults(LabReport report, List<BiomarkerResult> results) {
    store.runInTransaction(TxMode.write, () {
      labReportBox.put(report);
      for (final result in results) {
        result.report.target = report;
        biomarkerResultBox.put(result);
      }
      report.extractedCount = results.length;
      labReportBox.put(report);
    });
  }

  /// Delete a report and all its associated biomarker results
  void deleteReport(int reportId) {
    store.runInTransaction(TxMode.write, () {
      final query = biomarkerResultBox.query(
        BiomarkerResult_.report.equals(reportId),
      ).build();
      final results = query.find();
      query.close();

      for (final r in results) {
        biomarkerResultBox.remove(r.id);
      }
      labReportBox.remove(reportId);
    });
  }

  void close() {
    store.close();
  }
}
