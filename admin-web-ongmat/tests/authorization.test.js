const test = require('node:test');
const assert = require('node:assert/strict');

const { hashPassword, comparePassword } = require('../utils/authHelpers');
const { AppError, asyncHandler, positiveNumber, coordinates, isoDate } = require('../utils/http');
const { ROLES, requireRole } = require('../middleware/auth');

const mockRes = () => {
  const res = { statusCode: 200, body: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; return res; };
  return res;
};

test('hashed passwords verify and legacy plain passwords still work', () => {
  const stored = hashPassword('matkhau123');
  assert.match(stored, /^scrypt\$/);
  assert.equal(comparePassword('matkhau123', stored), true);
  assert.equal(comparePassword('sai-mat-khau', stored), false);
  assert.equal(comparePassword('nuoi123', 'nuoi123'), true);
});

test('requireRole only lets the listed roles through', () => {
  const guard = requireRole(ROLES.CHU_DAT);

  let passed = false;
  guard({ user: { id: 1, vaiTro: ROLES.CHU_DAT } }, mockRes(), () => { passed = true; });
  assert.equal(passed, true);

  const res = mockRes();
  passed = false;
  guard({ user: { id: 2, vaiTro: ROLES.NUOI_ONG } }, res, () => { passed = true; });
  assert.equal(passed, false);
  assert.equal(res.statusCode, 403);
  assert.match(res.body.message, /chủ đất/);
});

test('asyncHandler maps business and database errors to JSON responses', async () => {
  const res = mockRes();
  await asyncHandler(async () => { throw new AppError(409, 'Trùng'); })({}, res);
  assert.equal(res.statusCode, 409);
  assert.deepEqual(res.body, { success: false, message: 'Trùng' });

  const dbRes = mockRes();
  await asyncHandler(async () => { const e = new Error('x'); e.code = 'DB_UNAVAILABLE'; throw e; })({}, dbRes);
  assert.equal(dbRes.statusCode, 503);
});

test('input validators reject invalid business data', () => {
  assert.equal(positiveNumber('12', 'Số thùng', { integer: true }), 12);
  assert.throws(() => positiveNumber('0', 'Số thùng'), /lớn hơn 0/);
  assert.throws(() => positiveNumber('1.5', 'Số thùng', { integer: true }), /số nguyên/);
  assert.deepEqual(coordinates('16.05', '108.2'), { viDo: 16.05, kinhDo: 108.2 });
  assert.throws(() => coordinates(120, 108), /GPS/);
  assert.equal(isoDate('2026-10-12', 'Ngày'), '2026-10-12');
  assert.throws(() => isoDate('12/10/2026', 'Ngày'), /yyyy-mm-dd/);
});
