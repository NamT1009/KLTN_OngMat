const nodemailer = require('nodemailer');

// 1. Cấu hình transporter gửi Gmail với cấu hình timeout và pool
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
  pool: true,
  maxConnections: 5,
  maxMessages: 100,
});

// 2. Hàm gửi mã OTP qua Email với template chuyên nghiệp
async function sendEmailOtp(toEmail, otpCode, loaiHanhDong = 'Xác thực tài khoản') {
  const fromAddress = process.env.EMAIL_USER || 'no-reply@ongmat.com';
  
  const mailOptions = {
    from: `"Hệ Thống Truy Vết Ong Mật" <${fromAddress}>`,
    to: toEmail,
    subject: `🐝 [Ong Mật] Mã xác thực OTP của bạn là: ${otpCode}`,
    html: `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #fdfaf2; margin: 0; padding: 20px; color: #2d3748; }
          .container { max-width: 520px; margin: 0 auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(180, 83, 9, 0.08); border: 1px solid #fed7aa; }
          .header { background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); padding: 32px 24px; text-align: center; color: #ffffff; }
          .header h1 { margin: 0; font-size: 24px; font-weight: 800; letter-spacing: 0.5px; }
          .header p { margin: 6px 0 0; font-size: 14px; opacity: 0.9; }
          .content { padding: 32px 28px; }
          .greeting { font-size: 16px; font-weight: 600; color: #1f2937; margin-bottom: 12px; }
          .desc { font-size: 14px; line-height: 1.6; color: #4b5563; margin-bottom: 24px; }
          .otp-box { background: #fffbeb; border: 2px dashed #f59e0b; border-radius: 12px; padding: 20px; text-align: center; margin: 24px 0; }
          .otp-code { font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: 900; letter-spacing: 10px; color: #b45309; }
          .otp-hint { font-size: 13px; color: #92400e; margin-top: 8px; font-weight: 500; }
          .warning { font-size: 13px; color: #ef4444; background: #fef2f2; padding: 12px 16px; border-radius: 8px; border-left: 4px solid #ef4444; margin-top: 20px; line-height: 1.5; }
          .footer { background: #f9fafb; padding: 20px; text-align: center; font-size: 12px; color: #9ca3af; border-top: 1px solid #f3f4f6; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <div style="font-size: 40px; margin-bottom: 8px;">🐝</div>
            <h1>TRUY VẾT ONG MẬT</h1>
            <p>Hệ Thống Quản Lý & Minh Bạch Nguồn Gốc Mật Ong</p>
          </div>
          <div class="content">
            <div class="greeting">Xin chào bạn,</div>
            <div class="desc">
              Bạn đang thực hiện yêu cầu: <strong>${loaiHanhDong}</strong>.<br>
              Dưới đây là mã xác thực dùng một lần (OTP) của bạn:
            </div>
            <div class="otp-box">
              <div class="otp-code">${otpCode}</div>
              <div class="otp-hint">⏳ Mã này sẽ hết hạn sau <strong>5 phút</strong></div>
            </div>
            <div class="warning">
              ⚠️ <strong>Lưu ý bảo mật:</strong> Tuyệt đối không cung cấp hoặc chia sẻ mã xác thực này cho bất kỳ ai, kể cả nhân viên hỗ trợ hệ thống.
            </div>
          </div>
          <div class="footer">
            Email này được gửi tự động từ Hệ thống Quản lý Truy Vết Ong Mật.<br>
            Nếu bạn không yêu cầu mã này, vui lòng bỏ qua thư này.
          </div>
        </div>
      </body>
      </html>
    `,
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    console.log(`✅ [EMAIL-OTP] Gửi thành công tới ${toEmail} | MessageID: ${info.messageId}`);
    return { success: true, messageId: info.messageId };
  } catch (err) {
    console.error(`❌ [EMAIL-OTP-ERROR] Gửi tới ${toEmail} thất bại:`, err.message);
    throw err;
  }
}

// 3. EXPORT
module.exports = {
  sendEmailOtp,
};