const db = require('../config/db');
const policy = require('../lib/attendancePolicy');
const calendar = require('../lib/calendarWorkingDays');
const weeklyOffTemplates = require('../lib/weeklyOffTemplates');

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

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'];

const DEFAULT_POLICY = { weeklyOffDays: [0], deductApprovedLeave: true, deductExplicitAbsence: true, missingAttendanceIsAbsent: false };

function timeSeconds(value) { const p = String(value || '').slice(-8).split(':').map(Number); return (p[0] || 0) * 3600 + (p[1] || 0) * 60 + (p[2] || 0); }
function shiftDurationMinutes(start, end) {
  let duration = Math.round((timeSeconds(end) - timeSeconds(start)) / 60);
  if (duration <= 0) duration += 24 * 60;
  return duration;
}
function attendanceTimeSeconds(value) {
  const text = String(value || '');
  if (text.includes('T') || value instanceof Date) {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return timeSeconds(policy.partsInZone(date).time);
  }
  return timeSeconds(text);
}
function countWorkingDays(start, end, weeklyOff) { let total = 0; for (let date = start; date <= end; date = nextDate(date)) { const p = date.split('-').map(Number); if (!weeklyOff.has(utcWeekday(p[0], p[1], p[2]))) total += 1; } return total; }
function countEmployeeWorkingDays(start, end, weeklyResolver, overrides) {
  let total = 0;
  for (let date = start; date <= end; date = nextDate(date)) {
    if (employeeWorkingDay(date, weeklyResolver, overrides)) total += 1;
  }
  return total;
}
async function ensureDeductionStorage() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payroll_deduction_entries (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, profile_id BIGINT UNSIGNED NOT NULL,
    employee_user_id BIGINT UNSIGNED NOT NULL, pay_year SMALLINT UNSIGNED NOT NULL,
    pay_month TINYINT UNSIGNED NOT NULL, attendance_date DATE NOT NULL,
    deduction_type ENUM('late','absent') NOT NULL, late_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    UNIQUE KEY uq_payroll_deduction_date (profile_id,pay_year,pay_month,attendance_date,deduction_type)
  )`);
  for (const definition of [
    'late_deductions DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER deductions',
    'absent_deductions DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER late_deductions',
    'period_start DATE NULL AFTER pay_month',
    'period_end DATE NULL AFTER period_start'
  ]) {
    try { await db.query('ALTER TABLE hrms_payroll_items ADD COLUMN ' + definition); } catch (error) { if (error.code !== 'ER_DUP_FIELDNAME') throw error; }
  }
}

// A payroll item is the monthly total.  This table is its day-by-day
// accounting ledger.  Keeping it alongside the monthly row prevents the
// admin history, employee history and payslip views from independently
// recalculating the same attendance data in different ways.
async function ensureDailyPayrollStorage() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payroll_daily_entries (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    payroll_item_id BIGINT UNSIGNED NOT NULL,
    profile_id BIGINT UNSIGNED NOT NULL,
    employee_user_id BIGINT UNSIGNED NOT NULL,
    pay_year SMALLINT UNSIGNED NOT NULL,
    pay_month TINYINT UNSIGNED NOT NULL,
    attendance_date DATE NOT NULL,
    check_in_at DATETIME NULL,
    check_out_at DATETIME NULL,
    attendance_status VARCHAR(32) NOT NULL,
    daily_salary DECIMAL(12,2) NOT NULL DEFAULT 0,
    paid_units DECIMAL(4,2) NOT NULL DEFAULT 0,
    lop_units DECIMAL(4,2) NOT NULL DEFAULT 0,
    late_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    late_deduction DECIMAL(12,2) NOT NULL DEFAULT 0,
    early_exit_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    early_exit_deduction DECIMAL(12,2) NOT NULL DEFAULT 0,
    absent_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_deduction DECIMAL(12,2) NOT NULL DEFAULT 0,
    present_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    updated_salary DECIMAL(12,2) NOT NULL DEFAULT 0,
    UNIQUE KEY uq_payroll_daily_entry (profile_id, pay_year, pay_month, attendance_date),
    KEY idx_payroll_daily_item (payroll_item_id, attendance_date),
    KEY idx_payroll_daily_employee (employee_user_id, pay_year, pay_month)
  )`);
  for (const definition of [
    'paid_units DECIMAL(4,2) NOT NULL DEFAULT 0 AFTER daily_salary',
    'lop_units DECIMAL(4,2) NOT NULL DEFAULT 0 AFTER paid_units',
    'early_exit_minutes INT UNSIGNED NOT NULL DEFAULT 0 AFTER late_deduction',
    'early_exit_deduction DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER early_exit_minutes'
  ]) {
    try { await db.query('ALTER TABLE hrms_payroll_daily_entries ADD COLUMN ' + definition); } catch (error) { if (error.code !== 'ER_DUP_FIELDNAME') throw error; }
  }
}

async function ensurePayrollStatusAudit() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payroll_status_audit (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    payroll_item_id BIGINT UNSIGNED NOT NULL,
    profile_id BIGINT UNSIGNED NOT NULL,
    employee_user_id BIGINT UNSIGNED NOT NULL,
    previous_status VARCHAR(20) NOT NULL,
    new_status VARCHAR(20) NOT NULL,
    reason TEXT NULL,
    changed_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_payroll_status_audit_item (payroll_item_id, created_at)
  )`);
}

async function ensurePolicyTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payroll_policy (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    weekly_off_days JSON NOT NULL,
    deduct_approved_leave TINYINT(1) NOT NULL DEFAULT 1,
    deduct_explicit_absence TINYINT(1) NOT NULL DEFAULT 1,
    missing_attendance_is_absent TINYINT(1) NOT NULL DEFAULT 0,
    salary_day_divisor TINYINT UNSIGNED NOT NULL DEFAULT 26,
    auto_generate TINYINT(1) NOT NULL DEFAULT 0,
    auto_last_generated_date DATE NULL,
    updated_by BIGINT UNSIGNED NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  )`);
  try { await db.query('ALTER TABLE hrms_payroll_policy ADD COLUMN salary_day_divisor TINYINT UNSIGNED NOT NULL DEFAULT 26'); } catch (_) {}
  try { await db.query('ALTER TABLE hrms_payroll_policy ADD COLUMN auto_generate TINYINT(1) NOT NULL DEFAULT 0'); } catch (_) {}
  try { await db.query('ALTER TABLE hrms_payroll_policy ADD COLUMN auto_last_generated_date DATE NULL'); } catch (_) {}
  try { await db.query('ALTER TABLE hrms_payroll_policy ADD COLUMN updated_by BIGINT UNSIGNED NULL'); } catch (_) {}
  try { await db.query('ALTER TABLE hrms_payroll_policy ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'); } catch (_) {}
  await db.query(`INSERT IGNORE INTO hrms_payroll_policy (id, weekly_off_days, deduct_approved_leave, deduct_explicit_absence, missing_attendance_is_absent) VALUES (1, '[0]', 1, 1, 0)`);
}

async function payrollPolicy() {
  await ensurePolicyTable();
  const [rows] = await db.query('SELECT * FROM hrms_payroll_policy WHERE id = 1');
  const row = rows[0] || {};
  const weeklyOffDays = weeklyOffTemplates.parseDays(row.weekly_off_days, DEFAULT_POLICY.weeklyOffDays);
  return {
    weeklyOffDays: Array.isArray(weeklyOffDays) ? weeklyOffDays.map(Number).filter((day) => day >= 0 && day <= 6) : [0],
    deductApprovedLeave: Boolean(Number(row.deduct_approved_leave ?? 1)),
    deductExplicitAbsence: Boolean(Number(row.deduct_explicit_absence ?? 1)),
    missingAttendanceIsAbsent: Boolean(Number(row.missing_attendance_is_absent ?? 0)),
    autoGenerate: Boolean(Number(row.auto_generate ?? 0)),
    autoLastGeneratedDate: row.auto_last_generated_date ? isoDate(row.auto_last_generated_date) : null,
  };
}

function formatSalary(value) {
  if (value === null || value === undefined || value === '') return 'Not Set';
  const amount = Number(value);
  if (!Number.isFinite(amount)) return 'Not Set';
  return '₹' + Math.round(amount).toLocaleString('en-US');
}

function pad(value) {
  return String(value).padStart(2, '0');
}

function ymd(year, month, day) {
  return year + '-' + pad(month) + '-' + pad(day);
}

function utcWeekday(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

function employeeWorkingDay(date, resolver, overrides) {
  return calendar.isEmployeeWorkingDay(date, resolver, overrides);
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function dateForDay(year, month, day) {
  return ymd(year, month, Math.min(Math.max(1, Number(day) || 1), daysInMonth(year, month)));
}

function previousMonth(year, month) {
  return month === 1 ? { year: year - 1, month: 12 } : { year: year, month: month - 1 };
}

function nextMonth(year, month) {
  return month === 12 ? { year: year + 1, month: 1 } : { year: year, month: month + 1 };
}

function shiftMonth(year, month, offset) {
  let result = { year: year, month: month };
  const step = offset < 0 ? previousMonth : nextMonth;
  for (let index = 0; index < Math.abs(offset); index += 1) result = step(result.year, result.month);
  return result;
}

function nextDate(date) {
  const parts = String(date).split('-').map(Number);
  const value = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + 1));
  return ymd(value.getUTCFullYear(), value.getUTCMonth() + 1, value.getUTCDate());
}

