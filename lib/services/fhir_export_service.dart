import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart' as pkg_uuid;

import '../models/models.dart' as app;

/// Exports patient health data as spec-compliant FHIR R4 Bundles
/// using the typed [fhir_r4] package.
class FhirExportService {
  final _uuid = const pkg_uuid.Uuid();

  // ─── Public API ─────────────────────────────────────────────────────

  /// Export all reports as a single FHIR R4 collection Bundle.
  String exportAll({
    required app.Patient patient,
    required List<app.LabReport> reports,
    required Map<int, List<app.BiomarkerResult>> resultsByReport,
  }) {
    final patientId = _uuid.v4();
    final patientResource = _buildPatient(patient, patientId);

    final entries = <BundleEntry>[
      BundleEntry(
        fullUrl: FhirUri('urn:uuid:$patientId'),
        resource: patientResource,
      ),
    ];

    for (final report in reports) {
      final results = resultsByReport[report.id] ?? [];
      if (results.isEmpty) continue;

      final reportId = _uuid.v4();
      final obsRefs = <Reference>[];

      for (final result in results) {
        final obsId = _uuid.v4();
        final observation = _buildObservation(
          result: result,
          obsId: obsId,
          patientId: patientId,
        );
        entries.add(
          BundleEntry(
            fullUrl: FhirUri('urn:uuid:$obsId'),
            resource: observation,
          ),
        );
        obsRefs.add(Reference(reference: 'Observation/$obsId'.toFhirString));
      }

      final diagnosticReport = _buildDiagnosticReport(
        report: report,
        reportId: reportId,
        patientId: patientId,
        observationRefs: obsRefs,
      );
      entries.add(
        BundleEntry(
          fullUrl: FhirUri('urn:uuid:$reportId'),
          resource: diagnosticReport,
        ),
      );
    }

    final bundle = Bundle(
      id: _uuid.v4().toFhirString,
      type: BundleType.collection,
      timestamp: DateTime.now().toUtc().toFhirInstant,
      entry: entries,
    );

    return jsonEncode(bundle.toJson());
  }

  /// Export a single report as a FHIR R4 Bundle.
  String exportReport({
    required app.Patient patient,
    required app.LabReport report,
    required List<app.BiomarkerResult> results,
  }) {
    return exportAll(
      patient: patient,
      reports: [report],
      resultsByReport: {report.id: results},
    );
  }

  // ─── Resource Builders ──────────────────────────────────────────────

  Patient _buildPatient(app.Patient patient, String id) {
    final name = <HumanName>[HumanName(text: patient.name.toFhirString)];

    return Patient(
      id: id.toFhirString,
      name: name,
      gender: _mapGenderEnum(patient.sex),
      birthDate: patient.dateOfBirth != null
          ? DateFormat('yyyy-MM-dd').format(patient.dateOfBirth!).toFhirDate
          : null,
    );
  }

