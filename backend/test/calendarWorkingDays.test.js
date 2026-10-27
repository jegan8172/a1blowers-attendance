const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const context = { module: { exports: {} }, require: (name) => {
  assert.equal(name, '../config/db');
  return { query: () => { throw Error('No database calls allowed in calendar tests'); } };
} };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../lib/calendarWorkingDays.js'), 'utf8'), context);
const calendar = context.module.exports;
const off = new Set([0]);

test('October 2026 has 25 working days with Sundays off and two weekday holidays', () => {
  const overrides = new Map([['2026-10-19', 'Holiday'], ['2026-10-20', 'Holiday']]);
  assert.equal(calendar.countWorkingDays('2026-10-01', '2026-10-31', off, overrides), 25);
});

test('explicit Working Day overrides apply even with assigned employee templates', () => {
  const overrides = new Map([['2026-10-25', 'Working Day']]);
  const resolver = { forDate: () => off, assignments: [{ effectiveFrom: '2026-10-01' }] };
  assert.equal(calendar.isEmployeeWorkingDay('2026-10-25', resolver, overrides), true);
  assert.equal(calendar.isEmployeeWorkingDay('2026-10-18', resolver, overrides), false);
});

test('holidays override employee working days and counts are shared', () => {
  const overrides = new Map([['2026-10-19', 'Holiday'], ['2026-10-20', 'Holiday'], ['2026-10-25', 'Working Day']]);
  const resolver = { forDate: () => off };
  let employeeDays = 0;
  for (let day = 1; day <= 31; day++) {
    if (calendar.isEmployeeWorkingDay(`2026-10-${String(day).padStart(2, '0')}`, resolver, overrides)) employeeDays++;
  }
  assert.equal(employeeDays, 26);
  assert.equal(employeeDays, calendar.countWorkingDays('2026-10-01', '2026-10-31', off, overrides));
});

test('effective-dated employee schedules still apply when no date override exists', () => {
  const resolver = { forDate: date => new Set(date < '2026-10-15' ? [0] : [6]) };
  assert.equal(calendar.isEmployeeWorkingDay('2026-10-11', resolver, new Map()), false);
  assert.equal(calendar.isEmployeeWorkingDay('2026-10-17', resolver, new Map()), false);
  assert.equal(calendar.isEmployeeWorkingDay('2026-10-18', resolver, new Map()), true);
});
