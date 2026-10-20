const db = require('../config/db');
const bcrypt = require('bcrypt');
const { normalizePhone } = require('../lib/employeePhone');
const { employeeFilters } = require('../lib/employeeFilters');
const {
  createEmployeeAtomically,
  assertUniqueForUpdate,
  duplicateMessage
} = require('../lib/employeeCreationService');

function ok(res, data, message) {
  return res.json({ success: true, message: message || 'OK', data: data });
}

function fail(res, status, message) {
  return res.status(status).json({ success: false, message: message });
}

function requireAdmin(req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
}

function modeColor(mode) {
  if (mode === 'Home') return 0xFF0B8B16;
  if (mode === 'Field') return 0xFF16B9C5;
  return 0xFF0668F6;
}

function joiningDate(value) {
  const date = String(value || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  return date;
}

function formatSalary(value) {
  if (value === null || value === undefined || value === '') return 'Not Set';
  const amount = Number(value);
  if (!Number.isFinite(amount)) return 'Not Set';
  return '₹' + Math.round(amount).toLocaleString('en-US');
}

function parseSalary(value) {
  if (value === null || value === undefined || value === '' || value === 'Not Set') return null;
  const digits = String(value).replace(/[^0-9]/g, '');
  if (!digits) return null;
  return Number(digits);
}

function salaryCycle(body) {
  const salaryType = String(body.salaryType || body.salary_type || 'Standard').trim();
  if (!['Standard', 'Flexible'].includes(salaryType)) {
    return { error: 'salaryType must be Standard or Flexible' };
  }
  if (salaryType === 'Standard') return { salaryType: salaryType, cycleStartDay: null, cycleEndDay: null, cycleStartDate: null, cycleEndDate: null };
  const cycleStartDay = Number(body.flexibleCycleStartDay || body.flexible_cycle_start_day);
  const cycleEndDay = Number(body.flexibleCycleEndDay || body.flexible_cycle_end_day);
  if (!Number.isInteger(cycleStartDay) || cycleStartDay < 1 || cycleStartDay > 31 ||
      !Number.isInteger(cycleEndDay) || cycleEndDay < 1 || cycleEndDay > 31) {
    return { error: 'Flexible salary requires cycle start and end days from 1 to 31' };
  }
  const asDate = function (value) {
    const match = String(value || '').match(/^(\d{4}-\d{2}-\d{2})/);
    return match ? match[1] : null;
  };
  const cycleStartDate = asDate(body.flexibleCycleStartDate || body.flexible_cycle_start_date);
  const cycleEndDate = asDate(body.flexibleCycleEndDate || body.flexible_cycle_end_date);
  if ((cycleStartDate && !cycleEndDate) || (!cycleStartDate && cycleEndDate) ||
      (cycleStartDate && cycleEndDate && cycleStartDate > cycleEndDate)) {
    return { error: 'Flexible salary start and end dates must be valid' };
  }
  return { salaryType: salaryType, cycleStartDay: cycleStartDay, cycleEndDay: cycleEndDay, cycleStartDate: cycleStartDate, cycleEndDate: cycleEndDate };
}

async function ensureCompensationTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_employee_compensation (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    profile_id BIGINT UNSIGNED NULL,
    employee_user_id BIGINT UNSIGNED NULL,
    monthly_salary DECIMAL(12,2) NOT NULL,
    effective_from DATE NOT NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY profile_effective (profile_id, effective_from),
    KEY user_effective (employee_user_id, effective_from)
  )`);
  try { await db.query('ALTER TABLE hrms_employee_compensation ADD COLUMN profile_id BIGINT UNSIGNED NULL AFTER id'); } catch (_) {}
}

async function recordCompensation(profile, salary, adminId, executor) {
  if (salary === null || salary === undefined) return;
  const connection = executor || db;
  const [latest] = await connection.query(`SELECT monthly_salary FROM hrms_employee_compensation WHERE profile_id = ? ORDER BY effective_from DESC, id DESC LIMIT 1`, [profile.id]);
  if (latest[0] && Number(latest[0].monthly_salary) === Number(salary)) return;
  await connection.query(`INSERT INTO hrms_employee_compensation (profile_id, employee_user_id, monthly_salary, effective_from, created_by)
    VALUES (?, ?, ?, CURDATE(), ?)`, [profile.id, profile.employee_user_id || null, salary, adminId || null]);
}

function toUi(row) {
    return {
    id: row.id,
    name: row.full_name,
    employeeCode: row.employee_code,
    employeeId: row.employee_code,
    department: row.department,
    workMode: row.work_mode,
    employeeType: row.employee_type || 'Employee',
    overtimeEligible: Boolean(Number(row.overtime_eligible || 0)),
    gender: row.gender || 'Male',
    salary: formatSalary(row.monthly_salary),
    monthlySalary: row.monthly_salary,
    salaryType: row.salary_type || 'Standard',
    flexibleCycleStartDay: row.flexible_cycle_start_day == null ? null : Number(row.flexible_cycle_start_day),
    flexibleCycleEndDay: row.flexible_cycle_end_day == null ? null : Number(row.flexible_cycle_end_day),
    flexibleCycleStartDate: row.flexible_cycle_start_date || null,
    flexibleCycleEndDate: row.flexible_cycle_end_date || null,
    joiningDate: row.joining_date ? String(row.joining_date).slice(0, 10) : null,
    weeklyOffTemplate: row.weekly_off_template || 'Global Payroll Policy',
    status: row.employment_status,
    modeColor: modeColor(row.work_mode),
      email: row.email || '',
    phone: row.phone || '',
    username: row.username || '',
    passwordLastChangedAt: row.password_last_changed_at || null,
    employeeUserId: row.employee_user_id
  };
}

async function summary(req, res) {
  try {
    const [rows] = await db.query(
      "SELECT COUNT(*) AS total, SUM(p.employment_status = 'Active') AS active, SUM(p.employment_status = 'On Leave') AS onLeave, SUM(p.employment_status = 'Inactive') AS inactive FROM hrms_employee_profiles p INNER JOIN employee_users u ON u.id = p.employee_user_id WHERE u.is_active = 1"
    );
    const row = rows[0];
    return ok(res, {
      total: Number(row.total || 0),
      active: Number(row.active || 0),
      onLeave: Number(row.onLeave || 0),
      inactive: Number(row.inactive || 0)
    });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function list(req, res) {
  try {
    await db.query(`CREATE TABLE IF NOT EXISTS hrms_password_change_log (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_user_id BIGINT UNSIGNED NOT NULL,
      changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, changed_by VARCHAR(30) NOT NULL DEFAULT 'employee',
      KEY password_changed_employee (employee_user_id, changed_at)
    )`);
    const { clause, params } = employeeFilters(req.query);
    const page = Math.max(1, Number(req.query.page || 1));
    const limit = Math.min(50, Math.max(1, Number(req.query.limit || 6)));
    const [countRows] = await db.query('SELECT COUNT(*) AS total FROM hrms_employee_profiles p INNER JOIN employee_users u ON u.id = p.employee_user_id ' + clause, params);
    const total = Number(countRows[0].total || 0);
    const totalPages = Math.max(1, Math.ceil(total / limit));
    const safePage = Math.min(page, totalPages);
    const offset = (safePage - 1) * limit;

    const [rows] = await db.query(
      `SELECT p.*, DATE_FORMAT(p.joining_date, '%Y-%m-%d') AS joining_date, u.username AS username,
       (SELECT t.name FROM hrms_employee_weekly_off_assignments a
         JOIN hrms_weekly_off_templates t ON t.id = a.template_id
        WHERE a.profile_id = p.id AND a.effective_from <= CURDATE()
        ORDER BY a.effective_from DESC, a.id DESC LIMIT 1) AS weekly_off_template,
       (SELECT MAX(changed_at) FROM hrms_password_change_log l WHERE l.employee_user_id = p.employee_user_id) AS password_last_changed_at
       FROM hrms_employee_profiles p INNER JOIN employee_users u ON u.id = p.employee_user_id ` + clause + ' ORDER BY p.full_name ASC LIMIT ? OFFSET ?',
      params.concat([limit, offset])
    );
    const [allRows] = await db.query("SELECT p.employment_status FROM hrms_employee_profiles p INNER JOIN employee_users u ON u.id = p.employee_user_id WHERE u.user_type = 'employee' AND u.is_active = 1");
    // Roles are managed in the main admin area while older HRMS records keep
    // their designation in `department`.  Combining both sources keeps this
    // filter current as soon as an admin creates a role or employee.
   const [departmentRows] = await db.query(
  "SELECT DISTINCT CONVERT(role_name USING utf8mb4) COLLATE utf8mb4_unicode_ci AS name " +
  "FROM user_roles WHERE TRIM(COALESCE(role_name, '')) <> '' " +
  "UNION " +
  "SELECT DISTINCT CONVERT(role USING utf8mb4) COLLATE utf8mb4_unicode_ci AS name " +
  "FROM employee_users WHERE TRIM(COALESCE(role, '')) <> '' " +
  "UNION " +
  "SELECT DISTINCT CONVERT(department USING utf8mb4) COLLATE utf8mb4_unicode_ci AS name " +
  "FROM hrms_employee_profiles WHERE TRIM(COALESCE(department, '')) <> '' " +
  "ORDER BY name ASC"
);

    return ok(res, {
      items: rows.map(toUi),
      page: safePage,
      limit: limit,
      total: total,
      totalPages: totalPages,
      departments: departmentRows.map(function (row) { return row.name; }),
      kpis: {
        total: allRows.length,
        active: allRows.filter(function (r) { return r.employment_status === 'Active'; }).length,
        onLeave: allRows.filter(function (r) { return r.employment_status === 'On Leave'; }).length,
        inactive: allRows.filter(function (r) { return r.employment_status === 'Inactive'; }).length
      }
    });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function detail(req, res) {
  try {
    const id = Number(req.params.id);
    const [[profile]] = await db.query(
      `SELECT p.*, DATE_FORMAT(p.joining_date, '%Y-%m-%d') AS joining_date, u.username,
       (SELECT t.name FROM hrms_employee_weekly_off_assignments a JOIN hrms_weekly_off_templates t ON t.id = a.template_id WHERE a.profile_id = p.id AND a.effective_from <= CURDATE() ORDER BY a.effective_from DESC, a.id DESC LIMIT 1) AS weekly_off_template
       FROM hrms_employee_profiles p
       LEFT JOIN employee_users u ON u.id = p.employee_user_id WHERE p.id = ?`,
      [id]
    );
    if (!profile) return fail(res, 404, 'Employee not found');
    const employeeId = Number(profile.employee_user_id || 0);
    const [[attendance]] = await db.query(
      `SELECT
        SUM(CASE WHEN check_in_at IS NOT NULL AND attendance_status <> 'absent' THEN 1 ELSE 0 END) AS present,
        SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END) AS late,
        SUM(CASE WHEN attendance_status = 'absent' THEN 1 ELSE 0 END) AS absent
       FROM attendance_records WHERE employee_id = ?
         AND attendance_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
         AND attendance_date < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)`,
      [employeeId]
    );
    const [[leave]] = await db.query(
      `SELECT COUNT(*) AS total, SUM(status = 'approved') AS approved, SUM(status = 'pending') AS pending
       FROM employee_leaves WHERE employee_id = ?
         AND from_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')`,
      [employeeId]
    );
    const [[payroll]] = await db.query(
      `SELECT working_days, paid_days, lop_days, deductions, late_deductions,
              absent_deductions, net_pay, status
       FROM hrms_payroll_items WHERE profile_id = ?
       ORDER BY pay_year DESC, pay_month DESC LIMIT 1`,
      [id]
    );
    const [attendanceRows] = await db.query(
      `SELECT DATE_FORMAT(a.attendance_date, '%a, %d %b') AS date,
              DATE_FORMAT(a.check_in_at, '%h:%i %p') AS check_in,
              DATE_FORMAT(a.check_out_at, '%h:%i %p') AS check_out,
              CONCAT(FLOOR(COALESCE(a.working_minutes, 0) / 60), 'h ',
                     LPAD(MOD(COALESCE(a.working_minutes, 0), 60), 2, '0'), 'm') AS worked,
              DATE_FORMAT(MIN(b.started_at), '%h:%i %p') AS break_start,
              DATE_FORMAT(MAX(b.ended_at), '%h:%i %p') AS break_end,
              CONCAT(FLOOR(COALESCE(SUM(b.duration_minutes), 0) / 60), 'h ',
                     LPAD(MOD(COALESCE(SUM(b.duration_minutes), 0), 60), 2, '0'), 'm') AS break_duration,
              CASE WHEN a.attendance_status = 'absent' THEN 'Absent'
                   WHEN a.attendance_status = 'on_leave' THEN 'On leave'
                   WHEN a.attendance_status = 'half_leave' THEN 'Half leave'
                   WHEN a.is_late = 1 THEN 'Late' ELSE 'Present' END AS status,
              CASE WHEN a.attendance_status = 'absent' THEN 'Yes' ELSE 'No' END AS lop,
              COALESCE(a.check_in_method, '-') AS method,
              a.clock_out_reason,
              a.tracking_stop_reason
       FROM attendance_records a
       LEFT JOIN attendance_breaks b ON b.attendance_id = a.id
         AND b.status IN ('completed', 'auto_closed')
       WHERE a.employee_id = ?
         AND a.attendance_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
         AND a.attendance_date < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
       GROUP BY a.id, a.attendance_date, a.check_in_at, a.check_out_at,
                a.working_minutes, a.attendance_status, a.is_late, a.check_in_method
       ORDER BY a.attendance_date ASC`,
      [employeeId]
    );
    const [leaveRows] = await db.query(
      `SELECT leave_type, duration_type, DATE_FORMAT(from_date, '%d %b %Y') AS from_date,
              DATE_FORMAT(to_date, '%d %b %Y') AS to_date, days_count, reason, status
       FROM employee_leaves
       WHERE employee_id = ? AND from_date < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
         AND to_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
       ORDER BY from_date DESC`,
      [employeeId]
    );
    const [permissionRows] = await db.query(
      `SELECT request_type, DATE_FORMAT(request_date, '%d %b %Y') AS request_date,
              TIME_FORMAT(permission_start_time, '%h:%i %p') AS start_time,
              TIME_FORMAT(permission_end_time, '%h:%i %p') AS end_time, reason, status
       FROM attendance_permission_requests
       WHERE employee_id = ? AND request_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
         AND request_date < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
       ORDER BY request_date DESC`,
      [employeeId]
    );
    const [payrollHistoryRows] = await db.query(
      `SELECT pay_year, pay_month, monthly_salary, working_days, paid_days, lop_days,
              late_deductions, absent_deductions, deductions, net_pay, status
       FROM hrms_payroll_items WHERE profile_id = ?
       ORDER BY pay_year DESC, pay_month DESC LIMIT 6`,
      [id]
    );
    return ok(res, {
      employee: toUi(profile),
      attendance: {
        present: Number(attendance.present || 0), late: Number(attendance.late || 0), absent: Number(attendance.absent || 0),
      },
      leave: { total: Number(leave.total || 0), approved: Number(leave.approved || 0), pending: Number(leave.pending || 0) },
      payroll: payroll ? {
        workingDays: Number(payroll.working_days || 0), paidDays: Number(payroll.paid_days || 0),
        lopDays: Number(payroll.lop_days || 0),
        lateDeduction: Number(payroll.late_deductions || payroll.deductions || 0),
        absentDeduction: Number(payroll.absent_deductions || 0),
        totalDeduction: Number(payroll.late_deductions || payroll.deductions || 0) + Number(payroll.absent_deductions || 0),
        netPay: Number(payroll.net_pay || 0), status: payroll.status,
      } : null,
      attendanceRows: attendanceRows.map(function (row) {
        return Object.assign({}, row, {
          check_in: row.check_in || '-', check_out: row.check_out || '-',
          break_start: row.break_start || '-', break_end: row.break_end || '-'
        });
      }),
      leaveRows: leaveRows,
      permissionRows: permissionRows,
      payrollHistory: payrollHistoryRows.map(function (row) {
        const late = Number(row.late_deductions || row.deductions || 0);
        const absent = Number(row.absent_deductions || 0);
        return {
          month: new Date(Number(row.pay_year), Number(row.pay_month) - 1, 1).toLocaleString('en-US', { month: 'long', year: 'numeric' }),
          salary: Number(row.monthly_salary || 0), workingDays: Number(row.working_days || 0),
          paidDays: Number(row.paid_days || 0), lopDays: Number(row.lop_days || 0),
          lateDeduction: late, absentDeduction: absent, totalDeduction: late + absent,
          netPay: Number(row.net_pay || 0), status: row.status
        };
      })
    });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function create(req, res) {
  try {
    const body = req.body || {};
    let phone;
    try { phone = normalizePhone(body.phone); } catch (error) { return fail(res, 400, error.message); }
    const name = String(body.name || body.full_name || '').trim();
    const code = String(body.employeeCode || body.employee_code || body.id || '').trim();
    const department = String(body.department || 'Engineering').trim();
    const workMode = String(body.workMode || body.work_mode || 'Office').trim();
    const employeeType = String(body.employeeType || body.employee_type || 'Employee').trim();
    const overtimeEligible = body.overtimeEligible || body.overtime_eligible ? 1 : 0;
    if (!['Employee', 'Labour'].includes(employeeType)) return fail(res, 400, 'Employee type must be Employee or Labour');
    const gender = String(body.gender || 'Male').trim();
    if (!['Male', 'Female'].includes(gender)) return fail(res, 400, 'Gender must be Male or Female');
    const status = String(body.status || body.employment_status || 'Active').trim();
    const salary = parseSalary(body.salary || body.monthly_salary);
    const cycle = salaryCycle(body);
    const startDate = joiningDate(body.joiningDate || body.joining_date);
    if (cycle.error) return fail(res, 400, cycle.error);
    if (!startDate) return fail(res, 400, 'Joining date is required');
    const username = String(body.username || '').trim();
    const password = String(body.password || '');
    const email = String(body.email || '').trim() || null;
    if (!name || !code) return fail(res, 400, 'name and employeeCode are required');
    if (!username || !email || password.length < 8) return fail(res, 400, 'username, email and a password of at least 8 characters are required');

    // Ensure this table before opening the transaction: CREATE/ALTER TABLE
    // statements can force an implicit commit in MySQL.
    await ensureCompensationTable();
    const profile = await createEmployeeAtomically({
      pool: db,
      bcrypt: bcrypt,
      input: {
        name: name, code: code, department: department, workMode: workMode,
        employeeType: employeeType, overtimeEligible: overtimeEligible,
        gender: gender, status: status, salary: salary, salaryType: cycle.salaryType,
        cycleStartDay: cycle.cycleStartDay, cycleEndDay: cycle.cycleEndDay,
        cycleStartDate: cycle.cycleStartDate, cycleEndDate: cycle.cycleEndDate,
        username: username, email: email, phone: phone, password: password, joiningDate: startDate,
        firstName: name.split(/\s+/)[0], lastName: name.split(/\s+/).slice(1).join(' '),
        initials: name.split(/\s+/).map(function (part) { return part[0]; }).join('').slice(0, 3).toUpperCase()
      },
      adminId: req.user && req.user.id,
      recordCompensation: recordCompensation
    });
    return ok(res, { employee: toUi(profile), credentials: { username: username, email: email, password: password } }, 'Employee added');
  } catch (error) {
    const message = duplicateMessage(error);
    if (message) return fail(res, 409, message);
    return fail(res, 500, error.message);
  }
}

