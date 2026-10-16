async function ensureHrmsTrackingTables(db) {
  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_tracking_settings (
      id TINYINT PRIMARY KEY,
      office_name VARCHAR(120) NOT NULL,
      office_address VARCHAR(500) NOT NULL,
      office_latitude DECIMAL(10,7) NOT NULL,
      office_longitude DECIMAL(10,7) NOT NULL,
      office_radius_meters INT NOT NULL DEFAULT 100,
      field_ping_interval_minutes INT NOT NULL DEFAULT 15,
      field_waiting_minutes INT NOT NULL DEFAULT 60,
      popup_alert_repeat_seconds INT NOT NULL DEFAULT 5,
      auto_clock_out_enabled TINYINT(1) NOT NULL DEFAULT 0,
      auto_clock_out_confirmation_minutes INT NOT NULL DEFAULT 3,
      auto_clock_out_warning_seconds INT NOT NULL DEFAULT 60,
      auto_clock_out_boundary_buffer_meters INT NOT NULL DEFAULT 50,
      auto_clock_out_snooze_minutes INT NOT NULL DEFAULT 15,
      clock_out_reminder_enabled TINYINT(1) NOT NULL DEFAULT 1,
      clock_out_reminder_threshold_minutes INT NOT NULL DEFAULT 15,
      clock_out_reminder_repeat_minutes INT NOT NULL DEFAULT 15,
      clock_out_reminder_sound VARCHAR(120) NOT NULL DEFAULT 'notification.mp3',
      clock_out_reminder_updated_at DATETIME NULL,
      lunch_break_limit_minutes INT NOT NULL DEFAULT 70,
      stationary_radius_meters INT NOT NULL DEFAULT 50,
      updated_by INT NULL,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);

  const [settingsColumns] = await db.query(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hrms_tracking_settings'`
  );
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'lunch_break_limit_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN lunch_break_limit_minutes INT NOT NULL DEFAULT 70');
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'labour_lunch_break_limit_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN labour_lunch_break_limit_minutes INT NOT NULL DEFAULT 70');
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'employee_lunch_break_limit_minutes')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN employee_lunch_break_limit_minutes INT NOT NULL DEFAULT 70');
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'labour_lunch_start')) {
    await db.query("ALTER TABLE hrms_tracking_settings ADD COLUMN labour_lunch_start TIME NOT NULL DEFAULT '12:30:00'");
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'labour_lunch_end')) {
    await db.query("ALTER TABLE hrms_tracking_settings ADD COLUMN labour_lunch_end TIME NOT NULL DEFAULT '13:00:00'");
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'employee_lunch_start')) {
    await db.query("ALTER TABLE hrms_tracking_settings ADD COLUMN employee_lunch_start TIME NOT NULL DEFAULT '12:30:00'");
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'employee_lunch_end')) {
    await db.query("ALTER TABLE hrms_tracking_settings ADD COLUMN employee_lunch_end TIME NOT NULL DEFAULT '13:00:00'");
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'home_tracking_enabled')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN home_tracking_enabled TINYINT(1) NOT NULL DEFAULT 0');
  }
  if (!settingsColumns.some((column) => column.COLUMN_NAME === 'popup_alert_repeat_seconds')) {
    await db.query('ALTER TABLE hrms_tracking_settings ADD COLUMN popup_alert_repeat_seconds INT NOT NULL DEFAULT 5');
  }
  for (const [name, definition] of [
    ['auto_clock_out_enabled', 'TINYINT(1) NOT NULL DEFAULT 0'],
    ['auto_clock_out_confirmation_minutes', 'INT NOT NULL DEFAULT 3'],
    ['auto_clock_out_warning_seconds', 'INT NOT NULL DEFAULT 60'],
    ['auto_clock_out_boundary_buffer_meters', 'INT NOT NULL DEFAULT 50'],
    ['auto_clock_out_snooze_minutes', 'INT NOT NULL DEFAULT 15'],
    ['clock_out_reminder_enabled', 'TINYINT(1) NOT NULL DEFAULT 1'],
    ['clock_out_reminder_threshold_minutes', 'INT NOT NULL DEFAULT 15'],
    ['clock_out_reminder_repeat_minutes', 'INT NOT NULL DEFAULT 15'],
    ['clock_out_reminder_sound', "VARCHAR(120) NOT NULL DEFAULT 'notification.mp3'"],
    ['clock_out_reminder_updated_at', 'DATETIME NULL'],
  ]) {
    if (!settingsColumns.some((column) => column.COLUMN_NAME === name)) {
      await db.query(`ALTER TABLE hrms_tracking_settings ADD COLUMN ${name} ${definition}`);
    }
  }

  // Seed only after old installations have received every new column above.
  // INSERT IGNORE still validates its column list, so doing this earlier would
  // prevent the migration itself from running on an existing database.
  await db.query(`
    INSERT IGNORE INTO hrms_tracking_settings (
      id, office_name, office_address, office_latitude, office_longitude,
      office_radius_meters, field_ping_interval_minutes,
      field_waiting_minutes, popup_alert_repeat_seconds,
      lunch_break_limit_minutes, stationary_radius_meters
    ) VALUES (1, 'Main Office', 'Configure this address in Admin > Tracking',
      12.8542438, 80.0699862, 100, 15, 60, 5, 70, 50)
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_employee_location_status (
      employee_user_id INT PRIMARY KEY,
      status ENUM('office','home','field') NOT NULL DEFAULT 'office',
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_location_pings (
      id INT AUTO_INCREMENT PRIMARY KEY,
      employee_user_id INT NOT NULL,
      latitude DECIMAL(10,7) NOT NULL,
      longitude DECIMAL(10,7) NOT NULL,
      accuracy_meters DECIMAL(6,1) NULL,
      address VARCHAR(255) NULL,
      recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_employee_recorded (employee_user_id, recorded_at)
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_field_tracking_sessions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      employee_user_id INT NOT NULL,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      stopped_at DATETIME NULL,
      start_latitude DECIMAL(10,7) NULL,
      start_longitude DECIMAL(10,7) NULL,
      stop_latitude DECIMAL(10,7) NULL,
      stop_longitude DECIMAL(10,7) NULL,
      stop_reason TEXT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_field_employee (employee_user_id, is_active)
    )
  `);

  const [fieldSessionColumns] = await db.query(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hrms_field_tracking_sessions'`
  );
  if (!fieldSessionColumns.some((column) => column.COLUMN_NAME === 'stop_reason')) {
    await db.query('ALTER TABLE hrms_field_tracking_sessions ADD COLUMN stop_reason TEXT NULL');
  }

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_field_waiting_reasons (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      field_session_id BIGINT UNSIGNED NOT NULL,
      employee_user_id INT NOT NULL,
      latitude DECIMAL(10,7) NULL,
      longitude DECIMAL(10,7) NULL,
      waiting_started_at DATETIME NOT NULL,
      waiting_detected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      waiting_minutes INT NOT NULL DEFAULT 0,
      event_key VARCHAR(180) NOT NULL,
      reason TEXT NULL,
      reason_submitted_at DATETIME NULL,
      review_status ENUM('pending','reviewed') NOT NULL DEFAULT 'pending',
      reviewed_by INT NULL,
      reviewed_at DATETIME NULL,
      UNIQUE KEY uq_field_waiting_event (event_key),
      INDEX idx_waiting_employee (employee_user_id, review_status),
      INDEX idx_waiting_session (field_session_id)
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_auto_clockout_audit (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      employee_user_id INT NOT NULL,
      attendance_id BIGINT NULL,
      event_type VARCHAR(40) NOT NULL,
      latitude DECIMAL(10,7) NULL,
      longitude DECIMAL(10,7) NULL,
      accuracy_meters DECIMAL(6,1) NULL,
      distance_meters DECIMAL(10,2) NULL,
      details TEXT NULL,
      occurred_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_auto_clockout_employee (employee_user_id, occurred_at),
      INDEX idx_auto_clockout_attendance (attendance_id, occurred_at)
    )
  `);

  // A slot is deterministic for an attendance record. The unique key makes
  // scheduler retries and concurrent API polling harmless.
  await db.query(`
    CREATE TABLE IF NOT EXISTS hrms_clock_out_reminder_events (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
      employee_user_id INT NOT NULL,
      attendance_id BIGINT NOT NULL,
      attendance_date DATE NOT NULL,
      reminder_type VARCHAR(40) NOT NULL DEFAULT 'clock_out',
      reminder_slot INT NOT NULL,
      event_status ENUM('pending','responded','expired','cancelled') NOT NULL DEFAULT 'pending',
      response ENUM('still_working','clock_out_now','snooze') NULL,
      snoozed_until DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      responded_at DATETIME NULL,
      UNIQUE KEY uq_clock_out_reminder_slot (employee_user_id, attendance_id, reminder_slot),
      INDEX idx_clock_out_reminder_pending (employee_user_id, event_status, created_at),
      INDEX idx_clock_out_reminder_attendance (attendance_id, created_at)
    )
  `);

  // Attendance rows keep the small amount of server-owned state needed to
  // require two consecutive fixes and a warning response without trusting a
  // client timer.
  for (const [name, definition] of [
    ['auto_clockout_outside_count', 'INT NOT NULL DEFAULT 0'],
    ['auto_clockout_last_latitude', 'DECIMAL(10,7) NULL'],
    ['auto_clockout_last_longitude', 'DECIMAL(10,7) NULL'],
    ['auto_clockout_last_accuracy', 'DECIMAL(6,1) NULL'],
    ['auto_clockout_last_fix_at', 'DATETIME NULL'],
    ['auto_clockout_warning_at', 'DATETIME NULL'],
    ['auto_clockout_snoozed_until', 'DATETIME NULL'],
  ]) {
    const [columns] = await db.query(`SHOW COLUMNS FROM attendance_records LIKE '${name}'`);
    if (!columns.length) await db.query(`ALTER TABLE attendance_records ADD COLUMN ${name} ${definition}`);
  }
}

module.exports = { ensureHrmsTrackingTables };
