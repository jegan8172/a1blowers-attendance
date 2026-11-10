'use strict';

const policy = require('./attendancePolicy');
const calendar = require('./calendarWorkingDays');

const allowedSounds = new Set(['notification.mp3', 'notifications.mp3', 'notificationss.mp3', 'notification_ai voice.mp3']);

function asBool(value) { return value === true || value === 1 || value === '1'; }
function dateAt(date, time) {
  const [year, month, day] = String(date).slice(0, 10).split('-').map(Number);
  const [hour, minute, second] = String(time || '00:00:00').split(':').map(Number);
  return Date.UTC(year, month - 1, day, hour || 0, minute || 0, second || 0);
}
function nextDate(date) {
  const [year, month, day] = String(date).slice(0, 10).split('-').map(Number);
  const value = new Date(Date.UTC(year, month - 1, day + 1));
  return `${value.getUTCFullYear()}-${String(value.getUTCMonth() + 1).padStart(2, '0')}-${String(value.getUTCDate()).padStart(2, '0')}`;
}
function timeSeconds(value) {
  const [hour, minute, second] = String(value || '').split(':').map(Number);
  return (hour || 0) * 3600 + (minute || 0) * 60 + (second || 0);
}
function nowEpoch(now) {
  const parts = policy.partsInZone(now);
  return dateAt(parts.date, parts.time);
}
function reminderTiming({ attendanceDate, shiftStart, shiftEnd, threshold, repeat, now = new Date() }) {
  const endDate = timeSeconds(shiftEnd) <= timeSeconds(shiftStart)
    ? nextDate(attendanceDate) : attendanceDate;
  const endEpoch = dateAt(endDate, shiftEnd);
  const elapsed = Math.max(0, Math.floor((nowEpoch(now) - endEpoch) / 60000));
  return {
    endDate,
    elapsed,
    thresholdReached: elapsed >= threshold,
    slot: elapsed < threshold ? null : Math.floor((elapsed - threshold) / repeat),
  };
}
function interval(value, min, max) {
  const number = Number(value);
  return Number.isInteger(number) && number >= min && number <= max ? number : null;
}
function validateSettings(value) {
  const threshold = interval(value.clockOutReminderThresholdMinutes, 1, 24 * 60);
  const repeat = interval(value.clockOutReminderRepeatMinutes, 1, 24 * 60);
  const snooze = interval(value.autoClockOutSnoozeMinutes, 1, 24 * 60);
  const confirmation = interval(value.autoClockOutConfirmationMinutes, 1, 24 * 60);
  const warning = interval(value.autoClockOutWarningSeconds, 10, 60 * 60);
  const sound = String(value.clockOutReminderSound || '').trim();
  if (threshold === null || repeat === null || snooze === null || confirmation === null || warning === null) {
    throw Object.assign(new Error('Reminder intervals must be safe positive values.'), { status: 400 });
  }
  if (!allowedSounds.has(sound)) throw Object.assign(new Error('Invalid clock-out reminder sound.'), { status: 400 });
  return { threshold, repeat, snooze, confirmation, warning, sound };
}

async function isWorkingDay(db, date) {
  try {
    await calendar.ensureCalendarTables();
    const [policyRows] = await db.query('SELECT weekly_off_days FROM hrms_payroll_policy WHERE id = 1');
    let days = [0];
    try { days = JSON.parse(policyRows[0] && policyRows[0].weekly_off_days || '[0]'); } catch (_) {}
    const overrides = await calendar.overridesForPeriod(date, date);
    return calendar.isWorkingDay(date, new Set(days.map(Number)), overrides);
  } catch (_) {
    // An attendance row is authoritative if calendar policy is unavailable.
    return true;
  }
}