async function resetPassword(req, res) {
  try {
    const password = String((req.body && req.body.password) || '');
    if (password.length < 8) return fail(res, 400, 'Password must be at least 8 characters');
    const [rows] = await db.query('SELECT employee_user_id FROM hrms_employee_profiles WHERE id = ?', [Number(req.params.id)]);
    if (!rows[0] || !rows[0].employee_user_id) return fail(res, 404, 'Employee login not found');
    await db.query('UPDATE employee_users SET password = ? WHERE id = ?', [await bcrypt.hash(password, 10), rows[0].employee_user_id]);
    return ok(res, { password: password }, 'Password reset');
  } catch (error) { return fail(res, 500, error.message); }
}

async function deviceRequests(req, res) {
  try {
    await db.query(`CREATE TABLE IF NOT EXISTS hrms_device_change_requests (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_user_id BIGINT UNSIGNED NOT NULL,
      proposed_device_hash CHAR(64) NOT NULL, proposed_device_label VARCHAR(180) NOT NULL DEFAULT 'New browser',
      reason VARCHAR(500) NULL, status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
      requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, reviewed_at TIMESTAMP NULL, reviewed_by BIGINT UNSIGNED NULL,
      review_note VARCHAR(500) NULL, KEY device_request_status (status, requested_at)
    )`);
    const [rows] = await db.query(`SELECT r.id, r.employee_user_id, r.proposed_device_label, r.reason, r.status, r.requested_at,
      u.full_name, u.username, p.employee_code FROM hrms_device_change_requests r
      INNER JOIN employee_users u ON u.id = r.employee_user_id LEFT JOIN hrms_employee_profiles p ON p.employee_user_id = u.id
      WHERE r.status = 'pending' ORDER BY r.requested_at DESC`);
    return ok(res, { items: rows }, 'Device requests loaded');
  } catch (error) { return fail(res, 500, error.message); }
}

