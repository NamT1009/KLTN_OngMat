const { sql, poolPromise } = require('../config/db');
const { sendEmailOtp } = require('../services/mailService');
const { verifyEmailAddress } = require('../services/emailVerifier');

// Bảng ánh xạ loại hành động hiển thị thân thiện trong Email
const HANH_DONG_MAP = {
    'DANG_KY': 'Đăng ký tài khoản hệ thống Ong Mật',
    'KY_HOP_DONG': 'Ký duyệt hợp đồng điện tử thuê điểm đặt ong',
    'DUYET_HOP_DONG': 'Ký duyệt hợp đồng điện tử thuê điểm đặt ong',
    'QUEN_MAT_KHAU': 'Khôi phục mật khẩu tài khoản',
    'XAC_THUC_GIAO_DICH': 'Xác thực giao dịch'
};

// 1. API: Yêu cầu gửi mã OTP qua Email / SĐT (Hỗ trợ cả Đăng ký lẫn Ký duyệt hợp đồng)
exports.requestOtp = async (req, res) => {
    try {
        const { 
            email, 
            soDienThoai, 
            loaiHanhDong = 'DANG_KY',
            hopDongId = null,
            nguoiDungId = null 
        } = req.body;

        let cleanEmail = email ? email.trim() : null;
        let cleanPhone = soDienThoai ? soDienThoai.trim() : null;

        const pool = await poolPromise;
        if (!pool) {
            return res.status(503).json({ success: false, message: 'Không thể kết nối cơ sở dữ liệu.' });
        }

        // Nếu là hành động Ký hợp đồng mà chưa truyền Email trực tiếp, tự truy vấn email từ người dùng hoặc hợp đồng
        if ((loaiHanhDong === 'KY_HOP_DONG' || loaiHanhDong === 'DUYET_HOP_DONG') && !cleanEmail) {
            if (nguoiDungId) {
                const userQuery = await pool.request()
                    .input('id', sql.Int, nguoiDungId)
                    .query(`SELECT email, soDienThoai FROM dbo.nguoiDung WHERE id = @id`);
                if (userQuery.recordset.length > 0) {
                    cleanEmail = userQuery.recordset[0].email;
                    cleanPhone = cleanPhone || userQuery.recordset[0].soDienThoai;
                }
            } else if (hopDongId) {
                // Thử tìm email của chủ đất hoặc người nuôi ong trong bảng hợp đồng
                const hdQuery = await pool.request()
                    .input('hdId', sql.Int, hopDongId)
                    .query(`
                        SELECT nd.email, nd.soDienThoai 
                        FROM dbo.hopDong hd
                        JOIN dbo.nguoiDung nd ON hd.chuDatId = nd.id OR hd.nguoiNuoiOngId = nd.id
                        WHERE hd.id = @hdId
                    `);
                if (hdQuery.recordset.length > 0) {
                    cleanEmail = hdQuery.recordset[0].email;
                    cleanPhone = cleanPhone || hdQuery.recordset[0].soDienThoai;
                }
            }
        }

        if (!cleanEmail && !cleanPhone) {
            return res.status(400).json({ 
                success: false, 
                message: 'Không tìm thấy Email hoặc Số điện thoại để gửi mã xác thực OTP.' 
            });
        }

        // Kiểm tra tính hợp lệ và sự tồn tại thực tế của Gmail
        if (cleanEmail) {
            const emailVerification = await verifyEmailAddress(cleanEmail);
            if (!emailVerification.exists) {
                return res.status(400).json({
                    success: false,
                    message: emailVerification.message || 'Tài khoản Gmail không tồn tại. Vui lòng kiểm tra lại chính xác địa chỉ Gmail của bạn.'
                });
            }
        }

        // Nếu là ĐĂNG KÝ: Kiểm tra tài khoản đã tồn tại trong hệ thống chưa
        if (loaiHanhDong === 'DANG_KY') {
            if (cleanEmail) {
                const checkEmail = await pool.request()
                    .input('chkEmail', sql.VarChar(150), cleanEmail)
                    .query(`SELECT TOP 1 maNguoiDung FROM dbo.nguoiDung WHERE LOWER(email) = LOWER(@chkEmail)`);
                if (checkEmail.recordset.length > 0) {
                    return res.status(409).json({
                        success: false,
                        exists: true,
                        message: 'Email này đã được đăng ký tài khoản trong hệ thống! Vui lòng đăng nhập hoặc dùng email khác.'
                    });
                }
            }

            if (cleanPhone) {
                const checkPhone = await pool.request()
                    .input('chkPhone', sql.VarChar(20), cleanPhone)
                    .query(`SELECT TOP 1 maNguoiDung FROM dbo.nguoiDung WHERE soDienThoai = @chkPhone`);
                if (checkPhone.recordset.length > 0) {
                    return res.status(409).json({
                        success: false,
                        exists: true,
                        message: 'Số điện thoại này đã được sử dụng cho một tài khoản khác.'
                    });
                }
            }
        }

        // Đảm bảo bảng xacThucOtp tồn tại với đủ cấu trúc
        await pool.request().query(`
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='xacThucOtp' AND xtype='U')
            CREATE TABLE dbo.xacThucOtp (
                id INT IDENTITY(1,1) PRIMARY KEY,
                soDienThoai NVARCHAR(100) NULL,
                email NVARCHAR(150) NULL,
                maOtp VARCHAR(10) NOT NULL,
                loaiHanhDong NVARCHAR(50) DEFAULT 'DANG_KY',
                daSuDung BIT DEFAULT 0,
                ngayHetHan DATETIME NOT NULL,
                ngayTao DATETIME DEFAULT GETDATE()
            );

            IF NOT EXISTS (
                SELECT * FROM sys.columns 
                WHERE Name = N'email' AND Object_ID = Object_ID(N'dbo.xacThucOtp')
            )
            BEGIN
                ALTER TABLE dbo.xacThucOtp ADD email NVARCHAR(150) NULL;
            END;
        `);

        // Hủy các mã OTP cũ chưa sử dụng cùng loại hành động
        const cancelReq = pool.request();
        cancelReq.input('action', sql.NVarChar(50), loaiHanhDong);
        cancelReq.input('email', sql.NVarChar(150), cleanEmail);
        cancelReq.input('phone', sql.NVarChar(100), cleanPhone);
        await cancelReq.query(`
            UPDATE dbo.xacThucOtp 
            SET daSuDung = 1 
            WHERE daSuDung = 0 
              AND loaiHanhDong = @action
              AND (
                (@email IS NOT NULL AND email = @email) OR 
                (@phone IS NOT NULL AND soDienThoai = @phone)
              )
        `);

        // Sinh mã OTP 6 số
        const otpCode = Math.floor(100000 + Math.random() * 900000).toString();

        // Lưu vào CSDL (hết hạn sau 5 phút tính theo giờ hệ thống SQL Server)
        const insertReq = pool.request();
        insertReq.input('email', sql.NVarChar(150), cleanEmail);
        insertReq.input('phone', sql.NVarChar(100), cleanPhone);
        insertReq.input('maOtp', sql.NVarChar(10), otpCode);
        insertReq.input('action', sql.NVarChar(50), loaiHanhDong);

        await insertReq.query(`
            INSERT INTO dbo.xacThucOtp (email, soDienThoai, maOtp, loaiHanhDong, ngayHetHan, daSuDung, ngayTao)
            VALUES (@email, @phone, @maOtp, @action, DATEADD(minute, 5, GETDATE()), 0, GETDATE())
        `);

        // Tên hành động để gửi thư
        const titleHanhDong = HANH_DONG_MAP[loaiHanhDong] || loaiHanhDong;

        // Gửi qua Gmail nếu có email
        if (cleanEmail) {
            try {
                await sendEmailOtp(cleanEmail, otpCode, titleHanhDong);
                console.log(`[EMAIL-OTP] [${loaiHanhDong}] Đã gửi mã ${otpCode} đến ${cleanEmail}`);
            } catch (mailErr) {
                console.error('Lỗi sendEmailOtp:', mailErr.message);
                const errMsg = String(mailErr.message || '') + ' ' + String(mailErr.response || '');
                const isNotExist = 
                    mailErr.responseCode === 550 || 
                    mailErr.responseCode === 553 || 
                    mailErr.code === 'EENVELOPE' ||
                    /5\.1\.1|does not exist|not exist|user unknown|recipient address rejected|invalid recipient|no recipients/i.test(errMsg);

                return res.status(400).json({
                    success: false,
                    message: isNotExist 
                        ? 'Tài khoản Gmail không tồn tại. Vui lòng kiểm tra lại chính xác địa chỉ Gmail của bạn.' 
                        : `Không thể gửi mã xác thực tới Gmail (${cleanEmail}). Vui lòng kiểm tra lại địa chỉ email hoặc kết nối mạng.`
                });
            }
        } else {
            console.log(`[LOG-OTP] [${loaiHanhDong}] Mã OTP gửi SĐT ${cleanPhone} là: ${otpCode}`);
        }

        return res.json({
            success: true,
            message: cleanEmail 
                ? `Mã xác thực đã được gửi về Gmail: ${cleanEmail}` 
                : `Mã xác thực đã gửi đến số điện thoại: ${cleanPhone}`,
            emailNhan: cleanEmail,
            otpDemo: otpCode
        });
    } catch (error) {
        console.error('Lỗi requestOtp:', error);
        return res.status(500).json({ success: false, message: error.message || 'Lỗi server khi gửi OTP.' });
    }
};

