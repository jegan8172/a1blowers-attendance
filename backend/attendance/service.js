'use strict';

const attendancePolicy = require('../lib/attendancePolicy');

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function localDate(now, timeZone = 'Asia/Kolkata') {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = type => parts.find(part => part.type === type).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function isLateCheck(now, timeZone = 'Asia/Kolkata') {
  return attendancePolicy.isLateAt(now, timeZone);
}

const sqlTime = date => date.toISOString().slice(0, 23).replace('T', ' ');

const isoTime = value =>
  value == null
    ? null
    : value instanceof Date
    ? value.toISOString()
    : new Date(String(value).replace(' ', 'T') + (String(value).endsWith('Z') ? '' : 'Z')).toISOString();

function sessionView(row, now) {
  if (!row) return null;
  const clockIn = isoTime(row.clock_in_at);
  const clockOut = isoTime(row.clock_out_at);
  const workedSeconds = Math.max(
    0,
    Math.floor(
      ((clockOut ? Date.parse(clockOut) : now.getTime()) - Date.parse(clockIn)) /
        1000,
    ),
  );

  return {
    id: row.id,
    work_date: row.work_date,
    clock_in_at: clockIn,
    clock_out_at: clockOut,
    punch_in: clockIn,
    clock_in: clockIn,
    punch_out: clockOut,
    clock_out: clockOut,
    worked_seconds: workedSeconds,
    is_late: Boolean(row.is_late),
    status: row.attendance_status || (row.is_late ? 'late' : 'present'),
  };
}

function monthBounds(month) {
  if (typeof month !== 'string' || !/^[1-9]\d{3}-(0[1-9]|1[0-2])$/.test(month)) {
    fail(400, 'month must use YYYY-MM format');
  }
  const [year, number] = month.split('-').map(Number);
  return [
    month + '-01',
    number === 12
      ? `${year + 1}-01-01`
      : `${year}-${String(number + 1).padStart(2, '0')}-01`,
  ];
}

function createService(
  pool,
  { timeZone = 'Asia/Kolkata', clock = () => new Date() } = {},
) {
  async function dashboard(employee, requestedMonth) {
    const now = clock();
    const today = localDate(now, timeZone);
    const month = requestedMonth === undefined ? today.slice(0, 7) : requestedMonth;
    const [start, end] = monthBounds(month);

    // 1. Fetch entire month history for the calendar
    const [monthRecords] = await pool.execute(
      `SELECT id, attendance_date AS work_date, check_in_at AS clock_in_at, check_out_at AS clock_out_at, is_late, attendance_status
       FROM attendance_records
       WHERE employee_id = ? AND attendance_date >= ? AND attendance_date < ?
       ORDER BY work_date ASC`,
      [employee.id, start, end],
    );

    const [approvedLeaves] = await pool.execute(
      `SELECT leave_type, duration_type,
              DATE_FORMAT(from_date, '%Y-%m-%d') AS from_date,
              DATE_FORMAT(to_date, '%Y-%m-%d') AS to_date
       FROM employee_leaves
       WHERE employee_id = ? AND status = 'APPROVED'
         AND from_date < ? AND to_date >= ?
       ORDER BY from_date ASC`,
      [employee.id, end, start],
    );

    // 2. Fetch today's session
    const [sessions] = await pool.execute(
      `SELECT id, attendance_date AS work_date, check_in_at AS clock_in_at, check_out_at AS clock_out_at, is_late, attendance_status
       FROM attendance_records
       WHERE employee_id = ? AND (attendance_date = ? OR (check_out_at IS NULL AND attendance_date >= ?))
       ORDER BY check_out_at IS NULL DESC, attendance_date DESC LIMIT 1`,
      [employee.id, today, start],
    );

    // 3. Count present and late days
    const [counts] = await pool.execute(
      `SELECT 
         SUM(CASE WHEN attendance_status <> 'absent' AND is_late = 0 THEN 1 ELSE 0 END) AS present_days,
         SUM(CASE WHEN attendance_status <> 'absent' AND is_late = 1 THEN 1 ELSE 0 END) AS late_days,
         SUM(CASE WHEN attendance_status = 'absent' THEN 1 ELSE 0 END) AS absent_days
       FROM attendance_records
       WHERE employee_id = ? AND attendance_date >= ? AND attendance_date < ?`,
      [employee.id, start, end],
    );

    const recordedDates = new Set(
      monthRecords.map((row) => String(row.work_date || '').slice(0, 10)),
    );
    const approvedLeaveDates = new Set();
    for (const leave of approvedLeaves) {
      let date = String(leave.from_date || '').slice(0, 10);
      const lastDate = String(leave.to_date || '').slice(0, 10);
      while (date && date <= lastDate) {
        if (date >= start && date < end && date <= today && new Date(`${date}T00:00:00Z`).getUTCDay() !== 0 && !recordedDates.has(date)) {
          approvedLeaveDates.add(date);
        }
        const next = new Date(`${date}T00:00:00Z`);
        next.setUTCDate(next.getUTCDate() + 1);
        date = next.toISOString().slice(0, 10);
      }
    }

    const session = sessionView(sessions[0], now);
    let activeBreak = null;

    if (session) {
      const [breaks] = await pool.execute(
        `SELECT id, started_at, duration_minutes, status 
         FROM attendance_breaks 
         WHERE attendance_id = ? AND status = 'active' 
         ORDER BY id DESC LIMIT 1`,
        [session.id],
      );
      activeBreak = breaks[0] || null;
    }

    return {
      employee: {
        id: employee.id,
        name: employee.full_name,
        staff_id: employee.staff_id,
      },
      date: today,
      timezone: timeZone,
      server_time: now.toISOString(),
      status: !session
        ? 'not_checked_in'
        : session.clock_out_at
        ? 'checked_out'
        : 'checked_in',
      session,
      active_break: activeBreak,
      month_records: monthRecords,
      approved_leaves: approvedLeaves,
      actions: {
        can_clock_in: !session,
        can_clock_out: !!session && !session.clock_out_at,
      },
      month_overview: {
        month,
        present_days: Number(counts[0].present_days || 0),
        absent_days: Number(counts[0].absent_days || 0),
        late_days: Number(counts[0].late_days || 0),
        working_days: 26,
      },
    };
  }

  async function getTodayAttendance(employeeId) {
    const now = clock();
    const today = localDate(now, timeZone);

    const [sessions] = await pool.execute(
      `SELECT id, attendance_date AS work_date, check_in_at AS clock_in_at, check_out_at AS clock_out_at, is_late, attendance_status FROM attendance_records
       WHERE employee_id = ? AND (attendance_date = ? OR check_out_at IS NULL)
       ORDER BY id DESC LIMIT 1`,
      [employeeId, today],
    );

    const session = sessions[0] || null;
    let activeBreak = null;
    let totalBreakMinutes = 0;

    if (session) {
      const [breaks] = await pool.execute(
        `SELECT duration_minutes, status FROM attendance_breaks 
         WHERE attendance_id = ?`,
        [session.id],
      );

      for (const b of breaks) {
        if (b.status === 'active') {
          activeBreak = b;
        } else {
          totalBreakMinutes += (b.duration_minutes || 0);
        }
      }
    }

    let elapsedSeconds = 0;
    let extraSeconds = 0;

    if (session && session.clock_in_at) {
      const clockInTime = new Date(session.clock_in_at).getTime();
      const endTime = session.clock_out_at 
        ? new Date(session.clock_out_at).getTime() 
        : now.getTime();

      const grossMinutes = Math.max(0, Math.floor((endTime - clockInTime) / 60000));
      const netMinutes = Math.max(0, grossMinutes - totalBreakMinutes);
      
      elapsedSeconds = netMinutes * 60;
      if (netMinutes > 480) {
        extraSeconds = (netMinutes - 480) * 60;
      }
    }

    return {
      work_date: session ? session.work_date : today,
      session,
      is_checked_in: Boolean(session && !session.clock_out_at),
      clock_in_at: session ? session.clock_in_at : null,
      clock_out_at: session ? session.clock_out_at : null,
      is_late: Boolean(session && session.is_late),
      elapsed_seconds: elapsedSeconds,
      extra_seconds: extraSeconds,
      active_break: activeBreak,
      total_break_minutes: totalBreakMinutes,
    };
  }

  async function punch(employeeId, action) {
    if (!['in', 'out'].includes(action)) fail(400, 'Invalid attendance action');
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();

      const [employees] = await connection.execute(
        'SELECT id, is_active FROM employee_users WHERE id = ? FOR UPDATE',
        [employeeId],
      );
      if (employees.length !== 1 || Number(employees[0].is_active) !== 1) {
        fail(403, 'Employee is inactive');
      }

      const now = clock();
      const today = localDate(now, timeZone);
      const [open] = await connection.execute(
        `SELECT id, work_date, clock_in_at, clock_out_at, is_late FROM hrms_attendance_sessions
         WHERE employee_id = ? AND clock_out_at IS NULL ORDER BY work_date DESC LIMIT 1 FOR UPDATE`,
        [employeeId],
      );

      let row;
      if (action === 'in') {
        if (open.length) fail(409, 'You are already clocked in');
        const [existing] = await connection.execute(
          'SELECT id FROM hrms_attendance_sessions WHERE employee_id = ? AND work_date = ?',
          [employeeId, today],
        );
        if (existing.length) {
          fail(409, 'Attendance is already completed for today');
        }

        const isLate = isLateCheck(now, timeZone) ? 1 : 0;
        const isAbsent = attendancePolicy.isAbsentAt(now, timeZone);

        const [insert] = await connection.execute(
          'INSERT INTO hrms_attendance_sessions (employee_id, work_date, clock_in_at, is_late) VALUES (?, ?, ?, ?)',
          [employeeId, today, sqlTime(now), isLate],
        );
        row = {
          id: insert.insertId,
          work_date: today,
          clock_in_at: sqlTime(now),
          clock_out_at: null,
          is_late: isLate,
          attendance_status: isAbsent ? 'absent' : (isLate ? 'late' : 'present'),
        };
      } else {
        if (!open.length) fail(409, 'Clock in before clocking out');
        row = open[0];

        // Auto-close open breaks upon clock out
        await connection.execute(
          `UPDATE attendance_breaks 
           SET ended_at = ?, status = 'auto_closed' 
           WHERE attendance_id = ? AND status = 'active'`,
          [sqlTime(now), row.id],
        );

        await connection.execute(
          'UPDATE hrms_attendance_sessions SET clock_out_at = ? WHERE id = ? AND employee_id = ?',
          [sqlTime(now), row.id, employeeId],
        );
        row = { ...row, clock_out_at: sqlTime(now) };
      }

      // Keep Jega's admin attendance dashboard in sync with the employee
      // portal session. One employee/date record is updated, never duplicated.
      const workingMinutes = row.clock_out_at
        ? Math.max(0, Math.floor((new Date(row.clock_out_at).getTime() - new Date(row.clock_in_at).getTime()) / 60000))
        : 0;
      const attendanceStatus = attendancePolicy.isAbsentCheckIn(row.clock_in_at)
        ? 'absent'
        : (Number(row.is_late) ? 'late' : 'present');
      await connection.execute(
        `INSERT INTO attendance_records
          (employee_id, attendance_date, check_in_at, check_out_at, attendance_status,
           session_status, check_in_method, is_late, working_minutes)
         VALUES (?, ?, ?, ?, ?, ?, 'employee_portal', ?, ?)
         ON DUPLICATE KEY UPDATE
           check_in_at = VALUES(check_in_at),
           check_out_at = VALUES(check_out_at),
           attendance_status = VALUES(attendance_status),
           session_status = VALUES(session_status),
           check_in_method = VALUES(check_in_method),
           is_late = VALUES(is_late),
           working_minutes = VALUES(working_minutes)`,
        [
          employeeId,
          row.work_date,
          row.clock_in_at,
          row.clock_out_at,
          attendanceStatus,
          row.clock_out_at ? 'completed' : 'active',
          Number(row.is_late) ? 1 : 0,
          workingMinutes,
        ],
      );

      await connection.commit();
      return sessionView(row, now);
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
  }

  async function startBreak(employeeId) {
    const now = clock();
    const today = localDate(now, timeZone);

    const [sessions] = await pool.execute(
      `SELECT id FROM hrms_attendance_sessions 
       WHERE employee_id = ? AND (work_date = ? OR clock_out_at IS NULL) AND clock_out_at IS NULL 
       ORDER BY id DESC LIMIT 1`,
      [employeeId, today],
    );

    if (!sessions.length) {
      fail(400, 'No active clock-in session found');
    }

    const attendanceId = sessions[0].id;
    const [existing] = await pool.execute(
      `SELECT id FROM attendance_breaks WHERE attendance_id = ? AND status = 'active'`,
      [attendanceId],
    );
    if (existing.length) {
      fail(400, 'Break is already in progress');
    }

    await pool.execute(
      `INSERT INTO attendance_breaks (attendance_id, started_at, status) 
       VALUES (?, ?, 'active')`,
      [attendanceId, sqlTime(now)],
    );

    return { success: true, message: 'Break started' };
  }

  async function endBreak(employeeId) {
    const now = clock();
    const today = localDate(now, timeZone);

    const [sessions] = await pool.execute(
      `SELECT id FROM hrms_attendance_sessions 
       WHERE employee_id = ? AND (work_date = ? OR clock_out_at IS NULL)
       ORDER BY id DESC LIMIT 1`,
      [employeeId, today],
    );

    if (!sessions.length) {
      fail(400, 'No active session found');
    }

    const attendanceId = sessions[0].id;
    const [activeBreaks] = await pool.execute(
      `SELECT id, started_at FROM attendance_breaks 
       WHERE attendance_id = ? AND status = 'active' 
       ORDER BY id DESC LIMIT 1`,
      [attendanceId],
    );

    if (!activeBreaks.length) {
      fail(400, 'No active break found');
    }

    const breakRow = activeBreaks[0];
    const started = new Date(breakRow.started_at);
    const durationMinutes = Math.max(0, Math.round((now - started) / 60000));

    await pool.execute(
      `UPDATE attendance_breaks 
       SET ended_at = ?, duration_minutes = ?, status = 'completed' 
       WHERE id = ?`,
      [sqlTime(now), durationMinutes, breakRow.id],
    );

    return { success: true, message: 'Break ended' };
  }

  // HTTP route adapter helpers
  return {
    dashboard,
    punch,
    getTodayAttendance,
    startBreak,
    endBreak,
    // Controller handler wrappers
    async getAttendanceDashboardHandler(req, res) {
      try {
        const result = await dashboard(req.user, req.query.month);
        res.json({ success: true, data: result });
      } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.message });
      }
    },
    async getTodayAttendanceHandler(req, res) {
      try {
        const result = await getTodayAttendance(req.user.id);
        res.json({ success: true, data: result });
      } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.message });
      }
    },
    async clockInHandler(req, res) {
      try {
        const result = await punch(req.user.id, 'in');
        res.json({ success: true, message: 'Clocked in successfully', data: result });
      } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.message });
      }
    },
    async clockOutHandler(req, res) {
      try {
        const result = await punch(req.user.id, 'out');
        res.json({ success: true, message: 'Clocked out successfully', data: result });
      } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.message });
      }
    },
    async startBreakHandler(req, res) {
      try {
        const result = await startBreak(req.user.id);
        res.json(result);
      } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.message });
      }
    },
    async endBreakHandler(req, res) {
      try {
        const result = await endBreak(req.user.id);
        res.json(result);
      } catch (err) {
        res.status(err.status || 500).json({ success: false, message: err.message });
      }
    },
  };
}

module.exports = {
  createService,
  localDate,
  sessionView,
  monthBounds,
};
