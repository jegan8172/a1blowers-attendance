import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:godigital_portal/hrms_admin/features/dashboard/widgets/attendance_grid.dart';

void main() {
  testWidgets('grid fits narrow and wide viewports without overflow', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [768.0, 1024.0, 1440.0, 2560.0]) {
      tester.view.physicalSize = Size(width, 800);
      for (final summary in [true, false]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: AttendanceGrid(
          days: List.generate(31, (index) => index + 1),
          dayLabels: List.generate(31, (_) => 'Mon'),
          rows: [AttendanceRowData(name: 'Employee', designation: 'Engineer',
            days: List.generate(31, (_) => const AttendanceDayMark('P')),
            present: 31, absent: 0, absentDeduction: '0', late: 0, excused: 0,
            unexcused: 0, halfLeave: 0, earnedLeave: 0, approvedLeave: 0,
            salaryPerMonth: '100', totalSalaryAfterLeaves: '100', updatedSalary: '100')], showSummary: summary,
          toolbarLeading: const SizedBox(width: 340),
        ))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width $width, summary $summary');
      }
    }
  });
  testWidgets('attendance grid advances through the month', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AttendanceGrid(
      days: List.generate(31, (index) => index + 1),
      dayLabels: List.generate(31, (_) => 'Mon'),
      rows: [AttendanceRowData(name: 'Test Employee', designation: 'Engineer',
        days: List.generate(31, (_) => const AttendanceDayMark('P')),
        present: 31, absent: 0, absentDeduction: '0', late: 0, excused: 0,
        unexcused: 0, halfLeave: 0, earnedLeave: 0, approvedLeave: 0,
        salaryPerMonth: '100', totalSalaryAfterLeaves: '100', updatedSalary: '100')],
    ))));
    expect(find.text('Test Employee'), findsOneWidget);
    expect(find.byTooltip('Next 7 days'), findsOneWidget);
    await tester.tap(find.byTooltip('Next 7 days'));
    await tester.pump();
    expect(find.text('Days 8–14 of 31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
