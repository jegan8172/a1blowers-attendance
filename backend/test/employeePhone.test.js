const { test } = require('node:test');
const assert = require('node:assert/strict');
const { normalizePhone } = require('../lib/employeePhone');

test('accepts formatted numbers and treats empty values as unset', () => {
  assert.equal(normalizePhone('  +91 98765 43210  '), '+91 98765 43210');
  assert.equal(normalizePhone('   '), null);
  assert.equal(normalizePhone(null), null);
});

test('rejects non-phone input, non-text values and overlong numbers', () => {
  for (const value of ['hello', '++', '1'.repeat(33), 12345]) {
    assert.throws(() => normalizePhone(value));
  }
});
