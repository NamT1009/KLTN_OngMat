const repository = require('../config/beekeepingRepository');
const { AppError } = require('../utils/http');

// Quản trị viên xem toàn bộ dữ liệu (không lọc theo người dùng).
exports.dashboard = async (req, res) => {
    try {
        const [hives, care, moves, production, notifications, requests, contracts, reviews] = await Promise.all([
            repository.getHives(null), 
            repository.getCare(null), 
            repository.getMoves(null), 
            repository.getProduction(null),
            repository.getNotifications(null), 
            repository.getRentalRequests(), 
            repository.getContracts({ vaiTro: 'admin' }),
            repository.getAllReviews(),
        ]);

        // Lấy thông tin user từ session (từ đăng nhập)
        const currentUser = req.session.user || req.user || null;

        res.render('nguoi-nuoi-ong', {
            path: '/nguoi-nuoi-ong',
            hives, 
            care, 
            moves, 
            production, 
            notifications, 
            requests, 
            contracts,
            reviews,
            user: currentUser // Truyền biến user sang EJS
        });
    } catch (error) {
        console.error('Lỗi tải nghiệp vụ người nuôi ong:', error);
        res.status(500).send('Không thể tải dữ liệu nghiệp vụ người nuôi ong.');
    }
};
// Quản trị viên có thể duyệt thay chủ đất khi cần hỗ trợ.
exports.approveRequest = async (req, res) => {
    try {
        await repository.approveRentalRequest(null, String(req.params.id), req.body || {});
        return res.redirect('/nguoi-nuoi-ong');
    } catch (error) {
        if (error instanceof AppError) return res.status(error.status).send(error.message);
        console.error('Lỗi duyệt yêu cầu:', error);
        return res.status(500).send('Không thể duyệt yêu cầu.');
    }
};
