const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateSettings, reminderTiming } = require('../lib/clockOutReminder');

const valid = {
  clockOutReminderThresholdMinutes: 15,
  clockOutReminderRepeatMinutes: 10,
  autoClockOutSnoozeMinutes: 15,
  autoClockOutConfirmationMinutes: 3,
  autoClockOutWarningSeconds: 60,
  clockOutReminderSound: 'notification.mp3',
};

test('accepts safe reminder settings and rejects invalid intervals or sound', () => {
  assert.equal(validateSettings(valid).threshold, 15);
  for (const values of [
    { ...valid, clockOutReminderThresholdMinutes: 0 },
    { ...valid, clockOutReminderRepeatMinutes: -1 },
    { ...valid, autoClockOutSnoozeMinutes: 0 },
    { ...valid, clockOutReminderSound: 'missing.mp3' },
  ]) assert.throws(() => validateSettings(values), { status: 400 });
});

test('does not create a slot before threshold and assigns repeat slots after it', () => {
  const before = reminderTiming({ attendanceDate: '2026-10-15', shiftStart: '09:00:00', shiftEnd: '18:00:00', threshold: 15, repeat: 10, now: new Date('2026-10-15T12:35:00Z') });
  assert.equal(before.thresholdReached, false);
  assert.equal(before.slot, null);
  const first = reminderTiming({ attendanceDate: '2026-10-15', shiftStart: '09:00:00', shiftEnd: '18:00:00', threshold: 15, repeat: 10, now: new Date('2026-10-15T12:45:00Z') });
  assert.equal(first.slot, 0);
  const repeat = reminderTiming({ attendanceDate: '2026-10-15', shiftStart: '09:00:00', shiftEnd: '18:00:00', threshold: 15, repeat: 10, now: new Date('2026-10-15T13:05:00Z') });
  assert.equal(repeat.slot, 2);
});

test('uses Asia/Kolkata local wall time across midnight and month boundaries', () => {
  const timing = reminderTiming({
    attendanceDate: '2026-01-31', shiftStart: '22:00:00', shiftEnd: '06:00:00',
    threshold: 15, repeat: 15, now: new Date('2026-02-01T00:50:00Z'),
  });
  // 00:50Z is 06:20 IST on Feb 1: 20 minutes after the overnight shift end.
  assert.equal(timing.endDate, '2026-02-01');
  assert.equal(timing.elapsed, 20);
  assert.equal(timing.slot, 0);
});
