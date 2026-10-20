const { test } = require('node:test');
const assert = require('node:assert/strict');
const { employeeFilters } = require('../lib/employeeFilters');

test('all selected filters apply together using parameters', () => {
  const filters = employeeFilters({ search: ' okash ', department: 'Employee', status: 'Active', workMode: 'Field' });
  assert.match(filters.clause, /p\.full_name LIKE \?/);
  assert.match(filters.clause, /p\.department = \?/);
  assert.match(filters.clause, /p\.employment_status = \?/);
  assert.match(filters.clause, /p\.work_mode = \?/);
  assert.deepEqual(filters.params, ['%okash%', '%okash%', '%okash%', 'Employee', 'Active', 'Field']);
});

test('default filters include active employee accounts without pagination', () => {
  const filters = employeeFilters({ department: 'All Departments', status: 'All Status', workMode: 'All Work Modes' });
  assert.equal(filters.clause, "WHERE u.user_type = 'employee' AND u.is_active = 1");
  assert.deepEqual(filters.params, []);
});
