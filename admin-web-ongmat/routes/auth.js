const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');

// API đăng nhập / đăng ký dành cho Mobile & Web
router.post('/login', authController.dangNhap);
router.post('/register', authController.dangKy);
router.post('/google', authController.dangNhapGoogle);
router.post('/check-account', authController.kiemTraTaiKhoan);
router.post('/send-otp', authController.guiOtp);
router.post('/verify-otp', authController.xacThucOtp);

module.exports = router;