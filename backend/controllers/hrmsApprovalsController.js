const db = require('../config/db');
const policy = require('../lib/attendancePolicy');
const staff = require('../lib/staffDirectory');
const payroll = require('./hrmsPayrollController');
const leavePolicies = require('./leavePolicies');

function ok(res, data, message) {
  return res.json({ success: true, message: message || 'OK', data: data });
}

function fail(res, status, message) {
  return res.status(status).json({ success: false, message: message });
}

async function ensureRegularizationColumns() {
  const columns = [
    ['correction_kind', 'VARCHAR(48) NULL'],
    ['corrected_check_in_time', 'TIME NULL'],
    ['corrected_check_out_time', 'TIME NULL'],
  ];
  for (const [name, definition] of columns) {
    const [existing] = await db.query(`SHOW COLUMNS FROM attendance_permission_requests LIKE '${name}'`);
    if (!existing.length) await db.query(`ALTER TABLE attendance_permission_requests ADD COLUMN \`${name}\` ${definition}`);
  }
}

function dateTimeFor(date, value) {
  if (!date || !value) return null;
  return `${String(date).slice(0, 10)} ${String(value).slice(0, 8).padEnd(8, ':00')}`;
}

async function applyApprovedRegularization(request) {
  const kind = String(request.correction_kind || '').toLowerCase();
  if (!['missing_check_in', 'missing_check_out', 'incorrect_time'].includes(kind)) return;
  const [[record]] = await db.query(`SELECT a.*, DATE_FORMAT(a.check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_value,
    DATE_FORMAT(a.check_out_at, '%Y-%m-%d %H:%i:%s') AS check_out_value
    FROM attendance_records a WHERE employee_id = ? AND attendance_date = ? LIMIT 1`, [request.employee_id, request.request_date]);
  const checkIn = dateTimeFor(request.request_date, request.corrected_check_in_time) || (record && record.check_in_value ? record.check_in_value : null);
  const checkOut = dateTimeFor(request.request_date, request.corrected_check_out_time) || (record && record.check_out_value ? record.check_out_value : null);
  if (!checkIn || !checkOut) throw new Error('Both check-in and check-out are required before this correction can be applied');
  const [[profile]] = await db.query('SELECT gender FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1', [request.employee_id]);
  await policy.getTimeSettings(db);
  const [[breaks]] = await db.query("SELECT COALESCE(SUM(duration_minutes), 0) AS minutes FROM attendance_breaks WHERE attendance_id = ? AND status IN ('completed', 'auto_closed')", [record ? record.id : 0]);
  const workingMinutes = Math.max(0, policy.minutesBetween(checkIn, checkOut) - Number(breaks && breaks.minutes || 0));
  const gender = profile && profile.gender ? profile.gender : 'Male';
  const isAbsent = policy.isAbsentCheckIn(checkIn, gender);
  const isLate = !isAbsent && policy.isLateCheckIn(checkIn, gender);
  const attendanceStatus = isAbsent ? 'absent' : (policy.isEarlyExit(workingMinutes) ? 'early_exit' : (isLate ? 'late' : 'present'));
  if (record) {
    await db.query(`UPDATE attendance_records SET check_in_at = ?, check_out_at = ?, working_minutes = ?, is_late = ?, attendance_status = ?, session_status = 'completed', admin_status_override = NULL, admin_override_reason = NULL, admin_override_by = NULL, admin_override_at = NULL WHERE id = ?`, [checkIn, checkOut, workingMinutes, isLate ? 1 : 0, attendanceStatus, record.id]);
  } else {
    await db.query(`INSERT INTO attendance_records (employee_id, attendance_date, check_in_at, check_out_at, attendance_status, session_status, check_in_method, is_late, working_minutes) VALUES (?, ?, ?, ?, ?, 'completed', 'manual', ?, ?)`, [request.employee_id, request.request_date, checkIn, checkOut, attendanceStatus, isLate ? 1 : 0, workingMinutes]);
  }
}

function requireAdmin(req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
}

const LEAVE_TYPES = ['leave', 'risk_leave', 'annual_leave', 'sick_leave', 'personal_leave', 'casual_leave', 'earned_leave', 'optional_holiday'];
const EXTRA_TYPES = ['extra_hours', 'late_entry', 'early_exit', 'reclock_in', 'attendance_regularization'];

