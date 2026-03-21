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
  late final Box<ChatSession> chatSessionBox;
  late final Box<PersistedChatMessage> persistedChatMessageBox;

  ObjectBoxStore._create(this.store) {
    patientBox = Box<Patient>(store);
    labReportBox = Box<LabReport>(store);
    biomarkerResultBox = Box<BiomarkerResult>(store);
    chatSessionBox = Box<ChatSession>(store);
    persistedChatMessageBox = Box<PersistedChatMessage>(store);
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

  /// Get all chat sessions, ordered by recent activity (newest first).
  List<ChatSession> getAllSessions() {
    final query = chatSessionBox.query()
      ..order(ChatSession_.lastMessageAt, flags: Order.descending);
    final built = query.build();
    final sessions = built.find();
    built.close();
    return sessions;
  }

  /// Get all messages for a chat session, ordered by timestamp (oldest first).
  List<PersistedChatMessage> getMessagesForSession(int sessionId) {
    final query = persistedChatMessageBox.query(
      PersistedChatMessage_.session.equals(sessionId),
    )..order(PersistedChatMessage_.timestamp);
    final built = query.build();
    final messages = built.find();
    built.close();
    return messages;
  }

  /// Create a new chat session titled from the first message.
  ChatSession createSession(String firstMessage) {
    final trimmed = firstMessage.trim();
    final title = trimmed.isEmpty
        ? 'New Chat'
        : (trimmed.length <= 50
              ? trimmed
              : '${trimmed.substring(0, 50).trimRight()}...');
    final now = DateTime.now();
    final session = ChatSession(
      title: title,
      createdAt: now,
      lastMessageAt: now,
    );
    chatSessionBox.put(session);
    return session;
  }

  /// Save a chat message and update the session activity timestamp.
  void saveMessage(ChatSession session, PersistedChatMessage message) {
    store.runInTransaction(TxMode.write, () {
      message.session.target = session;
      persistedChatMessageBox.put(message);

      session.lastMessageAt = message.timestamp;
      chatSessionBox.put(session);
    });
  }

  /// Delete a chat session and all of its messages.
  void deleteSession(int sessionId) {
    store.runInTransaction(TxMode.write, () {
      final query = persistedChatMessageBox
          .query(PersistedChatMessage_.session.equals(sessionId))
          .build();
      query.remove();
      query.close();
      chatSessionBox.remove(sessionId);
    });
  }

  /// Get all biomarker results for a specific report
  List<BiomarkerResult> getResultsForReport(int reportId) {
    final query = biomarkerResultBox
        .query(BiomarkerResult_.report.equals(reportId))
        .build();
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

  /// Batch-fetch history for multiple biomarker keys in a single query.
  ///
  /// Returns a map of biomarkerKey → list of results (newest first).
  /// Used by DashboardScreen to avoid N+1 queries when computing trends.
  Map<String, List<BiomarkerResult>> getHistoryForBiomarkers(Set<String> keys) {
    if (keys.isEmpty) return {};

    final query = biomarkerResultBox.query(
      BiomarkerResult_.biomarkerKey.oneOf(keys.toList()),
    )..order(BiomarkerResult_.testDate, flags: Order.descending);
    final built = query.build();
    final all = built.find();
    built.close();

    final result = <String, List<BiomarkerResult>>{};
    for (final r in all) {
      result.putIfAbsent(r.biomarkerKey, () => []).add(r);
    }
    return result;
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
    return latest.values
        .where(
          (r) =>
              r.flag == BiomarkerFlag.high ||
              r.flag == BiomarkerFlag.low ||
              r.flag == BiomarkerFlag.critical,
        )
        .length;
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
      final query = biomarkerResultBox
          .query(BiomarkerResult_.report.equals(reportId))
          .build();
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
