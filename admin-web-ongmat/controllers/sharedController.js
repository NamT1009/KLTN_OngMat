const { sql, poolPromise } = require('../config/db');
const beekeeping = require('../config/beekeepingRepository');
const { AppError, asyncHandler, positiveNumber } = require('../utils/http');
const { comparePassword, hashPassword } = require('../utils/authHelpers');

// 1. Hồ sơ người dùng (GET)
exports.profile = asyncHandler(async (req, res) => {
    const userId = req.user?.id ?? req.user?.maNguoiDung ?? req.user?.userId;
    if (!userId) throw new AppError(401, 'Không xác định được ID người dùng từ Token.');

    const pool = await poolPromise;
    const result = await pool.request()
        .input('id', sql.Int, userId)
        .query(`
            SELECT 
                d.maNguoiDung, d.hoTen, d.email, d.soDienThoai, d.vaiTro, d.anhDaiDien, d.ngayTao, d.trangThaiTaiKhoan,
                ISNULL((SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = d.maNguoiDung), 0) AS tongDanhGia,
                (SELECT CAST(ROUND(AVG(CAST(dg.soSao AS FLOAT)), 1) AS DECIMAL(3,1)) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = d.maNguoiDung) AS uyTin,
                CASE WHEN (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = d.maNguoiDung) = 0 THEN 1 ELSE 0 END AS laNguoiMoi
            FROM dbo.nguoiDung d
            WHERE d.maNguoiDung = @id
        `);

    const user = result.recordset[0];
    if (!user) throw new AppError(404, 'Không tìm thấy người dùng.');
    
    // Thống kê nhanh hoạt động theo vai trò để hiển thị trang cá nhân sinh động
    user.stats = {};
    try {
        if (user.vaiTro === 'chuDat') {
            const stats = await pool.request().input('id', sql.Int, userId).query(`
                SELECT 
                    COUNT(*) AS tongDiaDiem,
                    SUM(CASE WHEN trangThaiKiemDuyet = 'DaDuyet' THEN 1 ELSE 0 END) AS diaDiemDaDuyet
                FROM dbo.diaDiemVuon WHERE maChuDat = @id
            `);
            user.stats = stats.recordset[0] || {};
        } else if (user.vaiTro === 'nguoiNuoiOng') {
            const stats = await pool.request().input('id', sql.Int, userId).query(`
                SELECT 
                    (SELECT COUNT(*) FROM dbo.danOng WHERE maNguoiDung = @id) AS tongDanOng,
                    (SELECT COUNT(*) FROM dbo.hopDongThueOng WHERE maNguoiNuoiOng = @id AND trangThai = 'DaKy') AS hopDongHieuLuc
            `);
            user.stats = stats.recordset[0] || {};
        }

        // Lấy danh sách 5 đánh giá sao gần đây nhất của đối tác
        const reviews = await pool.request().input('id', sql.Int, userId).query(`
            SELECT TOP 5 dg.maDanhGia, dg.soSao, dg.nhanXet, FORMAT(DATEADD(HOUR, 7, dg.ngayTao), 'dd/MM/yyyy') AS ngayTao,
                   nd.hoTen AS nguoiDanhGia, nd.anhDaiDien AS avatarNguoiDanhGia
            FROM dbo.danhGiaThueOng dg
            LEFT JOIN dbo.nguoiDung nd ON dg.maNguoiDanhGia = nd.maNguoiDung
            WHERE dg.maNguoiDuocDanhGia = @id
            ORDER BY dg.ngayTao DESC
        `);
        user.danhSachDanhGia = reviews.recordset || [];
    } catch (err) {
        console.error('Lỗi lấy stats/reviews profile:', err);
        user.danhSachDanhGia = [];
    }

    // Đồng bộ thuộc tính avatar để tương thích với app Flutter
    user.avatar = user.anhDaiDien || null; 

    res.json({ success: true, data: user });
});

