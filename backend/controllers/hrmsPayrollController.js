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

  const profileSql = `
    SELECT p.* FROM hrms_employee_profiles p JOIN employee_users u ON u.id = p.employee_user_id
    WHERE p.employment_status <> 'Inactive' AND u.is_active = 1
    ${requestedProfileIds.length ? 'AND p.id IN (?)' : ''}
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
                is_late, attendance_status
         FROM attendance_records
         WHERE attendance_date BETWEEN ? AND ?
           AND employee_id IN (?)`,
        [queryStart, queryEnd, userIds]
      )
    : [[]];

  const [leaves] = userIds.length
    ? await db.query(
        `SELECT l.employee_id, DATE_FORMAT(l.from_date, '%Y-%m-%d') AS request_date
         FROM employee_leaves l
         LEFT JOIN hrms_leave_approval_links link ON link.leave_id = l.id
         LEFT JOIN attendance_permission_requests approval ON approval.id = link.approval_request_id
         WHERE l.status = 'APPROVED'
           AND (l.leave_type = 'Earned Leave' OR approval.salary_mode = 'paid')
           AND l.from_date = l.to_date AND LOWER(l.duration_type) = 'full day'
           AND l.from_date BETWEEN ? AND ?
           AND l.employee_id IN (?)`,
        [queryStart, queryEnd, userIds]
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
  const leaveSet = new Set();
  const paidRegularizationSet = new Set();
  leaves.forEach(function (row) {
    leaveSet.add(row.employee_id + '|' + isoDate(row.request_date));
  });
  paidRegularizations.forEach(function (row) {
    const regularizationKey = row.employee_id + '|' + isoDate(row.request_date);
    leaveSet.add(regularizationKey);
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
    const absentEntries = [];

    for (let date = period.start; date <= cutoff; date = nextDate(date)) {
      const dateParts = date.split('-').map(Number);
      if (!employeeWorkingDay(date, weeklyResolver, calendarOverrides)) continue;
      elapsedWorkingDays += 1;
      const userId = profile.employee_user_id;
      const key = userId ? userId + '|' + date : '';
      const record = key ? recordMap.get(key) : null;

      // 1. Safely read the status to ignore case (e.g., 'Absent' vs 'absent')
      const attStatus = record && record.attendance_status ? String(record.attendance_status).toLowerCase().trim() : '';

      if (key && paidRegularizationSet.has(key)) {
        // An approved paid regularization wins over a generated/explicit
        // absence, without manufacturing a clock-in timestamp.
        present += 1;
        earnedDays += 1;
      } else if (attStatus === 'half_leave') {
        unpaidHalfDays += 0.5;
        absentEntries.push({ date: date, days: 0.5 });
        earnedDays += 0.5;
      } else if (attStatus === 'absent') {
        // An explicit absence is visible in the summary even when the policy
        // treats it as paid time.
        absent += 1;
        absentEntries.push({ date: date, days: 1 });
      } else if (record && record.check_in_at) {
        // Punched in
        if (Number(record.is_late) || attStatus === 'late') late += 1;
        const schedule = String(profile.gender).toLowerCase() === 'female' ? timeSettings.female : timeSettings.male;
        const lateMinutes = Math.max(0, Math.floor((attendanceTimeSeconds(record.check_in_at) - timeSeconds(schedule.lateAfter)) / 60));
        if (lateMinutes > 0) lateEntries.push({ date: date, minutes: lateMinutes });
        else present += 1;
        earnedDays += 1;
      } else if (key && leaveSet.has(key)) {
        // Approved leave
        leaveDays += 1;
        earnedDays += 1;
      } else {
        // A completed working day with no attendance is always absent. Its
        // value is not subtracted from accrued pay: it simply never becomes
        // a paid day in the first place.
        absent += 1;
        absentEntries.push({ date: date, days: 1 });
      }
    }

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
    const workingDays = periodWorkingDays;
    const paidDays = Math.min(workingDays, earnedDays);
    const lopDays = Math.max(0, elapsedWorkingDays - paidDays);
    // This is the unpaid value of mandatory absence days. Net pay is still
    // earned from zero through paid days, so this value is informational and
    // is never subtracted from money the employee has already earned.
    const absentDeductions = Math.round(
      absentEntries.reduce((sum, item) => sum + (dailyRate * item.days), 0) * 100,
    ) / 100;
    const deductions = salaryNumber ? Math.round(lateDeductions * 100) / 100 : 0;
    // Salary is accrued from paid days; an absence never removes pay already earned.
    const netPay = Math.max(0, Math.round((paidDays * dailyRate - deductions) * 100) / 100);

    const saved = savedMap.get(Number(profile.id));
    if (saved && (Number(saved.employee_user_id) !== Number(profile.employee_user_id) ||
        (saved.status === 'paid' && !(Number(saved.monthly_salary) > 0)))) {
      return { id: saved.id, profileId: profile.id, employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(), employeeCode: profile.employee_code,
        department: profile.department, monthlySalary: salaryNumber || null, salary: formatSalary(salaryNumber || null),
        salaryType: period.salaryType, periodStart: period.start, periodEnd: period.end, cycleOverridden: Boolean(period.overridden),
        workingDays, paidDays, lopDays, deductions: 0, deductionsLabel: 'Review required',
        netPay: 0, netPayLabel: 'Review required', status: 'Review required', paidAt: '',
        integrityError: 'Saved payroll has inconsistent ownership or missing paid salary. An audited correction is required.' };
    }

    if (!salaryNumber) {
      return {
        id: saved ? saved.id : null, profileId: profile.id, employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(), employeeCode: profile.employee_code,
        department: profile.department, monthlySalary: null, salary: 'Not Set',
        salaryType: period.salaryType, periodStart: period.start, periodEnd: period.end, cycleOverridden: Boolean(period.overridden),
        workingDays: workingDays, presentDays: present, lateDays: late, leaveDays: leaveDays, absentDays: absent,
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
        workingDays: Number(saved.working_days || 0), presentDays: present, lateDays: late, leaveDays: leaveDays, absentDays: absent,
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
      monthlySalary: salaryNumber || null,
      salary: formatSalary(salaryNumber),
      workingDays: workingDays,
      presentDays: present,
      lateDays: late,
      leaveDays: leaveDays,
      absentDays: absent,
      paidDays: paidDays,
      lopDays: lopDays,
      deductions: deductions,
      lateDeductions: Math.round(lateDeductions * 100) / 100,
      absentDeductions: Math.round(absentDeductions * 100) / 100,
      deductionEntries: [
        ...lateEntries.map(item => ({ date: item.date, type: 'late', lateMinutes: item.minutes, amount: Math.round(hourlyRate * item.minutes / 60 * 100) / 100 })),
        ...absentEntries.map(item => ({ date: item.date, type: 'absent', lateMinutes: 0, amount: Math.round(dailyRate * item.days * 100) / 100 })),
      ],
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

async function generatePayrollRun(year, month, today, options) {
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

async function markPaid(req, res) {
  try {
    const id = Number(req.params.id);
    const status = String((req.body && req.body.status) || 'paid').toLowerCase();
    const reason = String((req.body && req.body.reason) || '').trim();
    if (status !== 'paid' && status !== 'pending') {
      return fail(res, 400, 'status must be paid or pending');
    }
    const at = status === 'paid' ? policy.nowIstDateTime() : null;
    const [[payroll]] = await db.query(`SELECT p.id, p.profile_id, p.employee_user_id, p.monthly_salary, p.status FROM hrms_payroll_items p
      JOIN hrms_employee_profiles e ON e.id = p.profile_id AND e.employee_user_id = p.employee_user_id
      JOIN employee_users u ON u.id = e.employee_user_id WHERE p.id = ?`, [id]);
    if (!payroll) return fail(res, 404, 'Payroll row not found. Generate payroll for this month first.');
    if (Number(payroll.monthly_salary) <= 0) return fail(res, 400, 'Compensation must be configured before payroll can be paid.');
    const previousStatus = String(payroll.status || '').toLowerCase();
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
    // History is read-only: changing the selected month must not regenerate
    // payroll, alter tables, or replace saved deduction entries.
    const [[summary]] = await db.query(
      `SELECT monthly_salary, working_days, paid_days, lop_days,
              late_deductions, absent_deductions, deductions, net_pay, status
       FROM hrms_payroll_items
       WHERE profile_id = ? AND pay_year = ? AND pay_month = ?
       LIMIT 1`, [profileId, year, month]
    );
    const [rows] = await db.query(
      `SELECT DATE_FORMAT(x.attendance_date, '%Y-%m-%d') AS attendance_date,
              COALESCE(d.deduction_type, CASE WHEN a.attendance_status = 'present' THEN 'present' ELSE 'absent' END) AS deduction_type,
              COALESCE(d.late_minutes, 0) AS late_minutes,
              COALESCE(d.amount, 0) AS amount,
              ROUND(p.monthly_salary / NULLIF(p.working_days, 0), 2) AS daily_salary,
              ROUND((p.monthly_salary / NULLIF(p.working_days, 0)) - COALESCE(d.amount, 0), 2) AS updated_salary,
              DATE_FORMAT(a.check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_at,
              DATE_FORMAT(a.check_out_at, '%Y-%m-%d %H:%i:%s') AS check_out_at,
              CASE WHEN d.deduction_type = 'late' THEN 'Late'
                   WHEN a.check_in_at IS NOT NULL THEN 'Present' ELSE 'Absent' END AS attendance_status
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
    const late = Number(summary?.late_deductions || summary?.deductions || 0);
    const absent = Number(summary?.absent_deductions || 0);
    return ok(res, {
      summary: summary ? {
        salary: Number(summary.monthly_salary || 0), workingDays: Number(summary.working_days || 0),
        paidDays: Number(summary.paid_days || 0), lopDays: Number(summary.lop_days || 0),
        lateDeduction: late, absentDeduction: absent, totalDeduction: late + absent,
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
      const late = Number(row.late_deductions || row.deductions || 0);
      const absent = Number(row.absent_deductions || 0);
      return {
        year: Number(row.pay_year), month: Number(row.pay_month),
        label: `${row.pay_year}-${String(row.pay_month).padStart(2, '0')}`,
        salary: Number(row.monthly_salary || 0),
        workingDays: Number(row.working_days || 0), paidDays: Number(row.paid_days || 0),
        lopDays: Number(row.lop_days || 0), lateDeduction: late,
        absentDeduction: absent, totalDeduction: late + absent,
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
  runAutomaticPayroll,
  payrollPeriod,
  flexiblePeriodContaining,
};
