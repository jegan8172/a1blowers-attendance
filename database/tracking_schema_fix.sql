-- Apply this once only to an already-created godigital_attendance database.
ALTER TABLE hrms_field_tracking_sessions
  MODIFY employee_id INT NULL,
  ADD COLUMN employee_user_id INT NULL AFTER employee_id,
  ADD COLUMN is_active TINYINT(1) NOT NULL DEFAULT 1 AFTER employee_user_id,
  ADD COLUMN stopped_at DATETIME NULL AFTER started_at,
  ADD COLUMN start_latitude DECIMAL(10,7) NULL,
  ADD COLUMN start_longitude DECIMAL(10,7) NULL,
  ADD COLUMN stop_latitude DECIMAL(10,7) NULL,
  ADD COLUMN stop_longitude DECIMAL(10,7) NULL;

CREATE INDEX idx_field_employee_user_active
  ON hrms_field_tracking_sessions (employee_user_id, is_active);
 
CREATE TABLE IF NOT EXISTS hrms_employee_home_locations (
  employee_user_id INT NOT NULL PRIMARY KEY,
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  address VARCHAR(500) NULL,
  approval_status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_by INT NULL,
  reviewed_at DATETIME NULL,
  rejection_reason VARCHAR(500) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
