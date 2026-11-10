-- Select the SAME database used by the existing backend before running this.
-- Additive migration only. No existing tables or records are changed.
CREATE TABLE IF NOT EXISTS hrms_attendance_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  employee_id INT NOT NULL,
  work_date DATE NOT NULL,
  clock_in_at DATETIME(3) NOT NULL COMMENT 'UTC',
  clock_out_at DATETIME(3) NULL COMMENT 'UTC',
  PRIMARY KEY (id),
  UNIQUE KEY uq_hrms_attendance_employee_day (employee_id, work_date)
) ENGINE=InnoDB;
