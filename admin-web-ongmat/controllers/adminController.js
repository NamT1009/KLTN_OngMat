const { poolPromise, sql } = require('../config/db');
const { getSystemStats } = require('../config/statsRepository');

// Dashboard quản trị: số liệu thống kê thật từ CSDL
exports.getDashboard = async (req, res) => {
    try {
        const stats = await getSystemStats();
        res.render('dashboard', { stats, path: '/' });
    } catch (err) {
        console.error("Lỗi Dashboard: ", err);
        const fallbackStats = {
            kpi: {
                tongNguoiDung: 0, soNguoiNuoiOng: 0, soChuDat: 0, soTaiKhoanKhoa: 0,
                tongDiaDiem: 0, diaDiemDaDuyet: 0, diaDiemChoDuyet: 0, tongDanOng: 0,
                tongThungOng: 0, hopDongHieuLuc: 0, yeuCauChoDuyet: 0,
                tongSanLuongKg: 0, tongSanLuongLit: 0, soLoTruyXuat: 0, lichChamSocChuaXong: 0
            },
            sanLuongTheoThang: [],
            sanLuongTheoLoaiMat: [],
            danOngTheoTinhTrang: [],
            diaDiemSanLuongCao: [],
            loTruyXuatGanDay: []
        };
        try {
            res.render('dashboard', { stats: fallbackStats, path: '/' });
        } catch (renderErr) {
            console.error("Lỗi render dashboard:", renderErr);
            res.redirect('/portal');
        }
    }
};

// Xử lý API Duyệt địa điểm
exports.duyetDiaDiem = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;
        const sqlRequest = pool.request();
        sqlRequest.input('maDiaDiem', sql.Int, id); 
        await sqlRequest.query(`UPDATE diaDiemVuon SET trangThaiKiemDuyet = 'DaDuyet' WHERE maDiaDiem = @maDiaDiem`);
        res.json({ success: true, message: 'Đã duyệt địa điểm thành công!' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: 'Lỗi server khi duyệt' });
    }
};

// Xử lý API Từ chối địa điểm
exports.tuChoiDiaDiem = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;
        const sqlRequest = pool.request();
        sqlRequest.input('maDiaDiem', sql.Int, id);
        await sqlRequest.query(`UPDATE diaDiemVuon SET trangThaiKiemDuyet = 'TuChoi' WHERE maDiaDiem = @maDiaDiem`);
        res.json({ success: true, message: 'Đã từ chối địa điểm!' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: 'Lỗi server khi từ chối' });
    }
};

// ==========================================
// BỔ SUNG: Xử lý API Tìm kiếm toàn cục (4 bảng)
// ==========================================
exports.timKiemToanCuc = async (req, res) => {
    try {
        const tuKhoa = req.query.q;
        
        // Nếu không nhập gì mà bấm tìm kiếm thì trả về trang chủ
        if (!tuKhoa) return res.redirect('/'); 

        const pool = await poolPromise;
        
        // 1. Tìm Người Dùng (Tìm không dấu trên Họ Tên)
        const resNguoiDung = await pool.request()
            .input('tuKhoa', sql.NVarChar, `%${tuKhoa}%`)
            .query("SELECT * FROM nguoiDung WHERE hoTen COLLATE SQL_Latin1_General_CP1_CI_AI LIKE @tuKhoa OR soDienThoai LIKE @tuKhoa OR email LIKE @tuKhoa");

        // 2. Tìm Địa Điểm Vườn (Tìm không dấu trên Tên và Địa chỉ)
        const resDiaDiem = await pool.request()
            .input('tuKhoa', sql.NVarChar, `%${tuKhoa}%`)
            .query("SELECT * FROM diaDiemVuon WHERE tenDiaDiem COLLATE SQL_Latin1_General_CP1_CI_AI LIKE @tuKhoa OR diaChiChiTiet COLLATE SQL_Latin1_General_CP1_CI_AI LIKE @tuKhoa");

        // 3. Tìm Loài Hoa (Tìm không dấu)
        let danhSachHoa = [];
        try {
            const resHoa = await pool.request()
                .input('tuKhoa', sql.NVarChar, `%${tuKhoa}%`)
                .query("SELECT * FROM loaiHoa WHERE tenLoaiHoa COLLATE SQL_Latin1_General_CP1_CI_AI LIKE @tuKhoa");
            danhSachHoa = resHoa.recordset;
        } catch (err) { console.error("Lỗi tìm Hoa:", err.message); }

        // 4. Tìm Loài Ong (Tìm không dấu)
        let danhSachOng = [];
        try {
            const resOng = await pool.request()
                .input('tuKhoa', sql.NVarChar, `%${tuKhoa}%`)
                .query("SELECT * FROM loaiOng WHERE tenLoaiOng COLLATE SQL_Latin1_General_CP1_CI_AI LIKE @tuKhoa");
            danhSachOng = resOng.recordset;
        } catch (err) { console.error("Lỗi tìm Ong:", err.message); }

        // Chuyển toàn bộ dữ liệu ra trang hiển thị
        res.render('ket-qua-tim-kiem', {
            tuKhoa: tuKhoa,
            danhSachNguoiDung: resNguoiDung.recordset,
            danhSachDiaDiem: resDiaDiem.recordset,
            danhSachHoa: danhSachHoa,
            danhSachOng: danhSachOng,
            path: '/tim-kiem'
        });
    } catch (error) {
        console.error("Lỗi tìm kiếm tổng:", error);
        res.status(500).send("Đã xảy ra lỗi khi tìm kiếm.");
    }
};