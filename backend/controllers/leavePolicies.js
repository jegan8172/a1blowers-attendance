const db = require('../config/db');
async function ensure() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_leave_policies (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, leave_type VARCHAR(80) NOT NULL,
    annual_allowance DECIMAL(8,2) NOT NULL DEFAULT 0, carry_forward TINYINT(1) NOT NULL DEFAULT 0,
    effective_year INT NOT NULL, active TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uniq_leave_policy_year (leave_type, effective_year))`);

  const year = new Date().getFullYear();
  await db.query(
    `INSERT IGNORE INTO hrms_leave_policies
       (leave_type, annual_allowance, carry_forward, effective_year, active)
     VALUES
       ('Casual Leave', 12, 0, ?, 1),
       ('Sick Leave', 8, 0, ?, 1),
       ('Earned Leave', 18, 1, ?, 1),
       ('Optional Holiday', 3, 0, ?, 1)`,
    [year, year, year, year],
  );
}
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
  if (b.annual_allowance === '' || b.annual_allowance == null || !Number.isFinite(n) || n < 0 || n > 366 || n * 2 !== Math.floor(n * 2)) return res.status(400).json({success:false,message:'Allowance must be between 0 and 366 in half-day increments.'});
  try {
    await ensure();
    const [rows] = await db.query('SELECT id FROM hrms_leave_policies WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({success:false,message:'Leave policy not found.'});
    await db.query('UPDATE hrms_leave_policies SET annual_allowance = ?, carry_forward = ?, active = ? WHERE id = ?', [n, b.carry_forward === true || b.carry_forward === 1 ? 1 : 0, b.active === true || b.active === 1 ? 1 : 0, req.params.id]);
    res.json({success:true});
  } catch (_) { res.status(500).json({success:false,message:'Unable to save leave policy.'}); }
};
