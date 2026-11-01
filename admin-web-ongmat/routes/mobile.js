const express = require('express');
const { ROLES, requireAuth, requireRole } = require('../middleware/auth');
const shared = require('../controllers/sharedController');
const beekeeper = require('../controllers/beekeeperController');
const landowner = require('../controllers/landownerController');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Đảm bảo thư mục lưu avatar tồn tại
const uploadDir = path.join(__dirname, '../uploads/avatars');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// Cấu hình nơi lưu và cách đặt tên file
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, uploadDir);
    },
    filename: function (req, file, cb) {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, 'avatar-' + uniqueSuffix + ext);
    }
});

// Bộ lọc định dạng ảnh
const fileFilter = (req, file, cb) => {
    const isImageMime = file.mimetype && file.mimetype.startsWith('image/');
    const isImageExt = /\.(jpg|jpeg|png|gif|webp)$/i.test(file.originalname);

    if (isImageMime || isImageExt) {
        cb(null, true);
    } else {
        cb(new Error('Chỉ chấp nhận file hình ảnh!'), false);
    }
};

const uploadAvatar = multer({
    storage: storage,
    limits: { fileSize: 5 * 1024 * 1024 }, // Giới hạn 5MB
    fileFilter: fileFilter
});
// Mọi API mobile đều yêu cầu đăng nhập (JWT); từng nhóm được giới hạn theo vai trò.
const router = express.Router();
router.use(requireAuth);

// ----- Dùng chung cho mọi vai trò đã đăng nhập -----
router.get('/catalog/species', shared.getCatalogSpecies);
router.get('/catalog/flowers', shared.getCatalogFlowers);
router.get('/catalog/bees', shared.getCatalogBees);
router.get('/profile', shared.profile);
router.get('/notifications', shared.notifications);
router.put('/notifications/read', shared.markNotificationsRead);
router.get('/contracts', shared.contracts);
router.get('/contracts/:id', shared.contractDetail);
router.post('/contracts/:id/otp', requireRole(ROLES.NUOI_ONG), shared.requestContractOtp);
router.put('/contracts/:id/sign', requireRole(ROLES.NUOI_ONG), shared.signContract);
router.put('/contracts/:id/complete', shared.completeContract);
router.post('/contracts/:id/complete', shared.completeContract);
router.post('/contracts/:id/review', shared.submitReview);
router.put('/contracts/:id/review', shared.submitReview);
router.get('/contracts/:id/reviews', shared.getContractReviews);
// Cho phép cả người nuôi ong, chủ đất và admin xem vị trí địa điểm trên bản đồ
router.get('/beekeeping/locations', requireRole(ROLES.NUOI_ONG, ROLES.CHU_DAT, ROLES.ADMIN), beekeeper.availableLocations);

// ----- Người nuôi ong -----
const bk = express.Router();
bk.use(requireRole(ROLES.NUOI_ONG));
bk.get('/dashboard', beekeeper.dashboard);
bk.get('/hives', beekeeper.listHives);
bk.post('/hives', beekeeper.createHive);
bk.put('/hives/:id', beekeeper.updateHive);
bk.delete('/hives/:id', beekeeper.deleteHive);
bk.put('/hives/:id/location', beekeeper.updateLocation);
bk.get('/hives/:id/gps-history', beekeeper.gpsHistory);
bk.post('/location', beekeeper.updateLocation); // tương thích bản app cũ
bk.get('/rented-locations', beekeeper.listRentedLocations);
bk.get('/care-schedule', beekeeper.listCare);
bk.post('/care-log', beekeeper.createCare);
bk.put('/care-log/:id/status', beekeeper.updateCareStatus);
bk.delete('/care-log/:id', beekeeper.deleteCare);
bk.get('/movement', beekeeper.listMoves);
bk.post('/move', beekeeper.createMove);
bk.put('/move/:id/status', beekeeper.updateMoveStatus);
bk.get('/production', beekeeper.listProduction);
bk.post('/production', beekeeper.createProduction);
bk.get('/traces', beekeeper.listTraces);
bk.get('/locations', beekeeper.availableLocations);
bk.get('/rental-requests', beekeeper.listRequests);
bk.post('/rental-requests', beekeeper.createRequest);
bk.put('/rental-requests/:id/cancel', beekeeper.cancelRequest);
router.use('/beekeeping', bk);

// ----- Chủ đất -----
const lo = express.Router();
lo.use(requireRole(ROLES.CHU_DAT));
lo.get('/dashboard', landowner.dashboard);
lo.get('/locations', landowner.listLocations);
lo.post('/locations', landowner.createLocation);
lo.put('/locations/:id', landowner.updateLocation);
lo.delete('/locations/:id', landowner.deleteLocation);
lo.get('/rental-requests', landowner.listRequests);
lo.put('/rental-requests/:id/approve', landowner.approveRequest);
lo.put('/rental-requests/:id/reject', landowner.rejectRequest);
lo.get('/hives', landowner.hivesOnLand);
lo.get('/production', landowner.productionOnLand);
router.use('/landowner', lo);

// ----- Quản trị viên (theo dõi nhanh trên mobile) -----
router.get('/admin/overview', requireRole(ROLES.ADMIN), require('../controllers/publicController').adminOverview);
// ----- Dùng chung cho mọi vai trò đã đăng nhập -----
router.get('/profile', shared.profile);
router.put('/profile', shared.updateProfile);
router.get('/notifications', shared.notifications);
router.post('/profile/avatar', uploadAvatar.single('avatar'), shared.updateAvatar);
module.exports = router;