async function statusForEmployee(db, employeeId, now = new Date(), createEvent = true) {
  const [records] = await db.query(
    `SELECT id, attendance_date, check_in_at, check_out_at FROM attendance_records
     WHERE employee_id = ? AND check_in_at IS NOT NULL AND check_out_at IS NULL
     ORDER BY attendance_date DESC, id DESC LIMIT 1`, [employeeId]);
  const record = records[0];
  if (!record) return { checkedIn: false, reminderDue: false, nextReminderAt: null };
  const [settingsRows] = await db.query('SELECT * FROM hrms_tracking_settings WHERE id = 1');
  const settings = settingsRows[0] || {};
  const base = {
    checkedIn: true,
    attendanceId: record.id,
    sound: settings.clock_out_reminder_sound || 'notification.mp3',
    reminderEnabled: Number(settings.clock_out_reminder_enabled) === 1,
  };
  if (!base.reminderEnabled) return { ...base, reminderDue: false, nextReminderAt: null };
  if (!await isWorkingDay(db, String(record.attendance_date).slice(0, 10))) return { ...base, reminderDue: false, skipped: 'non_working_day', nextReminderAt: null };
  const [profiles] = await db.query('SELECT full_name, gender FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1', [employeeId]);
  const timeSettings = await policy.getTimeSettings(db);
  const schedule = String(profiles[0] && profiles[0].gender).toLowerCase() === 'female' ? timeSettings.female : timeSettings.male;
  const workDate = String(record.attendance_date).slice(0, 10);
  const timing = reminderTiming({ attendanceDate: workDate, shiftStart: schedule.shiftStart, shiftEnd: schedule.shiftEnd, threshold: Number(settings.clock_out_reminder_threshold_minutes || 15), repeat: Number(settings.clock_out_reminder_repeat_minutes || 15), now });
  const endDate = timing.endDate;
  const endEpoch = dateAt(endDate, schedule.shiftEnd);
  const elapsed = timing.elapsed;
  const threshold = Number(settings.clock_out_reminder_threshold_minutes || 15);
  const repeat = Number(settings.clock_out_reminder_repeat_minutes || 15);
  const common = { ...base, employeeName: profiles[0] && profiles[0].full_name || 'Employee', shiftEnd: `${endDate} ${schedule.shiftEnd}`, elapsedAfterShiftMinutes: elapsed, thresholdReached: elapsed >= threshold, repeatMinutes: repeat };
  if (elapsed < threshold) return { ...common, reminderDue: false, nextReminderAt: `${endDate} ${schedule.shiftEnd}` };
  const [snoozes] = await db.query(
    `SELECT snoozed_until FROM hrms_clock_out_reminder_events WHERE attendance_id = ?
     AND snoozed_until IS NOT NULL ORDER BY snoozed_until DESC LIMIT 1`, [record.id]);
  const snoozedUntil = snoozes[0] && snoozes[0].snoozed_until;
  if (snoozedUntil && new Date(snoozedUntil).getTime() > now.getTime()) {
    return { ...common, reminderDue: false, snoozeActive: true, nextReminderAt: snoozedUntil };
  }
  const slot = Math.floor((elapsed - threshold) / repeat);
  if (createEvent) {
    await db.query(
      `INSERT IGNORE INTO hrms_clock_out_reminder_events
       (employee_user_id, attendance_id, attendance_date, reminder_slot)
       VALUES (?, ?, ?, ?)`, [employeeId, record.id, workDate, slot]);
  }
  const [events] = await db.query(
    `SELECT * FROM hrms_clock_out_reminder_events WHERE employee_user_id = ? AND attendance_id = ? AND reminder_slot = ? LIMIT 1`,
    [employeeId, record.id, slot]);
  const event = events[0];
  return { ...common, reminderDue: Boolean(event && event.event_status === 'pending'), reminderEventId: event && event.id, reminderSlot: slot, nextReminderAt: new Date(endEpoch + (slot + 1) * repeat * 60000).toISOString() };
}

async function processAll(db, now = new Date()) {
  const [employees] = await db.query('SELECT DISTINCT employee_id FROM attendance_records WHERE check_in_at IS NOT NULL AND check_out_at IS NULL');
  const results = [];
  for (const employee of employees) {
    try { results.push(await statusForEmployee(db, employee.employee_id, now, true)); }
    catch (error) { console.error('Clock-out reminder processing failed for employee', employee.employee_id, error.message); }
  }
  return results;
}

module.exports = { allowedSounds, asBool, validateSettings, reminderTiming, statusForEmployee, processAll };
