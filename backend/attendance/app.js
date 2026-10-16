'use strict';

const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const { createService } = require('./service');
const attendanceController = require('../controllers/attendanceController');

function createApp({ pool, jwtSecret, timeZone = 'Asia/Kolkata', clock = () => new Date(), basePath = '/api/attendance' }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(cors());
  app.use(express.json({ limit: '100kb' }));

  const service = createService(pool, { timeZone, clock });

  const leaveRequestType = (leaveType) => ({
    'Casual Leave': 'casual_leave',
    'Sick Leave': 'sick_leave',
    'Earned Leave': 'earned_leave',
    'Optional Holiday': 'optional_holiday',
  }[String(leaveType)] || 'leave');

  const validatePaidLeaveAllowance = async (employeeId, fromDate, requestedDays, durationType) => {
    await pool.execute(`CREATE TABLE IF NOT EXISTS hrms_paid_leave_policy (
      id TINYINT NOT NULL PRIMARY KEY,
      weekly_limit DECIMAL(5,2) NOT NULL DEFAULT 1,
      monthly_limit DECIMAL(5,2) NOT NULL DEFAULT 2,
      yearly_limit DECIMAL(5,2) NOT NULL DEFAULT 12,
      probation_days INT NOT NULL DEFAULT 0,
      minimum_notice_days INT NOT NULL DEFAULT 0,
      max_consecutive_days DECIMAL(5,2) NOT NULL DEFAULT 0,
      allow_half_day TINYINT(1) NOT NULL DEFAULT 1,
      weekly_required_worked_days INT NOT NULL DEFAULT 0,
      monthly_required_worked_days INT NOT NULL DEFAULT 0,
      yearly_required_worked_days INT NOT NULL DEFAULT 0
    )`);
    const additions = [
      ['probation_days', 'INT NOT NULL DEFAULT 0'],
      ['minimum_notice_days', 'INT NOT NULL DEFAULT 0'],
      ['max_consecutive_days', 'DECIMAL(5,2) NOT NULL DEFAULT 0'],
      ['allow_half_day', 'TINYINT(1) NOT NULL DEFAULT 1'],
      ['weekly_required_worked_days', 'INT NOT NULL DEFAULT 0'],
      ['monthly_required_worked_days', 'INT NOT NULL DEFAULT 0'],
      ['yearly_required_worked_days', 'INT NOT NULL DEFAULT 0'],
    ];
    for (const [name, definition] of additions) {
      try { await pool.execute(`ALTER TABLE hrms_paid_leave_policy ADD COLUMN ${name} ${definition}`); }
      catch (error) { if (error.code !== 'ER_DUP_FIELDNAME') throw error; }
    }
    await pool.execute('INSERT IGNORE INTO hrms_paid_leave_policy (id, weekly_limit, monthly_limit, yearly_limit, probation_days, minimum_notice_days, max_consecutive_days, allow_half_day, weekly_required_worked_days, monthly_required_worked_days, yearly_required_worked_days) VALUES (1, 1, 2, 12, 0, 0, 0, 1, 0, 0, 0)');
    const [policies] = await pool.execute('SELECT weekly_limit, monthly_limit, yearly_limit, probation_days, minimum_notice_days, max_consecutive_days, allow_half_day, weekly_required_worked_days, monthly_required_worked_days, yearly_required_worked_days FROM hrms_paid_leave_policy WHERE id = 1');
    const policyRow = policies[0];
    const date = new Date(`${fromDate}T00:00:00Z`);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const requestedLocalDate = new Date(`${fromDate}T00:00:00`);
    const noticeDays = Math.floor((requestedLocalDate - today) / (24 * 60 * 60 * 1000));
    if (noticeDays < Number(policyRow.minimum_notice_days || 0)) {
      throw new Error(`This paid leave requires ${policyRow.minimum_notice_days} day(s) advance notice.`);
    }
    if (durationType === 'Half Day' && Number(policyRow.allow_half_day) !== 1) {
      throw new Error('Half-day paid leave is not available under the company policy.');
    }
    const maxConsecutive = Number(policyRow.max_consecutive_days || 0);
    if (maxConsecutive > 0 && requestedDays > maxConsecutive) {
      throw new Error(`Paid leave is limited to ${maxConsecutive} consecutive day(s) per request.`);
    }
    const [employees] = await pool.execute('SELECT created_at FROM employee_users WHERE id = ? LIMIT 1', [employeeId]);
    const probationDays = Number(policyRow.probation_days || 0);
    if (probationDays > 0 && employees.length) {
      const joined = new Date(employees[0].created_at);
      const eligibleOn = new Date(joined); eligibleOn.setDate(eligibleOn.getDate() + probationDays);
      if (requestedLocalDate < eligibleOn) {
        throw new Error(`Paid leave becomes available after ${probationDays} day(s) of employment.`);
      }
    }
    const weekday = (date.getUTCDay() + 6) % 7;
    const weekStart = new Date(date); weekStart.setUTCDate(date.getUTCDate() - weekday);
    const weekEnd = new Date(weekStart); weekEnd.setUTCDate(weekStart.getUTCDate() + 6);
    const monthStart = `${fromDate.slice(0, 7)}-01`;
    const monthEnd = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).toISOString().slice(0, 10);
    const yearStart = `${date.getUTCFullYear()}-01-01`;
    const yearEnd = `${date.getUTCFullYear()}-12-31`;
    const usage = async (start, end) => {
      const [rows] = await pool.execute(
        `SELECT COALESCE(SUM(days_count), 0) AS days FROM employee_leaves
         WHERE employee_id = ? AND status = 'APPROVED' AND from_date BETWEEN ? AND ?`,
        [employeeId, start, end]
      );
      return Number(rows[0].days || 0);
    };
    const [weeklyUsed, monthlyUsed, yearlyUsed] = await Promise.all([
      usage(weekStart.toISOString().slice(0, 10), weekEnd.toISOString().slice(0, 10)),
      usage(monthStart, monthEnd), usage(yearStart, yearEnd),
    ]);
    const workedDays = async (start, end) => {
      const [rows] = await pool.execute(
        `SELECT COUNT(*) AS days FROM attendance_records
         WHERE employee_id = ? AND attendance_date BETWEEN ? AND ?
           AND check_in_at IS NOT NULL`,
        [employeeId, start, end]
      );
      return Number(rows[0].days || 0);
    };
    const [weeklyWorked, monthlyWorked, yearlyWorked] = await Promise.all([
      workedDays(weekStart.toISOString().slice(0, 10), weekEnd.toISOString().slice(0, 10)),
      workedDays(monthStart, monthEnd),
      workedDays(yearStart, yearEnd),
    ]);
    const attendanceRequirements = [
      ['week', weeklyWorked, Number(policyRow.weekly_required_worked_days || 0)],
      ['month', monthlyWorked, Number(policyRow.monthly_required_worked_days || 0)],
      ['year', yearlyWorked, Number(policyRow.yearly_required_worked_days || 0)],
    ];
    for (const [period, worked, required] of attendanceRequirements) {
      if (required > 0 && worked < required) {
        throw new Error(`You are not eligible for paid leave yet: ${required} worked day(s) are required this ${period}; you have ${worked}.`);
      }
    }
    const checks = [
      ['weekly', weeklyUsed, Number(policyRow.weekly_limit)],
      ['monthly', monthlyUsed, Number(policyRow.monthly_limit)],
      ['yearly', yearlyUsed, Number(policyRow.yearly_limit)],
    ];
    for (const [period, used, limit] of checks) {
      if (used + requestedDays > limit) {
        throw new Error(`No paid leaves available: your ${period} limit is ${limit} day(s), with ${Math.max(0, limit - used)} remaining.`);
      }
    }
  };

  const ensureLeaveApprovalLinks = () => pool.execute(`
    CREATE TABLE IF NOT EXISTS hrms_leave_approval_links (
      leave_id BIGINT UNSIGNED NOT NULL,
      approval_request_id BIGINT UNSIGNED NOT NULL,
      PRIMARY KEY (leave_id),
      UNIQUE KEY uniq_leave_approval_request (approval_request_id)
    )
  `);

  const ensurePayslipDownloadRequests = () => pool.execute(`
    CREATE TABLE IF NOT EXISTS hrms_payslip_download_requests (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      payroll_item_id BIGINT UNSIGNED NOT NULL,
      employee_user_id INT NOT NULL,
      approval_request_id BIGINT UNSIGNED NOT NULL,
      status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_payslip_employee_period (payroll_item_id, employee_user_id),
      UNIQUE KEY uq_payslip_approval_request (approval_request_id)
    )
  `);

  // A successful Office/Home clock-in is also a confirmed location event.
  // Store it for the Admin Tracking screen without making attendance depend
  // on the optional live-tracking tables.
  const recordClockInLocation = async (employeeId, body) => {
    try {
      const latitude = Number(body && body.latitude);
      const longitude = Number(body && body.longitude);
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
      const accuracy = Number(body && body.accuracy);
      const [profiles] = await pool.execute(
        'SELECT work_mode FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1',
        [employeeId],
      );
      const workMode = String(profiles[0] && profiles[0].work_mode || 'Office').toLowerCase();
      const status = workMode === 'home' ? 'home' : workMode === 'field' ? 'field' : 'office';
      await pool.execute(
        'INSERT INTO hrms_location_pings (employee_user_id, latitude, longitude, accuracy_meters) VALUES (?, ?, ?, ?)',
        [employeeId, latitude, longitude, Number.isFinite(accuracy) ? accuracy : null],
      );
      await pool.execute(
        `INSERT INTO hrms_employee_location_status (employee_user_id, status)
         VALUES (?, ?)
         ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = CURRENT_TIMESTAMP`,
        [employeeId, status],
      );
    } catch (error) {
      console.error('Clock-in tracking location could not be recorded:', error.message);
    }
  };

  // JWT Auth Middleware
  const authMiddleware = async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    const authorization = req.get('authorization') || '';
    if (!authorization.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, message: 'Login required' });
    }

    let claims;
    try {
      claims = jwt.verify(authorization.slice(7), jwtSecret);
      if (!claims || !claims.id) throw new Error('Invalid identity');
    } catch {
      return res.status(401).json({ success: false, message: 'Invalid or expired login token' });
    }

    try {
      const [rows] = await pool.execute(
        'SELECT id, full_name, staff_id, is_active FROM employee_users WHERE id = ? LIMIT 1',
        [Number(claims.id)],
      );
      if (rows.length !== 1 || Number(rows[0].is_active) !== 1) {
        return res.status(403).json({ success: false, message: 'Employee is inactive' });
      }
      req.employee = rows[0];
      req.user = rows[0];
      next();
    } catch (error) {
      next(error);
    }
  };

  const prefixes = [basePath, '/attendance'];

  for (const prefix of prefixes) {
    // ==========================================
    // 1. ATTENDANCE & CLOCK IN / OUT
    // ==========================================
    app.get(`${prefix}/dashboard`, authMiddleware, async (req, res, next) => {
      try {
        const data = await service.dashboard(req.employee, req.query.month);
        res.json({ success: true, data });
      } catch (error) {
        next(error);
      }
    });

    app.get(`${prefix}/today`, authMiddleware, async (req, res, next) => {
      try {
        const data = await service.getTodayAttendance(req.employee.id);
        res.json({ success: true, data });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/clock-in`, authMiddleware, async (req, res, next) => {
      try {
        const [[profile]] = await pool.execute(
          'SELECT work_mode FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1',
          [req.employee.id],
        );
        const mode = String(profile?.work_mode || 'Office').toLowerCase();
        if (mode === 'field') {
          const [sessions] = await pool.execute(
            'SELECT id FROM employee_tracking_sessions WHERE employee_id = ? AND is_active = 1 ORDER BY id DESC LIMIT 1',
            [req.employee.id],
          );
          if (!sessions.length) return res.status(400).json({ success: false, message: 'Start live tracking before clocking in as a Field employee.' });
        }
        const data = await service.punch(req.employee.id, 'in');
        await recordClockInLocation(req.employee.id, req.body);
        res.json({ success: true, message: 'Clocked in successfully', data });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/clock-out`, authMiddleware, async (req, res, next) => {
      try {
        const data = await service.punch(req.employee.id, 'out');
        res.json({ success: true, message: 'Clocked out successfully', data });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/break-in`, authMiddleware, async (req, res, next) => {
      try {
        const data = await service.startBreak(req.employee.id);
        res.json({ success: true, data });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/break-out`, authMiddleware, async (req, res, next) => {
      try {
        const data = await service.endBreak(req.employee.id);
        res.json({ success: true, data });
      } catch (error) {
        next(error);
      }
    });

    // Permission requests share the main HRMS approval store. They are kept
    // separate from leave records, so they never create calendar marks.
    app.get(`${prefix}/permissions/mine`, authMiddleware, (req, res, next) =>
      attendanceController.myPermissions(req, res, next)
    );
    app.post(`${prefix}/permissions`, authMiddleware, (req, res, next) =>
      attendanceController.createPermission(req, res, next)
    );

    // ==========================================
    // 2. LEAVE ROUTES
    // ==========================================
    app.get(`${prefix}/leave/dashboard`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;

        const [leaves] = await pool.execute(
          `SELECT id, leave_type, duration_type, 
                  DATE_FORMAT(from_date, '%Y-%m-%d') AS from_date, 
                  DATE_FORMAT(to_date, '%Y-%m-%d') AS to_date, 
                  days_count, reason, status, created_at 
           FROM employee_leaves 
           WHERE employee_id = ? 
           ORDER BY created_at DESC`,
          [empId]
        );

        const consumed = { 'Casual Leave': 0, 'Sick Leave': 0, 'Earned Leave': 0, 'Optional Holiday': 0 };
        for (const row of leaves) {
          // A request changes the available balance only after an admin has
          // approved it. Pending and rejected requests keep the balance.
          if (row.status === 'APPROVED') {
            const count = parseFloat(row.days_count) || 1.0;
            if (consumed[row.leave_type] !== undefined) {
              consumed[row.leave_type] += count;
            }
          }
        }

        await pool.execute(`CREATE TABLE IF NOT EXISTS hrms_leave_type_policies (
          leave_type VARCHAR(64) NOT NULL PRIMARY KEY,
          yearly_limit DECIMAL(5,2) NOT NULL DEFAULT 0
        )`);
        const defaultLimits = [['Casual Leave', 12], ['Sick Leave', 8], ['Earned Leave', 12], ['Optional Holiday', 3]];
        for (const [type, limit] of defaultLimits) {
          await pool.execute('INSERT IGNORE INTO hrms_leave_type_policies (leave_type, yearly_limit) VALUES (?, ?)', [type, limit]);
        }
        const [policyRows] = await pool.execute('SELECT leave_type, yearly_limit FROM hrms_leave_type_policies');
        const quotas = Object.fromEntries(policyRows.map((row) => [row.leave_type, Number(row.yearly_limit)]));
        const balances = Object.keys(quotas).map((type) => ({
          type,
          used: consumed[type],
          total: quotas[type],
          isPaidLeave: type === 'Earned Leave',
        }));

        res.json({
          success: true,
          data: {
            balances,
            requests: leaves,
          },
        });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/leave/apply`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;
        const { leave_type, duration_type, from_date, to_date, reason } = req.body;
        if (!leave_type || !from_date || !to_date) {
          return res.status(400).json({ success: false, message: 'All fields are required.' });
        }
        const d1 = new Date(from_date);
        const d2 = new Date(to_date);
        let days = (d2 - d1) / (1000 * 60 * 60 * 24) + 1;
        if (days < 0) days = 1;
        if (duration_type === 'Half Day') days = 0.5;
        // Earned Leave is the company's paid-leave type. All Salary Master
        // allowance and eligibility rules apply only to this leave type.
        if (leave_type === 'Earned Leave') {
          try {
            await validatePaidLeaveAllowance(empId, from_date, days, duration_type);
          } catch (error) {
            return res.status(409).json({ success: false, message: error.message });
          }
        }

        const [result] = await pool.execute(
          `INSERT INTO employee_leaves
            (employee_id, leave_type, duration_type, from_date, to_date, days_count, reason, status)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'PENDING')`,
          [empId, leave_type, duration_type || 'Full Day', from_date, to_date, days, reason || '']
        );
        await ensureLeaveApprovalLinks();
        const adminReason = `${leave_type} · ${duration_type || 'Full Day'} · ${from_date} to ${to_date}\n${reason || ''}`.trim();
        const [approval] = await pool.execute(
          `INSERT INTO attendance_permission_requests
             (employee_id, request_type, request_date, reason, status)
           VALUES (?, ?, ?, ?, 'pending')`,
          [empId, leaveRequestType(leave_type), from_date, adminReason]
        );
        await pool.execute(
          'INSERT INTO hrms_leave_approval_links (leave_id, approval_request_id) VALUES (?, ?)',
          [result.insertId, approval.insertId]
        );
        await pool.execute(`
          CREATE TABLE IF NOT EXISTS hrms_admin_notifications (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            approval_request_id BIGINT UNSIGNED NOT NULL,
            title VARCHAR(160) NOT NULL,
            message VARCHAR(500) NOT NULL,
            is_read TINYINT(1) NOT NULL DEFAULT 0,
            read_at DATETIME NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uniq_approval_notification (approval_request_id)
          )
        `);
        await pool.execute(
          `INSERT IGNORE INTO hrms_admin_notifications (approval_request_id, title, message)
           VALUES (?, ?, ?)`,
          [approval.insertId, `New ${leave_type} request`, `${req.employee.full_name || 'Employee'} submitted a leave request.`]
        );
        res.json({ success: true, message: 'Leave application submitted for admin approval.', insertId: result.insertId });
      } catch (error) {
        next(error);
      }
    });
    app.post(`${prefix}/leave/cancel`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;
        const { leave_id } = req.body;
        await pool.execute(
          `UPDATE employee_leaves SET status = 'CANCELLED' WHERE id = ? AND employee_id = ? AND status = 'PENDING'`,
          [leave_id, empId]
        );
        await ensureLeaveApprovalLinks();
        await pool.execute(
          `UPDATE attendance_permission_requests p
           INNER JOIN hrms_leave_approval_links link ON link.approval_request_id = p.id
           SET p.status = 'rejected'
           WHERE link.leave_id = ? AND p.status = 'pending'`,
          [leave_id]
        );
        res.json({ success: true, message: 'Leave request cancelled.' });
      } catch (error) {
        next(error);
      }
    });
    // ==========================================
    // 3. EXTRA HOURS ROUTES
    // ==========================================
    app.get(`${prefix}/extra-hours/dashboard`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;
        const currentYear = new Date().getFullYear();
        const currentMonth = new Date().getMonth() + 1;

        const [rows] = await pool.execute(
          `SELECT id, 
                  DATE_FORMAT(work_date, '%Y-%m-%d') as work_date,
                  DATE_FORMAT(work_date, '%d %b') as date_str,
                  DATE_FORMAT(work_date, '%a') as day_str,
                  TIME_FORMAT(regular_out_time, '%h:%i %p') AS regular_out,
                  TIME_FORMAT(actual_out_time, '%h:%i %p') AS actual_out,
                  CONCAT('+', FLOOR(extra_minutes / 60), 'h ', LPAD(MOD(extra_minutes, 60), 2, '0'), 'm') AS hours_minutes,
                  extra_minutes, reason, status
           FROM employee_extra_hours 
           WHERE employee_id = ? 
           ORDER BY work_date DESC`,
          [empId]
        );

        let totalMinsYear = 0;
        let approvedSessions = 0;
        let totalSessions = rows.length;
        let pendingMins = 0;
        let pendingCount = 0;
        let thisMonthMins = 0;
        let thisMonthSessions = 0;
        let thisMonthApproved = 0;

        for (const row of rows) {
          const d = new Date(row.work_date);
          const isYear = d.getFullYear() === currentYear;
          const isMonth = isYear && d.getMonth() + 1 === currentMonth;

          if (isYear && row.status === 'APPROVED') totalMinsYear += row.extra_minutes || 0;
          if (row.status === 'APPROVED') {
            approvedSessions++;
            if (isMonth) thisMonthApproved++;
          }
          if (row.status === 'PENDING') {
            pendingMins += row.extra_minutes || 0;
            pendingCount++;
          }
          if (isMonth) {
            thisMonthMins += row.extra_minutes || 0;
            thisMonthSessions++;
          }
        }

        const formatH = (m) => `${Math.floor(m / 60)}h`;
        const formatHM = (m) => `${Math.floor(m / 60)}h ${(m % 60).toString().padStart(2, '0')}m`;

        res.json({
          success: true,
          data: {
            rows,
            metrics: {
              total_year: formatH(totalMinsYear),
              approved_ratio: `${approvedSessions} / ${totalSessions}`,
              pending_hours: formatHM(pendingMins),
              pending_count: `${pendingCount} session${pendingCount === 1 ? '' : 's'} awaiting review`,
              this_month_hours: formatH(thisMonthMins),
              this_month_detail: `${thisMonthSessions} sessions · ${thisMonthApproved} approved`,
            },
          },
        });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/extra-hours/log`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;
        const { work_date, hours_worked, reason, regular_out, actual_out } = req.body;

        if (!work_date || !hours_worked) {
          return res.status(400).json({ success: false, message: 'Date and hours worked are required.' });
        }

        let totalMinutes = 0;
        const hMatch = hours_worked.match(/(\d+)\s*h/i);
        const mMatch = hours_worked.match(/(\d+)\s*m/i);
        if (hMatch || mMatch) {
          if (hMatch) totalMinutes += parseInt(hMatch[1], 10) * 60;
          if (mMatch) totalMinutes += parseInt(mMatch[1], 10);
        } else {
          const num = parseFloat(hours_worked);
          totalMinutes = isNaN(num) ? 60 : Math.round(num * 60);
        }

        await pool.execute(
          `INSERT INTO employee_extra_hours 
             (employee_id, work_date, regular_out_time, actual_out_time, extra_minutes, reason, status)
           VALUES (?, ?, COALESCE(STR_TO_DATE(?, '%h:%i %p'), '18:00:00'),
                   STR_TO_DATE(?, '%h:%i %p'), ?, ?, 'PENDING')`,
          [
            empId,
            work_date,
            regular_out || '06:00 PM',
            actual_out || null,
            totalMinutes,
            reason || '',
          ]
        );

        res.json({ success: true, message: 'Extra hours logged successfully.' });
      } catch (error) {
        next(error);
      }
    });

    // ==========================================
    // 4. PERMISSION ROUTES
    // ==========================================
    app.get(`${prefix}/permission/dashboard`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;

        const [rows] = await pool.execute(
          `SELECT id, 
                  DATE_FORMAT(permission_date, '%d %b %Y') as date_formatted,
                  DATE_FORMAT(permission_date, '%Y-%m-%d') as permission_date,
                  time_required, reason, status, created_at
           FROM employee_permissions 
           WHERE employee_id = ? 
           ORDER BY permission_date DESC, created_at DESC`,
          [empId]
        );

        res.json({ success: true, data: rows });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/permission/apply`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;
        const { permission_date, time_required, reason } = req.body;

        if (!permission_date || !time_required || !reason) {
          return res.status(400).json({ success: false, message: 'All fields are required.' });
        }

        const [result] = await pool.execute(
          `INSERT INTO employee_permissions (employee_id, permission_date, time_required, reason, status)
           VALUES (?, ?, ?, ?, 'PENDING')`,
          [empId, permission_date, time_required, reason]
        );

        res.json({ success: true, message: 'Permission request submitted successfully.', insertId: result.insertId });
      } catch (error) {
        next(error);
      }
    });

    // ==========================================
    // 5. EMPLOYEE SALARY / PAYSLIPS
    // ==========================================
    app.get(`${prefix}/salary`, authMiddleware, async (req, res, next) => {
      try {
        const [profiles] = await pool.execute(
          `SELECT id, full_name, employee_code, monthly_salary
           FROM hrms_employee_profiles
           WHERE employee_user_id = ? LIMIT 1`,
          [req.employee.id]
        );
        if (!profiles.length || profiles[0].monthly_salary === null) {
          return res.json({ success: true, data: { hasSalary: false, payslips: [] } });
        }

        const profile = profiles[0];
        await ensurePayslipDownloadRequests();
        const [items] = await pool.execute(
          `SELECT id, pay_year, pay_month, monthly_salary, working_days, paid_days,
                  lop_days, deductions, net_pay, status, paid_at
           FROM hrms_payroll_items
           WHERE profile_id = ?
           ORDER BY pay_year DESC, pay_month DESC LIMIT 12`,
          [profile.id]
        );
        const latest = items[0] || null;
        const itemIds = items.map((item) => item.id);
        const [downloadRequests] = itemIds.length
          ? await pool.query(
              `SELECT payroll_item_id, status FROM hrms_payslip_download_requests
               WHERE employee_user_id = ? AND payroll_item_id IN (?)`,
              [req.employee.id, itemIds]
            )
          : [[]];
        const downloadStatusByItem = new Map(downloadRequests.map((row) => [Number(row.payroll_item_id), row.status]));
        const gross = Number(latest ? latest.monthly_salary : profile.monthly_salary);
        const deductions = Number(latest ? latest.deductions : 0);
        const netPay = Number(latest ? latest.net_pay : gross);
        const period = latest
          ? new Date(Date.UTC(Number(latest.pay_year), Number(latest.pay_month) - 1, 1))
              .toLocaleString('en-IN', { month: 'long', year: 'numeric', timeZone: 'UTC' })
          : '';

        res.json({
          success: true,
          data: {
            hasSalary: true,
            employeeName: profile.full_name,
            employeeCode: profile.employee_code,
            grossSalary: gross,
            deductions: deductions,
            netPay: netPay,
            basicSalary: Math.round(gross * 2 / 3),
            hra: Math.round(gross * 2 / 9),
            allowances: gross - Math.round(gross * 2 / 3) - Math.round(gross * 2 / 9),
            period: period,
            status: latest ? latest.status : 'draft',
            payslips: items.map((item) => ({
              id: item.id,
              period: new Date(Date.UTC(Number(item.pay_year), Number(item.pay_month) - 1, 1))
                .toLocaleString('en-IN', { month: 'long', year: 'numeric', timeZone: 'UTC' }),
              netPay: Number(item.net_pay),
              grossSalary: Number(item.monthly_salary),
              deductions: Number(item.deductions),
              workingDays: Number(item.working_days),
              paidDays: Number(item.paid_days),
              lopDays: Number(item.lop_days),
              status: item.status,
              paidAt: item.paid_at,
              downloadStatus: downloadStatusByItem.get(Number(item.id)) || 'not_requested',
            })),
          },
        });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/salary/payslips/:id/request`, authMiddleware, async (req, res, next) => {
      try {
        const payrollItemId = Number(req.params.id);
        if (!Number.isInteger(payrollItemId) || payrollItemId <= 0) {
          return res.status(400).json({ success: false, message: 'Invalid payslip.' });
        }
        const [items] = await pool.execute(
          `SELECT i.id, i.pay_year, i.pay_month FROM hrms_payroll_items i
           INNER JOIN hrms_employee_profiles p ON p.id = i.profile_id
           WHERE i.id = ? AND p.employee_user_id = ? LIMIT 1`,
          [payrollItemId, req.employee.id]
        );
        if (!items.length) return res.status(404).json({ success: false, message: 'Payslip not found.' });
        await ensurePayslipDownloadRequests();
        const [existing] = await pool.execute(
          'SELECT status FROM hrms_payslip_download_requests WHERE payroll_item_id = ? AND employee_user_id = ? LIMIT 1',
          [payrollItemId, req.employee.id]
        );
        if (existing.length) {
          return res.json({ success: true, data: { status: existing[0].status }, message: existing[0].status === 'approved' ? 'Payslip is approved for download.' : 'Payslip request is already pending.' });
        }
        const period = new Date(Date.UTC(Number(items[0].pay_year), Number(items[0].pay_month) - 1, 1))
          .toLocaleString('en-IN', { month: 'long', year: 'numeric', timeZone: 'UTC' });
        const [approval] = await pool.execute(
          `INSERT INTO attendance_permission_requests (employee_id, request_type, request_date, reason, status)
           VALUES (?, 'payslip_download', CURDATE(), ?, 'pending')`,
          [req.employee.id, `Payslip download request for ${period}`]
        );
        await pool.execute(
          `INSERT INTO hrms_payslip_download_requests
             (payroll_item_id, employee_user_id, approval_request_id, status)
           VALUES (?, ?, ?, 'pending')`,
          [payrollItemId, req.employee.id, approval.insertId]
        );
        return res.json({ success: true, data: { status: 'pending' }, message: 'Payslip request sent to the administrator for approval.' });
      } catch (error) { next(error); }
    });

    // ==========================================
    // 6. GLOBAL HEADER STATUS & NOTIFICATIONS
    // ==========================================
    app.get(`${prefix}/header-status`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;

        // Check today's punch state through service first, with direct fallback
        let isCheckedIn = false;
        let lastPunchTime = null;

        try {
          const todayData = await service.getTodayAttendance(empId);
          if (todayData) {
            isCheckedIn = Boolean(
              todayData.isCheckedIn ??
              todayData.is_checked_in ??
              todayData.punchedIn ??
              todayData.punch_type === 'in' ??
              todayData.status === 'Checked In' ??
              (todayData.firstPunch && !todayData.lastPunch)
            );
            lastPunchTime = todayData.firstPunch || todayData.punch_time || null;
          }
        } catch (_) {}

        if (!lastPunchTime) {
          try {
            const [punches] = await pool.execute(
              `SELECT punch_type, DATE_FORMAT(punch_time, '%h:%i %p') as time_str 
               FROM employee_punches 
               WHERE employee_id = ? AND DATE(punch_time) = CURDATE() 
               ORDER BY punch_time DESC LIMIT 1`,
              [empId]
            );
            if (punches.length > 0) {
              isCheckedIn = punches[0].punch_type === 'in';
              lastPunchTime = punches[0].time_str;
            }
          } catch (_) {}
        }

        const [leaves] = await pool.execute(
          `SELECT status, leave_type FROM employee_leaves WHERE employee_id = ? ORDER BY id DESC LIMIT 3`,
          [empId]
        ).catch(() => [[]]);

        const notifications = [
          {
            title: isCheckedIn ? 'Checked in successfully' : 'Not checked in yet',
            subtitle: isCheckedIn ? `Active since ${lastPunchTime || 'shift start'}` : 'Punch in to start shift',
            icon: 'punch',
          },
        ];

        for (const l of leaves) {
          notifications.push({
            title: `${l.leave_type} (${l.status})`,
            subtitle: l.status === 'APPROVED' ? 'Your manager approved this request' : 'Review in progress',
            icon: 'leave',
          });
        }

        res.json({
          success: true,
          data: {
            is_checked_in: isCheckedIn,
            status_label: isCheckedIn ? 'Checked In' : 'Checked Out',
            full_name: req.employee.full_name || 'Employee',
            staff_id: req.employee.staff_id || 'EMP',
            notifications,
            unread_count: notifications.length > 0 ? 1 : 0,
          },
        });
      } catch (error) {
        next(error);
      }
    });

    // ==========================================
    // 6. TRACKING DASHBOARD & TOGGLE
    // ==========================================
    app.get(`${prefix}/tracking/dashboard`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;

        const [sessions] = await pool.execute(
          `SELECT * FROM employee_tracking_sessions 
           WHERE employee_id = ? 
           ORDER BY id DESC LIMIT 1`,
          [empId]
        ).catch(() => [[]]);

        const activeSession = sessions.length > 0 ? sessions[0] : null;

        const [activities] = await pool.execute(
          `SELECT id, activity_time, activity_text 
           FROM employee_tracking_activities 
           WHERE employee_id = ? AND DATE(created_at) = CURDATE() 
           ORDER BY id DESC`,
          [empId]
        ).catch(() => [[]]);

        const activityList =
          activities.length > 0
            ? activities
            : [
                { activity_time: '09:20 AM', activity_text: 'Started field tracking' },
                { activity_time: '10:05 AM', activity_text: 'Reached Sector 63' },
                { activity_time: '11:08 AM', activity_text: 'Arrived at Sector 62' },
              ];

        res.json({
          success: true,
          data: {
            is_active: activeSession ? Boolean(activeSession.is_active) : false,
            work_mode: activeSession ? activeSession.work_mode : 'field',
            distance: activeSession ? `${activeSession.distance_km} km` : '18.6 km',
            duration: activeSession
              ? `${Math.floor(activeSession.duration_minutes / 60)}h ${(activeSession.duration_minutes % 60)}m`
              : '01h 48m',
            avg_speed: activeSession ? `${activeSession.avg_speed_kmh} km/h` : '24.3 km/h',
            activities: activityList,
          },
        });
      } catch (error) {
        next(error);
      }
    });

    app.post(`${prefix}/tracking/toggle`, authMiddleware, async (req, res, next) => {
      try {
        const empId = req.employee.id;
        const { is_active, work_mode } = req.body;

        const [existing] = await pool.execute(
          `SELECT id FROM employee_tracking_sessions WHERE employee_id = ? ORDER BY id DESC LIMIT 1`,
          [empId]
        ).catch(() => [[]]);

        const currentTimeStr = new Intl.DateTimeFormat('en-US', {
          hour: '2-digit',
          minute: '2-digit',
          hour12: true,
          timeZone: 'Asia/Kolkata',
        }).format(new Date());

        if (existing.length > 0) {
          await pool.execute(
            `UPDATE employee_tracking_sessions 
             SET is_active = ?, work_mode = ?, 
                 stopped_at = IF(? = 0, NOW(), stopped_at),
                 started_at = IF(? = 1, NOW(), started_at) 
             WHERE id = ?`,
            [is_active ? 1 : 0, work_mode || 'field', is_active ? 1 : 0, is_active ? 1 : 0, existing[0].id]
          );
        } else {
          await pool.execute(
            `INSERT INTO employee_tracking_sessions 
              (employee_id, work_mode, is_active, started_at, distance_km, duration_minutes, avg_speed_kmh) 
             VALUES (?, ?, ?, NOW(), 0.0, 0, 0.0)`,
            [empId, work_mode || 'field', is_active ? 1 : 0]
          );
        }

        await pool.execute(
          `INSERT INTO employee_tracking_activities (employee_id, activity_time, activity_text) 
           VALUES (?, ?, ?)`,
          [empId, currentTimeStr, is_active ? `Started ${work_mode || 'field'} tracking` : 'Live tracking stopped']
        );

        res.json({
          success: true,
          is_active: Boolean(is_active),
          message: is_active ? 'Tracking started' : 'Tracking stopped',
        });
      } catch (error) {
        next(error);
      }
    });
  }

  app.use((error, req, res, next) => {
    const status = error.status || 500;
    if (status >= 500) console.error('Attendance error:', error);
    res.status(status).json({
      success: false,
      message: status >= 500 ? 'Attendance service unavailable' : error.message,
    });
  });

  return app;
}

module.exports = { createApp };
