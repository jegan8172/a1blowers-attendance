function conflict(message) {
  const error = new Error(message);
  error.status = 409;
  error.code = 'EMPLOYEE_DUPLICATE';
  return error;
}

function duplicateMessage(error) {
  if (!error) return null;
  if (error.code === 'EMPLOYEE_DUPLICATE') return error.message;
  if (error.code !== 'ER_DUP_ENTRY') return null;
  const source = String(error.sqlMessage || error.message || '').toLowerCase();
  if (source.includes('username')) return 'Username already exists';
  if (source.includes('email')) return 'Email already exists';
  if (source.includes('employee_code') || source.includes('profile_code') || source.includes('staff_id')) {
    return 'Employee code already exists';
  }
  if (source.includes('employee_user_id')) return 'Employee already exists';
  return 'Employee already exists';
}

async function assertUnique(connection, input) {
  const [[matches]] = await connection.query(
    `SELECT
       EXISTS(SELECT 1 FROM hrms_employee_profiles WHERE LOWER(employee_code) = LOWER(?)) AS employee_code_exists,
       EXISTS(SELECT 1 FROM employee_users WHERE LOWER(email) = LOWER(?)) AS email_exists,
       EXISTS(SELECT 1 FROM employee_users WHERE LOWER(username) = LOWER(?)) AS username_exists,
       EXISTS(
         SELECT 1 FROM hrms_employee_profiles p
         INNER JOIN employee_users u ON u.id = p.employee_user_id
         WHERE LOWER(COALESCE(u.staff_id, '')) = LOWER(?)
       ) AS linked_profile_exists`,
    [input.code, input.email, input.username, input.code]
  );
  if (Number(matches.employee_code_exists)) throw conflict('Employee code already exists');
  if (Number(matches.email_exists)) throw conflict('Email already exists');
  if (Number(matches.username_exists)) throw conflict('Username already exists');
  if (Number(matches.linked_profile_exists)) throw conflict('Employee already exists');
}

async function assertUniqueForUpdate(connection, input, { profileId, employeeUserId }) {
  const [[matches]] = await connection.query(
    `SELECT
       EXISTS(
         SELECT 1 FROM hrms_employee_profiles
         WHERE LOWER(employee_code) = LOWER(?) AND id <> ?
       ) AS employee_code_exists,
       EXISTS(
         SELECT 1 FROM employee_users
         WHERE LOWER(COALESCE(staff_id, '')) = LOWER(?) AND id <> ?
       ) AS staff_id_exists,
       EXISTS(
         SELECT 1 FROM employee_users
         WHERE LOWER(email) = LOWER(?) AND id <> ?
       ) AS email_exists,
       EXISTS(
         SELECT 1 FROM employee_users
         WHERE LOWER(username) = LOWER(?) AND id <> ?
       ) AS username_exists`,
    [
      input.code, profileId,
      input.code, employeeUserId,
      input.email, employeeUserId,
      input.username, employeeUserId
    ]
  );
  if (Number(matches.employee_code_exists) || Number(matches.staff_id_exists)) {
    throw conflict('Employee code already exists');
  }
  if (Number(matches.email_exists)) throw conflict('Email already exists');
  if (Number(matches.username_exists)) throw conflict('Username already exists');
}

async function createEmployeeAtomically({ pool, bcrypt, input, adminId, recordCompensation }) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    await assertUnique(connection, input);

    const hashedPassword = await bcrypt.hash(input.password, 10);
    const [userResult] = await connection.query(
      "INSERT INTO employee_users (first_name, last_name, full_name, email, username, password, role, user_type, is_active, staff_id, initials) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)",
      [input.firstName, input.lastName, input.name, input.email, input.username, hashedPassword, input.employeeType === 'Administrator' ? 'Administrator' : input.department, input.userType || (input.employeeType === 'Administrator' ? 'admin' : 'employee'), input.code, input.initials]
    );
    const [profileResult] = await connection.query(
      'INSERT INTO hrms_employee_profiles (employee_user_id, employee_code, full_name, email, phone, department, designation, work_mode, employee_type, overtime_eligible, gender, employment_status, joining_date, monthly_salary, salary_type, flexible_cycle_start_day, flexible_cycle_end_day, flexible_cycle_start_date, flexible_cycle_end_date, tracking_template_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [userResult.insertId, input.code, input.name, input.email, input.phone || null, input.department, input.designation || null, input.workMode, input.employeeType, input.overtimeEligible, input.gender, input.status, input.joiningDate, input.salary, input.salaryType, input.cycleStartDay, input.cycleEndDay, input.cycleStartDate, input.cycleEndDate, input.trackingTemplateId || null]
    );
    const [[profile]] = await connection.query('SELECT * FROM hrms_employee_profiles WHERE id = ?', [profileResult.insertId]);
    if (!profile) throw new Error('Employee profile could not be created');
    await recordCompensation(profile, input.salary, adminId, connection);
    await connection.commit();
    return profile;
  } catch (error) {
    try { await connection.rollback(); } catch (_) {}
    throw error;
  } finally {
    connection.release();
  }
}

module.exports = {
  assertUnique,
  assertUniqueForUpdate,
  createEmployeeAtomically,
  duplicateMessage
};
