const express = require('express');
const router = express.Router();
const otpController = require('../controllers/otpController');

router.post('/send', otpController.requestOtp);    // Nhận lệnh gửi OTP
router.post('/verify', otpController.verifyOtp);  // Nhận lệnh kiểm tra OTP

module.exports = router;