async function reviewDeviceRequest(req, res) {
  try {
    const id = Number(req.params.id);
    const approved = req.body && req.body.approved === true;
    const note = String((req.body && req.body.note) || '').slice(0, 500);
    const [rows] = await db.query("SELECT * FROM hrms_device_change_requests WHERE id = ? AND status = 'pending' FOR UPDATE", [id]);
    if (!rows.length) return fail(res, 404, 'Pending device request not found');
    const request = rows[0];
    if (approved) {
      await db.query(`INSERT INTO hrms_registered_devices (employee_user_id, device_hash, device_label, registered_at, last_seen_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE device_hash = VALUES(device_hash), device_label = VALUES(device_label), registered_at = CURRENT_TIMESTAMP, last_seen_at = CURRENT_TIMESTAMP`,
        [request.employee_user_id, request.proposed_device_hash, request.proposed_device_label]);
    }
    await db.query("UPDATE hrms_device_change_requests SET status = ?, reviewed_at = CURRENT_TIMESTAMP, reviewed_by = ?, review_note = ? WHERE id = ?",
      [approved ? 'approved' : 'rejected', req.user.id, note || null, id]);
    return ok(res, { id: id, status: approved ? 'approved' : 'rejected' }, approved ? 'New browser approved. The employee can now sign in.' : 'Device request rejected.');
  } catch (error) { return fail(res, 500, error.message); }
}

