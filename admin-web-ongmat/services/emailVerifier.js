const dns = require('dns');
const net = require('net');

// Đảm bảo DNS servers công cộng để Node.js giải quyết chính xác bản ghi MX trên mọi hệ điều hành
try {
  dns.setServers(['8.8.8.8', '1.1.1.1', '8.8.4.4']);
} catch (_) {}

const dnsPromises = dns.promises;

/**
 * Kiểm tra xem địa chỉ email (đặc biệt là Gmail) có tồn tại thực tế hay không.
 * Các bước:
 * 1. Kiểm tra định dạng cú pháp (độ dài 6-30 ký tự cho gmail, ký tự hợp lệ).
 * 2. Tra cứu bản ghi MX của tên miền email.
 * 3. Bắt tay SMTP (HELO -> MAIL FROM -> RCPT TO) tới máy chủ MX.
 *    Nếu máy chủ trả về 550 / 5.1.1 / NoSuchUser / user unknown -> email chắc chắn không tồn tại.
 *    Nếu 250 OK -> email tồn tại.
 *    Nếu timeout hoặc cổng 25 bị chặn -> trả về exists: true (không chặn người dùng nếu mạng lỗi).
 */
async function verifyEmailAddress(email) {
  if (!email || typeof email !== 'string') {
    return { exists: false, message: 'Vui lòng cung cấp địa chỉ email.' };
  }

  const cleanEmail = email.trim().toLowerCase();

  // 1. Kiểm tra regex cơ bản
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) {
    return { exists: false, message: 'Tài khoản Gmail không đúng định dạng.' };
  }

  const parts = cleanEmail.split('@');
  if (parts.length !== 2) {
    return { exists: false, message: 'Định dạng email không hợp lệ.' };
  }

  const [username, domain] = parts;

  // 2. Kiểm tra quy tắc riêng của Gmail
  if (domain === 'gmail.com' || domain === 'googlemail.com') {
    if (username.length < 6 || username.length > 30) {
      return { exists: false, message: 'Tài khoản Gmail phải có độ dài từ 6 đến 30 ký tự.' };
    }
    if (!/^[a-z0-9.]+$/.test(username)) {
      return { exists: false, message: 'Tài khoản Gmail chỉ được chứa chữ cái, số và dấu chấm.' };
    }
    if (username.startsWith('.') || username.endsWith('.') || username.includes('..')) {
      return { exists: false, message: 'Tài khoản Gmail không đúng định dạng (dấu chấm không hợp lệ).' };
    }
  }

  // 3. Tra cứu bản ghi MX của tên miền
  let mxRecords;
  try {
    mxRecords = await dnsPromises.resolveMx(domain);
    if (!mxRecords || mxRecords.length === 0) {
      return { exists: false, message: 'Tên miền email không tồn tại hoặc không thể nhận thư.' };
    }
  } catch (dnsErr) {
    console.warn(`[EMAIL-VERIFY] Tra cứu MX thất bại cho ${domain}:`, dnsErr.message);
    return { exists: false, message: 'Tài khoản Gmail hoặc tên miền email không tồn tại.' };
  }

  // Sắp xếp máy chủ MX theo độ ưu tiên
  mxRecords.sort((a, b) => a.priority - b.priority);
  const mxHost = mxRecords[0].exchange;

  // 4. Bắt tay SMTP kiểm tra hòm thư có tồn tại không
  return new Promise((resolve) => {
    let client;
    let settled = false;

    const finish = (result) => {
      if (!settled) {
        settled = true;
        try {
          if (client) {
            client.write('QUIT\r\n');
            client.destroy();
          }
        } catch (_) {}
        resolve(result);
      }
    };

    // Timeout tổng thể 4.5 giây
    const timer = setTimeout(() => {
      finish({ exists: true, warning: 'timeout' });
    }, 4500);

    try {
      client = net.createConnection(25, mxHost);
      client.setTimeout(4000);

      let step = 0;

      client.on('data', (data) => {
        const response = data.toString();
        const code = response.substring(0, 3);

        if (step === 0 && code === '220') {
          step = 1;
          client.write('HELO mail.ongmat.com\r\n');
        } else if (step === 1 && code === '250') {
          step = 2;
          client.write('MAIL FROM:<check@ongmat.com>\r\n');
        } else if (step === 2 && code === '250') {
          step = 3;
          client.write(`RCPT TO:<${cleanEmail}>\r\n`);
        } else if (step === 3) {
          clearTimeout(timer);
          const isNotExist =
            code === '550' ||
            code === '551' ||
            code === '553' ||
            /5\.1\.1|does not exist|not exist|user unknown|recipient address rejected|nosuchuser|invalid recipient|no such user/i.test(response);

          if (isNotExist) {
            console.log(`[EMAIL-VERIFY] Phát hiện Gmail không tồn tại (${cleanEmail}): ${response.trim()}`);
            finish({
              exists: false,
              message: 'Tài khoản Gmail không tồn tại. Vui lòng kiểm tra lại chính xác địa chỉ Gmail của bạn.'
            });
          } else {
            finish({ exists: true });
          }
        }
      });

      client.on('error', (err) => {
        clearTimeout(timer);
        console.warn(`[EMAIL-VERIFY] Kết nối SMTP MX (${mxHost}) không thành công: ${err.message}`);
        finish({ exists: true, warning: err.message });
      });

      client.on('timeout', () => {
        clearTimeout(timer);
        finish({ exists: true, warning: 'timeout' });
      });
    } catch (e) {
      clearTimeout(timer);
      finish({ exists: true, warning: e.message });
    }
  });
}

module.exports = {
  verifyEmailAddress
};
