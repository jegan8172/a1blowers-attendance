'use strict';

// A weekly-off assignment is historical data.  Never overwrite a previous
// assignment: a new effective date creates a new row, which keeps old
// attendance and unpaid payroll calculations reproducible.
async function ensureWeeklyOffTemplateTables(db) {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_weekly_off_templates (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    weekly_off_days JSON NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_weekly_off_template_name (name)
  )`);
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_employee_weekly_off_assignments (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    profile_id BIGINT UNSIGNED NOT NULL,
    template_id BIGINT UNSIGNED NOT NULL,
    weekly_off_days_snapshot JSON NULL,
    effective_from DATE NOT NULL,
    assigned_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_employee_weekly_off_effective (profile_id, effective_from),
    KEY employee_weekly_off_lookup (profile_id, effective_from),
    KEY template_weekly_off_lookup (template_id)
  )`);
  try { await db.query('ALTER TABLE hrms_employee_weekly_off_assignments ADD COLUMN weekly_off_days_snapshot JSON NULL AFTER template_id'); } catch (error) { if (error.code !== 'ER_DUP_FIELDNAME') throw error; }
}

function normalizeDays(value) {
  const source = Array.isArray(value) ? value : [];
  const days = [...new Set(source.map(Number).filter((day) => Number.isInteger(day) && day >= 0 && day <= 6))].sort();
  if (!days.length) throw Object.assign(new Error('Select at least one weekly off day.'), { status: 400 });
  return days;
}

function parseDays(value, fallback) {
  try {
    // mysql2 can return a JSON column either as a string or as a decoded
    // JavaScript array depending on the connection configuration.
    const source = Array.isArray(value)
      ? value
      : JSON.parse(Buffer.isBuffer(value) ? value.toString('utf8') : (value || '[]'));
    const result = source;
    return normalizeDays(result);
  } catch (_) {
    return Array.isArray(fallback) && fallback.length ? fallback : [0];
  }
}

// Returns a Map keyed by profile id.  Each value is the weekly-off day Set
// effective on the requested date; the global Payroll Policy stays the safe
// fallback for employees with no assignment.
async function offDaysForProfiles(db, profileIds, date, globalFallback) {
  const fallback = new Set(globalFallback && globalFallback.length ? globalFallback.map(Number) : [0]);
  const output = new Map();
  const ids = [...new Set((profileIds || []).map(Number).filter(Number.isInteger))];
  ids.forEach((id) => output.set(id, new Set(fallback)));
  if (!ids.length) return output;
  await ensureWeeklyOffTemplateTables(db);
  const [rows] = await db.query(
    `SELECT a.profile_id, a.weekly_off_days_snapshot, t.weekly_off_days
       FROM hrms_employee_weekly_off_assignments a
       INNER JOIN hrms_weekly_off_templates t ON t.id = a.template_id
      WHERE a.profile_id IN (?) AND a.effective_from <= ?
      ORDER BY a.profile_id ASC, a.effective_from DESC, a.id DESC`,
    [ids, date]
  );
  const resolved = new Set();
  rows.forEach((row) => {
    const id = Number(row.profile_id);
    if (!resolved.has(id)) {
      output.set(id, new Set(parseDays(row.weekly_off_days_snapshot || row.weekly_off_days, [...fallback])));
      resolved.add(id);
    }
  });
  return output;
}

async function offDaysForProfileByDate(db, profileId, start, end, globalFallback) {
  await ensureWeeklyOffTemplateTables(db);
  const fallback = globalFallback && globalFallback.length ? globalFallback.map(Number) : [0];
  const [rows] = await db.query(
    `SELECT DATE_FORMAT(a.effective_from, '%Y-%m-%d') AS effective_from,
            a.weekly_off_days_snapshot, t.weekly_off_days
       FROM hrms_employee_weekly_off_assignments a
       INNER JOIN hrms_weekly_off_templates t ON t.id = a.template_id
      WHERE a.profile_id = ? AND a.effective_from <= ?
      ORDER BY a.effective_from ASC, a.id ASC`,
    [profileId, end]
  );
  const assignments = rows.map((row) => ({
    effectiveFrom: String(row.effective_from).slice(0, 10),
    days: parseDays(row.weekly_off_days_snapshot || row.weekly_off_days, fallback),
  }));
  function forDate(date) {
    let chosen = fallback;
    assignments.forEach((assignment) => { if (assignment.effectiveFrom <= date) chosen = assignment.days; });
    return new Set(chosen);
  }
  return { forDate, assignments };
}

function hasAssignmentForDate(resolver, date) {
  return Boolean(resolver && resolver.assignments && resolver.assignments.some((assignment) => assignment.effectiveFrom <= date));
}

module.exports = { ensureWeeklyOffTemplateTables, normalizeDays, parseDays, offDaysForProfiles, offDaysForProfileByDate, hasAssignmentForDate };
