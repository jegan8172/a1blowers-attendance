const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  payrollPeriod,
  flexiblePeriodContaining,
} = require('../controllers/hrmsPayrollController');

const gg = {
  salary_type: 'Flexible',
  flexible_cycle_start_day: 19,
  flexible_cycle_end_day: 18,
  flexible_cycle_start_date: '2026-10-19',
  flexible_cycle_end_date: '2026-11-18',
};

test('does not create a flexible payroll before its first configured cycle ends', () => {
  assert.equal(payrollPeriod(gg, 2026, 10), null);
});

test('uses the configured first flexible salary cycle exactly', () => {
  assert.deepEqual(payrollPeriod(gg, 2026, 11), {
    start: '2026-10-19', end: '2026-11-18', salaryType: 'Flexible', anchored: true,
  });
});

test('continues a flexible cycle into the next cycle without mixing history', () => {
  assert.deepEqual(payrollPeriod(gg, 2026, 12), {
    start: '2026-11-19', end: '2026-12-18', salaryType: 'Flexible',
  });
});

test('finds the active flexible cycle for automatic payroll', () => {
  assert.equal(flexiblePeriodContaining(gg, '2026-10-18'), null);
  assert.deepEqual(flexiblePeriodContaining(gg, '2026-10-19'), {
    start: '2026-10-19', end: '2026-11-18', year: 2026, month: 11,
  });
  assert.deepEqual(flexiblePeriodContaining(gg, '2026-11-19'), {
    start: '2026-11-19', end: '2026-12-18', salaryType: 'Flexible', year: 2026, month: 12,
  });
});
