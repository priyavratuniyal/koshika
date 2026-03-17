import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

class FhirExportService {
  final _uuid = const Uuid();

  /// Export all data as a single FHIR R4 Bundle
  String exportAll({
    required Patient patient,
    required List<LabReport> reports,
    required Map<int, List<BiomarkerResult>> resultsByReport,
  }) {
    final patientId = _uuid.v4();
    final patientResource = _buildPatientResource(patient, patientId);

    final entries = <Map<String, dynamic>>[
      {'fullUrl': 'urn:uuid:$patientId', 'resource': patientResource},
    ];

    for (final report in reports) {
      final results = resultsByReport[report.id] ?? [];
      if (results.isEmpty) continue;

      final reportId = _uuid.v4();
      final obsRefs = <Map<String, String>>[];

      for (final result in results) {
        final obsId = _uuid.v4();
        final obsResource = _buildObservationResource(
          result: result,
          obsId: obsId,
          patientId: patientId,
        );
        entries.add({'fullUrl': 'urn:uuid:$obsId', 'resource': obsResource});
        obsRefs.add({'reference': 'Observation/$obsId'});
      }

      final reportResource = _buildDiagnosticReportResource(
        report: report,
        reportId: reportId,
        patientId: patientId,
        observationReferences: obsRefs,
      );
      entries.add({
        'fullUrl': 'urn:uuid:$reportId',
        'resource': reportResource,
      });
    }

    final bundle = {
      'resourceType': 'Bundle',
      'id': _uuid.v4(),
      'type': 'collection',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'entry': entries,
    };

    return jsonEncode(bundle);
  }

  /// Export a single report as a FHIR R4 Bundle
  String exportReport({
    required Patient patient,
    required LabReport report,
    required List<BiomarkerResult> results,
  }) {
    return exportAll(
      patient: patient,
      reports: [report],
      resultsByReport: {report.id: results},
    );
  }

  Map<String, dynamic> _buildPatientResource(Patient patient, String id) {
    final resource = <String, dynamic>{
      'resourceType': 'Patient',
      'id': id,
      'name': [
        {'text': patient.name},
      ],
      'gender': _mapGender(patient.sex),
    };

    if (patient.dateOfBirth != null) {
      resource['birthDate'] = DateFormat(
        'yyyy-MM-dd',
      ).format(patient.dateOfBirth!);
    }

    return resource;
  }

  String _mapGender(String? sex) {
    switch (sex) {
      case 'M':
        return 'male';
      case 'F':
        return 'female';
      case 'O':
        return 'other';
      default:
        return 'unknown';
    }
  }

  Map<String, dynamic> _buildObservationResource({
    required BiomarkerResult result,
    required String obsId,
    required String patientId,
  }) {
    final resource = <String, dynamic>{
      'resourceType': 'Observation',
      'id': obsId,
      'status': 'final',
      'category': [
        {
          'coding': [
            {
              'system':
                  'http://terminology.hl7.org/CodeSystem/observation-category',
              'code': 'laboratory',
              'display': 'Laboratory',
            },
          ],
        },
      ],
      'subject': {'reference': 'Patient/$patientId'},
      'effectiveDateTime': DateFormat('yyyy-MM-dd').format(result.testDate),
    };

    // Code (LOINC or Text)
    if (result.loincCode != null && result.loincCode!.isNotEmpty) {
      resource['code'] = {
        'coding': [
          {
            'system': 'http://loinc.org',
            'code': result.loincCode,
            'display': result.displayName,
          },
        ],
        'text': result.displayName,
      };
    } else {
      resource['code'] = {'text': result.displayName};
    }

    // Value
    if (result.value != null) {
      final valueQuantity = <String, dynamic>{'value': result.value};

      if (result.unit != null && result.unit!.isNotEmpty) {
        valueQuantity['unit'] = result.unit;
        // Basic mapping to UCUM (not exhaustive but covers common ones)
        valueQuantity['system'] = 'http://unitsofmeasure.org';
        valueQuantity['code'] = _mapToUcum(result.unit!);
      }

      resource['valueQuantity'] = valueQuantity;
    } else if (result.valueText != null && result.valueText!.isNotEmpty) {
      resource['valueString'] = result.valueText;
    }

    // Reference Range
    if (result.refLow != null || result.refHigh != null) {
      final refRange = <String, dynamic>{};

      if (result.refLow != null) {
        refRange['low'] = {'value': result.refLow};
        if (result.unit != null) refRange['low']['unit'] = result.unit;
      }

      if (result.refHigh != null) {
        refRange['high'] = {'value': result.refHigh};
        if (result.unit != null) refRange['high']['unit'] = result.unit;
      }

      resource['referenceRange'] = [refRange];
    }

    // Interpretation Flag
    final interpretationStr = _mapInterpretation(result.flag);
    if (interpretationStr != null) {
      resource['interpretation'] = [
        {
          'coding': [
            {
              'system':
                  'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation',
              'code': interpretationStr['code'],
              'display': interpretationStr['display'],
            },
          ],
        },
      ];
    }

    return resource;
  }

