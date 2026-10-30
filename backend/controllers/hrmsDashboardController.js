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

function normalizeTime(value, label) {
  const time = String(value || '').trim();
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(time)) throw new Error(label + ' must use HH:mm');
  return time.length === 5 ? time + ':00' : time;
}

function seconds(time) {
  const parts = String(time).split(':').map(Number);
  return parts[0] * 3600 + parts[1] * 60 + (parts[2] || 0);
}

function requireAdmin(req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
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

function jsWeeklyOff(weeklyOff) {
  const value = Number(weeklyOff);
  if (value === 7) return 0;
  if (value >= 1 && value <= 6) return value;
  return 0;
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function nextDate(date) {
  const parts = String(date).split('-').map(Number);
  const value = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + 1));
  return ymd(value.getUTCFullYear(), value.getUTCMonth() + 1, value.getUTCDate());
}

function flexibleSalaryStartsOn(profile) {
  if (String(profile.salary_type || '').toLowerCase() !== 'flexible') return null;
  const value = profile.flexible_cycle_start_date;
  if (!value) return null;
  return String(value).slice(0, 10);
}

async function ensureCalendarOverridesTable() {
  await calendar.ensureCalendarTables();
}

async function calendarOverrides(req, res) {
  try {
    await ensureCalendarOverridesTable();
    const [rows] = await db.query(`SELECT DATE_FORMAT(calendar_date, '%Y-%m-%d') AS date,
      status, scope, reason, updated_at AS updatedAt
      FROM hrms_calendar_overrides ORDER BY calendar_date ASC`);
    const rules = await getPayrollPolicy();
    return ok(res, { overrides: rows, weeklyOffDays: [...rules.weeklyOffDays] });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function saveCalendarOverride(req, res) {
  try {
    const body = req.body || {};
    const date = String(body.date || '');
    const status = String(body.status || '');
    const scope = String(body.scope || 'All Employees').slice(0, 40);
    const reason = String(body.reason || '').trim().slice(0, 255);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('A valid calendar date is required');
    if (!['Working Day', 'Weekly Off', 'Holiday'].includes(status)) throw new Error('Invalid calendar status');
    if (!reason) throw new Error('A reason is required');
    await ensureCalendarOverridesTable();
    await db.query(`INSERT INTO hrms_calendar_overrides
      (calendar_date, status, scope, reason, updated_by)
      VALUES (?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE status = VALUES(status), scope = VALUES(scope),
        reason = VALUES(reason), updated_by = VALUES(updated_by)`,
      [date, status, scope, reason, req.user.id]);
    await db.query(`CREATE TABLE IF NOT EXISTS hrms_employee_calendar_notifications (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      employee_user_id BIGINT UNSIGNED NOT NULL,
      calendar_date DATE NOT NULL, status VARCHAR(20) NOT NULL, reason VARCHAR(255) NOT NULL,
      is_dismissed TINYINT(1) NOT NULL DEFAULT 0, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      KEY employee_unread (employee_user_id, is_dismissed, created_at)
    )`);
    if (scope === 'All Employees') {
      await db.query(`INSERT INTO hrms_employee_calendar_notifications (employee_user_id, calendar_date, status, reason)
        SELECT employee_user_id, ?, ?, ? FROM hrms_employee_profiles WHERE employment_status <> 'Inactive'`, [date, status, reason]);
    }
    return ok(res, { date: date, status: status, scope: scope, reason: reason }, 'Calendar override saved');
  } catch (error) {
    return fail(res, 400, error.message);
  }
}

async function getPayrollPolicy() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payroll_policy (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY, weekly_off_days JSON NOT NULL,
    deduct_approved_leave TINYINT(1) NOT NULL DEFAULT 1,
    deduct_explicit_absence TINYINT(1) NOT NULL DEFAULT 1,
    missing_attendance_is_absent TINYINT(1) NOT NULL DEFAULT 0
  )`);
  try { await db.query('ALTER TABLE hrms_payroll_policy ADD COLUMN salary_day_divisor TINYINT UNSIGNED NOT NULL DEFAULT 26'); } catch (_) {}
  await db.query(`INSERT IGNORE INTO hrms_payroll_policy (id, weekly_off_days) VALUES (1, '[0]')`);
  const [rows] = await db.query('SELECT * FROM hrms_payroll_policy WHERE id = 1');
  const row = rows[0] || {};
  const days = weeklyOffTemplates.parseDays(row.weekly_off_days, [0]);
  return { weeklyOffDays: new Set(Array.isArray(days) ? days.map(Number) : [0]), deductLeave: Boolean(Number(row.deduct_approved_leave ?? 1)), deductAbsence: Boolean(Number(row.deduct_explicit_absence ?? 1)), missingIsAbsent: Boolean(Number(row.missing_attendance_is_absent ?? 0)) };
}

async function saveCalendarWeeklyOff(req, res) {
  try {
    const days = weeklyOffTemplates.normalizeDays(req.body.weeklyOffDays);
    await getPayrollPolicy();
    await db.query('UPDATE hrms_payroll_policy SET weekly_off_days = ? WHERE id = 1', [JSON.stringify(days)]);
    return ok(res, { weeklyOffDays: days }, 'Default weekly off saved');
  } catch (error) {
    return fail(res, 400, error.message);
  }
}

async function timeSettings(req, res) {
  try {
    const [rows] = await db.query('SELECT labour_lunch_start, labour_lunch_end, employee_lunch_start, employee_lunch_end FROM hrms_tracking_settings WHERE id = 1');
    const row = rows[0] || {};
    return ok(res, { ...(await policy.getTimeSettings(db)), labourLunchStart: String(row.labour_lunch_start || '12:30:00'), labourLunchEnd: String(row.labour_lunch_end || '13:00:00'), employeeLunchStart: String(row.employee_lunch_start || '12:30:00'), employeeLunchEnd: String(row.employee_lunch_end || '13:00:00') });
  } catch (error) {
    console.error('GET /hrms/dashboard/time-settings', error);
    return fail(res, 500, error.message);
  }
}

async function updateTimeSettings(req, res) {
  try {
    const body = req.body || {};
    const labourStart = normalizeTime(body.labourLunchStart, 'Labour lunch start');
    const labourEnd = normalizeTime(body.labourLunchEnd, 'Labour lunch end');
    const employeeStart = normalizeTime(body.employeeLunchStart, 'Employee lunch start');
    const employeeEnd = normalizeTime(body.employeeLunchEnd, 'Employee lunch end');
    if (seconds(labourEnd) <= seconds(labourStart) || seconds(employeeEnd) <= seconds(employeeStart)) throw new Error('Lunch end time must be after lunch start time');
    const updated = await policy.updateTimeSettings(db, body);
    await db.query('UPDATE hrms_tracking_settings SET labour_lunch_start = ?, labour_lunch_end = ?, employee_lunch_start = ?, employee_lunch_end = ?, updated_by = ? WHERE id = 1', [labourStart, labourEnd, employeeStart, employeeEnd, req.user.id]);
    return ok(res, { ...updated, labourLunchStart: labourStart, labourLunchEnd: labourEnd, employeeLunchStart: employeeStart, employeeLunchEnd: employeeEnd }, 'Attendance time settings updated');
  } catch (error) {
    return fail(res, 400, error.message);
  }
}
async function monthView(req, res) {
  try {
    const year = Number(req.query.year);
    const month = Number(req.query.month);
    if (!year || month < 1 || month > 12) {
      return fail(res, 400, 'year and month (1-12) are required');
    }

    const payrollRules = await getPayrollPolicy();
    const weeklyOff = payrollRules.weeklyOffDays;
    const totalDays = daysInMonth(year, month);
    const start = ymd(year, month, 1);
    const end = ymd(year, month, totalDays);
    const calendarOverrides = await calendar.overridesForPeriod(start, end);
    // This aggregate remains the global-policy reference for legacy KPI
    // widgets. Employee rows below use their own effective-dated template.
    const globalWorkingDays = calendar.countWorkingDays(start, end, weeklyOff, calendarOverrides);
    const today = policy.todayIstDate();

    // Use the same HRMS profile source as the Employee Management page so
    // dashboard totals cannot include stale/orphan employee login accounts.
    const [profiles] = await db.query(`
      SELECT
        profile.id,
        employee.id AS employee_user_id,
        employee.full_name,
        COALESCE(NULLIF(profile.department, ''), employee.role, 'Not Set') AS department,
        COALESCE(profile.monthly_salary, 0) AS monthly_salary,
        profile.salary_type,
        DATE_FORMAT(profile.flexible_cycle_start_date, '%Y-%m-%d') AS flexible_cycle_start_date,
        DATE_FORMAT(profile.flexible_cycle_end_date, '%Y-%m-%d') AS flexible_cycle_end_date
      FROM hrms_employee_profiles AS profile
      INNER JOIN employee_users AS employee
        ON profile.employee_user_id = employee.id
      WHERE employee.user_type = 'employee'
        AND employee.is_active = 1
        AND profile.employment_status <> 'Inactive'
      ORDER BY profile.full_name ASC
    `);
    await weeklyOffTemplates.ensureWeeklyOffTemplateTables(db);
    const weeklyResolvers = new Map();
    for (const profile of profiles) {
      weeklyResolvers.set(Number(profile.id), await weeklyOffTemplates.offDaysForProfileByDate(
        db, Number(profile.id), start, end, [...weeklyOff]
      ));
    }
    const [leavePolicyRows] = await db.query(
      `SELECT leave_type FROM hrms_leave_policies
       WHERE effective_year = ? AND active = 1 AND annual_allowance > 0`,
      [year]
    ).catch(() => [[]]);
    const enabledLeaveTypes = leavePolicyRows.map(function (row) { return String(row.leave_type); });

    const userIds = profiles
      .map(function (row) { return row.employee_user_id; })
      .filter(Boolean);

    const [lateDeductionRows] = await db.query(
      `SELECT employee_user_id, COALESCE(SUM(amount), 0) AS late_deduction
       FROM hrms_payroll_deduction_entries
       WHERE pay_year = ? AND pay_month = ? AND deduction_type = 'late'
         AND employee_user_id IN (?)
       GROUP BY employee_user_id`,
      [year, month, userIds.length ? userIds : [0]]
    ).catch(() => [[]]);
    const lateDeductionByUser = new Map(
      lateDeductionRows.map(function (row) {
        return [Number(row.employee_user_id), Number(row.late_deduction || 0)];
      })
    );

    const [records] = userIds.length
      ? await db.query(
          `SELECT * FROM attendance_records
           WHERE attendance_date BETWEEN ? AND ?
             AND employee_id IN (?)`,
          [start, end, userIds]
        )
      : [[]];

    const [leaves] = userIds.length
      ? await db.query(
        `SELECT l.employee_id, l.duration_type, l.leave_type,
                  approval.salary_mode,
                  DATE_FORMAT(l.from_date, '%Y-%m-%d') AS from_date,
                  DATE_FORMAT(l.to_date, '%Y-%m-%d') AS to_date
           FROM employee_leaves l
           LEFT JOIN hrms_leave_approval_links link ON link.leave_id = l.id
           LEFT JOIN attendance_permission_requests approval ON approval.id = link.approval_request_id
           WHERE UPPER(l.status) = 'APPROVED'
             AND DATE(l.from_date) <= DATE(?) AND DATE(l.to_date) >= DATE(?)
             AND l.employee_id IN (?)`,
          [end, start, userIds]
        )
      : [[]];
    const [regularizations] = userIds.length
      ? await db.query(
          `SELECT employee_id, DATE_FORMAT(request_date, '%Y-%m-%d') AS request_date, salary_mode
           FROM attendance_permission_requests
           WHERE request_type = 'attendance_regularization' AND status = 'approved'
             AND request_date BETWEEN ? AND ? AND employee_id IN (?)`,
          [start, end, userIds]
        )
      : [[]];

    const recordMap = new Map();
    records.forEach(function (row) {
      const attendanceDate = row.attendance_date instanceof Date
        ? ymd(row.attendance_date.getFullYear(), row.attendance_date.getMonth() + 1, row.attendance_date.getDate())
        : String(row.attendance_date).slice(0, 10);
      const key = row.employee_id + '|' + attendanceDate;
      recordMap.set(key, row);
    });

    const leaveMap = new Map();
    leaves.forEach(function (row) {
      let date = row.from_date;
      const code = row.duration_type === 'Half Day' ? 'HL' : ({
        'Earned Leave': 'EL', 'Casual Leave': 'CL',
        'Sick Leave': 'SL', 'Optional Holiday': 'OL',
      }[row.leave_type] || 'LV');
      while (date <= row.to_date) {
        const key = row.employee_id + '|' + date;
        leaveMap.set(key, {
          code: code,
          leaveType: row.leave_type,
          isPaid: row.leave_type === 'Earned Leave' || String(row.salary_mode).toLowerCase() === 'paid',
        });
        date = nextDate(date);
      }
    });
    const regularizationMap = new Map();
    regularizations.forEach(function (row) {
      regularizationMap.set(row.employee_id + '|' + row.request_date, String(row.salary_mode || '').toLowerCase());
    });

    let presentDays = 0;
    let absentDays = 0;
    let lateDays = 0;

    const employees = profiles.map(function (profile) {
      const weeklyResolver = weeklyResolvers.get(Number(profile.id));
      const days = [];
      let present = 0;
      let late = 0;
      let halfLeave = 0;
      let earnedLeave = 0;
      let approvedLeave = 0;
      let absent = 0;
      let unexcused = 0;
      let accruedPaidDays = 0;
      const salaryStartsOn = flexibleSalaryStartsOn(profile);

      for (let day = 1; day <= totalDays; day += 1) {
        const date = ymd(year, month, day);
        // A Flexible employee's first configured salary cycle is an
        // effective date, not an absence period. Blank pre-cycle dates so
        // the attendance sheet never treats them as unpaid absences.
        if (salaryStartsOn && date < salaryStartsOn) {
          days.push('');
          continue;
        }
        if (!employeeWorkingDay(date, weeklyResolver, calendarOverrides)) {
          days.push('OFF');
          continue;
        }
        const userId = profile.employee_user_id;
        const key = userId ? userId + '|' + date : '';
        const record = key ? recordMap.get(key) : null;
        const leaveInfo = key ? leaveMap.get(key) : null;
        const regularization = key ? regularizationMap.get(key) : null;
        const leaveType = leaveInfo ? leaveInfo.code : null;

        // Future dates stay blank, except for leave that is already approved.
        if (date > today && !leaveType) {
          days.push('');
          continue;
        }

        // A recorded clock-in is the final decision for that date. Leave is
        // shown only when the employee has no attendance record.
        // An explicit absence is always shown as an absence. Whether it is
        // an LOP day is a separate payroll-policy decision.
        if (regularization === 'paid') {
          days.push('P');
          present += 1;
          presentDays += 1;
          accruedPaidDays += 1;
        } else if (regularization === 'unpaid') {
          days.push('AR');
        } else if (record && record.check_in_at && String(record.attendance_status).toLowerCase() !== 'absent') {
          if (String(record.attendance_status) === 'half_leave') {
            days.push('HL');
            halfLeave += 1;
            unexcused += 0.5;
            accruedPaidDays += 0.5;
          } else if (Number(record.is_late)) {
            days.push('L');
            late += 1;
            lateDays += 1;
            accruedPaidDays += 1;
          } else {
            days.push('P');
            present += 1;
            presentDays += 1;
            accruedPaidDays += 1;
          }
        } else if (leaveType) {
          days.push(leaveType);
          approvedLeave += 1;
          if (leaveType === 'HL') halfLeave += 1;
          if (leaveInfo.isPaid) {
            earnedLeave += 1;
            accruedPaidDays += leaveType === 'HL' ? 0.5 : 1;
          }
          if (date <= today && payrollRules.deductLeave) unexcused += leaveType === 'HL' ? 0.5 : 1;
        } else if (record && String(record.attendance_status).toLowerCase() === 'absent') {
          days.push('A');
          absent += 1;
          absentDays += 1;
          if (payrollRules.deductAbsence) unexcused += 1;
        } else {
          // A missing clock-in for today is still pending. It becomes an
          // absence only after the calendar date has finished (tomorrow).
          // A completed working day without attendance is always absent.
          // Today remains pending until the day has finished.
          if (date < today) {
            days.push('A');
            unexcused += 1;
            absent += 1;
            absentDays += 1;
          } else {
            days.push('–');
          }
        }
      }

      const salaryNumber = Number(profile.monthly_salary || 0);
      // Daily pay is always based on the full selected month's working days.
      // Using only days elapsed so far inflates absence values mid-month.
      let salaryWorkingDays = 0;
      for (let day = 1; day <= totalDays; day += 1) {
        const workDate = ymd(year, month, day);
        if (employeeWorkingDay(workDate, weeklyResolver, calendarOverrides)) salaryWorkingDays += 1;
      }
      salaryWorkingDays = Math.max(1, salaryWorkingDays);
      const lopDays = Math.min(salaryWorkingDays, unexcused);
      const dailyRate = salaryNumber / salaryWorkingDays;
      const absentDeduction = Math.round(absent * dailyRate * 100) / 100;
      const lateDeductionTotal = Number(
        lateDeductionByUser.get(Number(profile.employee_user_id)) || 0
      );
      // The dashboard is an earned-to-date view: pay starts at zero and
      // grows only for check-ins and approved paid leave.  Absence never
      // removes money already accrued.
      const accruedSalary = Math.max(
        0,
        Math.round(
          (Math.min(salaryWorkingDays, accruedPaidDays) * dailyRate - lateDeductionTotal) * 100
        ) / 100
      );

      return {
        id: profile.id,
        employeeUserId: profile.employee_user_id,
        name: profile.full_name,
        designation: profile.department,
        days: days,
        present: present,
        presentSalary: salaryNumber ? formatSalary(present * dailyRate) : '–',
        late: late,
        lateDeduction: salaryNumber ? formatSalary(lateDeductionTotal) : '–',
        lateSalary: salaryNumber
          ? formatSalary(Math.max(0, (late * dailyRate) - lateDeductionTotal))
          : '–',
        excused: halfLeave,
        unexcused: unexcused,
        halfLeave: halfLeave,
        earnedLeave: earnedLeave,
        approvedLeave: approvedLeave,
        absent: absent,
        absentDeduction: salaryNumber ? formatSalary(absentDeduction) : '–',
        salary: formatSalary(profile.monthly_salary),
        salaryPerDay: salaryNumber ? formatSalary(dailyRate) : '–',
        daysPaid: String(accruedPaidDays),
        afterLeaves: salaryNumber ? formatSalary(absentDeduction) : '–',
        updatedSalary: salaryNumber ? formatSalary(accruedSalary) : '–',
      };
    });

    // Day-wise KPIs reflect *today* specifically (a live snapshot) rather
    // than a month-to-date total, independent of whichever month/year is
    // being browsed in the calendar below.
    const [todayYear, todayMonth, todayDay] = today.split('-').map(Number);
    const todayWeekday = utcWeekday(todayYear, todayMonth, todayDay);
    let todayPresent = 0;
    let todayAbsent = 0;
    let todayLate = 0;

    if (userIds.length) {
      const [todayRecords] = await db.query(
        `SELECT * FROM attendance_records WHERE attendance_date = ? AND employee_id IN (?)`,
        [today, userIds]
      );
      const [todayLeaves] = await db.query(
        `SELECT l.employee_id FROM employee_leaves l
         LEFT JOIN hrms_leave_approval_links link ON link.leave_id = l.id
         LEFT JOIN attendance_permission_requests approval ON approval.id = link.approval_request_id
         WHERE l.status = 'APPROVED'
           AND (l.leave_type = 'Earned Leave' OR approval.salary_mode = 'paid')
           AND l.from_date = ? AND l.to_date = ?
           AND LOWER(l.duration_type) = 'full day' AND l.employee_id IN (?)`,
        [today, today, userIds]
      );
      const todayRecordMap = new Map();
      todayRecords.forEach(function (row) { todayRecordMap.set(row.employee_id, row); });
      const todayLeaveSet = new Set(todayLeaves.map(function (row) { return row.employee_id; }));

      profiles.forEach(function (profile) {
        const weeklyResolver = weeklyResolvers.get(Number(profile.id));
        if (!employeeWorkingDay(today, weeklyResolver, calendarOverrides)) return;
        const userId = profile.employee_user_id;
        const record = userId ? todayRecordMap.get(userId) : null;
        if (record && record.check_in_at) {
          if (String(record.attendance_status) === 'absent' && payrollRules.deductAbsence) {
            todayAbsent += 1;
          } else if (Number(record.is_late)) {
            todayLate += 1;
          } else {
            todayPresent += 1;
          }
        }
      });
    }

    return ok(res, {
      year: year,
      month: month,
      daysInMonth: totalDays,
      totalWorkingDays: globalWorkingDays,
      calendarOverrides: [...calendarOverrides].map(([date, status]) => ({ date, status })),
      enabledLeaveTypes: enabledLeaveTypes,
      timezone: policy.TIME_ZONE,
      payrollPolicy: { weeklyOffDays: [...payrollRules.weeklyOffDays], deductApprovedLeave: payrollRules.deductLeave, deductExplicitAbsence: payrollRules.deductAbsence, missingAttendanceIsAbsent: payrollRules.missingIsAbsent },
      kpis: {
        totalEmployees: profiles.length,
        present: todayPresent,
        absent: todayAbsent,
        late: todayLate,
      },
      employees: employees,
    });
  } catch (error) {
    console.error('GET /hrms/dashboard', error);
    return fail(res, 500, error.message);
  }
}

module.exports = {
  requireAdmin,
  monthView,
  timeSettings,
  updateTimeSettings,
  calendarOverrides,
  saveCalendarOverride,
  saveCalendarWeeklyOff,
};