async function update(req, res) {
  let connection;
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) return fail(res, 400, 'Invalid employee ID');
    const body = req.body || {};
    let phone;
    try { if (Object.prototype.hasOwnProperty.call(body, 'phone')) phone = normalizePhone(body.phone); } catch (error) { return fail(res, 400, error.message); }
    const name = String(body.name || body.full_name || '').trim();
    const code = String(body.employeeCode || body.employee_code || body.id || '').trim();
    const department = String(body.department || '').trim();
    const workMode = String(body.workMode || body.work_mode || '').trim();
    const employeeType = String(body.employeeType || body.employee_type || 'Employee').trim();
    const overtimeEligible = body.overtimeEligible || body.overtime_eligible ? 1 : 0;
    if (!['Employee', 'Labour'].includes(employeeType)) return fail(res, 400, 'Employee type must be Employee or Labour');
    const gender = String(body.gender || 'Male').trim();
    if (!['Male', 'Female'].includes(gender)) return fail(res, 400, 'Gender must be Male or Female');
    const requestedStatus = String(body.status || body.employment_status || '').trim();
    const salary = parseSalary(body.salary || body.monthly_salary);
    const cycle = salaryCycle(body);
    const requestedJoiningDate = joiningDate(body.joiningDate || body.joining_date);
    if (cycle.error) return fail(res, 400, cycle.error);
    if ((body.joiningDate || body.joining_date) && !requestedJoiningDate) return fail(res, 400, 'Joining date must use YYYY-MM-DD');
    const requestedEmail = String(body.email || '').trim();
    const requestedUsername = String(body.username || '').trim();
    const password = String(body.password || '');
    if (!name || !code) return fail(res, 400, 'Employee name and Employee ID are required');
    if (password && password.length < 8) {
      return fail(res, 400, 'New password must be at least 8 characters');
    }

    // DDL is intentionally performed before the transaction because MySQL
    // can implicitly commit around CREATE/ALTER TABLE operations.
    await ensureCompensationTable();
    connection = await db.getConnection();
    await connection.beginTransaction();
    const [profileRows] = await connection.query(
      `SELECT p.*, u.email AS linked_user_email, u.username AS linked_username
       FROM hrms_employee_profiles p
       LEFT JOIN employee_users u ON u.id = p.employee_user_id
       WHERE p.id = ? FOR UPDATE`,
      [id]
    );
    const existingProfile = profileRows[0];
    if (!existingProfile) {
      await connection.rollback();
      return fail(res, 404, 'Employee not found');
    }
    const employeeUserId = Number(existingProfile.employee_user_id);
    if (!Number.isInteger(employeeUserId) || employeeUserId < 1) {
      throw new Error('Employee profile is not linked to a user account');
    }
    // The legacy edit form has no email field. Retain the existing linked
    // account email/username when those optional request fields are omitted.
    const email = requestedEmail || String(
      existingProfile.linked_user_email || existingProfile.email || ''
    ).trim();
    const username = requestedUsername || String(
      existingProfile.linked_username || ''
    ).trim();
    const status = requestedStatus || String(
      existingProfile.employment_status || 'Active'
    ).trim();
    if (!username || !email) {
      await connection.rollback();
      return fail(res, 400, 'This employee is missing a username or email. Update the employee account details first.');
    }
    if (!['Active', 'On Leave', 'Inactive'].includes(status)) {
      await connection.rollback();
      return fail(res, 400, 'Employment status must be Active, On Leave, or Inactive');
    }

    // The current profile/user must be excluded from duplicate checks. This
    // allows an edit that retains its own employee code, email and username.
    await assertUniqueForUpdate(
      connection,
      { code, email, username },
      { profileId: id, employeeUserId }
    );

    await connection.query(
      'UPDATE hrms_employee_profiles SET employee_code = ?, full_name = ?, email = ?, phone = ?, department = ?, work_mode = ?, employee_type = ?, overtime_eligible = ?, gender = ?, employment_status = ?, joining_date = COALESCE(?, joining_date), monthly_salary = ?, salary_type = ?, flexible_cycle_start_day = ?, flexible_cycle_end_day = ?, flexible_cycle_start_date = ?, flexible_cycle_end_date = ? WHERE id = ?',
      [code, name, email, phone === undefined ? existingProfile.phone : phone, department, workMode, employeeType, overtimeEligible, gender, status, requestedJoiningDate, salary, cycle.salaryType, cycle.cycleStartDay, cycle.cycleEndDay, cycle.cycleStartDate, cycle.cycleEndDate, id]
    );

    const updates = ['full_name = ?', 'email = ?', 'username = ?', 'staff_id = ?'];
    const values = [name, email, username, code];
    if (password) {
      updates.push('password = ?');
      values.push(await bcrypt.hash(password, 10));
    }
    values.push(employeeUserId);
    await connection.query(
      'UPDATE employee_users SET ' + updates.join(', ') + ' WHERE id = ?',
      values
    );
    const [rows] = await connection.query(
      'SELECT * FROM hrms_employee_profiles WHERE id = ?',
      [id]
    );
    await recordCompensation(rows[0], salary, req.user && req.user.id, connection);
    await connection.commit();
    return ok(res, toUi(rows[0]), 'Employee updated');
  } catch (error) {
    if (connection) await connection.rollback();
    const message = duplicateMessage(error);
    if (message) return fail(res, 409, message);
    return fail(res, 500, error.message);
  } finally {
    if (connection) connection.release();
  }
}

