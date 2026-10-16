'use strict';

const db = require('../config/db');

function pad(value) { return String(value).padStart(2, '0'); }
function ymd(year, month, day) { return `${year}-${pad(month)}-${pad(day)}`; }
function nextDate(date) {
  const [year, month, day] = String(date).split('-').map(Number);
  const value = new Date(Date.UTC(year, month - 1, day + 1));
  return ymd(value.getUTCFullYear(), value.getUTCMonth() + 1, value.getUTCDate());
}
function weekday(date) {
  const [year, month, day] = String(date).split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

async function ensureCalendarTables() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_calendar_overrides (
    calendar_date DATE NOT NULL PRIMARY KEY,
    status ENUM('Working Day', 'Weekly Off', 'Holiday') NOT NULL,
    scope VARCHAR(40) NOT NULL DEFAULT 'All Employees',
    reason VARCHAR(255) NOT NULL,
    updated_by INT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  )`);
}

async function overridesForPeriod(start, end) {
  await ensureCalendarTables();
  const [rows] = await db.query(`SELECT DATE_FORMAT(calendar_date, '%Y-%m-%d') AS date, status
    FROM hrms_calendar_overrides WHERE calendar_date BETWEEN ? AND ?`, [start, end]);
  return new Map(rows.map((row) => [row.date, row.status]));
}

function isWorkingDay(date, weeklyOffDays, overrides) {
  const override = overrides.get(date);
  if (override === 'Working Day') return true;
  if (override === 'Holiday' || override === 'Weekly Off') return false;
  return !weeklyOffDays.has(weekday(date));
}

function countWorkingDays(start, end, weeklyOffDays, overrides) {
  let total = 0;
  for (let date = start; date <= end; date = nextDate(date)) {
    if (isWorkingDay(date, weeklyOffDays, overrides)) total += 1;
  }
  return total;
}

module.exports = { ensureCalendarTables, overridesForPeriod, isWorkingDay, countWorkingDays };
