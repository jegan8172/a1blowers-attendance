'use strict';

// Closes only forgotten attendance sessions from a *previous* business day.
// A manual Clock Out always wins because rows with check_out_at already set are
// never selected here.
const policy = require('./attendancePolicy');

function addCalendarDay(date, days) {
  const [year, month, day] = String(date).split('-').map(Number);
  const next = new Date(Date.UTC(year, month - 1, day + days));
  return [
    next.getUTCFullYear(),
    String(next.getUTCMonth() + 1).padStart(2, '0'),
    String(next.getUTCDate()).padStart(2, '0')
  ].join('-');
}

function seconds(value) {
  const [hours = 0, minutes = 0, secondsPart = 0] = String(value || '00:00:00')
    .split(':')
    .map(Number);
  return hours * 3600 + minutes * 60 + secondsPart;
}

function datePart(value) {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value || '').slice(0, 10);
}

function cutoffFor(record, shiftStart, shiftEnd) {
  const attendanceDate = datePart(record.attendance_date);
  const end = String(shiftEnd || '18:30:00').slice(0, 8);
  // Support a genuine overnight policy (for example 22:00 → 06:00).
  const cutoffDate = seconds(end) <= seconds(shiftStart) ? addCalendarDay(attendanceDate, 1) : attendanceDate;
  return `${cutoffDate} ${end}`;
}

function completedStatus(record, workingMinutes) {
  const prior = String(record.attendance_status || '').toLowerCase();
  if (prior === 'absent' || prior === 'on_leave' || prior === 'half_leave') return prior;
  // This service writes the configured shift-end timestamp, therefore the
  // employee did not leave early merely because they arrived late.
  return Number(record.is_late) ? 'late' : 'present';
}

async function closeForgottenCheckouts(db, options = {}) {
  const today = options.today || policy.todayIstDate();
  const schedules = await policy.getTimeSettings(db);
  const [records] = await db.query(
    `SELECT a.id, a.employee_id, a.attendance_date, a.check_in_at,
            a.attendance_status, a.is_late, a.scheduled_shift_start,
            a.scheduled_shift_end, p.gender
       FROM attendance_records a
       LEFT JOIN hrms_employee_profiles p ON p.employee_user_id = a.employee_id
      WHERE a.check_in_at IS NOT NULL
        AND a.check_out_at IS NULL
        AND a.attendance_date < ?
      ORDER BY a.attendance_date, a.id`,
    [today]
  );

  let closed = 0;
  for (const record of records) {
    const schedule = String(record.gender || '').toLowerCase() === 'female'
      ? schedules.female
      : schedules.male;
    const shiftStart = record.scheduled_shift_start || schedule.shiftStart;
    const shiftEnd = record.scheduled_shift_end || schedule.shiftEnd;
    const cutoff = cutoffFor(record, shiftStart, shiftEnd);
    const connection = await db.getConnection();
    try {
      await connection.beginTransaction();
      // A break cannot remain running after an automatically completed day.
      await connection.query(
        `UPDATE attendance_breaks
            SET ended_at = ?,
                duration_minutes = GREATEST(0, TIMESTAMPDIFF(MINUTE, started_at, ?)),
                status = 'auto_closed'
          WHERE attendance_id = ? AND status = 'active'`,
        [cutoff, cutoff, record.id]
      );
      const [[breakRow]] = await connection.query(
        `SELECT COALESCE(SUM(duration_minutes), 0) AS minutes
           FROM attendance_breaks
          WHERE attendance_id = ? AND status IN ('completed', 'auto_closed')`,
        [record.id]
      );
      const [[durationRow]] = await connection.query(
        'SELECT GREATEST(0, TIMESTAMPDIFF(MINUTE, ?, ?)) AS minutes',
        [record.check_in_at, cutoff]
      );
      const workingMinutes = Math.max(0, Number(durationRow.minutes || 0) - Number(breakRow.minutes || 0));
      const status = completedStatus(record, workingMinutes);
      const [result] = await connection.query(
        `UPDATE attendance_records
            SET check_out_at = ?,
                working_minutes = ?,
                early_exit_minutes = 0,
                attendance_status = ?,
                session_status = 'completed',
                clock_out_reason = ?,
                tracking_stop_reason = ?
          WHERE id = ? AND check_out_at IS NULL`,
        [
          cutoff,
          workingMinutes,
          status,
          `Auto clock-out at configured shift end (${String(shiftEnd).slice(0, 5)}): employee did not clock out.`,
          'Automatic end-of-day clock-out',
          record.id
        ]
      );
      if (result.affectedRows) {
        await connection.query(
          `UPDATE hrms_field_tracking_sessions
              SET is_active = 0, stopped_at = ?, stop_reason = ?
            WHERE employee_user_id = ? AND is_active = 1`,
          [cutoff, 'Automatic end-of-day clock-out', record.employee_id]
        );
        closed += 1;
      }
      await connection.commit();
      // A completed attendance row is payroll input. Refresh only unpaid
      // payroll after commit so admin payroll, employee salary and day-wise
      // history all receive the same auto-clock-out result immediately.
      if (result.affectedRows) {
        try {
          const payroll = require('../controllers/hrmsPayrollController');
          await payroll.refreshUnpaidForEmployee(record.employee_id, datePart(record.attendance_date));
        } catch (payrollError) {
          console.error(`Payroll refresh after auto clock-out failed for attendance ${record.id}:`, payrollError.message);
        }
      }
    } catch (error) {
      await connection.rollback();
      console.error(`End-of-day auto clock-out failed for attendance ${record.id}:`, error.message);
    } finally {
      connection.release();
    }
  }
  return { closed, examined: records.length, date: today };
}

module.exports = { closeForgottenCheckouts, cutoffFor };