function payrollPeriod(profile, year, month, override) {
  if (override) {
    return { start: isoDate(override.period_start), end: isoDate(override.period_end), salaryType: 'Flexible', overridden: true };
  }
  if (String(profile.salary_type || 'Standard') !== 'Flexible') {
    return { start: ymd(year, month, 1), end: ymd(year, month, daysInMonth(year, month)), salaryType: 'Standard' };
  }
  const configuredStart = isoDate(profile.flexible_cycle_start_date);
  const configuredEnd = isoDate(profile.flexible_cycle_end_date);
  // A selected payroll month represents the month in which a Flexible cycle
  // ends. Before the employee's first configured cycle there must be no
  // payroll row at all — missing attendance is not an absence before salary
  // commencement.
  if (configuredStart && configuredEnd) {
    const [firstEndYear, firstEndMonth] = configuredEnd.split('-').map(Number);
    if (year < firstEndYear || (year === firstEndYear && month < firstEndMonth)) return null;
    if (year === firstEndYear && month === firstEndMonth) {
      return { start: configuredStart, end: configuredEnd, salaryType: 'Flexible', anchored: true };
    }
  }
  const startDay = Number(profile.flexible_cycle_start_day || 1);
  const endDay = Number(profile.flexible_cycle_end_day || startDay);
  const end = dateForDay(year, month, endDay);
  const startMonth = startDay > endDay ? previousMonth(year, month) : { year: year, month: month };
  return {
    start: dateForDay(startMonth.year, startMonth.month, startDay),
    end: end,
    salaryType: 'Flexible'
  };
}

function flexiblePeriodContaining(profile, referenceDate) {
  const configuredStart = isoDate(profile.flexible_cycle_start_date);
  const configuredEnd = isoDate(profile.flexible_cycle_end_date);
  if (!configuredStart || !configuredEnd) {
    const [year, month] = referenceDate.split('-').map(Number);
    const legacy = payrollPeriod(profile, year, month, null);
    return legacy ? { ...legacy, year: year, month: month } : null;
  }
  if (referenceDate < configuredStart) return null;
  if (referenceDate <= configuredEnd) {
    const parts = configuredEnd.split('-').map(Number);
    return { start: configuredStart, end: configuredEnd, year: parts[0], month: parts[1] };
  }
  const [referenceYear, referenceMonth] = referenceDate.split('-').map(Number);
  for (const offset of [-1, 0, 1]) {
    const endMonth = shiftMonth(referenceYear, referenceMonth, offset);
    const candidate = payrollPeriod(profile, endMonth.year, endMonth.month, null);
    if (candidate && referenceDate >= candidate.start && referenceDate <= candidate.end) {
      return { ...candidate, year: endMonth.year, month: endMonth.month };
    }
  }
  return null;
}

