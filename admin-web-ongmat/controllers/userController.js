const { poolPromise, sql } = require('../config/db');

// Lấy danh sách toàn bộ người dùng
exports.getDanhSachNguoiDung = async (req, res) => {
    try {
        const pool = await poolPromise;
        // Truy vấn lấy người dùng, sắp xếp tài khoản mới tạo lên đầu
        const result = await pool.request().query(`
  SELECT maNguoiDung, hoTen, email, soDienThoai, vaiTro, trangThaiTaiKhoan, anhDaiDien, ngayTao 
  FROM nguoiDung
  ORDER BY maNguoiDung DESC
`);
        // Render ra file view 'nguoi-dung'
        res.render('nguoi-dung', {
            danhSachNguoiDung: result.recordset,
            path: '/nguoi-dung'
        });
    } catch (err) {
        console.error("Lỗi lấy danh sách người dùng: ", err);
        res.status(500).send("Lỗi hệ thống!");
    }
};

// Cập nhật trạng thái Khóa / Mở khóa tài khoản
exports.thayDoiTrangThai = async (req, res) => {
    try {
        const { id, trangThaiMoi } = req.body;
        const pool = await poolPromise;
        const sqlRequest = pool.request();

        sqlRequest.input('maNguoiDung', sql.Int, id);
        sqlRequest.input('trangThaiTaiKhoan', sql.VarChar, trangThaiMoi);

        await sqlRequest.query(`
            UPDATE nguoiDung 
            SET trangThaiTaiKhoan = @trangThaiTaiKhoan 
            WHERE maNguoiDung = @maNguoiDung
        `);

        res.json({ success: true, message: 'Cập nhật trạng thái tài khoản thành công!' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: 'Lỗi khi cập nhật trạng thái' });
    }
};
// Thêm người dùng mới
exports.themNguoiDung = async (req, res) => {
    try {
        const { hoTen, email, soDienThoai, matKhau, vaiTro } = req.body;
        const pool = await poolPromise;
        const sqlRequest = pool.request();

        // Kiểm tra xem Email hoặc SĐT đã tồn tại chưa
        const checkExist = await pool.request()
            .input('email', sql.VarChar, email)
            .input('soDienThoai', sql.VarChar, soDienThoai)
            .query('SELECT maNguoiDung FROM nguoiDung WHERE email = @email OR soDienThoai = @soDienThoai');

        if (checkExist.recordset.length > 0) {
            return res.status(400).json({ success: false, message: 'Email hoặc Số điện thoại đã được đăng ký!' });
        }

        // Thực hiện thêm mới
        sqlRequest.input('hoTen', sql.NVarChar, hoTen);
        sqlRequest.input('email', sql.VarChar, email);
        sqlRequest.input('soDienThoai', sql.VarChar, soDienThoai);
        sqlRequest.input('matKhauHash', sql.VarChar, matKhau);
        sqlRequest.input('vaiTro', sql.VarChar, vaiTro);
        sqlRequest.input('trangThaiTaiKhoan', sql.VarChar, 'HoatDong'); // Mặc định tài khoản mới tạo sẽ hoạt động ngay

        await sqlRequest.query(`
            INSERT INTO nguoiDung (hoTen, email, soDienThoai, matKhauHash, vaiTro, trangThaiTaiKhoan, ngayTao)
            VALUES (@hoTen, @email, @soDienThoai, @matKhauHash, @vaiTro, @trangThaiTaiKhoan, GETDATE())
        `);

        res.json({ success: true, message: 'Thêm người dùng thành công!' });
    } catch (err) {
        console.error("Lỗi thêm người dùng: ", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ khi thêm dữ liệu!' });
    }
};
exports.toggleKhoaNguoiDung = async (req, res) => {
    try {
        const { id, trangThaiMoi } = req.body;
        const pool = await poolPromise;
        await pool.request()
            .input('id', sql.Int, id)
            .input('trangThai', sql.VarChar, trangThaiMoi)
            .query("UPDATE nguoiDung SET trangThaiTaiKhoan = @trangThai WHERE maNguoiDung = @id");

        res.json({ success: true, message: trangThaiMoi === 'DaKhoa' ? 'Đã khóa tài khoản!' : 'Đã mở khóa tài khoản!' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ!' });
    }
};

// Cập nhật thông tin người dùng
exports.suaNguoiDung = async (req, res) => {
    try {
        const { maNguoiDung, hoTen, soDienThoai, vaiTro } = req.body;
        const pool = await poolPromise;
        await pool.request()
            .input('id', sql.Int, maNguoiDung)
            .input('hoTen', sql.NVarChar, hoTen)
            .input('sdt', sql.VarChar, soDienThoai)
            .input('vaiTro', sql.VarChar, vaiTro)
            .query("UPDATE nguoiDung SET hoTen = @hoTen, soDienThoai = @sdt, vaiTro = @vaiTro WHERE maNguoiDung = @id");

        res.json({ success: true, message: 'Cập nhật thông tin thành công!' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ!' });
    }
};

// Xóa người dùng
exports.xoaNguoiDung = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;
        await pool.request()
            .input('id', sql.Int, id)
            .query("DELETE FROM nguoiDung WHERE maNguoiDung = @id");

        res.json({ success: true, message: 'Xóa người dùng thành công!' });
    } catch (error) {
        console.error(error);
        // Bắt lỗi khóa ngoại nếu người dùng đang có vườn hoặc trại ong
        res.status(500).json({ success: false, message: 'Không thể xóa vì người dùng này đang có dữ liệu (Vườn/Trại ong) liên kết trong hệ thống!' });
    }
};