// 1.1 Cập nhật hồ sơ người dùng (PUT)
exports.updateProfile = asyncHandler(async (req, res) => {
    const userId = req.user?.id ?? req.user?.maNguoiDung ?? req.user?.userId;
    if (!userId) throw new AppError(401, 'Không xác định được ID người dùng.');

    const { hoTen, soDienThoai, email, matKhauCu, matKhauMoi, matKhau } = req.body;
    const pool = await poolPromise;

    // Lấy thông tin hiện tại của người dùng từ CSDL bao gồm matKhauHash
    const currentUserRes = await pool.request()
        .input('uid', sql.Int, userId)
        .query('SELECT maNguoiDung, matKhauHash, email, soDienThoai FROM dbo.nguoiDung WHERE maNguoiDung = @uid');
    
    const currentUser = currentUserRes.recordset[0];
    if (!currentUser) throw new AppError(404, 'Không tìm thấy người dùng.');

    const newPassword = String(matKhauMoi || matKhau || '').trim();
    const oldPassword = String(matKhauCu || '').trim();

    let shouldUpdatePassword = false;
    let hashedNewPassword = null;

    // Khi người dùng muốn đổi mật khẩu
    if (newPassword !== '' || oldPassword !== '') {
        if (!oldPassword) {
            throw new AppError(400, 'Vui lòng nhập mật khẩu hiện tại (mật khẩu cũ) để xác nhận đổi mật khẩu.');
        }
        if (!newPassword) {
            throw new AppError(400, 'Vui lòng nhập mật khẩu mới.');
        }
        if (newPassword.length < 6) {
            throw new AppError(400, 'Mật khẩu mới phải có ít nhất 6 ký tự.');
        }

        // Kiểm tra mật khẩu cũ khớp với dữ liệu trong database
        const isMatch = comparePassword(oldPassword, currentUser.matKhauHash);
        if (!isMatch) {
            throw new AppError(400, 'Mật khẩu cũ không chính xác. Vui lòng kiểm tra lại!');
        }

        if (oldPassword === newPassword) {
            throw new AppError(400, 'Mật khẩu mới không được trùng với mật khẩu cũ.');
        }

        shouldUpdatePassword = true;
        hashedNewPassword = hashPassword(newPassword);
    }

    const request = pool.request()
        .input('uid', sql.Int, userId)
        .input('hoTen', sql.NVarChar(100), hoTen ? hoTen.trim() : null)
        .input('soDienThoai', sql.VarChar(20), soDienThoai ? soDienThoai.trim() : null)
        .input('email', sql.VarChar(100), email ? email.trim() : null);

    let query = `
        UPDATE dbo.nguoiDung
        SET hoTen = ISNULL(@hoTen, hoTen),
            soDienThoai = ISNULL(@soDienThoai, soDienThoai),
            email = ISNULL(@email, email)
    `;

    if (shouldUpdatePassword && hashedNewPassword) {
        request.input('matKhauHash', sql.VarChar(255), hashedNewPassword);
        query += `, matKhauHash = @matKhauHash `;
    }

    query += ` WHERE maNguoiDung = @uid`;
    await request.query(query);

    if (req.session?.user) {
        if (hoTen) req.session.user.hoTen = hoTen.trim();
        if (soDienThoai) req.session.user.soDienThoai = soDienThoai.trim();
        if (email) req.session.user.email = email.trim();
    }

    res.json({ 
        success: true, 
        message: shouldUpdatePassword 
            ? 'Cập nhật thông tin và đổi mật khẩu thành công!' 
            : 'Cập nhật thông tin thành công!' 
    });
});

// 1.2 Cập nhật ảnh đại diện (POST)
exports.updateAvatar = asyncHandler(async (req, res) => {
    if (!req.file) {
        throw new AppError(400, 'Vui lòng chọn hình ảnh để tải lên.');
    }

    const userId = req.user?.id ?? req.user?.maNguoiDung ?? req.user?.userId;
    if (!userId) {
        throw new AppError(401, 'Không xác định được ID người dùng.');
    }

    // Đường dẫn tương đối lưu vào DB
    const avatarUrl = `/uploads/avatars/${req.file.filename}`;
    const pool = await poolPromise;

    await pool.request()
        .input('userId', sql.Int, userId)
        .input('avatarUrl', sql.NVarChar(500), avatarUrl)
        .query(`
            UPDATE dbo.nguoiDung 
            SET anhDaiDien = @avatarUrl 
            WHERE maNguoiDung = @userId
        `);

    if (req.session?.user) {
        req.session.user.anhDaiDien = avatarUrl;
    }

    res.json({
        success: true,
        message: 'Cập nhật ảnh đại diện thành công.',
        data: { 
            anhDaiDien: avatarUrl,
            avatar: avatarUrl
        }
    });
});