async function ensureCycleOverrides() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payroll_cycle_overrides (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    profile_id BIGINT UNSIGNED NOT NULL,
    pay_year SMALLINT UNSIGNED NOT NULL,
    pay_month TINYINT UNSIGNED NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    updated_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_profile_pay_period (profile_id, pay_year, pay_month)
  )`);
}

function isoDate(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  const match = String(value).match(/(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function parseMonth(req) {
  const today = policy.todayIstDate();
  const [ty, tm] = today.split('-').map(Number);
  const body = req.body || {};
  const year = Number(req.query.year || body.year || ty);
  const month = Number(req.query.month || body.month || tm);
  if (!year || month < 1 || month > 12) {
    return { error: 'year and month (1-12) are required' };
  }
  return { year: year, month: month, today: today };
}

function monthOptions(today) {
  const [ty, tm] = today.split('-').map(Number);
  const items = [];
  for (let i = 0; i < 12; i += 1) {
    let month = tm - i;
    let year = ty;
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    items.push({
      year: year,
      month: month,
      label: MONTHS[month - 1] + ' ' + year,
    });
  }
  return items;
}

async function computeRows(year, month, today, options) {
  const requestedProfileIds = options && Array.isArray(options.profileIds) ? options.profileIds.map(Number).filter(Number.isInteger) : [];
  await ensureCycleOverrides();
  await ensureDeductionStorage();
  const configuredPolicy = await payrollPolicy();
  const timeSettings = await policy.getTimeSettings(db);
  const weeklyOff = new Set(configuredPolicy.weeklyOffDays);
  const previous = previousMonth(year, month);
  // Load a one-month buffer because a Flexible cycle can begin in the
  // preceding month (for example 26 Aug–25 Sep).
  const queryStart = ymd(previous.year, previous.month, 1);
  const queryEnd = ymd(year, month, daysInMonth(year, month));
  const calendarOverrides = await calendar.overridesForPeriod(queryStart, queryEnd);

  // The regular payroll list intentionally shows only active employees. A
  // specifically requested employee, however, is used by the employee
  // overview and must retain access to the same historical/live projection
  // even after being marked inactive.
  const profileSql = `
    SELECT p.* FROM hrms_employee_profiles p JOIN employee_users u ON u.id = p.employee_user_id
    WHERE ${requestedProfileIds.length ? 'p.id IN (?)' : "p.employment_status <> 'Inactive' AND u.is_active = 1"}
    ORDER BY p.full_name ASC`;
  const [profiles] = await db.query(profileSql, requestedProfileIds.length ? [requestedProfileIds] : []);
  await weeklyOffTemplates.ensureWeeklyOffTemplateTables(db);
  const weeklyResolvers = new Map();
  for (const profile of profiles) {
    weeklyResolvers.set(Number(profile.id), await weeklyOffTemplates.offDaysForProfileByDate(
      db, Number(profile.id), queryStart, queryEnd, configuredPolicy.weeklyOffDays
    ));
  }

  // Compensation is versioned by immutable profile/user IDs. A name is display-only.
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
  for (const profile of profiles) {
    if (profile.monthly_salary === null || profile.monthly_salary === undefined) continue;
    await db.query(`INSERT INTO hrms_employee_compensation (profile_id, employee_user_id, monthly_salary, effective_from)
      SELECT ?, ?, ?, COALESCE(DATE(created_at), ?)
      FROM hrms_employee_profiles WHERE id = ?
      AND NOT EXISTS (SELECT 1 FROM hrms_employee_compensation c WHERE c.profile_id = ?)
      LIMIT 1`, [profile.id, profile.employee_user_id || null, profile.monthly_salary, queryStart, profile.id, profile.id]);
  }
  const [compensations] = await db.query(`SELECT profile_id, employee_user_id, monthly_salary, effective_from
    FROM hrms_employee_compensation WHERE effective_from <= ? ORDER BY effective_from ASC, id ASC`, [queryEnd]);
  const compensationMap = new Map();
  compensations.forEach(function (row) {
    if (row.profile_id) compensationMap.set('profile:' + row.profile_id, row);
    if (row.employee_user_id) compensationMap.set('user:' + row.employee_user_id, row);
  });

  const userIds = profiles.map(function (row) { return row.employee_user_id; }).filter(Boolean);

  // Attendance DATETIME values already contain India-local clock time. Return
  // text so mysql2 cannot interpret them in the host timezone as JS Dates and
  // attendanceTimeSeconds cannot apply the India offset a second time.
  const [records] = userIds.length
    ? await db.query(
        `SELECT employee_id, DATE_FORMAT(attendance_date, '%Y-%m-%d') AS attendance_date,
                DATE_FORMAT(check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_at,
                DATE_FORMAT(check_out_at, '%Y-%m-%d %H:%i:%s') AS check_out_at,
                is_late, attendance_status, admin_status_override,
                scheduled_shift_start, scheduled_shift_end, scheduled_late_after,
                early_exit_minutes
         FROM attendance_records
         WHERE attendance_date BETWEEN ? AND ?
           AND employee_id IN (?)`,
        [queryStart, queryEnd, userIds]
      )
    : [[]];

  const [leaves] = userIds.length
    ? await db.query(
        `SELECT l.employee_id, DATE_FORMAT(l.from_date, '%Y-%m-%d') AS from_date,
                DATE_FORMAT(l.to_date, '%Y-%m-%d') AS to_date, l.duration_type,
                COALESCE(NULLIF(LOWER(l.policy_payroll_mode), ''),
                  CASE WHEN l.leave_type = 'Earned Leave' THEN 'paid' ELSE 'unpaid' END) AS payroll_mode
         FROM employee_leaves l
         WHERE l.status = 'APPROVED'
           AND l.from_date <= ? AND l.to_date >= ?
           AND l.employee_id IN (?)`,
        [queryEnd, queryStart, userIds]
      )
    : [[]];
  const [paidRegularizations] = userIds.length
    ? await db.query(
        `SELECT employee_id, DATE_FORMAT(request_date, '%Y-%m-%d') AS request_date
         FROM attendance_permission_requests
         WHERE request_type = 'attendance_regularization' AND status = 'approved'
           AND salary_mode = 'paid' AND request_date BETWEEN ? AND ?
           AND employee_id IN (?)`,
        [queryStart, queryEnd, userIds]
      )
    : [[]];

  const [savedRows] = await db.query(
    `SELECT * FROM hrms_payroll_items WHERE pay_year = ? AND pay_month = ?`,
    [year, month]
  );
  const savedMap = new Map();
  savedRows.forEach(function (row) {
    savedMap.set(Number(row.profile_id), row);
  });
  const [overrideRows] = await db.query(
    `SELECT profile_id, period_start, period_end FROM hrms_payroll_cycle_overrides
     WHERE pay_year = ? AND pay_month = ?`,
    [year, month]
  );
  const overrideMap = new Map();
  overrideRows.forEach(function (row) { overrideMap.set(Number(row.profile_id), row); });

  const recordMap = new Map();
  records.forEach(function (row) {
    recordMap.set(row.employee_id + '|' + isoDate(row.attendance_date), row);
  });
  const leaveUnits = new Map();
  const paidRegularizationSet = new Set();
  leaves.forEach(function (row) {
    const start = isoDate(row.from_date);
    const end = isoDate(row.to_date);
    const units = String(row.duration_type || '').toLowerCase() === 'half day' ? 0.5 : 1;
    const paid = String(row.payroll_mode || '').toLowerCase() === 'paid';
    for (let date = start; date && end && date <= end; date = nextDate(date)) {
      if (date >= queryStart && date <= queryEnd) leaveUnits.set(row.employee_id + '|' + date, { units, paid });
    }
  });
  paidRegularizations.forEach(function (row) {
    const regularizationKey = row.employee_id + '|' + isoDate(row.request_date);
    paidRegularizationSet.add(regularizationKey);
  });

  return profiles.map(function (profile) {
    const weeklyResolver = weeklyResolvers.get(Number(profile.id));
    const period = payrollPeriod(profile, year, month, overrideMap.get(Number(profile.id)));
    if (!period) {
      const start = isoDate(profile.flexible_cycle_start_date);
      const end = isoDate(profile.flexible_cycle_end_date);
      return {
        id: null, profileId: profile.id, employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(), employeeCode: profile.employee_code,
        department: profile.department, monthlySalary: Number(profile.monthly_salary || 0) || null,
        salary: formatSalary(profile.monthly_salary), salaryType: 'Flexible',
        periodStart: start, periodEnd: end, cycleOverridden: false,
        dailySalary: null,
        workingDays: 0, presentDays: 0, lateDays: 0, leaveDays: 0, absentDays: 0,
        paidDays: 0, lopDays: 0, deductions: 0, deductionsLabel: '–',
        lateDeductions: 0, absentDeductions: 0, netPay: 0, netPayLabel: '–',
        status: 'Cycle not due', paidAt: '', payrollEligible: false,
      };
    }
    const cutoff = period.end < today ? period.end : today;
    let elapsedWorkingDays = 0;
    let earnedDays = 0;
    let present = 0;
    let late = 0;
    let leaveDays = 0;
    let unpaidHalfDays = 0;
    let absent = 0;
    const lateEntries = [];
    const earlyExitEntries = [];
    const absentEntries = [];
    const dailyRaw = [];

    for (let date = period.start; date <= cutoff; date = nextDate(date)) {
      const dateParts = date.split('-').map(Number);
      if (!employeeWorkingDay(date, weeklyResolver, calendarOverrides)) continue;
      elapsedWorkingDays += 1;
      const userId = profile.employee_user_id;
      const key = userId ? userId + '|' + date : '';
      const record = key ? recordMap.get(key) : null;

      // Today's open session is not payroll-final until the employee clocks
      // out or the end-of-day scheduler closes it at the configured shift end.
      // It must not become an absence or receive a full day's pay midway
      // through the workday.
      if (date === today && (!record || !record.check_out_at)) {
        elapsedWorkingDays -= 1;
        if (record && record.check_in_at) {
          dailyRaw.push({ date, record, status: 'In Progress', paidUnits: 0, absentUnits: 0, lateMinutes: 0 });
        }
        continue;
      }

      // 1. Safely read the status to ignore case (e.g., 'Absent' vs 'absent')
      const attStatus = record && record.attendance_status ? String(record.attendance_status).toLowerCase().trim() : '';

      if (String(record && record.admin_status_override || '').toLowerCase() === 'present') {
        present += 1;
        earnedDays += 1;
        dailyRaw.push({ date, record, status: 'Present', paidUnits: 1, absentUnits: 0, lateMinutes: 0 });
      } else if (String(record && record.admin_status_override || '').toLowerCase() === 'absent') {
        absent += 1;
        absentEntries.push({ date: date, days: 1 });
        dailyRaw.push({ date, record, status: 'Absent', paidUnits: 0, absentUnits: 1, lateMinutes: 0 });
      } else if (key && paidRegularizationSet.has(key)) {
        // An approved paid regularization wins over a generated/explicit
        // absence, without manufacturing a clock-in timestamp.
        present += 1;
        earnedDays += 1;
        dailyRaw.push({ date, record, status: 'Present', paidUnits: 1, absentUnits: 0, lateMinutes: 0 });
      } else if (key && leaveUnits.has(key)) {
        const leave = leaveUnits.get(key);
        const units = Number(leave.units || 0);
        const hasWorkedHalf = Boolean(record && record.check_in_at) && attStatus !== 'absent';
        const schedule = String(profile.gender).toLowerCase() === 'female' ? timeSettings.female : timeSettings.male;
        const lateAfter = record && record.scheduled_late_after || schedule.lateAfter;
        const lateMinutes = hasWorkedHalf
          ? Math.max(0, Math.floor((attendanceTimeSeconds(record.check_in_at) - timeSeconds(lateAfter)) / 60))
          : 0;
        const earlyExitMinutes = hasWorkedHalf ? Math.max(0, Number(record.early_exit_minutes || 0)) : 0;
        if (lateMinutes > 0) lateEntries.push({ date, minutes: lateMinutes });
        if (earlyExitMinutes > 0) earlyExitEntries.push({ date, minutes: earlyExitMinutes });
        leaveDays += units;
        if (leave.paid) {
          // Paid leave earns the selected leave portion. A completed opposite
          // half earns the remaining portion; missing it stays an absence.
          const paidUnits = hasWorkedHalf ? 1 : units;
          const absentUnits = hasWorkedHalf ? 0 : 1 - units;
          earnedDays += paidUnits;
          if (absentUnits > 0) {
            absent += absentUnits;
            absentEntries.push({ date, days: absentUnits });
          } else if (!lateMinutes && !earlyExitMinutes) {
            present += 1;
          }
          dailyRaw.push({ date, record, status: units === 0.5 ? 'Half Leave' : 'On Leave', paidUnits, absentUnits, lateMinutes, earlyExitMinutes });
        } else {
          // Unpaid leave never manufactures pay. With a completed opposite
          // half, the employee earns that half only; without it, the leave
          // itself is the unpaid half/full-day absence.
          const paidUnits = units === 0.5 && hasWorkedHalf ? 0.5 : 0;
          const absentUnits = units === 0.5 && hasWorkedHalf ? 0.5 : 1;
          earnedDays += paidUnits;
          absent += absentUnits;
          absentEntries.push({ date, days: absentUnits });
          dailyRaw.push({ date, record, status: units === 0.5 ? 'Half Leave' : 'On Leave', paidUnits, absentUnits, lateMinutes, earlyExitMinutes });
        }
      } else if (attStatus === 'half_leave') {
        unpaidHalfDays += 0.5;
        absentEntries.push({ date: date, days: 0.5 });
        earnedDays += 0.5;
        const schedule = String(profile.gender).toLowerCase() === 'female' ? timeSettings.female : timeSettings.male;
        const lateAfter = record && record.scheduled_late_after || schedule.lateAfter;
        const lateMinutes = record && record.check_in_at
          ? Math.max(0, Math.floor((attendanceTimeSeconds(record.check_in_at) - timeSeconds(lateAfter)) / 60))
          : 0;
        const earlyExitMinutes = Math.max(0, Number(record && record.early_exit_minutes || 0));
        if (lateMinutes > 0) lateEntries.push({ date: date, minutes: lateMinutes });
        if (earlyExitMinutes > 0) earlyExitEntries.push({ date: date, minutes: earlyExitMinutes });
        dailyRaw.push({ date, record, status: 'Half Leave', paidUnits: 0.5, absentUnits: 0.5, lateMinutes, earlyExitMinutes });
      } else if (attStatus === 'absent') {
        // An explicit absence is visible in the summary even when the policy
        // treats it as paid time.
        absent += 1;
        absentEntries.push({ date: date, days: 1 });
        dailyRaw.push({ date, record, status: 'Absent', paidUnits: 0, absentUnits: 1, lateMinutes: 0 });
      } else if (record && record.check_in_at) {
        // Punched in
        if (Number(record.is_late) || attStatus === 'late') late += 1;
        const schedule = String(profile.gender).toLowerCase() === 'female' ? timeSettings.female : timeSettings.male;
        // Use the rule snapshot written at Clock In. This is essential for
        // half-day shifts and keeps a finalized day immune to later admin edits.
        const lateAfter = record.scheduled_late_after || schedule.lateAfter;
        const lateMinutes = Math.max(0, Math.floor((attendanceTimeSeconds(record.check_in_at) - timeSeconds(lateAfter)) / 60));
        const earlyExitMinutes = Math.max(0, Number(record.early_exit_minutes || 0));
        if (lateMinutes > 0) lateEntries.push({ date: date, minutes: lateMinutes });
        if (earlyExitMinutes > 0) earlyExitEntries.push({ date: date, minutes: earlyExitMinutes });
        else present += 1;
        earnedDays += 1;
        dailyRaw.push({
          date,
          record,
          status: attStatus === 'early_exit' ? 'Early Exit' : (lateMinutes > 0 ? 'Late' : 'Present'),
          paidUnits: 1,
          absentUnits: 0,
          lateMinutes,
          earlyExitMinutes,
        });
      } else {
        // The current working day is only an absence after this employee's
        // configured absent-after time. Before then it remains an unresolved
        // live day and must not alter Present, LOP, paid days or pay.
        const currentDayBeforeCutoff = date === today && !policy.isAbsentCheckIn(
          policy.nowIstDateTime(),
          profile.gender,
        );
        if (currentDayBeforeCutoff) {
          elapsedWorkingDays -= 1;
          dailyRaw.push({ date, record, status: 'In Progress', paidUnits: 0, absentUnits: 0, lateMinutes: 0 });
          continue;
        }
        // A completed day, or today after the configured cutoff, with no
        // attendance is absent. Its value is not subtracted from accrued pay:
        // it simply never becomes a paid day in the first place.
        absent += 1;
        absentEntries.push({ date: date, days: 1 });
        dailyRaw.push({ date, record, status: 'Absent', paidUnits: 0, absentUnits: 1, lateMinutes: 0 });
      }
    }

    // Dashboard/calendar consumers still use a compact per-day view. Derive
    // it from the same raw ledger that is persisted for payroll history.
    const dayStatuses = Object.fromEntries(dailyRaw.map((entry) => [entry.date, entry.status]));
    const paidUnitsByDate = Object.fromEntries(dailyRaw.map((entry) => [entry.date, entry.paidUnits]));

    const compensation = compensationMap.get('profile:' + profile.id) || compensationMap.get('user:' + profile.employee_user_id);
    const salaryNumber = Number(compensation ? compensation.monthly_salary : profile.monthly_salary || 0);

    // A payroll day is a fixed policy divisor (normally 26), not the number
    // of days elapsed when the payroll is generated. This makes a three-day
    // absence from a Rs. 50,000 salary deduct Rs. 5,770 consistently.
    const periodWorkingDays = Math.max(1, countEmployeeWorkingDays(period.start, period.end, weeklyResolver, calendarOverrides));
    const dailyRate = salaryNumber / periodWorkingDays;
    const schedule = String(profile.gender).toLowerCase() === 'female' ? timeSettings.female : timeSettings.male;
    let shiftMinutes = Math.round((timeSeconds(schedule.shiftEnd) - timeSeconds(schedule.shiftStart)) / 60);
    if (shiftMinutes <= 0) shiftMinutes += 24 * 60;
    const hourlyRate = dailyRate / Math.max(1, shiftMinutes / 60);
    const lateDeductions = lateEntries.reduce((sum, item) => sum + (hourlyRate * item.minutes / 60), 0);
    const earlyExitDeductions = earlyExitEntries.reduce((sum, item) => sum + (hourlyRate * item.minutes / 60), 0);
    const workingDays = periodWorkingDays;
    const paidDays = Math.min(workingDays, earnedDays);
    const lopDays = Math.max(0, elapsedWorkingDays - paidDays);
    // This is the unpaid value of mandatory absence days. Net pay is still
    // earned from zero through paid days, so this value is informational and
    // is never subtracted from money the employee has already earned.
    const absentDeductions = Math.round(
      absentEntries.reduce((sum, item) => sum + (dailyRate * item.days), 0) * 100,
    ) / 100;
    const deductions = salaryNumber ? Math.round((lateDeductions + earlyExitDeductions) * 100) / 100 : 0;
    // Salary is accrued from paid days; an absence never removes pay already earned.
    const netPay = Math.max(0, Math.round((paidDays * dailyRate - deductions) * 100) / 100);
    let runningSalary = 0;
    const dailyEntries = dailyRaw.map((entry) => {
      const lateDeduction = Math.round((hourlyRate * entry.lateMinutes / 60) * 100) / 100;
      const earlyExitDeduction = Math.round((hourlyRate * Number(entry.earlyExitMinutes || 0) / 60) * 100) / 100;
      const absentAmount = Math.round((dailyRate * entry.absentUnits) * 100) / 100;
      const presentAmount = Math.max(0, Math.round((dailyRate * entry.paidUnits - lateDeduction - earlyExitDeduction) * 100) / 100);
      runningSalary = Math.round((runningSalary + presentAmount) * 100) / 100;
      return {
        date: entry.date,
        checkIn: entry.record && entry.record.check_in_at ? entry.record.check_in_at : null,
        checkOut: entry.record && entry.record.check_out_at ? entry.record.check_out_at : null,
        status: entry.status,
        paidUnits: entry.paidUnits,
        lopUnits: entry.absentUnits,
        dailySalary: Math.round(dailyRate * 100) / 100,
        lateMinutes: entry.lateMinutes,
        lateDeduction,
        earlyExitMinutes: Number(entry.earlyExitMinutes || 0),
        earlyExitDeduction,
        timeDeduction: Math.round((lateDeduction + earlyExitDeduction) * 100) / 100,
        absentAmount,
        totalDeduction: Math.round((lateDeduction + earlyExitDeduction + absentAmount) * 100) / 100,
        presentAmount,
        updatedSalary: runningSalary,
      };
    });

    const saved = savedMap.get(Number(profile.id));
    if (saved && (Number(saved.employee_user_id) !== Number(profile.employee_user_id) ||
        (saved.status === 'paid' && !(Number(saved.monthly_salary) > 0)))) {
      return { id: saved.id, profileId: profile.id, employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(), employeeCode: profile.employee_code,
        department: profile.department, monthlySalary: salaryNumber || null, salary: formatSalary(salaryNumber || null),
        salaryType: period.salaryType, periodStart: period.start, periodEnd: period.end, cycleOverridden: Boolean(period.overridden),
        shiftStart: schedule.shiftStart, shiftEnd: schedule.shiftEnd, shiftMinutes,
        dailySalary: salaryNumber ? Math.round(dailyRate * 100) / 100 : null,
        workingDays, paidDays, lopDays, deductions: 0, deductionsLabel: 'Review required',
        dailyEntries,
        netPay: 0, netPayLabel: 'Review required', status: 'Review required', paidAt: '',
        integrityError: 'Saved payroll has inconsistent ownership or missing paid salary. An audited correction is required.' };
    }

    if (!salaryNumber) {
      return {
        id: saved ? saved.id : null, profileId: profile.id, employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(), employeeCode: profile.employee_code,
        department: profile.department, monthlySalary: null, salary: 'Not Set',
        salaryType: period.salaryType, periodStart: period.start, periodEnd: period.end, cycleOverridden: Boolean(period.overridden),
        shiftStart: schedule.shiftStart, shiftEnd: schedule.shiftEnd, shiftMinutes,
        dailySalary: null,
        workingDays: workingDays, presentDays: present, lateDays: late, leaveDays: leaveDays, absentDays: absent,
        dayStatuses,
        paidUnitsByDate,
        dailyEntries,
        paidDays: paidDays, lopDays: lopDays, deductions: 0, deductionsLabel: '–',
        lateDeductions: 0, absentDeductions: 0, netPay: 0, netPayLabel: '–',
        status: 'Salary required', paidAt: '',
      };
    }

    if (saved && String(saved.status) === 'paid') {
      const savedPeriodStart = isoDate(saved.period_start) || period.start;
      const savedPeriodEnd = isoDate(saved.period_end) || period.end;
      return {
        id: saved.id, profileId: profile.id, employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(), employeeCode: profile.employee_code,
        department: profile.department, monthlySalary: Number(saved.monthly_salary || 0), salary: formatSalary(saved.monthly_salary),
        salaryType: period.salaryType, periodStart: savedPeriodStart, periodEnd: savedPeriodEnd, cycleOverridden: Boolean(period.overridden),
        shiftStart: schedule.shiftStart, shiftEnd: schedule.shiftEnd, shiftMinutes,
        dailySalary: Number(saved.working_days || 0) > 0
          ? Math.round((Number(saved.monthly_salary || 0) / Number(saved.working_days)) * 100) / 100
          : null,
        workingDays: Number(saved.working_days || 0), presentDays: present, lateDays: late, leaveDays: leaveDays, absentDays: absent,
        dayStatuses,
        paidUnitsByDate,
        dailyEntries,
        paidDays: Number(saved.paid_days || 0), lopDays: Number(saved.lop_days || 0), deductions: Number(saved.deductions || 0),
        deductionsLabel: formatSalary(saved.deductions),
        lateDeductions: Number(saved.late_deductions || saved.deductions || 0),
        absentDeductions: Number(saved.absent_deductions || 0),
        netPay: Number(saved.net_pay || 0), netPayLabel: formatSalary(saved.net_pay),
        status: 'Paid', paidAt: saved.paid_at ? isoDate(saved.paid_at) : '',
      };
    }

    const status = saved ? String(saved.status) : 'draft';

    return {
      id: saved ? saved.id : null,
      profileId: profile.id,
      employeeUserId: profile.employee_user_id,
      name: String(profile.full_name || '').trim(),
      employeeCode: profile.employee_code,
      department: profile.department,
      salaryType: period.salaryType,
      periodStart: period.start,
      periodEnd: period.end,
      cycleOverridden: Boolean(period.overridden),
      shiftStart: schedule.shiftStart,
      shiftEnd: schedule.shiftEnd,
      shiftMinutes,
      monthlySalary: salaryNumber || null,
      salary: formatSalary(salaryNumber),
      dailySalary: Math.round(dailyRate * 100) / 100,
      workingDays: workingDays,
      presentDays: present,
      lateDays: late,
      leaveDays: leaveDays,
      absentDays: absent,
      dayStatuses,
      paidUnitsByDate,
      paidDays: paidDays,
      lopDays: lopDays,
      deductions: deductions,
      lateDeductions: Math.round(lateDeductions * 100) / 100,
      absentDeductions: Math.round(absentDeductions * 100) / 100,
      deductionEntries: [
        // The compatibility table has one time-deduction row per day. Merge
        // late arrival and early checkout before writing so its unique key is
        // respected, while the daily ledger still exposes both components.
        ...Array.from(new Map([
          ...lateEntries.map(item => [item.date, { lateMinutes: item.minutes, amount: hourlyRate * item.minutes / 60 }]),
          ...earlyExitEntries.map(item => [item.date, {
            lateMinutes: (lateEntries.find(lateEntry => lateEntry.date === item.date)?.minutes || 0) + item.minutes,
            amount: (lateEntries.find(lateEntry => lateEntry.date === item.date) ? hourlyRate * lateEntries.find(lateEntry => lateEntry.date === item.date).minutes / 60 : 0) + hourlyRate * item.minutes / 60,
          }]),
        ]).entries()).map(([date, item]) => ({ date, type: 'late', lateMinutes: item.lateMinutes, amount: Math.round(item.amount * 100) / 100 })),
        ...absentEntries.map(item => ({ date: item.date, type: 'absent', lateMinutes: 0, amount: Math.round(dailyRate * item.days * 100) / 100 })),
      ],
      dailyEntries: dailyEntries,
      deductionsLabel: salaryNumber ? formatSalary(deductions) : '–',
      netPay: netPay,
      netPayLabel: salaryNumber ? formatSalary(netPay) : '–',
      status: status === 'paid' ? 'Paid' : status === 'pending' ? 'Pending' : 'Draft',
      paidAt: saved && saved.paid_at ? isoDate(saved.paid_at) : '',
    };
  });
}

function toKpis(items) {
  const withSalary = items.filter(function (item) { return item.monthlySalary; });
  const totalPayroll = withSalary.reduce(function (sum, item) { return sum + item.netPay; }, 0);
  const paid = items.filter(function (item) { return item.status === 'Paid'; }).length;
  const pending = items.filter(function (item) { return item.status === 'Pending'; }).length;
  const draft = items.filter(function (item) { return item.status === 'Draft'; }).length;
  return {
    totalPayroll: totalPayroll,
    totalPayrollLabel: formatSalary(totalPayroll || null),
    employees: items.length,
    paid: paid,
    pending: pending,
    draft: draft,
    totalWorkingDays: items.length === 0 ? 0 : Math.max(...items.map(function (item) { return Number(item.workingDays || 0); })),
  };
}

async function list(req, res) {
  try {
    const parsed = parseMonth(req);
    if (parsed.error) return fail(res, 400, parsed.error);
    // Refreshing the Payroll page always regenerates unpaid rows for the selected month.
    await generatePayrollRun(parsed.year, parsed.month, parsed.today);
    const employee = String(req.query.employee || '').trim();
    const status = String(req.query.status || '').trim();
    const allItems = await computeRows(parsed.year, parsed.month, parsed.today);
    let items = allItems;
    if (employee && employee !== 'All Employees') {
      items = items.filter(function (item) { return item.name === employee; });
    }
    if (status && status !== 'All Status') {
      items = items.filter(function (item) { return item.status === status; });
    }
    const names = [...new Set(allItems.map(function (item) { return item.name; }))];
    const configuredPolicy = await payrollPolicy();
    const start = ymd(parsed.year, parsed.month, 1);
    const end = ymd(parsed.year, parsed.month, daysInMonth(parsed.year, parsed.month));
    const overrides = await calendar.overridesForPeriod(start, end);
    const kpis = toKpis(items);
    // Monthly reference uses the shared calendar, not the maximum of saved
    // paid rows or employee-specific Flexible cycles/templates.
    kpis.totalWorkingDays = calendar.countWorkingDays(start, end, new Set(configuredPolicy.weeklyOffDays), overrides);
    return ok(res, {
      year: parsed.year,
      month: parsed.month,
      label: MONTHS[parsed.month - 1] + ' ' + parsed.year,
      months: monthOptions(parsed.today),
      timezone: policy.TIME_ZONE,
      policy: await payrollPolicy(),
      items: items,
      employees: names,
      kpis: kpis,
    });
  } catch (error) {
    console.error('GET /hrms/payroll', error);
    return fail(res, 500, error.message);
  }
}

async function getPolicy(req, res) {
  try { return ok(res, await payrollPolicy()); } catch (error) { return fail(res, 500, error.message); }
}

async function savePolicy(req, res) {
  try {
    const body = req.body || {};
    const weekly = Array.isArray(body.weeklyOffDays) ? [...new Set(body.weeklyOffDays.map(Number).filter((day) => day >= 0 && day <= 6))] : null;
    if (!weekly) return fail(res, 400, 'weeklyOffDays must contain weekday numbers from 0 to 6');
    await ensurePolicyTable();
    const current = await payrollPolicy();
    const autoGenerate = body.autoGenerate === undefined
      ? current.autoGenerate
      : body.autoGenerate === true || body.autoGenerate === 1 || body.autoGenerate === '1';
    const values = [JSON.stringify(weekly), body.deductApprovedLeave ? 1 : 0, body.deductExplicitAbsence ? 1 : 0, body.missingAttendanceIsAbsent ? 1 : 0, autoGenerate ? 1 : 0, req.user.id];
    await db.query(`UPDATE hrms_payroll_policy SET weekly_off_days = ?, deduct_approved_leave = ?, deduct_explicit_absence = ?, missing_attendance_is_absent = ?, auto_generate = ?, updated_by = ? WHERE id = 1`, values);
    const [year, month] = policy.todayIstDate().split('-').map(Number);
    await generatePayrollRun(year, month, policy.todayIstDate());
    return ok(res, await payrollPolicy(), 'Payroll policy saved');
  } catch (error) { return fail(res, 500, error.message); }
}

async function runAutomaticPayroll() {
  const settings = await payrollPolicy();
  if (!settings.autoGenerate) return false;
  const today = policy.todayIstDate();
  if (settings.autoLastGeneratedDate === today) return false;
  const parts = today.split('-').map(Number);
  const [profiles] = await db.query(`
    SELECT p.id, p.salary_type, p.flexible_cycle_start_date, p.flexible_cycle_end_date,
           p.flexible_cycle_start_day, p.flexible_cycle_end_day
    FROM hrms_employee_profiles p
    JOIN employee_users u ON u.id = p.employee_user_id
    WHERE p.employment_status <> 'Inactive' AND u.is_active = 1
  `);
  const standardIds = profiles
    .filter(function (profile) { return String(profile.salary_type || 'Standard') !== 'Flexible'; })
    .map(function (profile) { return Number(profile.id); });
  if (standardIds.length) await generatePayrollRun(parts[0], parts[1], today, { profileIds: standardIds });

  // Flexible employees are generated against the cycle containing today.
  // For 19 Oct–18 Nov, auto payroll writes the Nov key from 19 Oct onward;
  // on 19 Nov it starts a new Dec-keyed cycle without touching Nov history.
  const flexibleGroups = new Map();
  profiles.filter(function (profile) { return String(profile.salary_type) === 'Flexible'; }).forEach(function (profile) {
    const period = flexiblePeriodContaining(profile, today);
    if (!period) return;
    const key = period.year + '-' + period.month;
    const ids = flexibleGroups.get(key) || [];
    ids.push(Number(profile.id));
    flexibleGroups.set(key, ids);
  });
  for (const [key, profileIds] of flexibleGroups.entries()) {
    const [year, month] = key.split('-').map(Number);
    await generatePayrollRun(year, month, today, { profileIds: profileIds });
  }
  await db.query('UPDATE hrms_payroll_policy SET auto_last_generated_date = ? WHERE id = 1', [today]);
  return true;
}

async function generate(req, res) {
  try {
    const parsed = parseMonth(req);
    if (parsed.error) return fail(res, 400, parsed.error);
    const result = await generatePayrollRun(parsed.year, parsed.month, parsed.today);
    return ok(res, result, 'Payroll generated for ' + MONTHS[parsed.month - 1] + ' ' + parsed.year + '. ' + result.generatedCount + ' employee(s) included; ' + result.skippedCount + ' need compensation.');
  } catch (error) {
    console.error('POST /hrms/payroll/generate', error);
    return fail(res, 500, error.message);
  }
}

async function replaceDailySnapshots(payrollItemId, item, year, month) {
  await ensureDailyPayrollStorage();
  await db.query(
    `DELETE FROM hrms_payroll_daily_entries
      WHERE profile_id = ? AND pay_year = ? AND pay_month = ?`,
    [item.profileId, year, month]
  );
  for (const day of item.dailyEntries || []) {
    await db.query(
      `INSERT INTO hrms_payroll_daily_entries
        (payroll_item_id, profile_id, employee_user_id, pay_year, pay_month,
         attendance_date, check_in_at, check_out_at, attendance_status,
         daily_salary, paid_units, lop_units, late_minutes, late_deduction, early_exit_minutes, early_exit_deduction, absent_amount,
         total_deduction, present_amount, updated_salary)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        payrollItemId, item.profileId, item.employeeUserId, year, month,
        day.date, day.checkIn, day.checkOut, day.status,
        day.dailySalary, day.paidUnits, day.lopUnits, day.lateMinutes, day.lateDeduction, day.earlyExitMinutes, day.earlyExitDeduction, day.absentAmount,
        day.totalDeduction, day.presentAmount, day.updatedSalary,
      ]
    );
  }
}

