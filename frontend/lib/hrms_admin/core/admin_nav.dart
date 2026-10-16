/// Admin nav items per HRMS_PROJECT_BLUEPRINT.md, Section 1 (Approved
/// Admin pages). One "Approvals" tab covers both Leave and Extra Hours —
/// there is no separate Attendance tab (Manage Calendar is a Dashboard
/// modal, not a route).
enum AdminNavItem {
  dashboard('Dashboard', '/admin/dashboard'),
  employees('Employees', '/admin/employees'),
  approvals('Approvals', '/admin/approvals'),
  payroll('Payroll', '/admin/payroll'),
  tracking('Tracking', '/admin/tracking'),
  settings('Settings', '/admin/settings');

  final String label;
  final String route;
  const AdminNavItem(this.label, this.route);
}
