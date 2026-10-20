const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { createApp } = require('./app');
const secret = 'isolated-attendance-test-secret';

async function withApp(pool, callback) {
  const app = createApp({ pool, jwtSecret: secret });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  try { await callback(`http://127.0.0.1:${server.address().port}`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}

test('missing, invalid and expired tokens cannot query the database', async () => {
  await withApp({ execute: async () => assert.fail('unauthorized DB access') }, async base => {
    for (const token of ['', 'invalid', jwt.sign({ id: 7 }, secret, { expiresIn: -1 }),
      jwt.sign({ id: 7 }, 'wrong-secret')]) {
      const result = await fetch(base + '/api/attendance/dashboard', {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      assert.equal(result.status, 401);
    }
  });
});

test('dashboard uses JWT identity even when request supplies a different employee', async () => {
  const ids = [];
  const pool = { execute: async (sql, params) => {
    ids.push(params[0]);
    if (sql.includes('employee_users')) return [[{ id: 7, full_name: 'Employee', staff_id: 'EMP7', is_active: 1 }]];
    if (sql.includes('COUNT')) return [[{ present_days: 0 }]];
    return [[]];
  } };
  await withApp(pool, async base => {
    const response = await fetch(base + '/api/attendance/dashboard?employee_id=999', {
      headers: { Authorization: `Bearer ${jwt.sign({ id: 7 }, secret)}` },
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await response.json()).data.employee.id, 7);
    assert.deepEqual(ids, [7, 7, 7, 7]);
  });
});

test('inactive users are denied and invalid months fail validation', async () => {
  let active = 0;
  const pool = { execute: async () => [[{ id: 7, is_active: active }]] };
  await withApp(pool, async base => {
    const headers = { Authorization: `Bearer ${jwt.sign({ id: 7 }, secret)}` };
    assert.equal((await fetch(base + '/api/attendance/dashboard', { headers })).status, 403);
    active = 1;
    assert.equal((await fetch(base + '/api/attendance/dashboard?month=2026-13', { headers })).status, 400);
  });
});

test('attendance mounts under the existing API without intercepting unrelated routes', async () => {
  const express = require('express');
  const parent = express();
  parent.use('/api/attendance', createApp({ jwtSecret: secret, basePath: '',
    pool: { execute: async (sql) => {
      if (sql.includes('employee_users')) return [[{ id: 7, full_name: 'Employee', staff_id: 'EMP7', is_active: 1 }]];
      return sql.includes('COUNT') ? [[{ present_days: 0 }]] : [[]];
    } },
  }));
  parent.get('/api/unrelated', (req, res) => res.json({ intact: true }));
  const server = parent.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(base + '/api/attendance/dashboard', {
      headers: { Authorization: `Bearer ${jwt.sign({ id: 7 }, secret)}` },
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).data.employee.id, 7);
    assert.deepEqual(await (await fetch(base + '/api/unrelated')).json(), { intact: true });
  } finally { await new Promise(resolve => server.close(resolve)); }
});
