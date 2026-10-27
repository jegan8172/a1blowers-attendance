const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const policy = require('../lib/attendancePolicy');

// Load the real calculation with database/calendar fakes. No database module,
// .env file, server startup or real payroll writes are used by this test.
const source = fs.readFileSync(path.join(__dirname, '../controllers/hrmsPayrollController.js'), 'utf8');
const schedule = { shiftStart: '09:30:00', shiftEnd: '18:30:00', lateAfter: '09:40:00', absentAfter: '12:00:00' };

function loadPayroll(times, saved = null, legacyDates = false) {
  const profile = {
    id: 12, employee_user_id: 12, full_name: 'Haresh Rai', employee_code: 'EMP1010',
    gender: 'Male', monthly_salary: 19000, salary_type: 'Flexible',
    flexible_cycle_start_day: 1, flexible_cycle_end_day: 31,
  };
  const db = { query: async (sql) => {
    if (/^\s*(CREATE|ALTER|INSERT)/i.test(sql)) return [{ affectedRows: 0 }];
    if (sql.includes('SELECT * FROM hrms_payroll_policy')) return [[{ weekly_off_days: '[0]' }]];
    if (sql.includes('SELECT p.* FROM hrms_employee_profiles')) return [[profile]];
    if (sql.includes('FROM hrms_employee_compensation')) return [[{ profile_id: 12, employee_user_id: 12, monthly_salary: 19000 }]];
    if (sql.includes('FROM attendance_records')) {
      // Simulate mysql2's default DATETIME conversion unless SQL requests text.
      const formatted = !legacyDates && sql.includes("DATE_FORMAT(check_in_at, '%Y-%m-%d %H:%i:%s') AS check_in_at");
      return [times.map(([day, time]) => ({
        employee_id: 12, attendance_date: `2026-10-${day}`,
        check_in_at: formatted ? `2026-10-${day} ${time}` : new Date(`2026-10-${day}T${time}`),
        is_late: 0, attendance_status: 'present',
      }))];
    }
    if (sql.includes('FROM employee_leaves') || sql.includes('FROM attendance_permission_requests')) return [[]];
    if (sql.includes('SELECT * FROM hrms_payroll_items')) return [saved ? [saved] : []];
    if (sql.includes('FROM hrms_payroll_cycle_overrides')) return [[]];
    throw new Error(`Unexpected database query: ${sql}`);
  } };
  const dependencies = {
    '../config/db': db,
    '../lib/attendancePolicy': { ...policy, getTimeSettings: async () => ({ male: schedule, female: schedule }) },
    '../lib/calendarWorkingDays': {
      // Synthetic holiday fixture gives the observed 26-day divisor without
      // claiming to reproduce production's unexported calendar assignments.
      overridesForPeriod: async () => new Map([['2026-10-01', 'Holiday']]),
      isWorkingDay: (date, off, overrides) => overrides.get(date) !== 'Holiday' && !off.has(new Date(`${date}T00:00:00Z`).getUTCDay()),
      isEmployeeWorkingDay: (date, resolver, overrides) => overrides.get(date) !== 'Holiday' && !resolver.forDate(date).has(new Date(`${date}T00:00:00Z`).getUTCDay()),
    },
    '../lib/weeklyOffTemplates': {
      parseDays: (days) => Array.isArray(days) ? days : JSON.parse(days || '[0]'),
      ensureWeeklyOffTemplateTables: async () => {},
      offDaysForProfileByDate: async () => ({ forDate: () => new Set([0]) }),
      hasAssignmentForDate: () => false,
    },
  };
  const context = { module: { exports: {} }, Date, console,
    require: (name) => {
      assert.ok(Object.hasOwn(dependencies, name), `Unexpected module: ${name}`);
      return dependencies[name];
    },
  };
  vm.runInNewContext(source + '\nmodule.exports.computeRowsForTest = computeRows;', context);
  return context.module.exports;
}

const hareshTimes = [['22', '09:33:17'], ['23', '09:17:00'], ['24', '09:39:28'], ['26', '08:55:32']];

test('production incident is reproduced with default UTC Date decoding', async () => {
  const previous = process.env.TZ;
  process.env.TZ = 'UTC';
  try {
    const [item] = await loadPayroll(hareshTimes, null, true).computeRowsForTest(2026, 10, '2026-10-26');
    assert.equal(item.lateDeductions, 1683.48);
    assert.equal(item.deductionEntries.filter(e => e.type === 'late').map(e => e.lateMinutes).join(','), '323,307,329,285');
  } finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; }
});

for (const timezone of ['UTC', 'Asia/Kolkata', 'America/New_York']) {
  test(`on-time payroll is independent of host timezone: ${timezone}`, async () => {
    const previous = process.env.TZ;
    process.env.TZ = timezone;
    try {
      const [item] = await loadPayroll(hareshTimes).computeRowsForTest(2026, 10, '2026-10-26');
      assert.equal(item.paidDays, 4);
      assert.equal(item.lateDeductions, 0);
      assert.equal(item.netPay, 2923.08);
      assert.equal(item.deductionEntries.filter(e => e.type === 'late').length, 0);
    } finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; }
  });
}

test('a genuine late check-in still deducts actual minutes', async () => {
  const [item] = await loadPayroll([['22', '09:55:00'], ['23', '09:40:00']]).computeRowsForTest(2026, 10, '2026-10-26');
  const late = item.deductionEntries.filter(e => e.type === 'late');
  assert.equal(late.length, 1);
  assert.equal(late[0].lateMinutes, 15);
  assert.equal(late[0].amount, 20.30);
});

test('paid payroll retains its saved financial values', async () => {
  const saved = { id: 83, profile_id: 12, employee_user_id: 12, status: 'paid', monthly_salary: 19000,
    working_days: 26, paid_days: 4, lop_days: 17, deductions: 1683.48,
    late_deductions: 1683.48, absent_deductions: 12423.08, net_pay: 1239.60 };
  const [item] = await loadPayroll(hareshTimes, saved).computeRowsForTest(2026, 10, '2026-10-26');
  assert.equal(item.status, 'Paid');
  assert.equal(item.lateDeductions, saved.late_deductions);
  assert.equal(item.netPay, saved.net_pay);
});

test('pending payroll recalculates rather than reusing the saved false late amount', async () => {
  const saved = { id: 83, profile_id: 12, employee_user_id: 12, status: 'pending',
    monthly_salary: 19000, paid_days: 4, deductions: 1683.48,
    late_deductions: 1683.48, net_pay: 1239.60 };
  const [item] = await loadPayroll(hareshTimes, saved).computeRowsForTest(2026, 10, '2026-10-26');
  assert.equal(item.lateDeductions, 0);
  assert.equal(item.netPay, 2923.08);
});
