import 'package:animap/features/report/data/report_datetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convierte UTC a la hora correcta de Bogotá', () {
    expect(
      formatReportDateTimeInBogota('2026-09-12T15:30:00.000Z'),
      '12/09/2026, 10:30',
    );
  });

  test('conserva una fecha que ya llega con offset de Bogotá', () {
    expect(
      formatReportDateTimeInBogota('2026-09-12T10:30:00.000-05:00'),
      '12/09/2026, 10:30',
    );
  });

  test('interpreta timestamp sin zona como hora local de Bogotá', () {
    expect(
      formatReportDateTimeInBogota('2026-09-12 10:30:00'),
      '12/09/2026, 10:30',
    );
  });
}
