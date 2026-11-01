const express = require('express');
const router = express.Router();
const adminController = require('../controllers/adminController');
const danhMucController = require('../controllers/danhMucController');
const userController = require('../controllers/userController');
const giongOngController = require('../controllers/giongOngController');
const diaDiemController = require('../controllers/diaDiemController');
const banDoController = require('../controllers/banDoController');
const chatController = require('../controllers/chatController');
const beekeepingAdminController = require('../controllers/beekeepingAdminController');

router.get('/nguoi-nuoi-ong', beekeepingAdminController.dashboard);
router.post('/api/nguoi-nuoi-ong/yeu-cau/:id/duyet', beekeepingAdminController.approveRequest);

// Nhóm Router Quản Lý Giống Ong
router.get('/giong-ong', giongOngController.getDanhSachGiongOng);
router.post('/api/giong-ong/them', giongOngController.themGiongOng);
router.post('/api/giong-ong/sua', giongOngController.suaGiongOng);
router.post('/api/giong-ong/xoa', giongOngController.xoaGiongOng);

// Nhóm Router của Dashboard
router.get('/', adminController.getDashboard);
router.post('/api/dia-diem/duyet', adminController.duyetDiaDiem);
router.post('/api/dia-diem/tu-choi', adminController.tuChoiDiaDiem);

// Nhóm Router của Danh mục Hoa
router.get('/danh-muc-hoa', danhMucController.getDanhMucHoa);
router.post('/danh-muc-hoa/them', danhMucController.themLoaiHoa);
router.post('/api/danh-muc-hoa/xoa', danhMucController.xoaLoaiHoa);
router.post('/api/danh-muc-hoa/sua', danhMucController.suaLoaiHoa);

// Nhóm Router Quản lý Người Dùng (UC-21)
router.get('/nguoi-dung', userController.getDanhSachNguoiDung);
router.post('/api/nguoi-dung/trang-thai', userController.thayDoiTrangThai);
router.post('/api/nguoi-dung/them', userController.themNguoiDung);  
router.post('/api/nguoi-dung/toggle-khoa', userController.toggleKhoaNguoiDung);
router.post('/api/nguoi-dung/sua', userController.suaNguoiDung);
router.post('/api/nguoi-dung/xoa', userController.xoaNguoiDung);

// Thêm các Route này vào danh sách
router.get('/kiem-duyet', diaDiemController.getDanhSachKiemDuyet);
router.post('/api/dia-diem/duyet', diaDiemController.duyetDiaDiem);
router.post('/api/dia-diem/tu-choi', diaDiemController.tuChoiDiaDiem);
router.get('/danh-sach-bai-dang', diaDiemController.getBaiDangHoatDong);
router.post('/them-dia-diem', diaDiemController.themDiaDiem);
router.post('/api/dia-diem/xoa', diaDiemController.xoaDiaDiem);
// Route Bản đồ GIS
router.get('/ban-do', banDoController.getBanDoGIS);

// Tìm Kiếm
router.get('/tim-kiem', adminController.timKiemToanCuc);

// Route hiển thị giao diện chat (Truyền ID của người cần nhắn tin vào URL)
router.get('/phong-chat/:id', chatController.trangChat);
// Route trang danh sách Hỗ Trợ
router.get('/ho-tro', chatController.trangHoTro);
// API xử lý dữ liệu tin nhắn
router.get('/api/chat/danh-sach', chatController.getDanhSachCuocTroChuyen);
router.get('/api/chat/lich-su', chatController.getLichSuChat);
router.post('/api/chat/gui', chatController.guiTinNhan);
router.get('/api/chat/tim-kiem-nguoi-dung', chatController.timKiemNguoiDung);
router.post('/api/chat/heartbeat', chatController.heartbeat);
router.get('/api/chat/trang-thai-online/:id', chatController.checkOnlineStatus);
router.post('/api/chat/thu-hoi/:id', chatController.thuHoiTinNhan);
router.post('/api/chat/thu-hoi', chatController.thuHoiTinNhan);
router.get('/api/chat/partner/:id', chatController.getPartnerInfo);

module.exports = router;