// 2. API: Xác thực mã OTP (Đăng ký hoặc Duyệt hợp đồng)
exports.verifyOtp = async (req, res) => {
    try {
        const { email, soDienThoai, maOtp, loaiHanhDong = 'DANG_KY' } = req.body;
        const cleanEmail = email ? email.trim() : null;
        const cleanPhone = soDienThoai ? soDienThoai.trim() : null;
        const cleanOtp = maOtp ? maOtp.toString().trim() : null;

        if ((!cleanEmail && !cleanPhone) || !cleanOtp) {
            return res.status(400).json({ 
                success: false, 
                message: 'Vui lòng cung cấp mã OTP cùng Email hoặc Số điện thoại.' 
            });
        }

        const pool = await poolPromise;
        if (!pool) {
            return res.status(503).json({ success: false, message: 'Không thể kết nối cơ sở dữ liệu.' });
        }

        const checkReq = pool.request();
        checkReq.input('maOtp', sql.NVarChar(10), cleanOtp);
        checkReq.input('action', sql.NVarChar(50), loaiHanhDong);
        checkReq.input('email', sql.NVarChar(150), cleanEmail);
        checkReq.input('phone', sql.NVarChar(100), cleanPhone);

        // Kiểm tra mã OTP khớp và còn hạn (so sánh với GETDATE() của SQL Server)
        const checkQuery = `
            SELECT TOP 1 id, ngayHetHan, daSuDung,
                   CASE WHEN ngayHetHan < GETDATE() THEN 1 ELSE 0 END AS isExpired
            FROM dbo.xacThucOtp
            WHERE maOtp = @maOtp 
              AND loaiHanhDong = @action
              AND daSuDung = 0
              AND (
                (@email IS NOT NULL AND email = @email) OR 
                (@phone IS NOT NULL AND soDienThoai = @phone)
              )
            ORDER BY id DESC
        `;

        const result = await checkReq.query(checkQuery);

        if (result.recordset.length === 0) {
            return res.status(400).json({ 
                success: false, 
                message: 'Mã OTP không chính xác hoặc đã qua sử dụng.' 
            });
        }

        const record = result.recordset[0];
        if (record.isExpired === 1) {
            return res.status(400).json({ 
                success: false, 
                message: 'Mã OTP đã hết hiệu lực (chỉ có hiệu lực trong vòng 5 phút).' 
            });
        }

        // Đánh dấu mã đã sử dụng thành công
        const updateReq = pool.request();
        updateReq.input('id', sql.Int, record.id);
        await updateReq.query(`UPDATE dbo.xacThucOtp SET daSuDung = 1 WHERE id = @id`);

        return res.json({
            success: true,
            message: 'Xác thực OTP thành công!'
        });
    } catch (error) {
        console.error('Lỗi verifyOtp:', error);
        return res.status(500).json({ success: false, message: error.message || 'Lỗi server khi kiểm tra OTP.' });
    }
};