function displayType(requestType) {
  const value = String(requestType || '').toLowerCase();
  if (value === 'casual_leave') return 'Casual Leave';
  if (value === 'earned_leave') return 'Earned Leave';
  if (value === 'optional_holiday') return 'Optional Holiday';
  if (value === 'annual_leave' || value === 'leave') return 'Annual Leave';
  if (value === 'sick_leave') return 'Sick Leave';
  if (value === 'personal_leave' || value === 'risk_leave') return 'Personal Leave';
  if (value === 'extra_hours') return 'Extra Hours';
  if (value === 'late_entry') return 'Late Entry';
  if (value === 'early_exit') return 'Early Exit';
  if (value === 'reclock_in') return 'Clock In Request';
  if (value === 'attendance_regularization') return 'Attendance Regularization';
  return String(requestType || '').replace(/_/g, ' ');
}

function iconMeta(typeLabel) {
  if (typeLabel === 'Sick Leave') return { icon: 'medical', color: 0xFFFF4F62 };
  if (typeLabel === 'Personal Leave') return { icon: 'event_busy', color: 0xFFFF6D3A };
  if (typeLabel === 'Extra Hours' || typeLabel === 'Late Entry' || typeLabel === 'Early Exit' || typeLabel === 'Clock In Request' || typeLabel === 'Attendance Regularization') {
    return { icon: 'more_time', color: 0xFFFF6500 };
  }
  return { icon: 'beach', color: 0xFF7137E8 };
}