// 2. Thông báo
exports.notifications = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await beekeeping.getNotifications(req.user.id) });
});

exports.markNotificationsRead = asyncHandler(async (req, res) => {
    const id = req.body?.id ? positiveNumber(req.body.id, 'Mã thông báo', { integer: true }) : null;
    await beekeeping.markNotificationsRead(req.user.id, id);
    res.json({ success: true, message: 'Đã đánh dấu đã đọc.' });
});

// 3. Danh sách & chi tiết hợp đồng
exports.contracts = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await beekeeping.getContracts(req.user) });
});

exports.contractDetail = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await beekeeping.getContract(req.user, String(req.params.id)) });
});

// 4. Xác thực OTP & Ký hợp đồng
const otpStore = new Map();

exports.requestContractOtp = asyncHandler(async (req, res) => {
    const contractId = String(req.params.id);
    const contract = await beekeeping.getContract(req.user, contractId);
    if (contract.maNguoiNuoiOng !== req.user.id) {
        throw new AppError(403, 'Chỉ người nuôi ong trong hợp đồng mới có quyền ký.');
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    otpStore.set(`${req.user.id}:${contractId}`, { otp, expires: Date.now() + 5 * 60 * 1000 });
    
    await beekeeping.notify(
        await poolPromise,
        req.user.id,
        'Mã OTP ký hợp đồng',
        `Mã OTP ký hợp đồng ${contract.tenHopDong || contractId} là ${otp}. Hiệu lực 5 phút.`,
        'Cao'
    );
    res.json({ success: true, message: 'Đã gửi mã OTP vào mục thông báo.', data: { demoOtp: otp } });
});

exports.signContract = asyncHandler(async (req, res) => {
    const contractId = String(req.params.id);
    const otpInput = String(req.body?.otp ?? '').trim();
    const key = `${req.user.id}:${contractId}`;
    const record = otpStore.get(key);
    
    if (!record || record.expires < Date.now() || record.otp !== otpInput) {
        throw new AppError(400, 'Mã OTP không chính xác hoặc đã hết hạn.');
    }
    otpStore.delete(key);
    const signed = await beekeeping.signContract(req.user, contractId);
    res.json({ success: true, message: 'Đã ký hợp đồng thành công.', data: signed });
});

// Hoàn tất hợp đồng thuê
exports.completeContract = asyncHandler(async (req, res) => {
    const contractId = String(req.params.id);
    const contract = await beekeeping.completeContract(req.user, contractId);
    res.json({ success: true, message: 'Đã hoàn tất hợp đồng thuê đất.', data: contract });
});

// Gửi / Cập nhật đánh giá hợp đồng
exports.submitReview = asyncHandler(async (req, res) => {
    const contractId = String(req.params.id);
    const reviews = await beekeeping.submitReview(req.user, contractId, req.body || {});
    res.json({ success: true, message: 'Đã gửi đánh giá thành công.', data: reviews });
});

// Lấy danh sách đánh giá của 1 hợp đồng
exports.getContractReviews = asyncHandler(async (req, res) => {
    const contractId = String(req.params.id);
    const reviews = await beekeeping.getContractReviews(req.user, contractId);
    res.json({ success: true, data: reviews });
});

// Lấy đánh giá của 1 địa điểm vườn
exports.getLocationReviews = asyncHandler(async (req, res) => {
    const locId = Number(req.params.id || 0);
    const data = await beekeeping.getLocationReviews(locId);
    res.json({ success: true, data });
});

// Quản trị viên xem tất cả đánh giá
exports.getAllReviews = asyncHandler(async (req, res) => {
    const data = await beekeeping.getAllReviews();
    res.json({ success: true, data });
});

// 5. Truy xuất công khai (Web QR)
exports.publicTrace = async (req, res) => {
    try {
        const id = Number(req.query.ma || req.query.id || 0);
        const trace = await beekeeping.getPublicTrace(id);
        if (!trace) return res.status(404).send('Không tìm thấy thông tin lô mật.');
        res.render('truy-xuat', { trace, diaDiem: trace, danhSachSanPham: [] });
    } catch (err) {
        res.status(500).send('Lỗi máy chủ khi truy xuất.');
    }
};

// 6. GIAO DIỆN HỢP ĐỒNG PDF CHUẨN A4
exports.contractPdf = async (req, res) => {
    try {
        const maHopDong = req.params.id;
        const pool = await poolPromise;
        if (!pool) return res.status(503).send("Hệ thống cơ sở dữ liệu tạm thời không khả dụng.");

        const query = `
            SELECT 
                h.maHopDong, h.tenHopDong, h.giaThue, h.thoiHan, h.quyDinhBoiThuong, h.trangThai, h.otpVerified,
                FORMAT(DATEADD(HOUR, 7, h.ngayKy), 'dd/MM/yyyy HH:mm') AS ngayKyFormatted,
                FORMAT(DATEADD(HOUR, 7, h.ngayTao), 'dd/MM/yyyy HH:mm') AS ngayTaoFormatted,
                h.ngayKy, h.ngayTao,
                v.maDiaDiem, v.tenDiaDiem, v.diaChiChiTiet, v.dienTich, v.sucChuaToiDa, v.thongTinPhapLy,
                cd.hoTen AS tenChuDat, cd.soDienThoai AS sdtChuDat, cd.email AS emailChuDat,
                nn.hoTen AS tenNguoiNuoiOng, nn.soDienThoai AS sdtNguoiNuoiOng, nn.email AS emailNguoiNuoiOng,
                y.soDanOng, y.thoiGianBatDau, y.thoiGianKetThuc
            FROM dbo.hopDongThueOng h
            LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = h.maDiaDiem
            LEFT JOIN dbo.nguoiDung cd ON cd.maNguoiDung = COALESCE(h.maChuDat, v.maChuDat)
            LEFT JOIN dbo.nguoiDung nn ON nn.maNguoiDung = h.maNguoiNuoiOng
            LEFT JOIN dbo.yeuCauThueOng y ON y.maYeuCau = h.maYeuCau
            WHERE h.maHopDong = @maHopDong
        `;

        const result = await pool.request()
            .input('maHopDong', sql.NVarChar(50), maHopDong)
            .query(query);

        const hd = result.recordset[0];
        if (!hd) return res.status(404).send("<h3 style='text-align:center;margin-top:50px;color:red;'>Không tìm thấy thông tin hợp đồng!</h3>");

        const ngayLap = hd.ngayKy || hd.ngayTao || new Date();
        const dateObj = new Date(ngayLap);
        const ngay = dateObj.getDate().toString().padStart(2, '0');
        const thang = (dateObj.getMonth() + 1).toString().padStart(2, '0');
        const nam = dateObj.getFullYear();
        const giaThueText = hd.giaThue ? Number(hd.giaThue).toLocaleString('vi-VN') + ' VNĐ' : 'Theo thỏa thuận thực tế';
        const isDaKy = hd.trangThai === 'DaKy';

        res.send(`
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hợp Đồng Điện Tử - ${hd.maHopDong}</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Times New Roman', Times, serif; font-size: 13.5pt; line-height: 1.5; color: #000; background-color: #f3f4f6; margin: 0; padding: 20px 0; }
        .page { width: 210mm; min-height: 297mm; padding: 20mm 20mm 20mm 25mm; margin: 0 auto; background: #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.1); position: relative; }
        .header-top { display: flex; justify-content: space-between; text-align: center; margin-bottom: 25px; }
        .header-top .side { width: 48%; }
        .quoc-hieu { font-weight: bold; font-size: 11pt; text-transform: uppercase; }
        .tieu-ngu { font-weight: bold; font-size: 12pt; margin-top: 3px; }
        .line-decor { width: 130px; height: 1.5px; background: #000; margin: 4px auto 0; }
        .contract-title { text-align: center; font-size: 16pt; font-weight: bold; text-transform: uppercase; margin: 25px 0 5px 0; }
        .contract-sub { text-align: center; font-style: italic; font-size: 12pt; margin-bottom: 25px; }
        .legal-basis { font-style: italic; font-size: 12pt; margin-bottom: 15px; text-align: justify; }
        .party-box { margin-bottom: 15px; }
        .party-title { font-weight: bold; font-size: 13pt; text-transform: uppercase; margin-bottom: 5px; }
        .info-row { display: flex; margin-bottom: 4px; }
        .info-label { width: 220px; font-weight: bold; }
        .info-value { flex: 1; }
        .section-title { font-weight: bold; margin-top: 15px; margin-bottom: 6px; }
        p { margin: 6px 0; text-align: justify; }
        .signature-section { margin-top: 35px; display: flex; justify-content: space-between; page-break-inside: avoid; }
        .sig-box { width: 45%; text-align: center; position: relative; }
        .sig-title { font-weight: bold; text-transform: uppercase; }
        .sig-sub { font-style: italic; font-size: 11pt; margin-bottom: 65px; }
        .sig-name { font-weight: bold; font-size: 13pt; }
        .stamp-signed { position: absolute; top: 40px; left: 50%; transform: translateX(-50%) rotate(-8deg); border: 2px solid #dc2626; color: #dc2626; padding: 8px 14px; border-radius: 8px; font-weight: bold; font-size: 11pt; text-transform: uppercase; background: rgba(254, 226, 226, 0.65); pointer-events: none; }
        .stamp-waiting { position: absolute; top: 40px; left: 50%; transform: translateX(-50%); border: 2px dashed #f59e0b; color: #d97706; padding: 8px 12px; border-radius: 6px; font-weight: bold; font-size: 11pt; background: #fffbeb; }
        .floating-actions { position: fixed; bottom: 25px; right: 25px; display: flex; gap: 12px; z-index: 999; }
        .btn-action { background: #d97706; color: #fff; border: none; padding: 12px 20px; border-radius: 30px; font-size: 11pt; font-weight: bold; cursor: pointer; box-shadow: 0 4px 12px rgba(0,0,0,0.25); display: flex; align-items: center; gap: 8px; text-decoration: none; }
        .btn-action:hover { background: #b45309; }
        .btn-close-tab { background: #4b5563; }
        @media print {
            body { background: none; padding: 0; }
            .page { box-shadow: none; margin: 0; width: 100%; min-height: auto; padding: 15mm 15mm; }
            .floating-actions { display: none !important; }
            @page { size: A4; margin: 10mm; }
        }
    </style>
</head>
<body>
    <div class="floating-actions">
        <button class="btn-action" onclick="window.print()"><i class="fas fa-print"></i> In Hợp Đồng / Tải PDF</button>
        <button class="btn-action btn-close-tab" onclick="window.close()"><i class="fas fa-times"></i> Đóng</button>
    </div>
    <div class="page">
        <div class="header-top">
            <div class="side">
                <div class="quoc-hieu">HỆ THỐNG TRUY VẾT ONG MẬT</div>
                <div style="font-size: 10pt; font-style: italic;">Hợp đồng số: <b>${hd.maHopDong}</b></div>
            </div>
            <div class="side">
                <div class="quoc-hieu">CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM</div>
                <div class="tieu-ngu">Độc lập - Tự do - Hạnh phúc</div>
                <div class="line-decor"></div>
                <div style="font-size: 11pt; font-style: italic; margin-top: 6px;">Ngày ${ngay} tháng ${thang} năm ${nam}</div>
            </div>
        </div>
        <div class="contract-title">HỢP ĐỒNG THUÊ ĐỊA ĐIỂM ĐẶT TRẠI ONG MẬT</div>
        <div class="contract-sub">(V/v: Khai thác mật hoa kết hợp hỗ trợ thụ phấn cây trồng nông nghiệp)</div>
        <div class="legal-basis">
            - Căn cứ Bộ luật Dân sự số 91/2015/QH13 đã được Quốc hội nước CHXHCN Việt Nam thông qua;<br>
            - Căn cứ Luật Chăn nuôi số 32/2018/QH14 và các quy định quản lý an toàn dịch bệnh vật nuôi;
        </div>
        <div class="party-box">
            <div class="party-title">BÊN CHO THUÊ (BÊN A - CHỦ ĐẤT / CHỦ VƯỜN):</div>
            <div class="info-row"><span class="info-label">Họ và tên chủ vườn:</span><span class="info-value"><b>${hd.tenChuDat || '—'}</b></span></div>
            <div class="info-row"><span class="info-label">Số điện thoại:</span><span class="info-value">${hd.sdtChuDat || '—'}</span></div>
            <div class="info-row"><span class="info-label">Tên khu vườn:</span><span class="info-value"><b>${hd.tenDiaDiem || '—'}</b></span></div>
            <div class="info-row"><span class="info-label">Địa chỉ mặt bằng:</span><span class="info-value">${hd.diaChiChiTiet || '—'}</span></div>
            <div class="info-row"><span class="info-label">Quy mô diện tích:</span><span class="info-value">${hd.dienTich ? hd.dienTich + ' m² (ha)' : 'Theo ranh giới thực tế'} - Sức chứa: ${hd.sucChuaToiDa || 0} đàn</div>
        </div>
        <div class="party-box">
            <div class="party-title">BÊN THUÊ (BÊN B - NGƯỜI NUÔI ONG / CHỦ TRẠI ONG):</div>
            <div class="info-row"><span class="info-label">Họ và tên người nuôi ong:</span><span class="info-value"><b>${hd.tenNguoiNuoiOng || '—'}</b></span></div>
            <div class="info-row"><span class="info-label">Số điện thoại:</span><span class="info-value">${hd.sdtNguoiNuoiOng || '—'}</span></div>
            <div class="info-row"><span class="info-label">Số lượng đàn ong đưa vào:</span><span class="info-value"><b>${hd.soDanOng || 0} đàn</b></span></div>
        </div>
        <p>Hai bên đồng ý ký kết hợp đồng với các điều khoản sau:</p>
        <div class="section-title">ĐIỀU 1: MỤC ĐÍCH VÀ PHẠM VI SỬ DỤNG</div>
        <p>Bên A đồng ý cho Bên B thuê diện tích mặt bằng tại vườn <b>${hd.tenDiaDiem}</b> để hạ trại, bố trí thùng ong phục vụ thu hoạch mật hoa kết hợp hỗ trợ thụ phấn cây trồng.</p>
        <div class="section-title">ĐIỀU 2: THỜI HẠN THUÊ VÀ GIÁ THUÊ</div>
        <p>2.1. <b>Thời hạn thuê:</b> ${hd.thoiHan || 'Theo mùa vụ hoa'}.</p>
        <p>2.2. <b>Giá thuê mặt bằng:</b> <b>${giaThueText}</b>.</p>
        <div class="section-title">ĐIỀU 3: AN TOÀN VÀ BẢO VỆ MÔI TRƯỜNG</div>
        <p>Trong thời gian đàn ong lưu trú, nếu Bên A phun thuốc bảo vệ thực vật phải thông báo trước tối thiểu <b>48 giờ</b> để Bên B chủ động che chắn hoặc di dời đàn ong tạm thời.</p>
        <div class="section-title">ĐIỀU 4: BỒI THƯỜNG THIỆT HẠI</div>
        <p>${hd.quyDinhBoiThuong || 'Hai bên cam kết tuân thủ đúng nội dung đã thống nhất. Mọi tổn thất do vi phạm cam kết sẽ bồi thường theo giá thị trường.'}</p>
        <div class="signature-section">
            <div class="sig-box">
                <div class="sig-title">ĐẠI DIỆN BÊN A</div>
                <div class="sig-sub">(Chủ vườn ký xác nhận)</div>
                <div class="stamp-signed" style="color:#059669;border-color:#059669;background:rgba(209,250,229,0.6);"><i class="fas fa-check-circle"></i> ĐÃ DUYỆT MẶT BẰNG</div>
                <div class="sig-name">${hd.tenChuDat || 'Chủ đất'}</div>
            </div>
            <div class="sig-box">
                <div class="sig-title">ĐẠI DIỆN BÊN B</div>
                <div class="sig-sub">(Người nuôi ong ký xác nhận)</div>
                ${isDaKy ? `<div class="stamp-signed"><i class="fas fa-shield-alt"></i> ĐÃ KÝ ĐIỆN TỬ<br><span style="font-size:8pt;color:#991b1b;">OTP · ${hd.ngayKyFormatted || 'Đã chứng thực'}</span></div>` : `<div class="stamp-waiting"><i class="fas fa-clock"></i> CHỜ KÝ XÁC NHẬN</div>`}
                <div class="sig-name">${hd.tenNguoiNuoiOng || 'Người nuôi ong'}</div>
            </div>
        </div>
    </div>
</body>
</html>
        `);
    } catch (error) {
        console.error("Lỗi tạo hợp đồng PDF:", error);
        res.status(500).send("Lỗi máy chủ khi tạo hợp đồng PDF.");
    }
};

// API lấy danh mục các loài hoa và loài ong từ CSDL để Mobile hiển thị động
exports.getCatalogSpecies = asyncHandler(async (req, res) => {
    const pool = await poolPromise;
    let flowers = [];
    let bees = [];
    if (pool) {
        try {
            const flowerRes = await pool.request().query('SELECT maLoaiHoa, tenLoaiHoa, moTaMatDo FROM dbo.loaiHoa ORDER BY maLoaiHoa ASC');
            flowers = flowerRes.recordset || [];
        } catch (e) {
            console.warn('Lỗi lấy danh mục hoa:', e.message);
        }
        try {
            const beeRes = await pool.request().query('SELECT maLoaiOng, tenLoaiOng, khiHauThichHop, dacDiemSinhHoc, nguonHoaUaThich FROM dbo.loaiOng ORDER BY maLoaiOng ASC');
            bees = beeRes.recordset || [];
        } catch (e) {
            console.warn('Lỗi lấy danh mục giống ong:', e.message);
        }
    }
    // Nếu chưa có dữ liệu trong CSDL, trả về danh mục mặc định
    if (!flowers || flowers.length === 0) {
        flowers = [
            { maLoaiHoa: 1, tenLoaiHoa: 'Hoa Cà Phê', moTaMatDo: 'Tây Nguyên' },
            { maLoaiHoa: 2, tenLoaiHoa: 'Hoa Vải Thiều', moTaMatDo: 'Bắc Giang' },
            { maLoaiHoa: 3, tenLoaiHoa: 'Hoa Nhãn Lồng', moTaMatDo: 'Hưng Yên' },
            { maLoaiHoa: 4, tenLoaiHoa: 'Hoa Tràm Rừng', moTaMatDo: 'Miền Tây' },
            { maLoaiHoa: 5, tenLoaiHoa: 'Hoa Mận Mơ', moTaMatDo: 'Mộc Châu, Sơn La' },
            { maLoaiHoa: 6, tenLoaiHoa: 'Hoa Bạc Hà Đá', moTaMatDo: 'Hà Giang' },
            { maLoaiHoa: 7, tenLoaiHoa: 'Hoa Rừng Tự Nhiên', moTaMatDo: 'Đa loài hoa' }
        ];
    }
    if (!bees || bees.length === 0) {
        bees = [
            { maLoaiOng: 1, tenLoaiOng: 'Ong nội (Apis cerana)', khiHauThichHop: 'Nhiệt đới và cận nhiệt đới' },
            { maLoaiOng: 2, tenLoaiOng: 'Ong Ý (Apis mellifera)', khiHauThichHop: 'Ôn hòa khô ráo' },
            { maLoaiOng: 3, tenLoaiOng: 'Ong dú (Stingless bee)', khiHauThichHop: 'Nhiệt đới ẩm' },
            { maLoaiOng: 4, tenLoaiOng: 'Mọi loài ong', khiHauThichHop: 'Thích nghi tốt' }
        ];
    }
    res.json({
        success: true,
        data: {
            flowers,
            bees
        }
    });
});

exports.getCatalogFlowers = asyncHandler(async (req, res) => {
    const pool = await poolPromise;
    let flowers = [];
    if (pool) {
        const flowerRes = await pool.request().query('SELECT maLoaiHoa, tenLoaiHoa, moTaMatDo FROM dbo.loaiHoa ORDER BY maLoaiHoa ASC');
        flowers = flowerRes.recordset || [];
    }
    res.json({ success: true, data: flowers });
});

exports.getCatalogBees = asyncHandler(async (req, res) => {
    const pool = await poolPromise;
    let bees = [];
    if (pool) {
        const beeRes = await pool.request().query('SELECT maLoaiOng, tenLoaiOng, khiHauThichHop, dacDiemSinhHoc FROM dbo.loaiOng ORDER BY maLoaiOng ASC');
        bees = beeRes.recordset || [];
    }
    res.json({ success: true, data: bees });
});