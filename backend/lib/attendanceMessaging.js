'use strict';

const policy = require('./attendancePolicy');
const calendar = require('./calendarWorkingDays');
const staff = require('./staffDirectory');
const messaging = require('./messaging');

function hhmm(value) { return String(value || '').slice(0, 5); }
// The scheduler is periodic, so do not require it to land on one exact
// minute.  The event key in createAttendanceSystemCards still guarantees one
// reminder per employee and shift.
function inCheckInReminderWindow(time, schedule) {
  const start = hhmm(schedule.shiftStart);
  const lateAfter = hhmm(schedule.lateAfter);
  if (lateAfter <= start) return time === start;
  return time >= start && time < lateAfter;
}
async function isWorkingDay(db, date) {
  try {
    await calendar.ensureCalendarTables();
    const [rows] = await db.query('SELECT weekly_off_days FROM hrms_payroll_policy WHERE id=1');
    const days = new Set(JSON.parse(rows[0]?.weekly_off_days || '[0]').map(Number));
    return calendar.isWorkingDay(date, days, await calendar.overridesForPeriod(date, date));
  } catch (_) { return true; }
}
async function hasApprovedAllDayAbsence(db, employeeId, date) {
  const [[row]] = await db.query(`SELECT id FROM attendance_permission_requests WHERE employee_id=? AND request_date=? AND status='approved' AND request_type IN ('leave','risk_leave') LIMIT 1`, [employeeId, date]);
  return Boolean(row);
}
async function effectiveSchedule(db, employeeId, gender, date) {
  const all = await policy.getTimeSettings(db);
  let schedule = String(gender).toLowerCase() === 'female' ? all.female : all.male;
  const [[permission]] = await db.query(`SELECT permission_start_time,permission_end_time FROM attendance_permission_requests WHERE employee_id=? AND request_date=? AND request_type='permission' AND status='approved' AND permission_start_time IS NOT NULL AND permission_end_time IS NOT NULL ORDER BY reviewed_at DESC LIMIT 1`, [employeeId, date]);
  if (!permission) return schedule;
  const start = hhmm(permission.permission_start_time), end = hhmm(permission.permission_end_time);
  // An approved permission covering the first/second half moves the required
  // work window to the opposite configured half, matching attendanceController.
  if (start <= hhmm(schedule.shiftStart) && end >= hhmm(schedule.morning.shiftEnd)) return schedule.evening;
  if (start <= hhmm(schedule.evening.shiftStart) && end >= hhmm(schedule.shiftEnd)) return schedule.morning;
  return schedule;
}
async function process(db, io, now = new Date()) {
  const parts = policy.partsInZone(now); const date = parts.date; const time = hhmm(parts.time);
  if (!await isWorkingDay(db, date)) return [];
  const people = await staff.listActiveStaff(db); const results = [];
  for (const person of people) {
    if (String(person.role || '').toLowerCase() === 'admin') continue;
    if (await hasApprovedAllDayAbsence(db, person.id, date)) continue;
    const [[profile]] = await db.query('SELECT gender FROM hrms_employee_profiles WHERE employee_user_id=? LIMIT 1', [person.id]);
    const schedule = await effectiveSchedule(db, person.id, profile?.gender, date);
    const [[record]] = await db.query('SELECT id,check_in_at,check_out_at FROM attendance_records WHERE employee_id=? AND attendance_date=? LIMIT 1', [person.id, date]);
    let cards = [];
    if (inCheckInReminderWindow(time, schedule) && !record?.check_in_at) {
      cards = await messaging.createAttendanceSystemCards(db, { employeeId: person.id, attendanceDate: date, eventType: 'check_in_reminder', eventKey: `check-in:${date}:${hhmm(schedule.shiftStart)}`, body: `Reminder: please check in for your shift starting at ${hhmm(schedule.shiftStart)}.`, payload: { shiftStart: schedule.shiftStart } });
    }
    if (time === hhmm(schedule.shiftEnd) && record?.check_in_at && !record?.check_out_at) {
      cards = await messaging.createAttendanceSystemCards(db, { employeeId: person.id, attendanceDate: date, eventType: 'check_out_reminder', eventKey: `check-out:${date}:${hhmm(schedule.shiftEnd)}`, body: `Reminder: please check out. Your shift ended at ${hhmm(schedule.shiftEnd)}.`, payload: { shiftEnd: schedule.shiftEnd } });
    }
    await messaging.emitMessages(io, db, cards);
    results.push(...cards);
  }
  return results;
}
module.exports = { process };
