import 'package:flutter_test/flutter_test.dart';
import 'package:godigital_portal/hrms_admin/features/dashboard/yearly_attendance.dart';

void main() {
  test('sums months by employee ID without inventing annual salary', () {
    final rows = aggregateYearlyAttendance([
      {'employees': [{'id': 1, 'name': 'Sam', 'present': 3, 'late': 1}, {'id': 2, 'name': 'Sam', 'present': 5}]},
      {'employees': [{'id': 1, 'name': 'Sam', 'present': 4, 'late': 2}, {'id': 2, 'name': 'Sam', 'present': 6}]},
    ]);
    expect(rows, hasLength(2));
    expect(rows[0]['present'], 7);
    expect(rows[0]['late'], 3);
    expect(rows[1]['present'], 11);
    expect(rows[0]['salary'], '—');
  });
  test('rejects rows missing an ID rather than merging employees', () {
    expect(() => aggregateYearlyAttendance([{'employees': [{'name': 'Sam'}]}]), throwsFormatException);
  });
}
