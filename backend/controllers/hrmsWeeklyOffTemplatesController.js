'use strict';

const db = require('../config/db');
const templates = require('../lib/weeklyOffTemplates');

function ok(res, data, message) { return res.json({ success: true, message: message || 'OK', data }); }
function fail(res, status, message) { return res.status(status).json({ success: false, message }); }
function requireAdmin(req, res, next) {
  if (String(req.user && req.user.userType || '').toLowerCase() !== 'admin') return fail(res, 403, 'Admin access required');
  return next();
}
function dateOnly(value) {
  const date = String(value || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw Object.assign(new Error('A valid effective date is required.'), { status: 400 });
  return date;
}
function toTemplate(row) {
  return { id: Number(row.id), name: row.name, weeklyOffDays: templates.parseDays(row.weekly_off_days, [0]), active: Number(row.is_active) === 1, createdAt: row.created_at, updatedAt: row.updated_at };
}

async function list(req, res) {
  try {
    await templates.ensureWeeklyOffTemplateTables(db);
    const [rows] = await db.query('SELECT * FROM hrms_weekly_off_templates ORDER BY is_active DESC, name ASC');
    const [assignments] = await db.query(`SELECT a.id, a.profile_id AS profileId, a.template_id AS templateId,
       DATE_FORMAT(a.effective_from, '%Y-%m-%d') AS effectiveFrom, a.created_at AS assignedAt,
       p.full_name AS employeeName, p.employee_code AS employeeCode, t.name AS templateName
       FROM hrms_employee_weekly_off_assignments a
       JOIN hrms_employee_profiles p ON p.id = a.profile_id
       JOIN hrms_weekly_off_templates t ON t.id = a.template_id
       ORDER BY a.effective_from DESC, a.id DESC`);
    return ok(res, { templates: rows.map(toTemplate), assignments });
  } catch (error) { return fail(res, 500, error.message); }
}

async function create(req, res) {
  try {
    await templates.ensureWeeklyOffTemplateTables(db);
    const name = String(req.body && req.body.name || '').trim().slice(0, 100);
    const days = templates.normalizeDays(req.body && req.body.weeklyOffDays);
    if (!name) return fail(res, 400, 'Template name is required.');
    const [result] = await db.query('INSERT INTO hrms_weekly_off_templates (name, weekly_off_days, created_by) VALUES (?, ?, ?)', [name, JSON.stringify(days), req.user.id]);
    const [rows] = await db.query('SELECT * FROM hrms_weekly_off_templates WHERE id = ?', [result.insertId]);
    return ok(res, { template: toTemplate(rows[0]) }, 'Weekly off template created');
  } catch (error) { return fail(res, error.code === 'ER_DUP_ENTRY' ? 409 : (error.status || 400), error.code === 'ER_DUP_ENTRY' ? 'A template with this name already exists.' : error.message); }
}

async function update(req, res) {
  try {
    await templates.ensureWeeklyOffTemplateTables(db);
    const id = Number(req.params.id);
    const name = String(req.body && req.body.name || '').trim().slice(0, 100);
    const days = templates.normalizeDays(req.body && req.body.weeklyOffDays);
    const active = req.body && req.body.active === false ? 0 : 1;
    if (!Number.isInteger(id) || id < 1 || !name) return fail(res, 400, 'Template name is required.');
    const [result] = await db.query('UPDATE hrms_weekly_off_templates SET name = ?, weekly_off_days = ?, is_active = ? WHERE id = ?', [name, JSON.stringify(days), active, id]);
    if (!result.affectedRows) return fail(res, 404, 'Template not found.');
    const [rows] = await db.query('SELECT * FROM hrms_weekly_off_templates WHERE id = ?', [id]);
    return ok(res, { template: toTemplate(rows[0]) }, 'Weekly off template updated');
  } catch (error) { return fail(res, error.code === 'ER_DUP_ENTRY' ? 409 : (error.status || 400), error.code === 'ER_DUP_ENTRY' ? 'A template with this name already exists.' : error.message); }
}

async function assign(req, res) {
  try {
    await templates.ensureWeeklyOffTemplateTables(db);
    const profileId = Number(req.body && req.body.profileId);
    const templateId = Number(req.body && req.body.templateId);
    const effectiveFrom = dateOnly(req.body && req.body.effectiveFrom);
    if (!Number.isInteger(profileId) || profileId < 1 || !Number.isInteger(templateId) || templateId < 1) return fail(res, 400, 'Employee and template are required.');
    const connection = await db.getConnection();
    try {
      await connection.beginTransaction();
      const [profiles] = await connection.query('SELECT id FROM hrms_employee_profiles WHERE id = ? FOR UPDATE', [profileId]);
      const [templateRows] = await connection.query('SELECT id, weekly_off_days FROM hrms_weekly_off_templates WHERE id = ? AND is_active = 1', [templateId]);
      if (!profiles.length || !templateRows.length) throw Object.assign(new Error(!profiles.length ? 'Employee not found.' : 'Select an active template.'), { status: 404 });
      await connection.query(`INSERT INTO hrms_employee_weekly_off_assignments (profile_id, template_id, weekly_off_days_snapshot, effective_from, assigned_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE template_id = VALUES(template_id), weekly_off_days_snapshot = VALUES(weekly_off_days_snapshot), assigned_by = VALUES(assigned_by), created_at = CURRENT_TIMESTAMP`, [profileId, templateId, templateRows[0].weekly_off_days, effectiveFrom, req.user.id]);
      await connection.commit();
    } catch (error) { await connection.rollback(); throw error; } finally { connection.release(); }
    return ok(res, { profileId, templateId, effectiveFrom }, 'Weekly off template assigned. Past assignments are retained.');
  } catch (error) { return fail(res, error.status || 400, error.message); }
}

module.exports = { requireAdmin, list, create, update, assign };