async function updateStatus(req, res) {
  try {
    const id = Number(req.params.id);
    const status = String((req.body && req.body.status) || '').trim();
    if (['Active', 'On Leave', 'Inactive'].indexOf(status) === -1) {
      return fail(res, 400, 'status must be Active, On Leave, or Inactive');
    }
    const [result] = await db.query('UPDATE hrms_employee_profiles SET employment_status = ? WHERE id = ?', [status, id]);
    if (!result.affectedRows) return fail(res, 404, 'Employee not found');
    const [rows] = await db.query('SELECT * FROM hrms_employee_profiles WHERE id = ?', [id]);
    return ok(res, toUi(rows[0]), 'Status updated');
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function tableExists(connection, tableName) {
  const [rows] = await connection.query(
    `SELECT 1 FROM information_schema.tables
     WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1`,
    [tableName]
  );
  return rows.length > 0;
}

async function deleteByEmployeeKey(connection, tableName, columnName, value) {
  if (!value || !(await tableExists(connection, tableName))) return;
  // Table and column names come only from the fixed lists in remove().
  await connection.query(`DELETE FROM \`${tableName}\` WHERE \`${columnName}\` = ?`, [value]);
}

async function remove(req, res) {
  const connection = await db.getConnection();
  try {
    const id = Number(req.params.id);
    await connection.beginTransaction();
    const [profiles] = await connection.query('SELECT employee_user_id FROM hrms_employee_profiles WHERE id = ? FOR UPDATE', [id]);
    if (!profiles.length) { await connection.rollback(); return fail(res, 404, 'Employee not found'); }
    const userId = Number(profiles[0].employee_user_id || 0);

    // Remove children first so hard deletion works whether or not a deployment
    // later adds foreign-key constraints. All operations stay transactional.
    if (await tableExists(connection, 'hrms_leave_approval_links') && await tableExists(connection, 'employee_leaves')) {
      await connection.query(
        `DELETE links FROM hrms_leave_approval_links links
         INNER JOIN employee_leaves leaves ON leaves.id = links.leave_id
         WHERE leaves.employee_id = ?`,
        [userId]
      );
    }
    if (await tableExists(connection, 'hrms_admin_notifications') && await tableExists(connection, 'attendance_permission_requests')) {
      await connection.query(
        `DELETE notifications FROM hrms_admin_notifications notifications
         INNER JOIN attendance_permission_requests requests
           ON requests.id = notifications.approval_request_id
         WHERE requests.employee_id = ?`,
        [userId]
      );
    }
    if (await tableExists(connection, 'attendance_breaks') && await tableExists(connection, 'attendance_records')) {
      await connection.query(
        `DELETE breaks FROM attendance_breaks breaks
         INNER JOIN attendance_records records ON records.id = breaks.attendance_id
         WHERE records.employee_id = ?`,
        [userId]
      );
    }
    if (await tableExists(connection, 'hrms_overtime_entries') && await tableExists(connection, 'attendance_records')) {
      await connection.query(
        `DELETE overtime FROM hrms_overtime_entries overtime
         INNER JOIN attendance_records records ON records.id = overtime.attendance_id
         WHERE records.employee_id = ?`,
        [userId]
      );
    }

    for (const tableName of [
      'hrms_payslip_download_requests',
      'hrms_employee_location_status',
      'hrms_location_pings',
      'hrms_field_tracking_sessions',
      'hrms_field_waiting_reasons',
      'hrms_employee_home_locations',
      'hrms_auto_clockout_audit',
      'hrms_clock_out_reminder_events',
      'hrms_employee_tracking_comments',
      'hrms_registered_devices',
      'hrms_device_change_requests',
      'hrms_active_sessions',
      'hrms_password_change_log',
      'attendance_records',
      'attendance_permission_requests',
      'hrms_attendance_sessions',
      'employee_leaves',
      'employee_extra_hours',
      'employee_permissions',
      'employee_punches',
      'employee_tracking_sessions',
      'employee_tracking_activities',
      'role_page_access',
      'hrms_overtime_entries',
    ]) {
      await deleteByEmployeeKey(connection, tableName, tableName === 'role_page_access' ? 'employee_id' : tableName === 'hrms_payslip_download_requests' || tableName === 'hrms_field_waiting_reasons' || tableName === 'hrms_auto_clockout_audit' || tableName === 'hrms_clock_out_reminder_events' || tableName === 'hrms_employee_tracking_comments' || tableName === 'hrms_device_change_requests' || tableName === 'hrms_registered_devices' || tableName === 'hrms_active_sessions' || tableName === 'hrms_password_change_log' || tableName === 'hrms_employee_location_status' || tableName === 'hrms_location_pings' || tableName === 'hrms_field_tracking_sessions' || tableName === 'hrms_employee_home_locations' || tableName === 'hrms_overtime_entries' ? 'employee_user_id' : 'employee_id', userId);
    }

    await deleteByEmployeeKey(connection, 'hrms_payroll_items', 'profile_id', id);
    await deleteByEmployeeKey(connection, 'hrms_employee_compensation', 'profile_id', id);
    await deleteByEmployeeKey(connection, 'hrms_employee_weekly_off_assignments', 'profile_id', id);
    await connection.query('DELETE FROM hrms_employee_profiles WHERE id = ?', [id]);
    if (userId) await connection.query('DELETE FROM employee_users WHERE id = ?', [userId]);
    await connection.commit();
    return ok(res, { id: id }, 'Employee permanently deleted');
  } catch (error) {
    await connection.rollback();
    return fail(res, 500, error.message);
  } finally {
    connection.release();
  }
}

async function exportCsv(req, res) {
  try {
    const { clause, params } = employeeFilters(req.query);
    const [rows] = await db.query(
      'SELECT p.* FROM hrms_employee_profiles p INNER JOIN employee_users u ON u.id = p.employee_user_id ' + clause + ' ORDER BY p.full_name ASC',
      params
    );
    const lines = ['Employee,Employee ID,Department,Work Mode,Monthly Salary,Status'];
    rows.forEach(function (row) {
      const item = toUi(row);
      lines.push([item.name, item.employeeCode, item.department, item.workMode, item.salary, item.status]
        .map(function (v) { return '"' + String(v).replace(/"/g, '""') + '"'; }).join(','));
    });
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="employees.csv"');
    return res.send(lines.join('\n'));
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

module.exports = {
  requireAdmin: requireAdmin,
  summary: summary,
  detail: detail,
  list: list,
  create: create,
  resetPassword: resetPassword,
  deviceRequests: deviceRequests,
  reviewDeviceRequest: reviewDeviceRequest,
  update: update,
  updateStatus: updateStatus,
  remove: remove,
  exportCsv: exportCsv
};
