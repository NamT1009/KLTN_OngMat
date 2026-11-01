const beekeeping = require('../config/beekeepingRepository');
const stats = require('../config/statsRepository');
const { AppError, asyncHandler, positiveNumber, text } = require('../utils/http');

// API công khai cho khách hàng (web & mobile), không cần đăng nhập.

exports.traceJson = asyncHandler(async (req, res) => {
    const id = positiveNumber(String(req.params.id).replace(/^#/, ''), 'Mã lô', { integer: true });
    const trace = await beekeeping.getPublicTrace(id);
    if (!trace) throw new AppError(404, 'Không tìm thấy lô mật với mã này.');
    res.json({ success: true, data: trace });
});

exports.searchProducts = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await stats.searchPublicProducts(text(req.query.q, 200)) });
});

exports.lookupPage = (req, res) => res.render('tra-cuu');

// Quản trị viên trên mobile: thống kê và bản đồ toàn hệ thống.
exports.adminOverview = asyncHandler(async (req, res) => {
    const [summary, map] = await Promise.all([stats.getSystemStats(), stats.getSystemMap()]);
    res.json({ success: true, data: { ...summary, ...map } });
});
