import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae/utils/demo_attendance_seed.dart';

void main() {
  test('demo seed provides five complete attendance days', () {
    final records = DemoAttendanceSeed.records(
      nowUtc: DateTime.utc(2026, 11, 19, 4),
      offsetMinutes: 330,
    );

    expect(records, hasLength(5));
    expect(
      records.map((record) => record.dateKey).toList(),
      <String>[
        '2026-11-18',
        '2026-11-17',
        '2026-11-16',
        '2026-11-15',
        '2026-11-14',
      ],
    );
    for (final record in records) {
      expect(record.checkIn, isNotNull);
      expect(record.checkOut, isNotNull);
      expect(record.workingDuration, isNotNull);
    }
  });
}
