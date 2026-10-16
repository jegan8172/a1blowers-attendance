const db = require('../config/db');
const policy = require('../lib/attendancePolicy');
const staff = require('../lib/staffDirectory');

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

const LEAVE_TYPES = ['leave', 'risk_leave', 'annual_leave', 'sick_leave', 'personal_leave', 'casual_leave', 'earned_leave', 'optional_holiday'];
const EXTRA_TYPES = ['extra_hours', 'late_entry', 'early_exit', 'reclock_in'];

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
  return String(requestType || '').replace(/_/g, ' ');
}

function iconMeta(typeLabel) {
  if (typeLabel === 'Sick Leave') return { icon: 'medical', color: 0xFFFF4F62 };
  if (typeLabel === 'Personal Leave') return { icon: 'event_busy', color: 0xFFFF6D3A };
  if (typeLabel === 'Extra Hours' || typeLabel === 'Late Entry' || typeLabel === 'Early Exit' || typeLabel === 'Clock In Request') {
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
              p.permission_start_time, p.permission_end_time,
              DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date,
              DATE_FORMAT(leave_request.from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(leave_request.to_date, '%Y-%m-%d') AS to_date,
              leave_request.duration_type,
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
    const id = Number(req.params.id);
    const status = String((req.body && req.body.status) || '').toLowerCase();
    const salaryMode = String((req.body && req.body.salaryMode) || '').toLowerCase();
    if (status !== 'approved' && status !== 'rejected') {
      return fail(res, 400, 'status must be approved or rejected');
    }
    const [[pendingRequest]] = await db.query(
      `SELECT id, employee_id, request_type, request_date
       FROM attendance_permission_requests WHERE id = ? AND status = 'pending'`,
      [id]
    );
    if (!pendingRequest) return fail(res, 404, 'Pending request not found');
    if (status === 'approved' && pendingRequest.request_type === 'permission' &&
        salaryMode !== 'paid' && salaryMode !== 'unpaid') {
      return fail(res, 400, 'Choose paid or unpaid permission before approving');
    }
    // Approval intentionally does not rewrite attendance. It unlocks a single
    // additional Clock In; that Clock In reopens the same session while keeping
    // the original Clock In timestamp for the full workday calculation.
    const at = policy.nowIstDateTime();
    const [result] = await db.query(
      `UPDATE attendance_permission_requests
       SET status = ?, salary_mode = ?, reviewed_by = ?, reviewed_at = ?
       WHERE id = ? AND status = 'pending'`,
      [status, pendingRequest.request_type === 'permission' && status === 'approved' ? salaryMode : null, req.user.id, at, id]
    );
    await db.query(`
      CREATE TABLE IF NOT EXISTS hrms_leave_approval_links (
        leave_id BIGINT UNSIGNED NOT NULL,
        approval_request_id BIGINT UNSIGNED NOT NULL,
        PRIMARY KEY (leave_id),
        UNIQUE KEY uniq_leave_approval_request (approval_request_id)
      )
    `);
    await db.query(
      `UPDATE employee_leaves l
       INNER JOIN hrms_leave_approval_links link ON link.leave_id = l.id
       SET l.status = ?
       WHERE link.approval_request_id = ?`,
      [status === 'approved' ? 'APPROVED' : 'DENIED', id]
    );    const [rows] = await db.query(
      `SELECT p.id, p.employee_id, p.request_type, p.reason, p.status, p.salary_mode,
              p.permission_start_time, p.permission_end_time,
              DATE_FORMAT(p.request_date, '%Y-%m-%d') AS request_date,
              DATE_FORMAT(leave_request.from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(leave_request.to_date, '%Y-%m-%d') AS to_date,
              leave_request.duration_type,
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
