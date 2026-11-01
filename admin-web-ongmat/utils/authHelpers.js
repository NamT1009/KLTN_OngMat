const crypto = require('crypto');

const HASH_PREFIX = 'scrypt$';

function normalizeRole(role) {
  return String(role ?? '').trim().toLowerCase();
}

function isAccountActive(status) {
  const normalizedStatus = String(status ?? '').trim();
  return normalizedStatus !== 'DaKhoa';
}

// Định dạng: scrypt$<salt hex>$<hash hex>
function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(String(password ?? '').trim(), salt, 32).toString('hex');
  return `${HASH_PREFIX}${salt}$${hash}`;
}

// Hỗ trợ cả mật khẩu đã băm và mật khẩu dạng thường của các tài khoản cũ.
function comparePassword(inputPassword, storedPassword) {
  const input = String(inputPassword ?? '').trim();
  const stored = String(storedPassword ?? '').trim();

  if (stored.startsWith(HASH_PREFIX)) {
    const [salt, hash] = stored.slice(HASH_PREFIX.length).split('$');
    if (!salt || !hash) return false;
    const expected = Buffer.from(hash, 'hex');
    const actual = crypto.scryptSync(input, salt, expected.length);
    return crypto.timingSafeEqual(expected, actual);
  }

  return input === stored;
}

module.exports = {
  normalizeRole,
  isAccountActive,
  hashPassword,
  comparePassword,
};
