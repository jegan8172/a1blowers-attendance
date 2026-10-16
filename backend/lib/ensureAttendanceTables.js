const fs = require('fs');
const path = require('path');

async function ensureAttendanceTables(db) {
  const sqlPath = path.join(__dirname, '..', 'sql', 'attendance.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');
  const statements = sql.split(/;\s*$/m).map(function (chunk) {
    return chunk.trim();
  }).filter(function (chunk) {
    return chunk && chunk.indexOf('--') !== 0;
  });

  for (var i = 0; i < statements.length; i++) {
    await db.query(statements[i]);
  }

  // CREATE TABLE IF NOT EXISTS does not upgrade an older installation.  Add
  // only missing columns so existing attendance data is preserved.
  const [columns] = await db.query(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'attendance_records'`
  );
  const existing = new Set(columns.map(function (column) {
    return column.COLUMN_NAME;
  }));
  const required = {
    check_in_at: 'DATETIME NULL',
    check_out_at: 'DATETIME NULL',
    attendance_status: "VARCHAR(32) NOT NULL DEFAULT 'absent'",
    session_status: "VARCHAR(32) NOT NULL DEFAULT 'open'",
    check_in_method: 'VARCHAR(32) NULL',
    is_late: 'TINYINT(1) NOT NULL DEFAULT 0',
    working_minutes: 'INT UNSIGNED NOT NULL DEFAULT 0',
    clock_out_reason: 'TEXT NULL',
    tracking_stop_reason: 'TEXT NULL'
  };
  for (const [name, definition] of Object.entries(required)) {
    if (!existing.has(name)) {
      await db.query(`ALTER TABLE attendance_records ADD COLUMN \`${name}\` ${definition}`);
    }
  }

  const [permissionColumns] = await db.query(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'attendance_permission_requests'`
  );
  const permissionExisting = new Set(permissionColumns.map(function (column) {
    return column.COLUMN_NAME;
  }));
  const permissionRequired = {
    permission_start_time: 'TIME NULL',
    permission_end_time: 'TIME NULL',
    salary_mode: 'VARCHAR(16) NULL'
  };
  for (const [name, definition] of Object.entries(permissionRequired)) {
    if (!permissionExisting.has(name)) {
      await db.query(`ALTER TABLE attendance_permission_requests ADD COLUMN \`${name}\` ${definition}`);
    }
  }
}

module.exports = { ensureAttendanceTables: ensureAttendanceTables };
