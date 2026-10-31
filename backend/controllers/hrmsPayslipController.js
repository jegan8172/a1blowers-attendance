const db = require('../config/db');
const weeklyOffTemplates = require('../lib/weeklyOffTemplates');
const calendarWorkingDays = require('../lib/calendarWorkingDays');

const ok = (res, data, message) => res.json({ success: true, message: message || 'OK', data });
const fail = (res, status, message) => res.status(status).json({ success: false, message });

async function ensureTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payslip_requests (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    payroll_item_id BIGINT UNSIGNED NOT NULL,
    employee_user_id BIGINT UNSIGNED NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    reviewed_by BIGINT UNSIGNED NULL,
    reviewed_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_payslip_employee (payroll_item_id, employee_user_id)
  )`);
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_payslip_approval_links (
    payslip_request_id BIGINT UNSIGNED NOT NULL,
    approval_request_id BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (payslip_request_id),
    UNIQUE KEY uniq_payslip_approval_request (approval_request_id)
  )`);
}

async function ensureCompensationTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_employee_compensation (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    profile_id BIGINT UNSIGNED NULL,
    employee_user_id BIGINT UNSIGNED NOT NULL,
    monthly_salary DECIMAL(12,2) NOT NULL,
    effective_from DATE NOT NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY employee_effective (employee_user_id, effective_from)
  )`);
  try { await db.query('ALTER TABLE hrms_employee_compensation ADD COLUMN profile_id BIGINT UNSIGNED NULL AFTER id'); } catch (_) {}
}

function requireAdmin(req, res, next) {
  if (String(req.user && req.user.userType || '').toLowerCase() !== 'admin') return fail(res, 403, 'Admin access required');
  return next();
}

function _countWorkingDays(start, end) {
  let total = 0;
  const d = new Date(start + 'T00:00:00Z');
  const endMs = new Date(end + 'T00:00:00Z').getTime();
  while (d.getTime() <= endMs) {
    const dow = d.getUTCDay();
    if (dow !== 0) total += 1; // Sunday off by default
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return total;
}
function _ymd(date) { return date.toISOString().slice(0, 10); }
function _formatMoney(n) { return '₹' + Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 0 }); }

async function summary(req, res) {
  try {
    await ensureCompensationTable();
    const [[compensation]] = await db.query(`SELECT COALESCE(c.monthly_salary, e.monthly_salary) AS monthly_salary,
              COALESCE(c.effective_from, DATE(e.created_at)) AS effective_from
      FROM hrms_employee_profiles e
      LEFT JOIN hrms_employee_compensation c ON (c.profile_id = e.id OR (c.profile_id IS NULL AND c.employee_user_id = e.employee_user_id))
        AND c.effective_from <= CURDATE()
      WHERE e.employee_user_id = ?
      ORDER BY c.effective_from DESC, c.id DESC LIMIT 1`, [req.user.id]);
    // Payroll rows created by older versions may have a valid profile link but
    // a missing or stale employee_user_id. Resolve through either immutable
    // key so a generated pending row is still visible to its employee.
    const [[payroll]] = await db.query(`SELECT p.* FROM hrms_payroll_items p
      WHERE (p.employee_user_id = ? OR p.profile_id = (
        SELECT id FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1
      )) AND p.monthly_salary > 0
      ORDER BY p.pay_year DESC, p.pay_month DESC, p.id DESC LIMIT 1`, [req.user.id, req.user.id]);
    const [[invalid]] = await db.query(`SELECT p.id FROM hrms_payroll_items p
      JOIN hrms_employee_profiles e ON e.id = p.profile_id
      WHERE (p.employee_user_id = ? OR e.employee_user_id = ?)
        AND (NOT(p.employee_user_id <=> e.employee_user_id) OR (p.status = 'paid' AND COALESCE(p.monthly_salary, 0) <= 0))
      LIMIT 1`, [req.user.id, req.user.id]);

    // Live payroll: compute earnedToDate = days_attended_so_far × daily_rate
    let livePayroll = null;
    const monthlySalary = Number(compensation && compensation.monthly_salary || (payroll && payroll.monthly_salary) || 0);
    if (monthlySalary > 0) {
      const now = new Date();
      const year = now.getUTCFullYear();
      const month = now.getUTCMonth() + 1;
      const monthStart = _ymd(new Date(Date.UTC(year, month - 1, 1)));
      const monthEnd = _ymd(new Date(Date.UTC(year, month, 0)));
      const today = _ymd(now);
      const cutoff = today < monthEnd ? today : monthEnd;
      const periodWorkingDays = Math.max(1, _countWorkingDays(monthStart, monthEnd));
      const dailyRate = monthlySalary / periodWorkingDays;

      // Count days with check-in up to today
      const [[attRow]] = await db.query(`SELECT COUNT(DISTINCT DATE(check_in_at)) AS present_days
        FROM attendance_records
        WHERE employee_id = ? AND DATE(check_in_at) BETWEEN ? AND ? AND check_in_at IS NOT NULL`,
        [req.user.id, monthStart, cutoff]);
      const paidDaysToDate = Number(attRow && attRow.present_days || 0);
      const earnedToDate = Math.round(paidDaysToDate * dailyRate * 100) / 100;
      const savedDeductions = payroll && Number(payroll.deductions) > 0 ? Number(payroll.deductions) : 0;

      livePayroll = {
        monthlySalary: monthlySalary,
        dailyRate: Math.round(dailyRate * 100) / 100,
        dailyRateLabel: _formatMoney(dailyRate),
        workingDays: periodWorkingDays,
        paidDaysToDate: paidDaysToDate,
        earnedToDate: earnedToDate,
        earnedToDateLabel: _formatMoney(earnedToDate),
        deductions: savedDeductions,
        deductionsLabel: _formatMoney(savedDeductions),
        netPay: earnedToDate,
        netPayLabel: _formatMoney(earnedToDate),
        periodStart: monthStart,
        periodEnd: monthEnd,
        status: payroll && payroll.status === 'paid' ? 'paid' : 'pending',
      };
    }

    return ok(res, { compensation: compensation || null, payroll: payroll || null, livePayroll, reviewRequired: Boolean(invalid) });
  } catch (error) { return fail(res, 500, error.message); }
}

async function compensationList(req, res) {
  try {
    await ensureCompensationTable();
    const employeeId = Number(req.query.employeeUserId || 0);
    const [rows] = await db.query(`SELECT id, employee_user_id, monthly_salary, effective_from, created_at FROM hrms_employee_compensation ${employeeId ? 'WHERE employee_user_id = ?' : ''} ORDER BY employee_user_id, effective_from DESC`, employeeId ? [employeeId] : []);
    return ok(res, rows);
  } catch (error) { return fail(res, 500, error.message); }
}

async function saveCompensation(req, res) {
  try {
    await ensureCompensationTable();
    const employeeUserId = Number(req.body && req.body.employeeUserId);
    const monthlySalary = Number(req.body && req.body.monthlySalary);
    const effectiveFrom = String(req.body && req.body.effectiveFrom || '').slice(0, 10);
    if (!employeeUserId || !Number.isFinite(monthlySalary) || monthlySalary < 0 || !/^\d{4}-\d{2}-\d{2}$/.test(effectiveFrom)) return fail(res, 400, 'employeeUserId, monthlySalary, and effectiveFrom are required');
    const [[profile]] = await db.query('SELECT id FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1', [employeeUserId]);
    const [result] = await db.query(`INSERT INTO hrms_employee_compensation (profile_id, employee_user_id, monthly_salary, effective_from, created_by) VALUES (?, ?, ?, ?, ?)`, [profile ? profile.id : null, employeeUserId, monthlySalary, effectiveFrom, req.user.id]);
    // Profile is the live Admin/dashboard source; the history row remains the payroll source.
    if (profile) await db.query('UPDATE hrms_employee_profiles SET monthly_salary = ? WHERE id = ?', [monthlySalary, profile.id]);
    return ok(res, { id: result.insertId }, 'Compensation saved');
  } catch (error) { return fail(res, 500, error.message); }
}

async function mine(req, res) {
  try {
    await ensureTable();
    const [rows] = await db.query(`
      SELECT p.id, p.pay_year, p.pay_month, p.monthly_salary, p.deductions, p.net_pay, p.status,
             COALESCE(a.status, 'not_requested') AS request_status
      FROM hrms_payroll_items p
      JOIN hrms_employee_profiles e ON e.id = p.profile_id AND e.employee_user_id = p.employee_user_id
      LEFT JOIN hrms_payslip_requests request ON request.payroll_item_id = p.id AND request.employee_user_id = p.employee_user_id
      LEFT JOIN hrms_payslip_approval_links link ON link.payslip_request_id = request.id
      LEFT JOIN attendance_permission_requests a ON a.id = link.approval_request_id
      WHERE p.employee_user_id = ? AND p.status = 'paid' AND p.monthly_salary > 0
      ORDER BY p.pay_year DESC, p.pay_month DESC`, [req.user.id]);
    return ok(res, rows);
  } catch (error) { return fail(res, 500, error.message); }
}

async function myDeductionHistory(req, res) {
  try {
    const [[payroll]] = await db.query(`SELECT p.pay_year, p.pay_month, p.profile_id
      FROM hrms_payroll_items p JOIN hrms_employee_profiles e ON e.id = p.profile_id
      WHERE e.employee_user_id = ? ORDER BY p.pay_year DESC, p.pay_month DESC, p.id DESC LIMIT 1`, [req.user.id]);
    if (!payroll) return ok(res, []);
    const [rows] = await db.query(`SELECT DATE_FORMAT(d.attendance_date, '%Y-%m-%d') AS attendance_date,
      d.deduction_type, d.late_minutes, d.amount FROM hrms_payroll_deduction_entries d
      WHERE d.profile_id = ? AND d.pay_year = ? AND d.pay_month = ?
      ORDER BY d.attendance_date DESC, d.deduction_type ASC`, [payroll.profile_id, payroll.pay_year, payroll.pay_month]);
    return ok(res, rows);
  } catch (error) { return fail(res, 500, error.message); }
}

async function myHistory(req, res) {
  try {
    await ensureCompensationTable();
    const raw = String(req.query.month || '');
    const now = new Date();
    const fallback = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
    const month = /^\d{4}-(0[1-9]|1[0-2])$/.test(raw) ? raw : fallback;
    const [year, monthNumber] = month.split('-').map(Number);
    const start = `${month}-01`;
    const end = _ymd(new Date(Date.UTC(year, monthNumber, 0)));
    const cutoff = month === fallback && _ymd(now) < end ? _ymd(now) : end;
    const [[profile]] = await db.query('SELECT id, monthly_salary FROM hrms_employee_profiles WHERE employee_user_id = ? LIMIT 1', [req.user.id]);
    if (!profile) return fail(res, 404, 'Employee profile not found');
    await weeklyOffTemplates.ensureWeeklyOffTemplateTables(db);
    const weeklyResolver = await weeklyOffTemplates.offDaysForProfileByDate(db, profile.id, start, end, [0]);
    const calendarOverrides = await calendarWorkingDays.overridesForPeriod(start, end);
    const [[comp]] = await db.query(`SELECT monthly_salary FROM hrms_employee_compensation
      WHERE employee_user_id = ? AND effective_from <= ? ORDER BY effective_from DESC, id DESC LIMIT 1`, [req.user.id, end]);
    const monthlySalary = Number((comp && comp.monthly_salary) || profile.monthly_salary || 0);
    let workingDaysCount = 0;
    for (let d = new Date(`${start}T00:00:00Z`); d.toISOString().slice(0, 10) <= end; d.setUTCDate(d.getUTCDate() + 1)) {
      if (calendarWorkingDays.isEmployeeWorkingDay(_ymd(d), weeklyResolver, calendarOverrides)) workingDaysCount++;
    }
    const workingDays = Math.max(1, workingDaysCount);
    const dailySalary = monthlySalary / workingDays;
    const [[payroll]] = await db.query(`SELECT p.* FROM hrms_payroll_items p
      WHERE p.employee_user_id = ? AND p.pay_year = ? AND p.pay_month = ?
      ORDER BY p.id DESC LIMIT 1`, [req.user.id, year, monthNumber]);
    const [attendance] = await db.query(`SELECT DATE_FORMAT(attendance_date, '%Y-%m-%d') AS day,
      check_in_at, check_out_at, is_late, attendance_status
      FROM attendance_records WHERE employee_id = ? AND attendance_date BETWEEN ? AND ?`, [req.user.id, start, cutoff]);
    const [deductions] = await db.query(`SELECT DATE_FORMAT(attendance_date, '%Y-%m-%d') AS day,
      deduction_type, late_minutes, amount FROM hrms_payroll_deduction_entries
      WHERE employee_user_id = ? AND pay_year = ? AND pay_month = ?`, [req.user.id, year, monthNumber]);
    const byDay = new Map(attendance.map((r) => [String(r.day), r]));
    const dedByDay = new Map();
    deductions.forEach((d) => { const key = String(d.day); const current = dedByDay.get(key) || { late: 0, absent: 0 }; if (d.deduction_type === 'late') current.late += Number(d.amount || 0); else current.absent += Number(d.amount || 0); dedByDay.set(key, current); });
    const rows = [];
    for (let d = new Date(`${start}T00:00:00Z`); d.toISOString().slice(0, 10) <= cutoff; d.setUTCDate(d.getUTCDate() + 1)) {
      const day = _ymd(d); const a = byDay.get(day); const saved = dedByDay.get(day) || { late: 0, absent: 0 };
      if (!calendarWorkingDays.isEmployeeWorkingDay(day, weeklyResolver, calendarOverrides)) continue;
      const present = Boolean(a && a.check_in_at); const late = present && (Boolean(a.is_late) || String(a.attendance_status || '').toLowerCase() === 'late');
      const status = late ? 'Late' : present ? 'Present' : 'Absent';
      const lateDeduction = late ? saved.late : 0;
      const absentDeduction = status === 'Absent' ? (saved.absent || dailySalary) : 0;
      rows.push({ date: day, salary: dailySalary, working: present ? 1 : 0, check_in: a && a.check_in_at, check_out: a && a.check_out_at, status, late_deduction: lateDeduction, absent_deduction: absentDeduction, total_deduction: lateDeduction + absentDeduction });
    }
    let balance = 0;
    rows.forEach((r) => { if (r.status === 'Present') balance += r.salary; else if (r.status === 'Late') balance += r.salary - r.late_deduction; r.updated_salary = balance; });
    rows.reverse();
    return ok(res, { month, summary: payroll || { monthly_salary: monthlySalary, working_days: workingDays, net_pay: balance }, items: rows });
  } catch (error) { return fail(res, 500, error.message); }
}

async function request(req, res) {
  try {
    await ensureTable();
    const payrollId = Number(req.params.payrollId);
    const [[payroll]] = await db.query(
      `SELECT id, pay_year, pay_month FROM hrms_payroll_items WHERE id = ? AND employee_user_id = ? AND status = 'paid'`,
      [payrollId, req.user.id]
    );
    if (!payroll) return fail(res, 404, 'Paid payroll item not found');
    const [[existing]] = await db.query(`
      SELECT a.status FROM hrms_payslip_requests request
      LEFT JOIN hrms_payslip_approval_links link ON link.payslip_request_id = request.id
      LEFT JOIN attendance_permission_requests a ON a.id = link.approval_request_id
      WHERE request.payroll_item_id = ? AND request.employee_user_id = ?`, [payrollId, req.user.id]);
    if (existing) return ok(res, { status: existing.status }, 'Request already exists');
    const today = new Date().toISOString().slice(0, 10);
    const [created] = await db.query(`
      INSERT INTO attendance_permission_requests (employee_id, request_type, request_date, reason, status, created_at)
      VALUES (?, 'payslip_download', ?, ?, 'pending', NOW())`,
      [req.user.id, today, `Payslip download request for ${payroll.pay_month}/${payroll.pay_year}`]
    );
    const [requestRow] = await db.query(`INSERT INTO hrms_payslip_requests (payroll_item_id, employee_user_id, status) VALUES (?, ?, 'pending')`, [payrollId, req.user.id]);
    await db.query('INSERT INTO hrms_payslip_approval_links (payslip_request_id, approval_request_id) VALUES (?, ?)', [requestRow.insertId, created.insertId]);
    return ok(res, { status: 'pending' }, 'Payslip request sent to Admin');
  } catch (error) { return fail(res, 500, error.message); }
}

async function download(req, res) {
  try {
    await ensureTable();
    const payrollId = Number(req.params.payrollId);
    const [[row]] = await db.query(`
      SELECT p.*, a.status AS request_status, e.full_name, e.employee_code, e.department
      FROM hrms_payroll_items p
      JOIN hrms_employee_profiles e ON e.id = p.profile_id AND e.employee_user_id = p.employee_user_id
      JOIN hrms_payslip_requests request ON request.payroll_item_id = p.id AND request.employee_user_id = p.employee_user_id
      JOIN hrms_payslip_approval_links link ON link.payslip_request_id = request.id
      JOIN attendance_permission_requests a ON a.id = link.approval_request_id
      WHERE p.id = ? AND p.employee_user_id = ?`, [payrollId, req.user.id]);
    if (!row || row.request_status !== 'approved') return fail(res, 403, 'Admin approval is required before download');
    let generatedPdf;
    try {
      const { buildPayslipPdf } = require('../lib/payslipPdf');
      generatedPdf = await buildPayslipPdf(row);
    } catch (error) {
      return fail(res, 501, 'Payslip PDF generation is not configured on this server.');
    }
    res.set('Content-Disposition', `attachment; filename="Salary-Slip-${row.pay_month}-${row.pay_year}.pdf"`);
    res.type('application/pdf').send(generatedPdf);
    return;
    const money = (value) => `Rs. ${Number(value || 0).toLocaleString('en-IN')}`;
    const employeeName = row.employee_name || row.name || 'Employee';
    const pdfText = (value) => String(value ?? '').replace(/[\\()]/g, '\\$&');
    const lines = [
      'GO DIGITAL', `SALARY SLIP FOR THE MONTH - ${row.pay_month}/${row.pay_year}`,
      `Employee Name: ${employeeName}`, `Employee Code: ${row.employee_code || row.employee_user_id || '-'}`,
      `Gross Earnings (A): ${money(row.monthly_salary)}`, `Leave Deduction: ${money(row.deductions)}`,
      `Total Deductions (B): ${money(row.deductions)}`, `TOTAL NET PAYABLE (A-B): ${money(row.net_pay)}`,
      'This is a system generated pay slip and hence company signature is not required.'
    ];
    let y = 770;
    const commands = ['BT /F1 16 Tf 50 800 Td'];
    lines.forEach((line, index) => { commands.push(`/F1 ${index < 2 ? 16 : 11} Tf 0 -${index === 0 ? 28 : 25} Td (${pdfText(line)}) Tj`); });
    commands.push('ET');
    const stream = commands.join('\n');
    const objects = [
      '<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>', `<< /Length ${Buffer.byteLength(stream, 'utf8')} >>\nstream\n${stream}\nendstream`
    ];
    let pdf = '%PDF-1.4\n'; const offsets = [0];
    objects.forEach((object, index) => { offsets.push(Buffer.byteLength(pdf, 'utf8')); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; });
    const xref = Buffer.byteLength(pdf, 'utf8'); pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`; offsets.slice(1).forEach((offset) => { pdf += `${String(offset).padStart(10, '0')} 00000 n \n`; }); pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
    res.set('Content-Disposition', `attachment; filename="Salary-Slip-${row.pay_month}-${row.pay_year}.pdf"`);
    res.type('application/pdf').send(Buffer.from(pdf, 'utf8'));
    return;
    res.type('html').send(`<!doctype html><html><head><meta charset="utf-8"><style>
      body{font-family:Arial,sans-serif;color:#172554;margin:0;padding:32px;background:#f5f7fb}
      .sheet{max-width:760px;margin:auto;background:#fff;border:1px solid #dbe3f0;border-radius:12px;overflow:hidden}
      .head{background:#0b3b8f;color:#fff;padding:26px 32px}.brand{font-size:22px;font-weight:700;letter-spacing:.5px}.title{font-size:18px;margin-top:8px;opacity:.9}
      .meta{display:grid;grid-template-columns:1fr 1fr 1fr 1fr;padding:22px 32px;border-bottom:1px solid #e5eaf2}.label{color:#64748b;font-size:12px;text-transform:uppercase}.value{font-weight:700;margin-top:5px}
      table{width:calc(100% - 64px);margin:24px 32px;border-collapse:collapse}th,td{padding:10px 12px;border:1px solid #dbe3f0;text-align:left}th{background:#eef3fb}td:nth-child(even),th:nth-child(even){text-align:right}
      .net{margin:0 32px 30px;padding:20px;background:#eaf2ff;border-left:5px solid #1261e8;display:flex;justify-content:space-between;font-size:20px;font-weight:700}.foot{padding:16px 32px;color:#64748b;font-size:12px;border-top:1px solid #e5eaf2}
    </style></head><body><section class="sheet"><header class="head"><div class="brand">GO DIGITAL</div><div class="title">Salary Slip</div></header>
      <div class="meta"><div><div class="label">Employee Name</div><div class="value">${employeeName}</div></div><div><div class="label">Employee Code</div><div class="value">${row.employee_code || row.employee_user_id || '—'}</div></div><div><div class="label">Pay period</div><div class="value">${row.pay_month}/${row.pay_year}</div></div><div><div class="label">Net days payable</div><div class="value">${row.paid_days || '—'}</div></div></div>
      <table><tr><th>Earnings</th><th>Amount (INR)</th><th>Deductions</th><th>Amount (INR)</th></tr><tr><td>Gross Salary</td><td>${money(row.monthly_salary)}</td><td>Leave Deduction</td><td>${money(row.deductions)}</td></tr><tr><td>Other Earnings</td><td>${money(0)}</td><td>Other Deductions</td><td>${money(0)}</td></tr><tr><th>Total Earnings (A)</th><th>${money(row.monthly_salary)}</th><th>Total Deductions (B)</th><th>${money(row.deductions)}</th></tr></table>
      <div class="net"><span>Total Net Payable (A − B)</span><span>${money(row.net_pay)}</span></div><div class="foot">This is a system generated pay slip and hence company signature is not required.</div></section></body></html>`);
  } catch (error) { return fail(res, 500, error.message); }
}

module.exports = { ensureTable, ensureCompensationTable, requireAdmin, mine, summary, myDeductionHistory, myHistory, request, download, compensationList, saveCompensation };
