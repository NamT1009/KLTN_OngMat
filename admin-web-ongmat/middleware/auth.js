const jwt = require('jsonwebtoken');
const { sql, poolPromise } = require('../config/db');
const { normalizeRole, isAccountActive } = require('../utils/authHelpers');
const { touchUserOnline } = require('../services/presenceService');

const JWT_SECRET = process.env.JWT_SECRET || 'ongmat_secret_key_2026';

// Vai trò sau khi normalizeRole (chữ thường) để so sánh thống nhất.
const ROLES = {
    ADMIN: 'admin',
    CHU_DAT: 'chudat',
    NUOI_ONG: 'nguoinuoiong',
};

// Đọc lại vai trò/trạng thái từ CSDL để khóa tài khoản hoặc đổi vai trò có hiệu lực ngay,
// cache ngắn để không phải truy vấn ở mọi request.
const ACCOUNT_CACHE_MS = 30 * 1000;
const accountCache = new Map();

async function loadAccount(id) {
    const cached = accountCache.get(id);
    if (cached && cached.expires > Date.now()) return cached.account;

    const pool = await poolPromise;
    if (!pool) return null;
    const result = await pool.request()
        .input('id', sql.Int, id)
        .query('SELECT maNguoiDung, hoTen, vaiTro, trangThaiTaiKhoan FROM nguoiDung WHERE maNguoiDung = @id');
    const account = result.recordset[0] || null;
    accountCache.set(id, { account, expires: Date.now() + ACCOUNT_CACHE_MS });
    return account;
}

function signToken(user) {
    return jwt.sign({ id: user.maNguoiDung, vaiTro: normalizeRole(user.vaiTro) }, JWT_SECRET, { expiresIn: '30d' });
}

// Chấp nhận JWT (mobile) hoặc session của web admin.
async function requireAuth(req, res, next) {
    try {
        let userId = null;
        const header = String(req.headers.authorization || '');
        if (header.startsWith('Bearer ')) {
            try {
                userId = Number(jwt.verify(header.slice(7), JWT_SECRET).id);
            } catch {
                return res.status(401).json({ success: false, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' });
            }
        } else if (req.session?.user?.maNguoiDung) {
            userId = Number(req.session.user.maNguoiDung);
        }

        if (!userId) {
            return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập để tiếp tục.' });
        }

        const account = await loadAccount(userId);
        if (!account) {
            return res.status(401).json({ success: false, message: 'Tài khoản không tồn tại.' });
        }
        if (!isAccountActive(account.trangThaiTaiKhoan)) {
            return res.status(403).json({ success: false, message: 'Tài khoản của bạn đã bị khóa.' });
        }

        req.user = { id: account.maNguoiDung, hoTen: account.hoTen, vaiTro: normalizeRole(account.vaiTro) };
        touchUserOnline(userId);
        return next();
    } catch (error) {
        console.error('Lỗi xác thực:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
}

const ROLE_LABELS = { [ROLES.ADMIN]: 'quản trị viên', [ROLES.CHU_DAT]: 'chủ đất', [ROLES.NUOI_ONG]: 'người nuôi ong' };

function requireRole(...roles) {
    return (req, res, next) => {
        if (req.user && roles.includes(req.user.vaiTro)) return next();
        const allowed = roles.map((role) => ROLE_LABELS[role] || role).join(' hoặc ');
        return res.status(403).json({ success: false, message: `Chức năng này chỉ dành cho ${allowed}.` });
    };
}

module.exports = { ROLES, JWT_SECRET, signToken, requireAuth, requireRole };
