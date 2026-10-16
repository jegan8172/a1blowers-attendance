/// Employee nav items per HRMS_PROJECT_BLUEPRINT.md, Section 1 (Approved
/// Employee pages), using the top-nav pattern (Section 3, revised
/// 2026-08-28 — no left sidebar on desktop/tablet).
enum EmployeeNavItem {
  dashboard('Dashboard', '/employee/dashboard'),
  attendance('Attendance', '/employee/attendance'),
  clockLog('Clock In/Out', '/employee/clock-log'),
  leave('Leave', '/employee/leave'),
  extraHours('Extra Hours', '/employee/extra-hours'),
  salary('Salary', '/employee/salary'),
  tracking('Tracking', '/employee/tracking');

  final String label;
  final String route;
  const EmployeeNavItem(this.label, this.route);
}
