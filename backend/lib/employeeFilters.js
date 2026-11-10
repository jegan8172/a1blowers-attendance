function employeeFilters(query = {}) {
  const search = String(query.search || query.query || '').trim();
  const department = String(query.department || '').trim();
  const status = String(query.status || '').trim();
  const workMode = String(query.workMode || query.work_mode || '').trim();
  const where = ["u.user_type = 'employee'", 'u.is_active = 1'];
  const params = [];
  if (search) {
    where.push('(p.full_name LIKE ? OR p.employee_code LIKE ? OR p.email LIKE ?)');
    const like = '%' + search + '%';
    params.push(like, like, like);
  }
  if (department && department !== 'All Departments') { where.push('p.department = ?'); params.push(department); }
  if (status && status !== 'All Status') { where.push('p.employment_status = ?'); params.push(status); }
  if (workMode && workMode !== 'All Work Modes') { where.push('p.work_mode = ?'); params.push(workMode); }
  return { clause: 'WHERE ' + where.join(' AND '), params };
}
module.exports = { employeeFilters };
