const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  createEmployeeAtomically,
  assertUniqueForUpdate,
  duplicateMessage,
} = require('../lib/employeeCreationService');

const input = {
  name: 'Asha Kumar', code: 'EMP1001', department: 'Engineering',
  workMode: 'Office', employeeType: 'Employee', overtimeEligible: 0,
  gender: 'Female', status: 'Active', salary: 50000, salaryType: 'Standard',
  cycleStartDay: null, cycleEndDay: null, username: 'asha',
  email: 'asha@example.com', password: 'secure-pass', firstName: 'Asha',
  lastName: 'Kumar', initials: 'AK',
};

function fakePool(responses, calls = []) {
  const connection = {
    beginTransaction: async () => calls.push('begin'),
    commit: async () => calls.push('commit'),
    rollback: async () => calls.push('rollback'),
    release: () => calls.push('release'),
    query: async (sql, params) => {
      calls.push({ sql, params });
      const next = responses.shift();
      if (next instanceof Error) throw next;
      return [next];
    },
  };
  return { getConnection: async () => connection, calls };
}

const bcrypt = { hash: async () => 'hashed-password' };
const noDuplicates = {
  employee_code_exists: 0, email_exists: 0, username_exists: 0, linked_profile_exists: 0,
};
const duplicateRows = (values = noDuplicates) => [values];

async function createWith(pool, overrides = {}) {
  return createEmployeeAtomically({
    pool, bcrypt, input: { ...input, ...overrides }, adminId: 99,
    recordCompensation: async () => {},
  });
}

for (const [field, message] of [
  ['employee_code_exists', 'Employee code already exists'],
  ['email_exists', 'Email already exists'],
  ['username_exists', 'Username already exists'],
  ['linked_profile_exists', 'Employee already exists'],
]) {
  test('rejects duplicate ' + field, async () => {
    const pool = fakePool([duplicateRows({ ...noDuplicates, [field]: 1 })]);
    await assert.rejects(createWith(pool), { message, status: 409 });
    assert.deepEqual(pool.calls.slice(-2), ['rollback', 'release']);
  });
}

test('commits one successful unique employee creation', async () => {
  const pool = fakePool([
    duplicateRows(),
    { insertId: 44 },
    { insertId: 77 },
    [{ id: 77, employee_user_id: 44, employee_code: 'EMP1001' }],
  ]);
  const profile = await createWith(pool);
  assert.equal(profile.id, 77);
  assert.deepEqual(pool.calls.slice(-2), ['commit', 'release']);
});

test('stores the submitted phone in the shared employee profile', async () => {
  const pool = fakePool([duplicateRows(), { insertId: 44 }, { insertId: 77 }, [{ id: 77 }]]);
  await createWith(pool, { phone: '+91 98765 43210' });
  const insert = pool.calls.find((call) => call.sql && call.sql.includes('INSERT INTO hrms_employee_profiles'));
  assert.match(insert.sql, /email, phone, department/);
  assert.equal(insert.params[4], '+91 98765 43210');
});

test('a second Create click is rejected and does not add another employee', async () => {
  const first = fakePool([duplicateRows(), { insertId: 44 }, { insertId: 77 }, [{ id: 77 }]]);
  await createWith(first);
  const second = fakePool([duplicateRows({ ...noDuplicates, username_exists: 1 })]);
  await assert.rejects(createWith(second), { message: 'Username already exists', status: 409 });
  assert.equal(second.calls.filter((call) => typeof call === 'object' && /INSERT INTO/.test(call.sql)).length, 0);
});

test('rolls back the user insert when profile creation fails', async () => {
  const pool = fakePool([
    duplicateRows(),
    { insertId: 44 },
    new Error('profile insert failed'),
  ]);
  await assert.rejects(createWith(pool), /profile insert failed/);
  assert.deepEqual(pool.calls.slice(-2), ['rollback', 'release']);
});

test('rolls back user and profile when a related assignment fails', async () => {
  const pool = fakePool([
    duplicateRows(),
    { insertId: 44 },
    { insertId: 77 },
    [{ id: 77, employee_user_id: 44 }],
  ]);
  await assert.rejects(
    createEmployeeAtomically({
      pool, bcrypt, input, adminId: 99,
      recordCompensation: async () => { throw new Error('compensation insert failed'); },
    }),
    /compensation insert failed/,
  );
  assert.deepEqual(pool.calls.slice(-2), ['rollback', 'release']);
});

test('translates database duplicate constraint errors to an API-safe message', () => {
  assert.equal(duplicateMessage({ code: 'ER_DUP_ENTRY', sqlMessage: "Duplicate entry for key 'uq_employee_users_email'" }), 'Email already exists');
  assert.equal(duplicateMessage({ code: 'ER_DUP_ENTRY', sqlMessage: "Duplicate entry for key 'uq_hrms_profile_code'" }), 'Employee code already exists');
});

test('allows an employee edit that keeps its own code, email and username', async () => {
  const calls = [];
  const connection = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return [[{
        employee_code_exists: 0,
        staff_id_exists: 0,
        email_exists: 0,
        username_exists: 0,
      }]];
    },
  };
  await assertUniqueForUpdate(
    connection,
    { code: 'EMP1115', email: 'gg@example.com', username: 'gg' },
    { profileId: 51, employeeUserId: 99 },
  );
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].params, [
    'EMP1115', 51, 'EMP1115', 99, 'gg@example.com', 99, 'gg', 99,
  ]);
});

test('rejects an employee edit when another employee owns the code', async () => {
  const connection = {
    query: async () => [[{
      employee_code_exists: 1,
      staff_id_exists: 0,
      email_exists: 0,
      username_exists: 0,
    }]],
  };
  await assert.rejects(
    assertUniqueForUpdate(
      connection,
      { code: 'EMP1115', email: 'gg@example.com', username: 'gg' },
      { profileId: 51, employeeUserId: 99 },
    ),
    { message: 'Employee code already exists', status: 409 },
  );
});
