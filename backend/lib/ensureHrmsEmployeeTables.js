const fs = require('fs');
const path = require('path');

async function ensureUniqueIndex(db, table, indexName, columns) {
  const [indexes] = await db.query('SHOW INDEX FROM `' + table + '` WHERE Key_name = ?', [indexName]);
  if (indexes.length) return;
  const columnList = columns.map(function (column) { return '`' + column + '`'; }).join(', ');
  const [duplicates] = await db.query(
    'SELECT ' + columnList + ', COUNT(*) AS duplicate_count FROM `' + table + '` ' +
    'WHERE ' + columns.map(function (column) { return '`' + column + '` IS NOT NULL'; }).join(' AND ') +
    ' GROUP BY ' + columnList + ' HAVING COUNT(*) > 1 LIMIT 1'
  );
  if (duplicates.length) {
    console.warn('Skipping unique index ' + indexName + ' because existing duplicate data must be resolved first.');
    return;
  }
  await db.query('ALTER TABLE `' + table + '` ADD UNIQUE KEY `' + indexName + '` (' + columnList + ')');
}

async function ensureHrmsEmployeeTables(db) {
  const sqlPath = path.join(__dirname, '..', 'sql', 'hrms_employee_profiles.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');
  await db.query(sql);
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN phone VARCHAR(32) NULL AFTER email');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query(
      'ALTER TABLE hrms_employee_profiles ADD COLUMN field_tracking_enabled TINYINT(1) NOT NULL DEFAULT 0 AFTER employment_status'
    );
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN designation VARCHAR(120) NULL AFTER department');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query("ALTER TABLE hrms_employee_profiles ADD COLUMN employee_type ENUM('Employee', 'Labour') NOT NULL DEFAULT 'Employee' AFTER work_mode");
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN overtime_eligible TINYINT(1) NOT NULL DEFAULT 0 AFTER employee_type');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query("ALTER TABLE hrms_employee_profiles ADD COLUMN gender ENUM('Male', 'Female') NOT NULL DEFAULT 'Male' AFTER overtime_eligible");
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN joining_date DATE NULL AFTER employment_status');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  // Existing employee rows predate the explicit joining-date field.  Preserve
  // a meaningful historical date instead of showing a frontend placeholder.
  await db.query('UPDATE hrms_employee_profiles SET joining_date = DATE(created_at) WHERE joining_date IS NULL');
  try {
    await db.query("ALTER TABLE hrms_employee_profiles ADD COLUMN salary_type ENUM('Standard','Flexible') NOT NULL DEFAULT 'Standard' AFTER monthly_salary");
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN flexible_cycle_start_day TINYINT UNSIGNED NULL AFTER salary_type');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN flexible_cycle_end_day TINYINT UNSIGNED NULL AFTER flexible_cycle_start_day');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN flexible_cycle_start_date DATE NULL AFTER flexible_cycle_end_day');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  try {
    await db.query('ALTER TABLE hrms_employee_profiles ADD COLUMN flexible_cycle_end_date DATE NULL AFTER flexible_cycle_start_date');
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }

  await db.query(
    "INSERT INTO hrms_employee_profiles (employee_user_id, employee_code, full_name, email, department, work_mode, employment_status) " +
    "SELECT u.id, COALESCE(NULLIF(u.staff_id, ''), CONCAT('EMP', LPAD(u.id, 4, '0'))), " +
    "COALESCE(NULLIF(u.full_name, ''), CONCAT(u.first_name, ' ', u.last_name)), u.email, " +
    "COALESCE(NULLIF(u.role, ''), 'Engineering'), 'Office', " +
    "CASE WHEN u.is_active = 1 THEN 'Active' ELSE 'Inactive' END " +
    "FROM employee_users u LEFT JOIN hrms_employee_profiles p ON p.employee_user_id = u.id " +
    "WHERE p.id IS NULL AND LOWER(u.user_type) = 'employee' " +
    "AND NOT EXISTS (SELECT 1 FROM hrms_employee_profiles existing WHERE existing.employee_code = COALESCE(NULLIF(u.staff_id, ''), CONCAT('EMP', LPAD(u.id, 4, '0'))))"
  );

  // These constraints back up the application prechecks and make concurrent
  // employee creation safe even when two requests arrive at the same time.
  await ensureUniqueIndex(db, 'employee_users', 'uq_employee_users_email', ['email']);
  await ensureUniqueIndex(db, 'employee_users', 'uq_employee_users_username', ['username']);
  await ensureUniqueIndex(db, 'employee_users', 'uq_employee_users_staff_id', ['staff_id']);
  await ensureUniqueIndex(db, 'hrms_employee_profiles', 'uq_hrms_profile_user', ['employee_user_id']);
  await ensureUniqueIndex(db, 'hrms_employee_profiles', 'uq_hrms_profile_code', ['employee_code']);
}

module.exports = { ensureHrmsEmployeeTables: ensureHrmsEmployeeTables };
