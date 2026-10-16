const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createService, localDate, sessionView, monthBounds } = require('./service');

test('local date rolls over at Indian midnight while timestamps stay UTC', () => {
  assert.equal(localDate(new Date('2026-09-05T20:00:00Z'), 'Asia/Kolkata'), '2026-09-06');
  assert.deepEqual(monthBounds('2026-12'), ['2026-12-01', '2027-01-01']);
  for (const invalid of ['2026-13', '2026-1', {}, ['2026-09'], '']) {
    assert.throws(() => monthBounds(invalid), { status: 400 });
  }
});

test('duration supports active, completed and overnight sessions', () => {
  const row = { id: 1, work_date: '2026-09-05', clock_in_at: '2026-09-05 18:00:00.000', clock_out_at: null };
  const now = new Date('2026-09-06T02:20:00Z');
  assert.equal(sessionView(row, now).worked_seconds, 30000);
  assert.equal(sessionView({ ...row, clock_out_at: '2026-09-05 20:00:00.000' }, now).worked_seconds, 7200);
});

function fakePool(responses) {
  const calls = [];
  const connection = {
    beginTransaction: async () => calls.push('begin'),
    commit: async () => calls.push('commit'),
    rollback: async () => calls.push('rollback'),
    release: () => calls.push('release'),
    execute: async (sql, params) => {
      calls.push({ sql, params });
      assert.ok(responses.length, 'unexpected database query');
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return [response];
    },
  };
  return { calls, getConnection: async () => connection, execute: connection.execute };
}
const options = { clock: () => new Date('2026-09-06T02:20:00Z') };

test('clock in derives date and time from server under an employee row lock', async () => {
  const pool = fakePool([[{ id: 7, is_active: 1 }], [], [], { insertId: 20 }, { affectedRows: 1 }]);
  const result = await createService(pool, options).punch(7, 'in');
  assert.equal(result.work_date, '2026-09-06');
  assert.equal(result.clock_in_at, '2026-09-06T02:20:00.000Z');
  assert.match(pool.calls[1].sql, /FOR UPDATE/);
  assert.deepEqual(pool.calls[4].params, [7, '2026-09-06', '2026-09-06 02:20:00.000', 0]);
  assert.deepEqual(pool.calls[5].params.slice(0, 4), [7, '2026-09-06', '2026-09-06 02:20:00.000', null]);
  assert.deepEqual(pool.calls.slice(-2), ['commit', 'release']);
});

test('duplicate clock in rolls back and releases connection', async () => {
  const pool = fakePool([[{ id: 7, is_active: 1 }], [{ id: 20 }]]);
  await assert.rejects(createService(pool, options).punch(7, 'in'), { status: 409 });
  assert.deepEqual(pool.calls.slice(-2), ['rollback', 'release']);
});

test('second daily session and clock out without clock in are rejected', async () => {
  for (const [action, responses] of [
    ['in', [[{ id: 7, is_active: 1 }], [], [{ id: 20 }]]],
    ['out', [[{ id: 7, is_active: 1 }], []]],
  ]) {
    const pool = fakePool(responses);
    await assert.rejects(createService(pool, options).punch(7, action), { status: 409 });
    assert.deepEqual(pool.calls.slice(-2), ['rollback', 'release']);
  }
});

test('clock out closes the previous date session', async () => {
  const pool = fakePool([[{ id: 7, is_active: 1 }], [{ id: 20, work_date: '2026-09-05',
    clock_in_at: '2026-09-05 18:00:00.000', clock_out_at: null }], { affectedRows: 1 }, { affectedRows: 1 }, { affectedRows: 1 }]);
  const result = await createService(pool, options).punch(7, 'out');
  assert.equal(result.work_date, '2026-09-05');
  assert.equal(result.worked_seconds, 30000);
  assert.deepEqual(pool.calls[4].params, ['2026-09-06 02:20:00.000', 20, 7]);
  assert.deepEqual(pool.calls[5].params.slice(0, 4), [7, '2026-09-05', '2026-09-05 18:00:00.000', '2026-09-06 02:20:00.000']);
});

test('inactive employee and database failure roll back', async () => {
  for (const responses of [[[{ id: 7, is_active: 0 }]], [new Error('database failed')]]) {
    const pool = fakePool(responses);
    await assert.rejects(createService(pool, options).punch(7, 'in'));
    assert.deepEqual(pool.calls.slice(-2), ['rollback', 'release']);
  }
});

test('dashboard scopes data to identity and reports unconfigured rules as unavailable', async () => {
  const pool = fakePool([[], [], [{ present_days: '3' }]]);
  const result = await createService(pool, options).dashboard({ id: 7, full_name: 'Employee', staff_id: 'EMP7' });
  assert.equal(result.status, 'not_checked_in');
  assert.equal(result.actions.can_clock_in, true);
  assert.equal(result.month_overview.present_days, 3);
  assert.equal(result.month_overview.absent_days, null);
  assert.equal(result.month_overview.late_days, 0);
  assert.deepEqual(pool.calls[1].params, [7, '2026-09-06', '2026-09-01']);
  assert.deepEqual(pool.calls[2].params, [7, '2026-09-01', '2026-10-01']);
});