  Observation _buildObservation({
    required app.BiomarkerResult result,
    required String obsId,
    required String patientId,
  }) {
    // Code (LOINC or free-text)
    final coding = <Coding>[];
    if (result.loincCode != null && result.loincCode!.isNotEmpty) {
      coding.add(
        Coding(
          system: FhirUri('http://loinc.org'),
          code: FhirCode(result.loincCode!),
          display: result.displayName.toFhirString,
        ),
      );
    }

    final code = CodeableConcept(
      coding: coding.isNotEmpty ? coding : null,
      text: result.displayName.toFhirString,
    );

    // Category — laboratory
    final category = <CodeableConcept>[
      CodeableConcept(
        coding: [
          Coding(
            system: FhirUri(
              'http://terminology.hl7.org/CodeSystem/observation-category',
            ),
            code: FhirCode('laboratory'),
            display: 'Laboratory'.toFhirString,
          ),
        ],
      ),
    ];

    // Value
    Quantity? valueQuantity;
    FhirString? valueString;

    if (result.value != null) {
      valueQuantity = Quantity(
        value: FhirDecimal(result.value!),
        unit: result.unit?.toFhirString,
        system: result.unit != null
            ? FhirUri('http://unitsofmeasure.org')
            : null,
        code: result.unit != null ? FhirCode(_mapToUcum(result.unit!)) : null,
      );
    } else if (result.valueText != null && result.valueText!.isNotEmpty) {
      valueString = result.valueText!.toFhirString;
    }

    // Reference range
    final refRanges = <ObservationReferenceRange>[];
    if (result.refLow != null || result.refHigh != null) {
      refRanges.add(
        ObservationReferenceRange(
          low: result.refLow != null
              ? Quantity(
                  value: FhirDecimal(result.refLow!),
                  unit: result.unit?.toFhirString,
                )
              : null,
          high: result.refHigh != null
              ? Quantity(
                  value: FhirDecimal(result.refHigh!),
                  unit: result.unit?.toFhirString,
                )
              : null,
        ),
      );
    }

    // Interpretation
    final interpretationMapping = _mapInterpretation(result.flag);
    final interpretation = interpretationMapping != null
        ? <CodeableConcept>[
            CodeableConcept(
              coding: [
                Coding(
                  system: FhirUri(
                    'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation',
                  ),
                  code: FhirCode(interpretationMapping['code']!),
                  display: interpretationMapping['display']!.toFhirString,
                ),
              ],
            ),
          ]
        : null;

    return Observation(
      id: obsId.toFhirString,
      status: ObservationStatus.final_,
      category: category,
      code: code,
      subject: Reference(reference: 'Patient/$patientId'.toFhirString),
      effectiveDateTime: DateFormat(
        'yyyy-MM-dd',
      ).format(result.testDate).toFhirDateTime,
      valueQuantity: valueQuantity,
      valueString: valueString,
      interpretation: interpretation,
      referenceRange: refRanges.isNotEmpty ? refRanges : null,
    );
  }

  DiagnosticReport _buildDiagnosticReport({
    required app.LabReport report,
    required String reportId,
    required String patientId,
    required List<Reference> observationRefs,
  }) {
    return DiagnosticReport(
      id: reportId.toFhirString,
      status: DiagnosticReportStatus.final_,
      category: [
        CodeableConcept(
          coding: [
            Coding(
              system: FhirUri('http://terminology.hl7.org/CodeSystem/v2-0074'),
              code: FhirCode('LAB'),
              display: 'Laboratory'.toFhirString,
            ),
          ],
        ),
      ],
      code: CodeableConcept(
        text: '${report.labName ?? report.originalFileName ?? "Lab"} Report'
            .toFhirString,
      ),
      subject: Reference(reference: 'Patient/$patientId'.toFhirString),
      effectiveDateTime: DateFormat(
        'yyyy-MM-dd',
      ).format(report.reportDate).toFhirDateTime,
      result: observationRefs,
    );
  }

  // ─── Mapping Helpers ────────────────────────────────────────────────

  AdministrativeGender _mapGenderEnum(String? sex) {
    switch (sex) {
      case 'M':
        return AdministrativeGender.male;
      case 'F':
        return AdministrativeGender.female;
      case 'O':
        return AdministrativeGender.other;
      default:
        return AdministrativeGender.unknown;
    }
  }

  Map<String, String>? _mapInterpretation(app.BiomarkerFlag flag) {
    switch (flag) {
      case app.BiomarkerFlag.normal:
        return {'code': 'N', 'display': 'Normal'};
      case app.BiomarkerFlag.borderline:
        return {'code': 'IND', 'display': 'Indeterminate'};
      case app.BiomarkerFlag.low:
        return {'code': 'L', 'display': 'Low'};
      case app.BiomarkerFlag.high:
        return {'code': 'H', 'display': 'High'};
      case app.BiomarkerFlag.critical:
        return {'code': 'HH', 'display': 'Critically high'};
      case app.BiomarkerFlag.unknown:
        return null;
    }
  }

  String _mapToUcum(String unit) {
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
        return unit;
    }
  }
}
