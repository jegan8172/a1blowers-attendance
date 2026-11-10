'use strict';

async function ensureAuthSchema(db) {
  const [columns] = await db.query(
    "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'employee_users' AND COLUMN_NAME = 'is_main_admin'"
  );
  if (!columns.length) {
    try {
      await db.query('ALTER TABLE employee_users ADD COLUMN is_main_admin TINYINT(1) NOT NULL DEFAULT 0');
    } catch (error) {
      // Another server instance may have added the column during startup.
      if (error.code !== 'ER_DUP_FIELDNAME') throw error;
    }
  }
  await db.query(`CREATE TABLE IF NOT EXISTS role_page_access (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    allowed_pages TEXT NOT NULL,
    KEY employee_id (employee_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci`);
}

module.exports = { ensureAuthSchema };
