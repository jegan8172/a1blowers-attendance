const db = require('../config/db');
async function ensure() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_leave_policies (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, leave_type VARCHAR(80) NOT NULL,
    annual_allowance DECIMAL(8,2) NOT NULL DEFAULT 0, monthly_allowance DECIMAL(8,2) NOT NULL DEFAULT 0,
    carry_forward TINYINT(1) NOT NULL DEFAULT 0,
    effective_year INT NOT NULL, active TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uniq_leave_policy_year (leave_type, effective_year))`);

  try { await db.query('ALTER TABLE hrms_leave_policies ADD COLUMN monthly_allowance DECIMAL(8,2) NOT NULL DEFAULT 0 AFTER annual_allowance'); } catch (_) {}
  // Card visibility is presentation only.  It must not change whether a
  // leave type is eligible for approval or payroll treatment.
  try { await db.query('ALTER TABLE hrms_leave_policies ADD COLUMN employee_card_visible TINYINT(1) NULL DEFAULT NULL AFTER active'); } catch (_) {}
  try { await db.query("ALTER TABLE hrms_leave_policies ADD COLUMN employee_card_display_mode VARCHAR(32) NULL DEFAULT NULL AFTER employee_card_visible"); } catch (_) {}
  try { await db.query("ALTER TABLE hrms_leave_policies ADD COLUMN payroll_mode VARCHAR(10) NULL DEFAULT NULL AFTER employee_card_display_mode"); } catch (_) {}
  try { await db.query('ALTER TABLE hrms_leave_policies ADD COLUMN allow_half_day TINYINT(1) NULL DEFAULT NULL AFTER payroll_mode'); } catch (_) {}
  // A request keeps the rules that existed when it was created.  This is a
  // snapshot only; it never rewrites legacy leave rows or payroll history.
  try { await db.query("ALTER TABLE employee_leaves ADD COLUMN policy_payroll_mode VARCHAR(10) NULL AFTER duration_type"); } catch (_) {}
  try { await db.query('ALTER TABLE employee_leaves ADD COLUMN policy_allow_half_day TINYINT(1) NULL AFTER policy_payroll_mode'); } catch (_) {}
  await db.query(`UPDATE hrms_leave_policies
    SET employee_card_visible = CASE WHEN leave_type IN ('Sick Leave', 'Earned Leave') THEN 1 ELSE 0 END
    WHERE employee_card_visible IS NULL`);
  await db.query(`UPDATE hrms_leave_policies
    SET employee_card_display_mode = CASE WHEN leave_type = 'Sick Leave' THEN 'Usage only' ELSE 'Balance & usage' END
    WHERE employee_card_display_mode IS NULL OR employee_card_display_mode = ''`);
  await db.query(`UPDATE hrms_leave_policies
    SET payroll_mode = CASE WHEN leave_type = 'Earned Leave' THEN 'paid' ELSE 'unpaid' END
    WHERE payroll_mode IS NULL OR payroll_mode NOT IN ('paid', 'unpaid')`);
  await db.query('UPDATE hrms_leave_policies SET allow_half_day = 1 WHERE allow_half_day IS NULL');
  const year = new Date().getFullYear();
  await db.query(
    `INSERT IGNORE INTO hrms_leave_policies
       (leave_type, annual_allowance, monthly_allowance, carry_forward, effective_year, active)
     VALUES
       ('Casual Leave', 12, 0, 0, ?, 1),
       ('Sick Leave', 8, 0, 0, ?, 1),
       ('Earned Leave', 18, 0, 1, ?, 1),
       ('Optional Holiday', 3, 0, 0, ?, 1)`,
    [year, year, year, year],
  );
  await db.query(`UPDATE hrms_leave_policies
    SET employee_card_visible = CASE WHEN leave_type IN ('Sick Leave', 'Earned Leave') THEN 1 ELSE 0 END
    WHERE employee_card_visible IS NULL`);
  await db.query(`UPDATE hrms_leave_policies
    SET employee_card_display_mode = CASE WHEN leave_type = 'Sick Leave' THEN 'Usage only' ELSE 'Balance & usage' END
    WHERE employee_card_display_mode IS NULL OR employee_card_display_mode = ''`);
  await db.query(`UPDATE hrms_leave_policies
    SET payroll_mode = CASE WHEN leave_type = 'Earned Leave' THEN 'paid' ELSE 'unpaid' END
    WHERE payroll_mode IS NULL OR payroll_mode NOT IN ('paid', 'unpaid')`);
  await db.query('UPDATE hrms_leave_policies SET allow_half_day = 1 WHERE allow_half_day IS NULL');
}
exports.ensure = ensure;
exports.list = async (req, res) => {
  try {
    await ensure();
    const [rows] = await db.query('SELECT * FROM hrms_leave_policies WHERE effective_year = ? ORDER BY id', [new Date().getFullYear()]);
    res.json({success:true, data:rows});
  } catch (_) { res.status(500).json({success:false,message:'Unable to load leave policies.'}); }
};
exports.save = async (req, res) => {
  const b = req.body;
  const n = Number(b.annual_allowance);
  const monthly = Number(b.monthly_allowance || 0);
  if (b.annual_allowance === '' || b.annual_allowance == null || !Number.isFinite(n) || n < 0 || n > 366 || n * 2 !== Math.floor(n * 2)) return res.status(400).json({success:false,message:'Allowance must be between 0 and 366 in half-day increments.'});
  if (!Number.isFinite(monthly) || monthly < 0 || monthly > 31 || monthly * 2 !== Math.floor(monthly * 2)) return res.status(400).json({success:false,message:'Monthly allowance must be between 0 and 31 in half-day increments.'});
  try {
    await ensure();
    const [rows] = await db.query('SELECT id FROM hrms_leave_policies WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({success:false,message:'Leave policy not found.'});
    const visible = b.employee_card_visible === true || b.employee_card_visible === 1 || b.employee_card_visible === '1';
    const displayMode = b.employee_card_display_mode === 'Usage only' ? 'Usage only' : 'Balance & usage';
    const payrollMode = b.payroll_mode === 'paid' ? 'paid' : 'unpaid';
    const allowHalfDay = b.allow_half_day === true || b.allow_half_day === 1 || b.allow_half_day === '1';
    await db.query('UPDATE hrms_leave_policies SET annual_allowance = ?, monthly_allowance = ?, carry_forward = ?, active = ?, employee_card_visible = ?, employee_card_display_mode = ?, payroll_mode = ?, allow_half_day = ? WHERE id = ?', [n, monthly, b.carry_forward === true || b.carry_forward === 1 ? 1 : 0, b.active === true || b.active === 1 ? 1 : 0, visible ? 1 : 0, displayMode, payrollMode, allowHalfDay ? 1 : 0, req.params.id]);
    res.json({success:true});
  } catch (_) { res.status(500).json({success:false,message:'Unable to save leave policy.'}); }
};
