const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function endpoint(rows = []) {
  const queries = [];
  const db = { query: async (sql, params) => {
    assert.match(sql.trim(), /^SELECT\b/i, 'History must never write or regenerate payroll');
    queries.push({ sql, params });
    return [rows];
  } };
  const context = {
    module: { exports: {} }, console,
    require: name => name === '../config/db' ? db : {},
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../controllers/hrmsPayrollController.js'), 'utf8'), context);
  const res = {
    code: 200, body: null,
    status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; },
  };
  return { handler: context.module.exports.deductionHistory, queries, res };
}

test('history returns punch times without changing saved amounts or durations', async () => {
  const rows = [{ attendance_date: '2026-10-22', deduction_type: 'late', late_minutes: 323,
    amount: '437.11', check_in_at: '2026-10-22 09:33:17', check_out_at: '2026-10-22 18:41:22' }];
  const { handler, queries, res } = endpoint(rows);
  await handler({ params: { profileId: '12' }, query: { year: '2026', month: '10' } }, res);
  assert.equal(res.code, 200);
  assert.deepEqual(res.body.data, rows);
  assert.equal(queries.length, 1);
  assert.equal(Array.from(queries[0].params).join(','), '12,2026,10');
  assert.match(queries[0].sql, /a\.employee_id = d\.employee_user_id/);
  assert.match(queries[0].sql, /a\.attendance_date = d\.attendance_date/);
  assert.match(queries[0].sql, /DATE_FORMAT\(MIN\(a\.check_in_at\)/);
  assert.match(queries[0].sql, /DATE_FORMAT\(MAX\(a\.check_out_at\)/);
});

test('history month selection uses the requested payroll key and preserves missing punches', async () => {
  const rows = [{ attendance_date: '2026-09-01', check_in_at: null, check_out_at: null }];
  const { handler, queries, res } = endpoint(rows);
  await handler({ params: { profileId: '12' }, query: { year: '2026', month: '9' } }, res);
  assert.equal(Array.from(queries[0].params).join(','), '12,2026,9');
  assert.equal(res.body.data[0].check_in_at, null);
});

test('invalid month is rejected before querying the database', async () => {
  for (const month of ['0', '13', 'invalid', '1.5']) {
    const { handler, queries, res } = endpoint();
    await handler({ params: { profileId: '12' }, query: { year: '2026', month } }, res);
    assert.equal(res.code, 400);
    assert.equal(queries.length, 0);
  }
});
