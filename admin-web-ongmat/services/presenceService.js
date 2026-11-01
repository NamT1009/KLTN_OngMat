const { poolPromise, sql } = require('../config/db');

// Lưu trữ trạng thái hoạt động của người dùng trong bộ nhớ RAM
// Map<userId (number), timestamp (number)>
const activeUsers = new Map();

// Ngưỡng xác định trực tuyến: 60 giây (1 phút không có hoạt động -> tính là ngoại tuyến)
const ONLINE_THRESHOLD_MS = 60 * 1000;

// Throttling cập nhật CSDL: chỉ ghi DB tối đa 1 lần mỗi 2 phút cho mỗi người dùng
const dbUpdateThrottles = new Map();
const DB_UPDATE_INTERVAL_MS = 2 * 60 * 1000;

/**
 * Cập nhật thời điểm hoạt động gần nhất của người dùng
 * @param {number|string} userId Mã người dùng
 */
function touchUserOnline(userId) {
    if (!userId) return;
    const uid = Number(userId);
    if (!isNaN(uid) && uid > 0) {
        const now = Date.now();
        activeUsers.set(uid, now);

        // Ghi nhận vào CSDL SQL Server (không chặn luồng chính, có throttle)
        const lastDbUpdate = dbUpdateThrottles.get(uid) || 0;
        if (now - lastDbUpdate > DB_UPDATE_INTERVAL_MS) {
            dbUpdateThrottles.set(uid, now);
            updateDbLastActive(uid).catch(() => {});
        }
    }
}

/**
 * Cập nhật thời gian hoạt động vào bảng nguoiDung trong SQL Server
 */
async function updateDbLastActive(userId) {
    try {
        const pool = await poolPromise;
        if (!pool) return;
        await pool.request()
            .input('uid', sql.Int, userId)
            .query(`
                IF COL_LENGTH('dbo.nguoiDung', 'ngayHoatDongCuoi') IS NOT NULL
                BEGIN
                    UPDATE dbo.nguoiDung
                    SET ngayHoatDongCuoi = GETDATE()
                    WHERE maNguoiDung = @uid;
                END
            `);
    } catch (_) {
        // Bỏ qua lỗi cập nhật DB ngầm
    }
}

/**
 * Đánh dấu người dùng đăng xuất / ngoại tuyến
 */
function setUserOffline(userId) {
    if (!userId) return;
    const uid = Number(userId);
    activeUsers.delete(uid);
    dbUpdateThrottles.delete(uid);
}

/**
 * Kiểm tra xem người dùng có đang trực tuyến không
 * @param {number|string} userId
 * @returns {boolean} true nếu hoạt động trong vòng ONLINE_THRESHOLD_MS
 */
function isUserOnline(userId) {
    if (!userId) return false;
    const uid = Number(userId);
    const lastActive = activeUsers.get(uid);
    if (!lastActive) return false;
    return (Date.now() - lastActive) < ONLINE_THRESHOLD_MS;
}

/**
 * Lấy danh sách ID tất cả người dùng đang online
 */
function getOnlineUserIds() {
    const now = Date.now();
    const list = [];
    for (const [uid, lastActive] of activeUsers.entries()) {
        if (now - lastActive < ONLINE_THRESHOLD_MS) {
            list.push(uid);
        } else {
            // Xóa người dùng quá hạn khỏi Map để giải phóng bộ nhớ
            activeUsers.delete(uid);
        }
    }
    return list;
}

/**
 * Lấy thời gian hoạt động cuối cùng
 */
function getLastActiveTime(userId) {
    if (!userId) return null;
    return activeUsers.get(Number(userId)) || null;
}

// Định kỳ dọn dẹp các user offline sau 10 phút
const cleanupInterval = setInterval(() => {
    const now = Date.now();
    for (const [uid, lastActive] of activeUsers.entries()) {
        if (now - lastActive > 10 * 60 * 1000) {
            activeUsers.delete(uid);
            dbUpdateThrottles.delete(uid);
        }
    }
}, 5 * 60 * 1000);
if (cleanupInterval.unref) cleanupInterval.unref();

module.exports = {
    touchUserOnline,
    setUserOffline,
    isUserOnline,
    getOnlineUserIds,
    getLastActiveTime,
    ONLINE_THRESHOLD_MS
};
