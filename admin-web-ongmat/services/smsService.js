const axios = require('axios');

// Đặt token vào file .env hoặc điền trực tiếp để kiểm thử
const SPEEDSMS_AUTH_TOKEN = process.env.SPEEDSMS_AUTH_TOKEN || 'YOUR_ACCESS_TOKEN';

/**
 * Gửi SMS OTP đến số điện thoại thật
 * @param {string} phone - Số điện thoại người nhận (vd: 0912345678)
 * @param {string} otpCode - Mã OTP 6 chữ số
 * @param {string} actionType - 'DANG_KY' hoặc 'KY_HOP_DONG'
 */
async function sendSmsOtp(phone, otpCode, actionType) {
  let formattedPhone = phone.trim().replace(/\s+/g, '');
  if (formattedPhone.startsWith('0')) {
    formattedPhone = '84' + formattedPhone.substring(1);
  }

  const actionText = actionType === 'KY_HOP_DONG' ? 'ky hop dong' : 'dang ky tai khoan';
  const content = `[OngMat] Ma OTP xac thuc ${actionText} cua ban la: ${otpCode}. Ma co hieu luc trong 3 phut.`;

  try {
    const response = await axios.post(
      'https://api.speedsms.vn/index.php/sms/send',
      {
        to: [formattedPhone],
        content: content,
        sms_type: 2, // 2: OTP / CSKH
        sender: ''   // Để trống nếu dùng Brandname mặc định của dịch vụ thử nghiệm
      },
      {
        headers: {
          'Authorization': `Basic ${Buffer.from(`${SPEEDSMS_AUTH_TOKEN}:x`).toString('base64')}`,
          'Content-Type': 'application/json'
        }
      }
    );
    return response.data;
  } catch (error) {
    console.error('Loi gui tin nhan SMS OTP:', error.response?.data || error.message);
    throw new Error('Không thể gửi tin nhắn OTP qua SMS.');
  }
}

module.exports = { sendSmsOtp };