async function generatePayrollRun(year, month, today, options) {
    await ensureDailyPayrollStorage();
    const allItems = await computeRows(year, month, today, options);
    const items = allItems.filter(function (item) { return item.payrollEligible !== false && Number(item.monthlySalary) > 0 && !item.integrityError && item.employeeUserId; });
    for (const item of items) {
      if (item.status === 'Paid') continue;
      await db.query(
        `INSERT INTO hrms_payroll_items
          (profile_id, employee_user_id, pay_year, pay_month, monthly_salary,
           period_start, period_end, working_days, paid_days, lop_days, deductions, late_deductions, absent_deductions, net_pay, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
         ON DUPLICATE KEY UPDATE
           monthly_salary = IF(status = 'paid', monthly_salary, VALUES(monthly_salary)),
           period_start = IF(status = 'paid', period_start, VALUES(period_start)),
           period_end = IF(status = 'paid', period_end, VALUES(period_end)),
           working_days = IF(status = 'paid', working_days, VALUES(working_days)),
           paid_days = IF(status = 'paid', paid_days, VALUES(paid_days)),
           lop_days = IF(status = 'paid', lop_days, VALUES(lop_days)),
           deductions = IF(status = 'paid', deductions, VALUES(deductions)),
           late_deductions = IF(status = 'paid', late_deductions, VALUES(late_deductions)),
           absent_deductions = IF(status = 'paid', absent_deductions, VALUES(absent_deductions)),
           net_pay = IF(status = 'paid', net_pay, VALUES(net_pay)),
           status = IF(status = 'paid', 'paid', 'pending')`,
        [
          item.profileId,
          item.employeeUserId || null,
          year,
          month,
          item.monthlySalary,
          item.periodStart,
          item.periodEnd,
          item.workingDays,
          item.paidDays,
          item.lopDays,
          item.deductions,
          item.lateDeductions || 0,
          item.absentDeductions || 0,
          item.netPay,
        ]
      );
      const [[saved]] = await db.query('SELECT id, status FROM hrms_payroll_items WHERE profile_id = ? AND pay_year = ? AND pay_month = ?', [item.profileId, year, month]);
      if (saved && String(saved.status) !== 'paid') {
        await db.query('DELETE FROM hrms_payroll_deduction_entries WHERE profile_id = ? AND pay_year = ? AND pay_month = ?', [item.profileId, year, month]);
        for (const entry of item.deductionEntries || []) await db.query(
          `INSERT INTO hrms_payroll_deduction_entries (profile_id, employee_user_id, pay_year, pay_month, attendance_date, deduction_type, late_minutes, amount)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [item.profileId, item.employeeUserId, year, month, entry.date, entry.type, entry.lateMinutes, entry.amount]
        );
        await replaceDailySnapshots(saved.id, item, year, month);
      }
    }
    const refreshed = await computeRows(year, month, today, options);
    return {
      year: year,
      month: month,
      items: refreshed,
      kpis: toKpis(refreshed),
      generatedCount: items.filter(item => item.status !== 'Paid').length,
      retainedPaidCount: items.filter(item => item.status === 'Paid').length,
      reviewCount: allItems.filter(item => item.integrityError).length,
      skippedCount: allItems.length - items.length,
    };
}

// Payroll generation is the primary writer. This smaller reconciliation pass
// protects the day-wise history from a stale/missing late entry when an
// attendance record was completed after the initial payroll draft was made.
// Paid payroll remains immutable for audit purposes.
async function reconcilePendingLateDeductions(profileId, year, month, schedule) {
  const [[item]] = await db.query(
    `SELECT id, employee_user_id, monthly_salary, working_days, paid_days,
            period_start, period_end, status
       FROM hrms_payroll_items
      WHERE profile_id = ? AND pay_year = ? AND pay_month = ? LIMIT 1`,
    [profileId, year, month]
  );
  if (!item || String(item.status || '').toLowerCase() === 'paid' || !item.employee_user_id) return;

  const periodStart = isoDate(item.period_start) || ymd(year, month, 1);
  const periodEnd = isoDate(item.period_end) || ymd(year, month, daysInMonth(year, month));
  const [records] = await db.query(
    `SELECT DATE_FORMAT(attendance_date, '%Y-%m-%d') AS attendance_date,
            DATE_FORMAT(check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_at,
            DATE_FORMAT(check_out_at, '%Y-%m-%d %H:%i:%s') AS check_out_at,
            attendance_status, is_late
       FROM attendance_records
      WHERE employee_id = ? AND attendance_date BETWEEN ? AND ?`,
    [item.employee_user_id, periodStart, periodEnd]
  );
  const dailyRate = Number(item.monthly_salary || 0) / Math.max(1, Number(item.working_days || 0));
  const shiftMinutes = shiftDurationMinutes(schedule.shiftStart, schedule.shiftEnd);
  const hourlyRate = dailyRate / Math.max(1, shiftMinutes / 60);
  const lateEntries = records.flatMap((record) => {
    const status = String(record.attendance_status || '').toLowerCase();
    if (!record.check_in_at || !record.check_out_at || ['absent', 'on_leave', 'half_leave'].includes(status)) return [];
    const minutes = Math.max(0, Math.floor((attendanceTimeSeconds(record.check_in_at) - timeSeconds(schedule.lateAfter)) / 60));
    if (!minutes) return [];
    return [{ date: record.attendance_date, minutes, amount: Math.round(hourlyRate * minutes / 60 * 100) / 100 }];
  });

  await db.query(
    `DELETE FROM hrms_payroll_deduction_entries
      WHERE profile_id = ? AND pay_year = ? AND pay_month = ? AND deduction_type = 'late'`,
    [profileId, year, month]
  );
  for (const entry of lateEntries) {
    await db.query(
      `INSERT INTO hrms_payroll_deduction_entries
        (profile_id, employee_user_id, pay_year, pay_month, attendance_date, deduction_type, late_minutes, amount)
       VALUES (?, ?, ?, ?, ?, 'late', ?, ?)`,
      [profileId, item.employee_user_id, year, month, entry.date, entry.minutes, entry.amount]
    );
  }
  const lateTotal = Math.round(lateEntries.reduce((sum, entry) => sum + entry.amount, 0) * 100) / 100;
  const netPay = Math.max(0, Math.round((Number(item.paid_days || 0) * dailyRate - lateTotal) * 100) / 100);
  await db.query(
    `UPDATE hrms_payroll_items
        SET late_deductions = ?, deductions = ?, net_pay = ?
      WHERE id = ? AND status <> 'paid'`,
    [lateTotal, lateTotal, netPay, item.id]
  );
}

// Shared read model for every leave/payroll UI.  Payroll remains the single
// owner of calculation rules; callers must not re-count attendance or leave.
async function projectionForEmployee(employeeUserId, year, month, today) {
  const [[profile]] = await db.query(
    'SELECT id FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1',
    [employeeUserId]
  );
  if (!profile) return null;
  const rows = await computeRows(year, month, today || policy.todayIstDate(), {
    profileIds: [Number(profile.id)],
  });
  return rows[0] || null;
}

// Persist the current result for one employee only when the impacted payroll
// period is still unpaid. Paid payroll is deliberately immutable.
async function refreshUnpaidForEmployee(employeeUserId, referenceDate) {
  const [[profile]] = await db.query(
    `SELECT id, salary_type, flexible_cycle_start_date, flexible_cycle_end_date,
            flexible_cycle_start_day, flexible_cycle_end_day
       FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1`,
    [employeeUserId]
  );
  if (!profile) return null;
  const date = isoDate(referenceDate) || policy.todayIstDate();
  const parts = date.split('-').map(Number);
  let year = parts[0];
  let month = parts[1];
  if (String(profile.salary_type || 'Standard') === 'Flexible') {
    const flexible = flexiblePeriodContaining(profile, date);
    if (!flexible) return null;
    year = flexible.year;
    month = flexible.month;
  }
  const [[saved]] = await db.query(
    `SELECT status FROM hrms_payroll_items
     WHERE profile_id = ? AND pay_year = ? AND pay_month = ? LIMIT 1`,
    [profile.id, year, month]
  );
  if (saved && String(saved.status).toLowerCase() === 'paid') return null;
  return generatePayrollRun(year, month, policy.todayIstDate(), {
    profileIds: [Number(profile.id)],
  });
}

async function markPaid(req, res) {
  try {
    const id = Number(req.params.id);
    const status = String((req.body && req.body.status) || 'paid').toLowerCase();
    const reason = String((req.body && req.body.reason) || '').trim();
    if (status !== 'paid' && status !== 'pending') {
      return fail(res, 400, 'status must be paid or pending');
    }
    const at = status === 'paid' ? policy.nowIstDateTime() : null;
    const [[payroll]] = await db.query(`SELECT p.id, p.profile_id, p.employee_user_id, p.monthly_salary, p.pay_year, p.pay_month, p.status FROM hrms_payroll_items p
      JOIN hrms_employee_profiles e ON e.id = p.profile_id AND e.employee_user_id = p.employee_user_id
      JOIN employee_users u ON u.id = e.employee_user_id WHERE p.id = ?`, [id]);
    if (!payroll) return fail(res, 404, 'Payroll row not found. Generate payroll for this month first.');
    if (Number(payroll.monthly_salary) <= 0) return fail(res, 400, 'Compensation must be configured before payroll can be paid.');
    const previousStatus = String(payroll.status || '').toLowerCase();
    // Lock a freshly generated monthly/day ledger at the exact point payroll
    // is paid.  The paid snapshot is then never recalculated implicitly.
    if (status === 'paid' && previousStatus !== 'paid') {
      await generatePayrollRun(Number(payroll.pay_year), Number(payroll.pay_month), policy.todayIstDate(), {
        profileIds: [Number(payroll.profile_id)],
      });
    }
    if (status === 'pending') {
      if (previousStatus !== 'paid') return fail(res, 400, 'Only a paid payroll can be reverted.');
      if (reason.length < 5) return fail(res, 400, 'Provide a reason of at least 5 characters before reverting paid payroll.');
      await ensurePayrollStatusAudit();
    }
    const [result] = await db.query(
      `UPDATE hrms_payroll_items
       SET status = ?, paid_at = ?
       WHERE id = ?`,
      [status, at, id]
    );
    if (!result.affectedRows) {
      return fail(res, 404, 'Payroll row not found. Generate payroll for this month first.');
    }
    if (status === 'pending') {
      await db.query(
        `INSERT INTO hrms_payroll_status_audit
          (payroll_item_id, profile_id, employee_user_id, previous_status, new_status, reason, changed_by)
         VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
        [payroll.id, payroll.profile_id, payroll.employee_user_id, previousStatus, reason, req.user && req.user.id ? req.user.id : null]
      );
    }
    const [rows] = await db.query('SELECT * FROM hrms_payroll_items WHERE id = ?', [id]);
    return ok(res, rows[0] || {}, status === 'pending' ? 'Payroll reverted to pending. Regenerate it to apply current attendance rules.' : 'Marked paid');
  } catch (error) {
    console.error('PATCH /hrms/payroll/:id', error);
    return fail(res, 500, error.message);
  }
}

async function saveCycleOverride(req, res) {
  try {
    const profileId = Number(req.params.profileId);
    const body = req.body || {};
    const year = Number(body.year);
    const month = Number(body.month);
    const periodStart = isoDate(body.periodStart);
    const periodEnd = isoDate(body.periodEnd);
    if (!profileId || !year || month < 1 || month > 12 || !periodStart || !periodEnd || periodStart > periodEnd) {
      return fail(res, 400, 'Valid employee profile, payroll month, start date, and end date are required.');
    }
    const [[profile]] = await db.query(
      `SELECT id, salary_type FROM hrms_employee_profiles WHERE id = ?`,
      [profileId]
    );
    if (!profile) return fail(res, 404, 'Employee profile not found.');
    if (String(profile.salary_type || 'Standard') !== 'Flexible') {
      return fail(res, 400, 'Only Flexible employees can have a payroll-cycle override.');
    }
    const [[paid]] = await db.query(
      `SELECT id FROM hrms_payroll_items WHERE profile_id = ? AND pay_year = ? AND pay_month = ? AND status = 'paid' LIMIT 1`,
      [profileId, year, month]
    );
    if (paid) return fail(res, 409, 'A paid payroll period cannot be changed.');
    await ensureCycleOverrides();
    await db.query(
      `INSERT INTO hrms_payroll_cycle_overrides
       (profile_id, pay_year, pay_month, period_start, period_end, updated_by)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE period_start = VALUES(period_start), period_end = VALUES(period_end), updated_by = VALUES(updated_by)`,
      [profileId, year, month, periodStart, periodEnd, req.user.id]
    );
    const [[owner]] = await db.query(
      'SELECT employee_user_id FROM hrms_employee_profiles WHERE id = ? LIMIT 1',
      [profileId]
    );
    if (owner && owner.employee_user_id) {
      await refreshUnpaidForEmployee(Number(owner.employee_user_id), periodEnd);
    }
    return ok(res, { profileId, year, month, periodStart, periodEnd }, 'Custom payroll cycle saved.');
  } catch (error) {
    console.error('PUT /hrms/payroll/:profileId/cycle-override', error);
    return fail(res, 500, error.message);
  }
}

async function deductionHistory(req, res) {
  try {
    const profileId = Number(req.params.profileId);
    const year = Number(req.query.year);
    const month = Number(req.query.month);
    if (!Number.isInteger(profileId) || profileId < 1 || !Number.isInteger(year) || year < 1 ||
        !Number.isInteger(month) || month < 1 || month > 12) {
      return fail(res, 400, 'profile, year, and month are required');
    }
    const [[profile]] = await db.query(
      `SELECT monthly_salary, gender
       FROM hrms_employee_profiles
       WHERE id = ?`,
      [profileId]
    );
    if (!profile) return fail(res, 404, 'Employee profile not found.');
    const timeSettings = await policy.getTimeSettings(db);
    const schedule = String(profile.gender).toLowerCase() === 'female'
      ? timeSettings.female
      : timeSettings.male;

    // Keep draft/pending payroll in sync with attendance changes before it is
    // displayed. A paid run is immutable: generatePayrollRun deliberately
    // preserves its amounts and deduction entries.
    await generatePayrollRun(year, month, policy.todayIstDate(), {
      profileIds: [profileId],
    });

    const [[summary]] = await db.query(
      `SELECT monthly_salary, working_days, paid_days, lop_days,
              late_deductions, absent_deductions, deductions, net_pay, status
       FROM hrms_payroll_items
       WHERE profile_id = ? AND pay_year = ? AND pay_month = ?
       LIMIT 1`, [profileId, year, month]
    );
    // Preferred read path: the monthly summary and every visible day now
    // come from the same generated payroll snapshot.  This is what keeps
    // admin payroll, employee salary and the history modal in agreement.
    const [dailyRows] = await db.query(
      `SELECT DATE_FORMAT(attendance_date, '%Y-%m-%d') AS attendance_date,
              attendance_status, paid_units, lop_units, late_minutes, daily_salary, late_deduction,
              early_exit_minutes, early_exit_deduction,
              absent_amount, total_deduction, present_amount, updated_salary,
              DATE_FORMAT(check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_at,
              DATE_FORMAT(check_out_at, '%Y-%m-%d %H:%i:%s') AS check_out_at
         FROM hrms_payroll_daily_entries
        WHERE profile_id = ? AND pay_year = ? AND pay_month = ?
        ORDER BY attendance_date DESC`,
      [profileId, year, month]
    );
    if (dailyRows.length) {
      const late = Number(summary?.late_deductions || 0);
      const timeDeduction = Number(summary?.deductions || late);
      const absent = Number(summary?.absent_deductions || 0);
      return ok(res, {
        overview: {
          monthlySalary: Number(summary?.monthly_salary ?? profile.monthly_salary ?? 0),
          workingDays: summary ? Number(summary.working_days || 0) : null,
          shiftStart: schedule.shiftStart,
          shiftEnd: schedule.shiftEnd,
          shiftMinutes: shiftDurationMinutes(schedule.shiftStart, schedule.shiftEnd),
        },
        summary: summary ? {
          salary: Number(summary.monthly_salary || 0), workingDays: Number(summary.working_days || 0),
          paidDays: Number(summary.paid_days || 0), lopDays: Number(summary.lop_days || 0),
          lateDeduction: late, absentDeduction: absent, totalDeduction: timeDeduction + absent,
          netPay: Number(summary.net_pay || 0), status: summary.status,
        } : null,
        items: dailyRows.map((row) => {
          const status = String(row.attendance_status || '');
          const isLate = status === 'Late' || status === 'Early Exit';
          const isAbsence = status === 'Absent' || status === 'Half Leave';
          const dailySalary = Number(row.daily_salary || 0);
          const timeDeduction = Number(row.late_deduction || 0) + Number(row.early_exit_deduction || 0);
          // Units are persisted with the ledger. The UI only renders them;
          // it never infers payroll values from attendance text or money.
          const paidUnits = Number(row.paid_units || 0);
          const lopUnits = Number(row.lop_units || 0);
          // Keep `amount` for older consumers, but make it describe the
          // applicable deduction for the row. Newer clients should use the
          // explicit amount fields below.
          const amount = isLate
            ? Number(row.late_deduction || 0) + Number(row.early_exit_deduction || 0)
            : isAbsence
              ? Number(row.absent_amount || 0)
              : 0;
          return {
          attendance_date: row.attendance_date,
          deduction_type: isLate ? 'late' : isAbsence ? 'absent' : status === 'In Progress' ? 'pending' : 'present',
          late_minutes: Number(row.late_minutes || 0),
          amount,
          daily_salary: dailySalary,
          paid_units: paidUnits,
          lop_units: lopUnits,
          updated_salary: Number(row.updated_salary || 0),
          check_in_at: row.check_in_at,
          check_out_at: row.check_out_at,
          attendance_status: row.attendance_status,
          // Existing tables have one time-deduction column.  It shows both
          // late-arrival and early-checkout deductions without changing the
          // established column layout; raw values remain available too.
          late_deduction: timeDeduction,
          time_deduction: timeDeduction,
          early_exit_minutes: Number(row.early_exit_minutes || 0),
          early_exit_deduction: Number(row.early_exit_deduction || 0),
          absent_amount: Number(row.absent_amount || 0),
          total_deduction: Number(row.total_deduction || 0),
          present_amount: Number(row.present_amount || 0),
          };
        }),
      });
    }
    const [rows] = await db.query(
      `SELECT DATE_FORMAT(x.attendance_date, '%Y-%m-%d') AS attendance_date,
              COALESCE(d.deduction_type,
                CASE
                  WHEN a.check_in_at IS NOT NULL AND a.check_out_at IS NULL THEN 'pending'
                  WHEN LOWER(COALESCE(a.attendance_status, '')) = 'late' OR a.is_late = 1 THEN 'late'
                  WHEN a.check_in_at IS NOT NULL THEN 'present'
                  ELSE 'absent'
                END) AS deduction_type,
              COALESCE(d.late_minutes, 0) AS late_minutes,
              COALESCE(d.amount, 0) AS amount,
              ROUND(p.monthly_salary / NULLIF(p.working_days, 0), 2) AS daily_salary,
              ROUND((p.monthly_salary / NULLIF(p.working_days, 0)) - COALESCE(d.amount, 0), 2) AS updated_salary,
              DATE_FORMAT(a.check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_at,
              DATE_FORMAT(a.check_out_at, '%Y-%m-%d %H:%i:%s') AS check_out_at,
              CASE
                WHEN a.check_in_at IS NOT NULL AND a.check_out_at IS NULL THEN 'In Progress'
                WHEN LOWER(COALESCE(a.attendance_status, '')) = 'early_exit'
                     AND a.scheduled_shift_end IS NOT NULL
                     AND TIME(a.check_out_at) < a.scheduled_shift_end THEN 'Early Exit'
                WHEN d.deduction_type = 'late' OR LOWER(COALESCE(a.attendance_status, '')) = 'late' OR a.is_late = 1 THEN 'Late'
                WHEN LOWER(COALESCE(a.attendance_status, '')) = 'early_exit' THEN 'Early Exit'
                WHEN LOWER(COALESCE(a.attendance_status, '')) = 'half_leave' THEN 'Half Leave'
                WHEN LOWER(COALESCE(a.attendance_status, '')) = 'on_leave' THEN 'On Leave'
                WHEN LOWER(COALESCE(a.attendance_status, '')) = 'absent' OR a.check_in_at IS NULL THEN 'Absent'
                ELSE 'Present'
              END AS attendance_status
       FROM (
         SELECT attendance_date FROM attendance_records
         WHERE employee_id = (SELECT employee_user_id FROM hrms_payroll_items WHERE profile_id = ? AND pay_year = ? AND pay_month = ? LIMIT 1)
           AND YEAR(attendance_date) = ? AND MONTH(attendance_date) = ?
         UNION SELECT attendance_date FROM hrms_payroll_deduction_entries
         WHERE profile_id = ? AND pay_year = ? AND pay_month = ?
           AND YEAR(attendance_date) = ? AND MONTH(attendance_date) = ?
       ) x
       LEFT JOIN hrms_payroll_items p ON p.profile_id = ? AND p.pay_year = ? AND p.pay_month = ?
       LEFT JOIN attendance_records a ON a.employee_id = p.employee_user_id AND a.attendance_date = x.attendance_date
       LEFT JOIN hrms_payroll_deduction_entries d ON d.profile_id = p.profile_id AND d.pay_year = p.pay_year AND d.pay_month = p.pay_month AND d.attendance_date = x.attendance_date
       ORDER BY x.attendance_date ASC`,
      [profileId, year, month, year, month, profileId, year, month, year, month, profileId, year, month]
    );
    // Updated salary is a running payroll-month balance. Present days add the
    // daily salary; late days add the daily salary after that day's deduction;
    // absent days do not add to the balance.
    let runningSalary = 0;
    for (const row of rows) {
      const status = String(row.attendance_status || '').toLowerCase();
      const daily = Number(row.daily_salary || 0);
      const amount = Number(row.amount || 0);
      if (status === 'present' || status === 'late') {
        runningSalary += daily - (status === 'late' ? amount : 0);
      }
      row.updated_salary = Number(runningSalary.toFixed(2));
    }
    rows.reverse();
    const late = Number(summary?.late_deductions || 0);
    const timeDeduction = Number(summary?.deductions || late);
    const absent = Number(summary?.absent_deductions || 0);
    return ok(res, {
      overview: {
        monthlySalary: Number(summary?.monthly_salary ?? profile.monthly_salary ?? 0),
        workingDays: summary ? Number(summary.working_days || 0) : null,
        shiftStart: schedule.shiftStart,
        shiftEnd: schedule.shiftEnd,
        shiftMinutes: shiftDurationMinutes(schedule.shiftStart, schedule.shiftEnd),
      },
      summary: summary ? {
        salary: Number(summary.monthly_salary || 0), workingDays: Number(summary.working_days || 0),
        paidDays: Number(summary.paid_days || 0), lopDays: Number(summary.lop_days || 0),
        lateDeduction: late, absentDeduction: absent, totalDeduction: timeDeduction + absent,
        netPay: Number(summary.net_pay || 0), status: summary.status,
      } : null,
      items: rows,
    });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function history(req, res) {
  try {
    const profileId = Number(req.params.profileId);
    if (!Number.isInteger(profileId) || profileId < 1) {
      return fail(res, 400, 'profile is required');
    }
    const [rows] = await db.query(
      `SELECT pay_year, pay_month, monthly_salary, working_days, paid_days, lop_days,
              late_deductions, absent_deductions, deductions, net_pay, status
       FROM hrms_payroll_items
       WHERE profile_id = ?
       ORDER BY pay_year DESC, pay_month DESC`,
      [profileId]
    );
    return ok(res, rows.map((row) => {
      const late = Number(row.late_deductions || 0);
      const timeDeduction = Number(row.deductions || late);
      const absent = Number(row.absent_deductions || 0);
      return {
        year: Number(row.pay_year), month: Number(row.pay_month),
        label: `${row.pay_year}-${String(row.pay_month).padStart(2, '0')}`,
        salary: Number(row.monthly_salary || 0),
        workingDays: Number(row.working_days || 0), paidDays: Number(row.paid_days || 0),
        lopDays: Number(row.lop_days || 0), lateDeduction: late,
        absentDeduction: absent, totalDeduction: timeDeduction + absent,
        netPay: Number(row.net_pay || 0), status: row.status,
      };
    }));
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

module.exports = {
  requireAdmin,
  list,
  generate,
  markPaid,
  saveCycleOverride,
  deductionHistory,
  history,
  getPolicy,
  savePolicy,
  generatePayrollRun,
  ensureDailyPayrollStorage,
  computeRows,
  projectionForEmployee,
  refreshUnpaidForEmployee,
  runAutomaticPayroll,
  payrollPeriod,
  flexiblePeriodContaining,
};