  Map<String, dynamic> _buildDiagnosticReportResource({
    required LabReport report,
    required String reportId,
    required String patientId,
    required List<Map<String, String>> observationReferences,
  }) {
    return {
      'resourceType': 'DiagnosticReport',
      'id': reportId,
      'status': 'final',
      'category': [
        {
          'coding': [
            {
              'system': 'http://terminology.hl7.org/CodeSystem/v2-0074',
              'code': 'LAB',
              'display': 'Laboratory',
            },
          ],
        },
      ],
      'code': {
        'text': '${report.labName ?? report.originalFileName ?? "Lab"} Report',
      },
      'subject': {'reference': 'Patient/$patientId'},
      'effectiveDateTime': DateFormat('yyyy-MM-dd').format(report.reportDate),
      'result': observationReferences,
    };
  }

  Map<String, String>? _mapInterpretation(BiomarkerFlag flag) {
    switch (flag) {
      case BiomarkerFlag.normal:
        return {'code': 'N', 'display': 'Normal'};
      case BiomarkerFlag.borderline:
        return {'code': 'IND', 'display': 'Indeterminate'};
      case BiomarkerFlag.low:
        return {'code': 'L', 'display': 'Low'};
      case BiomarkerFlag.high:
        return {'code': 'H', 'display': 'High'};
      case BiomarkerFlag.critical:
        return {'code': 'HH', 'display': 'Critically high'};
      case BiomarkerFlag.unknown:
        return null; // Omit if unknown
    }
  }

  String _mapToUcum(String unit) {
    // Map common Indian lab units to UCUM codes
    switch (unit.toLowerCase()) {
      case 'mg/dl':
        return 'mg/dL';
      case 'g/dl':
        return 'g/dL';
      case 'miu/l':
        return 'm[IU]/L';
      case 'µiu/ml':
      case 'uiu/ml':
        return 'u[IU]/mL';
      case 'ng/ml':
        return 'ng/mL';
      case 'pg/ml':
        return 'pg/mL';
      case 'cells/cumm':
      case 'cells/ul':
        return '/uL';
      case 'million/cumm':
      case 'million/ul':
        return '10*6/uL';
      case '%':
        return '%';
      case 'mm/hr':
      case 'mm/h':
        return 'mm/h';
      case 'iu/l':
        return '[IU]/L';
      case 'u/l':
        return 'U/L';
      case 'mmol/l':
        return 'mmol/L';
      case 'meq/l':
        return 'meq/L';
      case 'µg/dl':
      case 'ug/dl':
        return 'ug/dL';
      case 'fl':
        return 'fL';
      case 'pg':
        return 'pg';
      default:
        return unit; // Pass through unknown as-is
    }
  }
}
