import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/models/biomarker_result.dart';

void main() {
  group('BiomarkerResult.computeFlag', () {
    BiomarkerResult make({double? value, double? refLow, double? refHigh}) {
      return BiomarkerResult(
        biomarkerKey: 'test',
        displayName: 'Test',
        value: value,
        refLow: refLow,
        refHigh: refHigh,
        testDate: DateTime(2026, 3, 19),
      );
    }

    test('null value → unknown', () {
      final r = make(value: null, refLow: 0.4, refHigh: 4.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.unknown);
    });

    test('value in normal range → normal', () {
      final r = make(value: 2.0, refLow: 0.4, refHigh: 4.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.normal);
    });

    test('value below refLow → low', () {
      final r = make(value: 0.1, refLow: 0.4, refHigh: 4.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.low);
    });

    test('value above refHigh → high', () {
      final r = make(value: 5.0, refLow: 0.4, refHigh: 4.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.high);
    });

    test('value within 10% of refLow → borderline', () {
      // Range: 10.0 – 20.0, margin = 1.0, so ≤11.0 is borderline
      final r = make(value: 10.5, refLow: 10.0, refHigh: 20.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.borderline);
    });

    test('value within 10% of refHigh → borderline', () {
      // Range: 10.0 – 20.0, margin = 1.0, so ≥19.0 is borderline
      final r = make(value: 19.5, refLow: 10.0, refHigh: 20.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.borderline);
    });

    test('value at exact refLow boundary → borderline', () {
      final r = make(value: 10.0, refLow: 10.0, refHigh: 20.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.borderline);
    });

    test('value at exact refHigh boundary → borderline', () {
      final r = make(value: 20.0, refLow: 10.0, refHigh: 20.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.borderline);
    });

    test('only upper bound: value below → normal', () {
      final r = make(value: 100.0, refHigh: 200.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.normal);
    });

    test('only upper bound: value above → high', () {
      final r = make(value: 250.0, refHigh: 200.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.high);
    });

    test('only upper bound: value near boundary → borderline', () {
      // 10% of 200 = 20; ≥180 is borderline
      final r = make(value: 185.0, refHigh: 200.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.borderline);
    });

    test('only lower bound: value above → normal', () {
      final r = make(value: 100.0, refLow: 50.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.normal);
    });

    test('only lower bound: value below → low', () {
      final r = make(value: 30.0, refLow: 50.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.low);
    });

    test('only lower bound: value near boundary → borderline', () {
      // 10% of 50 = 5; ≤55 is borderline
      final r = make(value: 53.0, refLow: 50.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.borderline);
    });

    test('no reference range → unknown', () {
      final r = make(value: 42.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.unknown);
    });

    test('zero-width range (refLow == refHigh) → normal when at boundary', () {
      // margin = 0 (range * 0.10 = 0), margin > 0 check fails → normal
      final r = make(value: 5.0, refLow: 5.0, refHigh: 5.0);
      r.computeFlag();
      expect(r.flag, BiomarkerFlag.normal);
    });
  });

  group('BiomarkerResult.flag getter safety', () {
    test('valid flagIndex returns correct flag', () {
      final r = BiomarkerResult(
        biomarkerKey: 'test',
        displayName: 'Test',
        flagIndex: BiomarkerFlag.high.index,
        testDate: DateTime(2026, 3, 19),
      );
      expect(r.flag, BiomarkerFlag.high);
    });

    test('out-of-bounds flagIndex returns unknown', () {
      final r = BiomarkerResult(
        biomarkerKey: 'test',
        displayName: 'Test',
        flagIndex: 99,
        testDate: DateTime(2026, 3, 19),
      );
      expect(r.flag, BiomarkerFlag.unknown);
    });

    test('negative flagIndex returns unknown', () {
      final r = BiomarkerResult(
        biomarkerKey: 'test',
        displayName: 'Test',
        flagIndex: -1,
        testDate: DateTime(2026, 3, 19),
      );
      expect(r.flag, BiomarkerFlag.unknown);
    });
  });

  group('BiomarkerResult.formattedValue', () {
    BiomarkerResult make({double? value, String? valueText}) {
      return BiomarkerResult(
        biomarkerKey: 'test',
        displayName: 'Test',
        value: value,
        valueText: valueText,
        testDate: DateTime(2026, 3, 19),
      );
    }

    test('whole number → no decimals', () {
      expect(make(value: 150.0).formattedValue, '150');
    });

    test('normal decimal → 2 places', () {
      expect(make(value: 5.67).formattedValue, '5.67');
    });

    test('very small value → 4 places', () {
      expect(make(value: 0.005).formattedValue, '0.0050');
    });

    test('sub-1 value → 3 places', () {
      expect(make(value: 0.45).formattedValue, '0.450');
    });

    test('large value → no decimals', () {
      expect(make(value: 15000.5).formattedValue, '15001');
    });

    test('null value with valueText → returns valueText', () {
      expect(make(valueText: 'Reactive').formattedValue, 'Reactive');
    });

    test('null value without valueText → returns --', () {
      expect(make().formattedValue, '--');
    });
  });

  group('BiomarkerResult.formattedRefRange', () {
    BiomarkerResult make({double? refLow, double? refHigh, String? raw}) {
      return BiomarkerResult(
        biomarkerKey: 'test',
        displayName: 'Test',
        refLow: refLow,
        refHigh: refHigh,
        refRangeRaw: raw,
        testDate: DateTime(2026, 3, 19),
      );
    }

    test('both bounds → range string', () {
      expect(make(refLow: 0.4, refHigh: 4.0).formattedRefRange, '0.4 – 4.0');
    });

    test('only upper bound → less-than string', () {
      expect(make(refHigh: 200.0).formattedRefRange, '< 200.0');
    });

    test('only lower bound → greater-than string', () {
      expect(make(refLow: 50.0).formattedRefRange, '> 50.0');
    });

    test('raw string fallback', () {
      expect(make(raw: '< 200 mg/dL').formattedRefRange, '< 200 mg/dL');
    });

    test('no range at all → --', () {
      expect(make().formattedRefRange, '--');
    });
  });
}