function toIsoDate(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const year = value.getUTCFullYear();
    const month = String(value.getUTCMonth() + 1).padStart(2, '0');
    const day = String(value.getUTCDate()).padStart(2, '0');
    return year + '-' + month + '-' + day;
  }
  const match = String(value).match(/(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function formatDay(value) {
  const date = toIsoDate(value);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return { pretty: '—', weekday: '—', iso: '' };
  }
  const [year, month, day] = date.split('-').map(Number);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const weekday = weekdays[new Date(Date.UTC(year, month - 1, day)).getUTCDay()];
  return {
    pretty: day + ' ' + months[month - 1] + ' ' + year,
    weekday: weekday,
    iso: date,
  };
}

function leaveDuration(row) {
  if (String(row.duration_type || '').toLowerCase() === 'half day') return 'Half Day';
  const from = toIsoDate(row.from_date || row.request_date);
  const to = toIsoDate(row.to_date || row.request_date);
  if (!from || !to) return '1 Day';
  const days = Math.max(1, Math.round((Date.parse(to + 'T00:00:00Z') - Date.parse(from + 'T00:00:00Z')) / 86400000) + 1);
  return days + (days === 1 ? ' Day' : ' Days');
}

function toUi(row) {
  const type = displayType(row.request_type);
  const start = formatDay(row.request_date);
  const extra = EXTRA_TYPES.indexOf(String(row.request_type).toLowerCase()) !== -1;
  const meta = iconMeta(type);
  return {
    id: row.id,
    name: String(row.full_name || 'Unknown employee').trim(),
    employeeCode: row.staff_id || ('EMP' + row.employee_id),
    type: type,
    requestType: row.request_type,
    dates: start.pretty || '—',
    dayRange: start.weekday && start.weekday !== '—' ? '(' + start.weekday + ')' : '',
    duration: extra ? '—' : leaveDuration(row),
    reason: row.reason || '',
    status: String(row.status || 'pending').replace(/^./, function (c) { return c.toUpperCase(); }),
    salaryMode: row.salary_mode || null,
    permissionStartTime: row.permission_start_time || null,
    permissionEndTime: row.permission_end_time || null,
    correctionKind: row.correction_kind || null,
    correctedCheckIn: row.corrected_check_in_time || null,
    correctedCheckOut: row.corrected_check_out_time || null,
    leaveType: row.leave_type || null,
    hasPolicySnapshot: row.policy_payroll_mode === 'paid' || row.policy_payroll_mode === 'unpaid',
    icon: meta.icon,
    color: meta.color,
    tab: extra ? 'extra' : 'leave',
  };
}

async function ensureAdminNotifications() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_admin_notifications (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      approval_request_id BIGINT UNSIGNED NOT NULL,
      title VARCHAR(160) NOT NULL,
      message VARCHAR(500) NOT NULL,
      is_read TINYINT(1) NOT NULL DEFAULT 0,
      read_at DATETIME NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_approval_notification (approval_request_id)
    )
  `);
}

async function syncPendingNotifications() {
  await ensureAdminNotifications();
  await db.query(`
    INSERT IGNORE INTO hrms_admin_notifications (approval_request_id, title, message)
    SELECT p.id,
           CONCAT('New ', REPLACE(p.request_type, '_', ' '), ' request'),
           CONCAT(COALESCE(u.full_name, CONCAT('Employee #', p.employee_id)), ' submitted a request for approval.')
    FROM attendance_permission_requests p
    LEFT JOIN employee_users u ON u.id = p.employee_id
    WHERE p.status = 'pending'
  `);
}

async function notifications(req, res) {
  try {
    await syncPendingNotifications();
    const [rows] = await db.query(`
      SELECT id, approval_request_id, title, message, is_read, created_at
      FROM hrms_admin_notifications
      ORDER BY created_at DESC
      LIMIT 12
    `);
    const [counts] = await db.query(
      'SELECT COUNT(*) AS total FROM hrms_admin_notifications WHERE is_read = 0'
    );
    return ok(res, {
      unreadCount: Number(counts[0] && counts[0].total || 0),
      items: rows.map(function (row) {
        return {
          id: row.id,
          approvalRequestId: row.approval_request_id,
          title: row.title,
          message: row.message,
          isRead: Boolean(row.is_read),
          createdAt: row.created_at,
        };
      }),
    });
  } catch (error) {
    console.error('GET /hrms/approvals/notifications', error);
    return fail(res, 500, error.message);
  }
}

async function markAllNotificationsRead(req, res) {
  try {
    await ensureAdminNotifications();
    await db.query(
      'UPDATE hrms_admin_notifications SET is_read = 1, read_at = ? WHERE is_read = 0',
      [policy.nowIstDateTime()]
    );
    return ok(res, { unreadCount: 0 }, 'All notifications marked as read');
  } catch (error) {
    console.error('PATCH /hrms/approvals/notifications/read-all', error);
    return fail(res, 500, error.message);
  }
}
async function list(req, res) {
  try {
    // The list reads the leave-request policy snapshot, so make sure the
    // additive migration has completed before this first query.
    await leavePolicies.ensure();
    await ensureRegularizationColumns();
    const tab = String(req.query.tab || 'leave').toLowerCase();
    const status = String(req.query.status || '').trim();
    const employee = String(req.query.employee || '').trim();
    const extraPlaceholders = EXTRA_TYPES.map(function () { return '?'; }).join(', ');
    const where = [];
    const params = [];

    if (tab === 'extra') {
      where.push('p.request_type IN (' + extraPlaceholders + ')');
      params.push.apply(params, EXTRA_TYPES);
    } else {
      where.push('p.request_type NOT IN (' + extraPlaceholders + ')');
      params.push.apply(params, EXTRA_TYPES);
    }

    if (status && status !== 'All Status') {
      where.push('p.status = ?');
      params.push(status.toLowerCase());
    }
    if (employee && employee !== 'All Employees') {
      where.push('s.' + staff.quote(staff.STAFF.name) + ' = ?');
      params.push(employee);
    }

    const [rows] = await db.query(
      `SELECT p.id, p.employee_id, p.request_type, p.reason, p.status, p.salary_mode,
              p.permission_start_time, p.permission_end_time, p.correction_kind,
              p.corrected_check_in_time, p.corrected_check_out_time,
              DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date,
              DATE_FORMAT(leave_request.from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(leave_request.to_date, '%Y-%m-%d') AS to_date,
              leave_request.leave_type, leave_request.duration_type, leave_request.policy_payroll_mode,
              s.${staff.quote(staff.STAFF.name)} AS full_name,
              s.${staff.quote(staff.STAFF.staffCode)} AS staff_id
       FROM attendance_permission_requests p
       LEFT JOIN ${staff.staffFrom()} s ON s.${staff.quote(staff.STAFF.id)} = p.employee_id
       LEFT JOIN hrms_leave_approval_links link ON link.approval_request_id = p.id
       LEFT JOIN employee_leaves leave_request ON leave_request.id = link.leave_id
       WHERE ${where.join(' AND ')}
       ORDER BY p.created_at DESC
       LIMIT 200`,
      params
    );

    const [allRows] = await db.query(
      `SELECT status FROM attendance_permission_requests`
    );
    const items = rows.map(toUi);
    const names = [...new Set(items.map(function (item) { return item.name; }))];

    return ok(res, {
      items: items,
      employees: names,
      kpis: {
        pending: allRows.filter(function (r) { return r.status === 'pending'; }).length,
        approved: allRows.filter(function (r) { return r.status === 'approved'; }).length,
        rejected: allRows.filter(function (r) { return r.status === 'rejected'; }).length,
      },
    });
  } catch (error) {
    console.error('GET /hrms/approvals', error);
    return fail(res, 500, error.message);
  }
}

async function review(req, res) {
  try {
    await leavePolicies.ensure();
    await ensureRegularizationColumns();
    const id = Number(req.params.id);
    const status = String((req.body && req.body.status) || '').toLowerCase();
    const salaryMode = String((req.body && req.body.salaryMode) || '').toLowerCase();
    if (status !== 'approved' && status !== 'rejected') {
      return fail(res, 400, 'status must be approved or rejected');
    }
    await db.query(`
      CREATE TABLE IF NOT EXISTS hrms_leave_approval_links (
        leave_id BIGINT UNSIGNED NOT NULL,
        approval_request_id BIGINT UNSIGNED NOT NULL,
        PRIMARY KEY (leave_id),
        UNIQUE KEY uniq_leave_approval_request (approval_request_id)
      )
    `);
    const [[pendingRequest]] = await db.query(
      `SELECT p.id, p.employee_id, p.request_type, DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date, p.correction_kind,
              p.corrected_check_in_time, p.corrected_check_out_time,
              leave_request.leave_type, leave_request.policy_payroll_mode
       FROM attendance_permission_requests p
       LEFT JOIN hrms_leave_approval_links link ON link.approval_request_id = p.id
       LEFT JOIN employee_leaves leave_request ON leave_request.id = link.leave_id
       WHERE p.id = ? AND p.status = 'pending'`,
      [id]
    );
    if (!pendingRequest) return fail(res, 404, 'Pending request not found');
    let approvedSalaryMode = null;
    if (status === 'approved' && pendingRequest.request_type === 'permission' &&
        salaryMode !== 'paid' && salaryMode !== 'unpaid') {
      return fail(res, 400, 'Choose paid or unpaid permission before approving');
    }
    if (status === 'approved' && pendingRequest.request_type === 'attendance_regularization' &&
        salaryMode !== 'paid' && salaryMode !== 'unpaid') {
      return fail(res, 400, 'Choose paid or unpaid attendance regularization before approving');
    }
    if (status === 'approved' && pendingRequest.leave_type) {
      const snapshot = String(pendingRequest.policy_payroll_mode || '').toLowerCase();
      if (snapshot === 'paid' || snapshot === 'unpaid') {
        approvedSalaryMode = snapshot;
      } else if (pendingRequest.leave_type === 'Earned Leave') {
        // Legacy request created before snapshots were introduced.
        approvedSalaryMode = 'paid';
      } else if (salaryMode === 'paid' || salaryMode === 'unpaid') {
        approvedSalaryMode = salaryMode;
      } else {
        return fail(res, 400, 'Choose paid or unpaid leave before approving');
      }
    } else if (status === 'approved' && pendingRequest.request_type === 'permission') {
      approvedSalaryMode = salaryMode;
    } else if (status === 'approved' && pendingRequest.request_type === 'attendance_regularization') {
      approvedSalaryMode = salaryMode;
    }
    // Validate and apply requested clock values before finalizing the approval,
    // so an invalid correction cannot become an approved request.
    if (status === 'approved' && pendingRequest.request_type === 'attendance_regularization') {
      await applyApprovedRegularization(pendingRequest);
    }
    const at = policy.nowIstDateTime();
    const [result] = await db.query(
      `UPDATE attendance_permission_requests
       SET status = ?, salary_mode = ?, reviewed_by = ?, reviewed_at = ?
       WHERE id = ? AND status = 'pending'`,
      [status, approvedSalaryMode, req.user.id, at, id]
    );
    await db.query(
      `UPDATE employee_leaves l
       INNER JOIN hrms_leave_approval_links link ON link.leave_id = l.id
       SET l.status = ?
       WHERE link.approval_request_id = ?`,
      [status === 'approved' ? 'APPROVED' : 'DENIED', id]
    );
    if (pendingRequest.employee_id) {
      await payroll.refreshUnpaidForEmployee(
        Number(pendingRequest.employee_id),
        pendingRequest.request_date
      );
    }
    const [rows] = await db.query(
      `SELECT p.id, p.employee_id, p.request_type, p.reason, p.status, p.salary_mode,
              p.permission_start_time, p.permission_end_time, p.correction_kind,
              p.corrected_check_in_time, p.corrected_check_out_time,
              DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date,
              DATE_FORMAT(leave_request.from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(leave_request.to_date, '%Y-%m-%d') AS to_date,
              leave_request.leave_type, leave_request.duration_type, leave_request.policy_payroll_mode,
              s.${staff.quote(staff.STAFF.name)} AS full_name,
              s.${staff.quote(staff.STAFF.staffCode)} AS staff_id
       FROM attendance_permission_requests p
       LEFT JOIN ${staff.staffFrom()} s ON s.${staff.quote(staff.STAFF.id)} = p.employee_id
       LEFT JOIN hrms_leave_approval_links link ON link.approval_request_id = p.id
       LEFT JOIN employee_leaves leave_request ON leave_request.id = link.leave_id
       WHERE p.id = ?`,
      [id]
    );
    return ok(res, toUi(rows[0] || {}), 'Request ' + status);
  } catch (error) {
    console.error('PATCH /hrms/approvals/:id', error);
    return fail(res, 500, error.message);
  }
}

module.exports = {
  requireAdmin,
  list,
  review,
  notifications,
  markAllNotificationsRead,
  LEAVE_TYPES,
};
