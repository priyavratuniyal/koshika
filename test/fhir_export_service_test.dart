import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:koshika/models/models.dart';
import 'package:koshika/services/fhir_export_service.dart';

void main() {
  group('FhirExportService', () {
    test('normalizes cells per microliter to UCUM', () {
      final service = FhirExportService();
      final patient = Patient(name: 'Tester');
      final report = LabReport(
        id: 1,
        reportDate: DateTime(2026, 3, 14),
        pdfPath: '/tmp/report.pdf',
      );
      final result = BiomarkerResult(
        biomarkerKey: 'wbc_count',
        displayName: 'WBC Count',
        value: 8500,
        unit: 'cells/uL',
        loincCode: '6690-2',
        testDate: DateTime(2026, 3, 14),
      );

      final bundleJson = service.exportReport(
        patient: patient,
        report: report,
        results: [result],
      );
      final bundle = jsonDecode(bundleJson) as Map<String, dynamic>;
      final entries = bundle['entry'] as List<dynamic>;
      final observation = entries
          .map((entry) => entry['resource'] as Map<String, dynamic>)
          .firstWhere((resource) => resource['resourceType'] == 'Observation');

      expect(observation['valueQuantity']['code'], '/uL');
    });
  });
}
