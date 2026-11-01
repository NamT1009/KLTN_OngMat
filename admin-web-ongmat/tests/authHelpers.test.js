const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeRole,
  isAccountActive,
  comparePassword,
} = require('../utils/authHelpers');

test('normalizeRole lowercases and trims role strings', () => {
  assert.equal(normalizeRole(' ChuDat '), 'chudat');
  assert.equal(normalizeRole('nguoiNuoiOng'), 'nguoinuoiong');
  assert.equal(normalizeRole('ADMIN'), 'admin');
});

test('account is active unless explicitly locked', () => {
  assert.equal(isAccountActive('HoatDong'), true);
  assert.equal(isAccountActive('ChoXacThuc'), true);
  assert.equal(isAccountActive('DaKhoa'), false);
  assert.equal(isAccountActive(null), true);
});

test('password comparison ignores accidental whitespace', () => {
  assert.equal(comparePassword(' 123456 ', '123456'), true);
  assert.equal(comparePassword('123456', '654321'), false);
});
