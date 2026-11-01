const { sql, poolPromise } = require('../config/db');
const { signToken } = require('../middleware/auth');
const { AppError } = require('../utils/http');
const { sendEmailOtp } = require('../services/mailService');
const { verifyEmailAddress } = require('../services/emailVerifier');
const {
    normalizeRole,
    isAccountActive,
    comparePassword,
    hashPassword,
} = require('../utils/authHelpers');

// Bảng ánh xạ loại hành động hiển thị tiếng Việt trên Gmail
const HANH_DONG_MAP = {
    'DANG_KY': 'Đăng ký tài khoản hệ thống Ong Mật',
    'KY_HOP_DONG': 'Ký duyệt hợp đồng điện tử thuê điểm đặt ong',
    'QUEN_MAT_KHAU': 'Khôi phục mật khẩu tài khoản'
};

// =======================================================
// 0. API XÁC THỰC MÃ OTP (GỬI VÀ XÁC THỰC)
// =======================================================

exports.guiOtp = async (req, res) => {
    try {
        const { soDienThoai, email, loaiHanhDong = 'DANG_KY' } = req.body;
        const sdt = soDienThoai ? String(soDienThoai).replace(/\s+/g, '') : null;
        const cleanEmail = email ? String(email).trim().toLowerCase() : null;

        if (!cleanEmail && !sdt) {
            return res.status(400).json({ success: false, message: 'Vui lòng cung cấp email hoặc số điện thoại.' });
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

        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được CSDL.' });

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

            if (sdt) {
                const checkPhone = await pool.request()
                    .input('chkPhone', sql.VarChar(20), sdt)
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

        const maOtp = Math.floor(100000 + Math.random() * 900000).toString();

        await pool.request().query(`
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='xacThucOtp' AND xtype='U')
            CREATE TABLE dbo.xacThucOtp (
                id INT IDENTITY(1,1) PRIMARY KEY,
                soDienThoai VARCHAR(20) NULL,
                email NVARCHAR(150) NULL,
                maOtp VARCHAR(10) NOT NULL,
                loaiHanhDong NVARCHAR(50) DEFAULT 'DANG_KY',
                daSuDung BIT DEFAULT 0,
                ngayHetHan DATETIME NOT NULL,
                ngayTao DATETIME DEFAULT GETDATE()
            );

            IF NOT EXISTS (SELECT * FROM sys.columns WHERE Name = N'email' AND Object_ID = Object_ID(N'dbo.xacThucOtp'))
            BEGIN
                ALTER TABLE dbo.xacThucOtp ADD email NVARCHAR(150) NULL;
            END;
        `);

        await pool.request()
            .input('sdt', sql.VarChar(20), sdt)
            .input('email', sql.NVarChar(150), cleanEmail)
            .input('action', sql.NVarChar(50), loaiHanhDong)
            .query(`
                UPDATE dbo.xacThucOtp 
                SET daSuDung = 1 
                WHERE daSuDung = 0 
                  AND loaiHanhDong = @action 
                  AND ((@email IS NOT NULL AND email = @email) OR (@sdt IS NOT NULL AND soDienThoai = @sdt))
            `);

        await pool.request()
            .input('sdt', sql.VarChar(20), sdt)
            .input('email', sql.NVarChar(150), cleanEmail)
            .input('otp', sql.VarChar(10), maOtp)
            .input('action', sql.NVarChar(50), loaiHanhDong)
            .query(`
                INSERT INTO dbo.xacThucOtp (soDienThoai, email, maOtp, loaiHanhDong, ngayHetHan, ngayTao) 
                VALUES (@sdt, @email, @otp, @action, DATEADD(MINUTE, 5, GETDATE()), GETDATE())
            `);

        const tenHanhDong = HANH_DONG_MAP[loaiHanhDong] || loaiHanhDong;
        if (cleanEmail) {
            try {
                await sendEmailOtp(cleanEmail, maOtp, tenHanhDong);
                console.log(`[EMAIL-OTP] [${loaiHanhDong}] Đã gửi mã ${maOtp} tới ${cleanEmail}`);
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
        }

        return res.json({
            success: true,
            message: cleanEmail 
                ? `Mã xác thực OTP đã được gửi đến hộp thư Gmail: ${cleanEmail}. Vui lòng kiểm tra hộp thư đến (hoặc Thư rác/Spam).` 
                : 'Đã gửi mã xác thực OTP thành công!',
            emailNhan: cleanEmail,
            otpDemo: maOtp
        });
    } catch (err) {
        console.error('Lỗi guiOtp:', err);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ khi gửi mã xác thực.' });
    }
};

exports.xacThucOtp = async (req, res) => {
    try {
        const { soDienThoai, email, maOtp, loaiHanhDong = 'DANG_KY' } = req.body;
        const sdt = soDienThoai ? String(soDienThoai).replace(/\s+/g, '') : null;
        const cleanEmail = email ? String(email).trim().toLowerCase() : null;
        const otp = String(maOtp ?? '').trim();

        if ((!cleanEmail && !sdt) || !otp) {
            return res.status(400).json({ success: false, message: 'Thiếu mã OTP hoặc thông tin người nhận.' });
        }

        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được CSDL.' });

        const result = await pool.request()
            .input('sdt', sql.VarChar(20), sdt)
            .input('email', sql.NVarChar(150), cleanEmail)
            .input('otp', sql.VarChar(10), otp)
            .input('action', sql.NVarChar(50), loaiHanhDong)
            .query(`
                SELECT TOP 1 id, ngayHetHan,
                       CASE WHEN ngayHetHan < GETDATE() THEN 1 ELSE 0 END AS daHetHan
                FROM dbo.xacThucOtp 
                WHERE maOtp = @otp 
                  AND loaiHanhDong = @action 
                  AND daSuDung = 0 
                  AND (
                    (@email IS NOT NULL AND email = @email) OR
                    (@sdt IS NOT NULL AND soDienThoai = @sdt)
                  )
                ORDER BY id DESC
            `);

        if (!result.recordset || result.recordset.length === 0) {
            return res.status(400).json({ success: false, message: 'Mã OTP không chính xác hoặc đã được sử dụng.' });
        }

        const record = result.recordset[0];
        if (record.daHetHan === 1) {
            return res.status(400).json({ success: false, message: 'Mã OTP đã hết hiệu lực (5 phút).' });
        }

        await pool.request()
            .input('id', sql.Int, record.id)
            .query(`UPDATE dbo.xacThucOtp SET daSuDung = 1 WHERE id = @id`);

        return res.json({ success: true, message: 'Xác thực OTP thành công.' });
    } catch (err) {
        console.error('Lỗi xacThucOtp:', err);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ khi kiểm tra OTP.' });
    }
};

// =======================================================
// 1. API GỬI OTP VÀ KÝ HỢP ĐỒNG CHO MOBILE APP
// =======================================================

exports.requestContractOtp = async (req, res) => {
    try {
        const contractId = req.params.id || req.body.contractId || req.body.maHopDong;
        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được CSDL.' });

        let emailNhan = req.user?.email || null;
        let sdtNhan = req.user?.soDienThoai || null;

        if (req.user?.id) {
            const userRes = await pool.request()
                .input('maND', sql.Int, Number(req.user.id))
                .query(`SELECT email, soDienThoai FROM dbo.nguoiDung WHERE maNguoiDung = @maND`);
            if (userRes.recordset.length > 0) {
                emailNhan = emailNhan || userRes.recordset[0].email;
                sdtNhan = sdtNhan || userRes.recordset[0].soDienThoai;
            }
        }

        if (!emailNhan) {
            const fallbackRes = await pool.request()
                .input('maHD', sql.NVarChar(50), String(contractId))
                .query(`
                    SELECT TOP 1 nd.email, nd.soDienThoai
                    FROM dbo.hopDong hd
                    LEFT JOIN dbo.yeuCauDatCho yc ON hd.maDatCho = yc.maDatCho
                    LEFT JOIN dbo.nguoiDung nd ON yc.maNguoiNuoiOng = nd.maNguoiDung
                    WHERE CAST(hd.maHopDong AS NVARCHAR(50)) = @maHD
                `);
            if (fallbackRes.recordset.length > 0) {
                emailNhan = fallbackRes.recordset[0].email;
                sdtNhan = fallbackRes.recordset[0].soDienThoai;
            }
        }

        if (!emailNhan && !sdtNhan) {
            return res.status(400).json({ success: false, message: 'Không tìm thấy thông tin email của tài khoản ký.' });
        }

        const maOtp = Math.floor(100000 + Math.random() * 900000).toString();

        await pool.request().query(`
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='xacThucOtp' AND xtype='U')
            CREATE TABLE dbo.xacThucOtp (
                id INT IDENTITY(1,1) PRIMARY KEY,
                soDienThoai VARCHAR(20) NULL,
                email NVARCHAR(150) NULL,
                maOtp VARCHAR(10) NOT NULL,
                loaiHanhDong NVARCHAR(50) DEFAULT 'KY_HOP_DONG',
                daSuDung BIT DEFAULT 0,
                ngayHetHan DATETIME NOT NULL,
                ngayTao DATETIME DEFAULT GETDATE()
            );

            IF NOT EXISTS (SELECT * FROM sys.columns WHERE Name = N'email' AND Object_ID = Object_ID(N'dbo.xacThucOtp'))
            BEGIN
                ALTER TABLE dbo.xacThucOtp ADD email NVARCHAR(150) NULL;
            END;
        `);

        await pool.request()
            .input('email', sql.NVarChar(150), emailNhan)
            .input('sdt', sql.VarChar(20), sdtNhan)
            .query(`
                UPDATE dbo.xacThucOtp 
                SET daSuDung = 1 
                WHERE daSuDung = 0 
                  AND loaiHanhDong = 'KY_HOP_DONG'
                  AND ((@email IS NOT NULL AND email = @email) OR (@sdt IS NOT NULL AND soDienThoai = @sdt))
            `);

        await pool.request()
            .input('email', sql.NVarChar(150), emailNhan)
            .input('sdt', sql.VarChar(20), sdtNhan)
            .input('otp', sql.VarChar(10), maOtp)
            .query(`
                INSERT INTO dbo.xacThucOtp (email, soDienThoai, maOtp, loaiHanhDong, ngayHetHan, ngayTao)
                VALUES (@email, @sdt, @otp, 'KY_HOP_DONG', DATEADD(MINUTE, 5, GETDATE()), GETDATE())
            `);

        if (emailNhan) {
            try {
                await sendEmailOtp(emailNhan, maOtp, 'Ký duyệt hợp đồng điện tử thuê điểm đặt ong');
                console.log(`[EMAIL-OTP] Đã gửi mã ${maOtp} tới ${emailNhan} cho HĐ ${contractId}`);
            } catch (errMail) {
                console.error('Lỗi khi gửi email:', errMail.message);
            }
        }

        return res.json({
            success: true,
            message: emailNhan ? `Đã gửi mã OTP đến ${emailNhan}` : 'Đã tạo mã OTP.',
            emailNhan: emailNhan,
            data: { emailNhan: emailNhan, demoOtp: maOtp }
        });
    } catch (err) {
        console.error('Lỗi requestContractOtp:', err);
        return res.status(500).json({ success: false, message: 'Lỗi khi gửi OTP hợp đồng.' });
    }
};

// API: Ký xác nhận hợp đồng bằng OTP
exports.signContractWithOtp = async (req, res) => {
    try {
        const rawContractId = req.params.id || req.body.contractId || req.body.maHopDong || req.body.id;
        const cleanContractId = String(rawContractId ?? '').trim();
        const cleanOtp = String(req.body.otp || req.body.maOtp || req.body.code || '').trim();

        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được CSDL.' });

        // 1. Kiểm tra OTP
        const checkOtp = await pool.request()
            .input('otp', sql.VarChar(10), cleanOtp)
            .query(`
                SELECT TOP 1 id 
                FROM dbo.xacThucOtp
                WHERE maOtp = @otp AND loaiHanhDong = 'KY_HOP_DONG' AND daSuDung = 0
            `);

        if (checkOtp.recordset.length === 0) {
            return res.status(400).json({ success: false, message: 'Mã OTP không chính xác hoặc đã hết hạn.' });
        }

        // 2. Đánh dấu OTP đã dùng
        await pool.request().input('id', sql.Int, checkOtp.recordset[0].id)
            .query(`UPDATE dbo.xacThucOtp SET daSuDung = 1 WHERE id = @id`);

        // 3. Cập nhật hợp đồng thực tế trong dbo.hopDongThueOng & dbo.yeuCauThueOng
        let signed = null;
        try {
            const beekeeping = require('../config/beekeepingRepository');
            signed = await beekeeping.signContract(req.user, cleanContractId);
        } catch (repoErr) {
            await pool.request()
                .input('maHD', sql.NVarChar(50), cleanContractId)
                .query(`
                    UPDATE dbo.hopDongThueOng 
                    SET trangThai = 'DaKy', otpVerified = 1, ngayKy = SYSUTCDATETIME() 
                    WHERE maHopDong = @maHD;

                    UPDATE dbo.yeuCauThueOng 
                    SET trangThai = 'DaKy', ngayCapNhat = SYSUTCDATETIME() 
                    WHERE maYeuCau IN (SELECT maYeuCau FROM dbo.hopDongThueOng WHERE maHopDong = @maHD);
                `);
        }

        // 4. Đồng bộ thêm bảng dbo.hopDong cũ nếu có
        try {
            const existingHd = await pool.request()
                .input('codePattern', sql.NVarChar(200), `%${cleanContractId}%`)
                .query(`SELECT TOP 1 maHopDong FROM dbo.hopDong WHERE noiDungHopDong LIKE @codePattern`);

            if (existingHd.recordset.length > 0) {
                const targetHdId = existingHd.recordset[0].maHopDong;
                await pool.request().input('id', sql.Int, targetHdId).query(`
                    UPDATE dbo.hopDong SET trangThaiHopDong = 'DaKy', ngayKyKet = GETDATE() WHERE maHopDong = @id
                `);
            }
        } catch (oldErr) {
            // Bỏ qua lỗi đồng bộ bảng cũ
        }

        return res.json({
            success: true,
            message: 'Ký xác nhận hợp đồng thành công!',
            data: signed || { maHopDong: cleanContractId, id: cleanContractId, trangThai: 'DaKy' }
        });
    } catch (err) {
        console.error('>>> [LỖI signContractWithOtp]:', err);
        return res.status(500).json({ success: false, message: 'Lỗi server khi ký hợp đồng.' });
    }
};

// =======================================================

async function registerUser(body = {}) {
    const hoTen = String(body.hoTen ?? '').trim();
    const email = String(body.email ?? '').trim().toLowerCase();
    const soDienThoai = String(body.soDienThoai ?? '').replace(/\s+/g, '');
    const matKhau = String(body.matKhau ?? '').trim();
    const vaiTro = { chudat: 'chuDat', nguoinuoiong: 'nguoiNuoiOng' }[normalizeRole(body.vaiTro)];

    if (hoTen.length < 2) throw new AppError(400, 'Vui lòng nhập họ tên.');
    const emailVerification = await verifyEmailAddress(email);
    if (!emailVerification.exists) {
        throw new AppError(400, emailVerification.message || 'Tài khoản Gmail không tồn tại. Vui lòng kiểm tra lại chính xác địa chỉ Gmail của bạn.');
    }
    if (!/^0\d{9,10}$/.test(soDienThoai)) throw new AppError(400, 'Số điện thoại phải gồm 10-11 chữ số, bắt đầu bằng 0.');
    if (matKhau.length < 6) throw new AppError(400, 'Mật khẩu phải có ít nhất 6 ký tự.');
    if (!vaiTro) throw new AppError(400, 'Vui lòng chọn vai trò chủ đất hoặc người nuôi ong.');

    const pool = await poolPromise;
    if (!pool) throw new AppError(503, 'Không kết nối được cơ sở dữ liệu.');

    const existing = await pool.request()
        .input('email', sql.VarChar, email).input('sdt', sql.VarChar, soDienThoai)
        .query('SELECT email, soDienThoai FROM dbo.nguoiDung WHERE LOWER(email) = @email OR soDienThoai = @sdt');
    if (existing.recordset.length) {
        const duplicatedEmail = existing.recordset.some((row) => String(row.email).toLowerCase() === email);
        throw new AppError(409, duplicatedEmail ? 'Email đã được sử dụng.' : 'Số điện thoại đã được sử dụng.');
    }

    const created = await pool.request()
        .input('hoTen', sql.NVarChar, hoTen)
        .input('email', sql.VarChar, email)
        .input('sdt', sql.VarChar, soDienThoai)
        .input('matKhauHash', sql.VarChar, hashPassword(matKhau))
        .input('vaiTro', sql.VarChar, vaiTro)
        .query(`INSERT INTO dbo.nguoiDung (hoTen, email, soDienThoai, matKhauHash, vaiTro, trangThaiTaiKhoan, ngayTao)
                OUTPUT INSERTED.maNguoiDung, INSERTED.hoTen, INSERTED.email, INSERTED.soDienThoai, INSERTED.vaiTro, INSERTED.trangThaiTaiKhoan
                VALUES (@hoTen, @email, @sdt, @matKhauHash, @vaiTro, 'HoatDong', GETDATE())`);
    return created.recordset[0];
}

exports.dangKy = async (req, res) => {
    try {
        const user = await registerUser(req.body);
        return res.status(201).json({
            success: true,
            message: 'Đăng ký thành công',
            token: signToken(user),
            user: { id: user.maNguoiDung, hoTen: user.hoTen, vaiTro: normalizeRole(user.vaiTro) },
        });
    } catch (err) {
        if (err instanceof AppError) return res.status(err.status).json({ success: false, message: err.message });
        console.error('Lỗi đăng ký mobile: ', err);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getDangKyWeb = (req, res) => res.render('dang-ky', { error: null, form: {} });

exports.postDangKyWeb = async (req, res) => {
    try {
        const user = await registerUser(req.body);
        req.session.user = { ...user, vaiTro: normalizeRole(user.vaiTro) };
        return res.redirect('/portal');
    } catch (err) {
        if (!(err instanceof AppError)) console.error('Lỗi đăng ký web: ', err);
        const { matKhau, ...form } = req.body || {};
        return res.status(err.status || 500).render('dang-ky', { error: err instanceof AppError ? err.message : 'Lỗi máy chủ!', form });
    }
};

exports.dangNhap = async (req, res) => {
    try {
        const { taiKhoan, matKhau } = req.body;
        const normalizedTaiKhoan = String(taiKhoan ?? '').trim();
        const normalizedPassword = String(matKhau ?? '').trim();
        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được cơ sở dữ liệu.' });

        let result = await pool.request()
            .input('taiKhoan', sql.VarChar, normalizedTaiKhoan)
            .query(`SELECT * FROM dbo.nguoiDung WHERE email = @taiKhoan OR soDienThoai = @taiKhoan`);

        if (result.recordset.length === 0) {
            const fallback = await pool.request()
                .input('taiKhoan', sql.VarChar, normalizedTaiKhoan.toLowerCase())
                .query(`SELECT * FROM dbo.nguoiDung WHERE LOWER(email) = @taiKhoan OR LOWER(soDienThoai) = @taiKhoan`);
            result = fallback;
        }

        if (result.recordset.length === 0) {
            return res.status(401).json({ success: false, message: 'Tài khoản không tồn tại!' });
        }

        const user = result.recordset[0];
        const vaiTro = normalizeRole(user.vaiTro);

        if (!comparePassword(normalizedPassword, String(user.matKhauHash ?? '').trim())) {
            return res.status(401).json({ success: false, message: 'Mật khẩu không chính xác!' });
        }

        if (!isAccountActive(user.trangThaiTaiKhoan)) {
            return res.status(403).json({ success: false, message: 'Tài khoản của bạn đã bị khóa!' });
        }

        const token = signToken(user);

        res.json({
            success: true,
            message: 'Đăng nhập thành công',
            token: token,
            user: {
                id: user.maNguoiDung,
                hoTen: user.hoTen,
                vaiTro
            }
        });
    } catch (err) {
        console.error('Lỗi đăng nhập mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

const homeOf = (user) => (user.vaiTro === 'admin' ? '/' : '/portal');

exports.getLoginAdmin = (req, res) => {
    if (req.session.user) return res.redirect(homeOf(req.session.user));
    res.render('login', { error: null });
};

exports.postLoginAdmin = async (req, res) => {
    try {
        const { email, matKhau } = req.body;
        const normalizedEmail = String(email ?? '').trim();
        const pool = await poolPromise;
        if (!pool) return res.render('login', { error: 'Không kết nối được cơ sở dữ liệu!' });

        const result = await pool.request()
            .input('email', sql.VarChar, normalizedEmail)
            .query(`SELECT * FROM dbo.nguoiDung WHERE email = @email OR soDienThoai = @email`);
        const user = result.recordset[0];

        if (!user || !comparePassword(matKhau, user.matKhauHash)) {
            return res.render('login', { error: 'Email hoặc mật khẩu không chính xác!' });
        }
        if (!isAccountActive(user.trangThaiTaiKhoan)) {
            return res.render('login', { error: 'Tài khoản của bạn đã bị khóa!' });
        }

        const { matKhauHash, ...safeUser } = user;
        req.session.user = { ...safeUser, vaiTro: normalizeRole(user.vaiTro) };
        return res.redirect(homeOf(req.session.user));
    } catch (err) {
        console.error('Lỗi đăng nhập web: ', err);
        res.render('login', { error: 'Lỗi kết nối máy chủ!' });
    }
};

exports.logoutAdmin = (req, res) => {
    req.session.destroy(() => {
        res.redirect('/login');
    });
};

// =======================================================
// 4. API KIỂM TRA SỰ TỒN TẠI CỦA EMAIL / SĐT (CHECK ACCOUNT)
// =======================================================
exports.kiemTraTaiKhoan = async (req, res) => {
    try {
        const { email, soDienThoai } = req.body;
        const cleanEmail = email ? String(email).trim().toLowerCase() : null;
        const sdt = soDienThoai ? String(soDienThoai).replace(/\s+/g, '') : null;
        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được CSDL.' });

        let emailExists = false;
        let phoneExists = false;

        if (cleanEmail) {
            const emailVerification = await verifyEmailAddress(cleanEmail);
            if (!emailVerification.exists) {
                return res.json({
                    success: false,
                    emailExists: false,
                    available: false,
                    message: emailVerification.message || 'Tài khoản Gmail không tồn tại. Vui lòng kiểm tra lại chính xác địa chỉ Gmail của bạn.'
                });
            }

            const r = await pool.request()
                .input('email', sql.VarChar(150), cleanEmail)
                .query(`SELECT TOP 1 maNguoiDung FROM dbo.nguoiDung WHERE LOWER(email) = LOWER(@email)`);
            emailExists = r.recordset.length > 0;
        }

        if (sdt) {
            const r = await pool.request()
                .input('sdt', sql.VarChar(20), sdt)
                .query(`SELECT TOP 1 maNguoiDung FROM dbo.nguoiDung WHERE soDienThoai = @sdt`);
            phoneExists = r.recordset.length > 0;
        }

        return res.json({
            success: true,
            emailExists,
            phoneExists,
            available: !emailExists && !phoneExists,
            message: emailExists
                ? 'Email này đã được đăng ký tài khoản trong hệ thống.'
                : phoneExists
                ? 'Số điện thoại này đã được sử dụng.'
                : 'Thông tin tài khoản hợp lệ để đăng ký.'
        });
    } catch (err) {
        console.error('Lỗi kiemTraTaiKhoan:', err);
        return res.status(500).json({ success: false, message: 'Lỗi kiểm tra tài khoản.' });
    }
};

// =======================================================
// 5. API ĐĂNG NHẬP / ĐĂNG KÝ BẰNG TÀI KHOẢN GOOGLE (GOOGLE SIGN-IN)
// =======================================================
exports.dangNhapGoogle = async (req, res) => {
    try {
        const { email, hoTen, googleId, avatarUrl, vaiTro: requestedRole = 'nguoiNuoiOng' } = req.body;
        const cleanEmail = email ? String(email).trim().toLowerCase() : null;
        const cleanName = hoTen ? String(hoTen).trim() : (cleanEmail ? cleanEmail.split('@')[0] : 'Người dùng Google');
        const cleanGoogleId = googleId ? String(googleId).trim() : null;
        const cleanRole = { chudat: 'chuDat', nguoinuoiong: 'nguoiNuoiOng' }[normalizeRole(requestedRole)] || 'nguoiNuoiOng';

        if (!cleanEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) {
            return res.status(400).json({ success: false, message: 'Địa chỉ Gmail Google không hợp lệ.' });
        }

        const pool = await poolPromise;
        if (!pool) return res.status(503).json({ success: false, message: 'Không kết nối được CSDL.' });

        // Tự động kiểm tra và thêm các cột nếu chưa có trong dbo.nguoiDung
        await pool.request().query(`
            IF COL_LENGTH('dbo.nguoiDung', 'googleId') IS NULL ALTER TABLE dbo.nguoiDung ADD googleId NVARCHAR(150) NULL;
            IF COL_LENGTH('dbo.nguoiDung', 'avatarUrl') IS NULL ALTER TABLE dbo.nguoiDung ADD avatarUrl NVARCHAR(500) NULL;
        `);

        // Tìm user theo email hoặc googleId
        let result = await pool.request()
            .input('email', sql.VarChar(150), cleanEmail)
            .input('googleId', sql.NVarChar(150), cleanGoogleId)
            .query(`
                SELECT TOP 1 * FROM dbo.nguoiDung 
                WHERE LOWER(email) = LOWER(@email) 
                   OR (@googleId IS NOT NULL AND googleId = @googleId)
            `);

        let user = null;

        if (result.recordset.length > 0) {
            user = result.recordset[0];
            // Đồng bộ googleId hoặc avatarUrl nếu chưa lưu
            if ((cleanGoogleId && !user.googleId) || (avatarUrl && !user.avatarUrl)) {
                await pool.request()
                    .input('id', sql.Int, user.maNguoiDung)
                    .input('googleId', sql.NVarChar(150), cleanGoogleId || user.googleId)
                    .input('avatarUrl', sql.NVarChar(500), avatarUrl || user.avatarUrl)
                    .query(`
                        UPDATE dbo.nguoiDung 
                        SET googleId = COALESCE(@googleId, googleId),
                            avatarUrl = COALESCE(@avatarUrl, avatarUrl)
                        WHERE maNguoiDung = @id
                    `);
            }
        } else {
            // Tài khoản chưa từng tồn tại -> Đăng ký tự động từ tài khoản Google
            const randomPassword = 'Gg_' + Math.random().toString(36).slice(2, 12) + '!@#$';
            const sdtTam = '09' + Math.floor(10000000 + Math.random() * 90000000).toString();

            const createRes = await pool.request()
                .input('hoTen', sql.NVarChar(100), cleanName)
                .input('email', sql.VarChar(150), cleanEmail)
                .input('sdt', sql.VarChar(20), sdtTam)
                .input('matKhauHash', sql.VarChar(255), hashPassword(randomPassword))
                .input('vaiTro', sql.VarChar(50), cleanRole)
                .input('googleId', sql.NVarChar(150), cleanGoogleId)
                .input('avatarUrl', sql.NVarChar(500), avatarUrl || null)
                .query(`
                    INSERT INTO dbo.nguoiDung (hoTen, email, soDienThoai, matKhauHash, vaiTro, trangThaiTaiKhoan, ngayTao, googleId, avatarUrl)
                    OUTPUT INSERTED.maNguoiDung, INSERTED.hoTen, INSERTED.email, INSERTED.soDienThoai, INSERTED.vaiTro, INSERTED.trangThaiTaiKhoan
                    VALUES (@hoTen, @email, @sdt, @matKhauHash, @vaiTro, 'HoatDong', GETDATE(), @googleId, @avatarUrl)
                `);
            user = createRes.recordset[0];
            console.log(`✅ [GOOGLE-AUTH] Đăng ký thành công tài khoản mới bằng Google: ${cleanEmail}`);
        }

        if (!isAccountActive(user.trangThaiTaiKhoan)) {
            return res.status(403).json({ success: false, message: 'Tài khoản của bạn đã bị khóa!' });
        }

        const normalizedUserRole = normalizeRole(user.vaiTro);
        const token = signToken(user);

        return res.json({
            success: true,
            message: 'Đăng nhập bằng tài khoản Google thành công!',
            token: token,
            user: {
                id: user.maNguoiDung,
                hoTen: user.hoTen,
                email: user.email,
                soDienThoai: user.soDienThoai,
                vaiTro: normalizedUserRole
            }
        });
    } catch (err) {
        console.error('Lỗi dangNhapGoogle:', err);
        return res.status(500).json({ success: false, message: 'Lỗi xác thực Google từ máy chủ.' });
    }
};