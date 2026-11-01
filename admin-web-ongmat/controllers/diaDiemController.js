const os = require('os');
const { sql, poolPromise } = require('../config/db');

// Hàm tự động lấy đúng IP mạng nội bộ của máy tính (tránh dải .1 và VPN)
function getLocalIp() {
    const interfaces = os.networkInterfaces();
    let selectedIp = 'localhost';

    for (const name of Object.keys(interfaces)) {
        for (const net of interfaces[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                const ip = net.address;
                // Bỏ qua các IP Gateway kết thúc bằng .1 hoặc dải VPN (26.)
                if (!ip.endsWith('.1') && !ip.startsWith('26.')) {
                    if (ip.startsWith('192.168.') || ip.startsWith('172.16.') || ip.startsWith('10.')) {
                        selectedIp = ip; // Ưu tiên dải mạng Wi-Fi/LAN chính
                    } else if (selectedIp === 'localhost') {
                        selectedIp = ip;
                    }
                }
            }
        }
    }
    return selectedIp;
}

// 1. Lấy danh sách địa điểm cần kiểm duyệt
exports.getDanhSachKiemDuyet = async (req, res) => {
    try {
        const pool = await poolPromise;
        const queryDiaDiem = `
            SELECT d.*, n.hoTen AS tenChuDat 
            FROM diaDiemVuon d
            INNER JOIN nguoiDung n ON d.maChuDat = n.maNguoiDung
            ORDER BY CASE WHEN d.trangThaiKiemDuyet = 'ChoDiemDuyet' THEN 1 ELSE 2 END, d.ngayTao DESC
        `;
        const resultDiaDiem = await pool.request().query(queryDiaDiem);

        const queryChuDat = `SELECT maNguoiDung, hoTen, soDienThoai FROM nguoiDung WHERE LOWER(vaiTro) = 'chudat'`;
        const resultChuDat = await pool.request().query(queryChuDat);

        res.render('kiem-duyet', {
            danhSachDiaDiem: resultDiaDiem.recordset,
            danhSachChuDat: resultChuDat.recordset,
            danhSachHoa: (await pool.request().query("SELECT tenLoaiHoa FROM loaiHoa ORDER BY tenLoaiHoa")).recordset || [],
            danhSachOng: (await pool.request().query("SELECT tenLoaiOng FROM loaiOng ORDER BY tenLoaiOng")).recordset || [],
            path: '/kiem-duyet'
        });
    } catch (err) {
        console.error("Lỗi lấy danh sách địa điểm: ", err);
        res.status(500).send("Lỗi máy chủ khi tải trang kiểm duyệt");
    }
};

// 2. Hàm xử lý Phê duyệt
exports.duyetDiaDiem = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;
        await pool.request()
            .input('maDiaDiem', sql.Int, id)
            .query(`UPDATE diaDiemVuon SET trangThaiKiemDuyet = 'DaDuyet' WHERE maDiaDiem = @maDiaDiem`);

        res.json({ success: true, message: 'Đã phê duyệt địa điểm thành công!' });
    } catch (err) {
        console.error("Lỗi duyệt địa điểm:", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ!' });
    }
};

// 3. Hàm xử lý Từ chối
exports.tuChoiDiaDiem = async (req, res) => {
    try {
        const { id, lyDo } = req.body;
        const pool = await poolPromise;
        await pool.request()
            .input('maDiaDiem', sql.Int, id)
            .input('lyDo', sql.NVarChar, lyDo)
            .query(`UPDATE diaDiemVuon SET trangThaiKiemDuyet = 'TuChoi', lyDoTuChoi = @lyDo WHERE maDiaDiem = @maDiaDiem`);

        res.json({ success: true, message: 'Đã từ chối địa điểm và lưu lý do thành công!' });
    } catch (err) {
        console.error("Lỗi từ chối địa điểm:", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ!' });
    }
};

// 4. Lấy danh sách bài đăng hoạt động kèm host động cho mã QR
exports.getBaiDangHoatDong = async (req, res) => {
    try {
        const pool = await poolPromise;
        const query = `
            SELECT 
                d.maDiaDiem, d.tenDiaDiem, d.dienTich, d.sucChuaToiDa, d.diaChiChiTiet, d.hinhAnh,
                d.loaiHoa, d.loaiOngPhuHop, d.giaThueThang, d.khiHau,
                n.hoTen AS tenChuDat, n.soDienThoai,
                
                -- Tổng số đàn ong đã ký hợp đồng thuê có hiệu lực
                ISNULL((
                    SELECT SUM(y.soDanOng)
                    FROM dbo.hopDongThueOng h
                    JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                    WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = 'DaKy'
                ), 0) AS soDanDaThue,

                -- Sức chứa còn lại (chỗ trống còn nhận thêm)
                CASE 
                    WHEN d.sucChuaToiDa - ISNULL((
                        SELECT SUM(y.soDanOng)
                        FROM dbo.hopDongThueOng h
                        JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                        WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = 'DaKy'
                    ), 0) < 0 THEN 0
                    ELSE d.sucChuaToiDa - ISNULL((
                        SELECT SUM(y.soDanOng)
                        FROM dbo.hopDongThueOng h
                        JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                        WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = 'DaKy'
                    ), 0)
                END AS sucChuaConLai,

                -- Danh sách người nuôi ong đang thuê
                (
                    SELECT STRING_AGG(CONCAT(nn.hoTen, ' (', y.soDanOng, ' đàn)'), ', ')
                    FROM dbo.hopDongThueOng h
                    JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                    JOIN dbo.nguoiDung nn ON h.maNguoiNuoiOng = nn.maNguoiDung
                    WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = 'DaKy'
                ) AS danhSachNguoiThue,

                (SELECT TOP 1 m.sanLuongMatDuKien 
                 FROM muaVuHoa m 
                 WHERE m.maDiaDiem = d.maDiaDiem AND m.trangThaiMuaVu = 'DangNo') AS sanLuongHienCo
                 
            FROM diaDiemVuon d
            JOIN nguoiDung n ON d.maChuDat = n.maNguoiDung
            WHERE d.trangThaiKiemDuyet = 'DaDuyet'
            ORDER BY d.ngayTao DESC
        `;

        const result = await pool.request().query(query);
        const danhSachBaiDang = result.recordset;

        const serverIp = getLocalIp();
        const dynamicHost = `${serverIp}:3000`;

        res.render('danh-sach-bai-dang', {
            danhSachBaiDang,
            host: dynamicHost
        });
    } catch (err) {
        console.error(err);
        res.status(500).send("Lỗi server");
    }
};

// 5. Xử lý API Thêm địa điểm mới bởi Admin
exports.themDiaDiem = async (req, res) => {
    try {
        const { maChuDat, tenDiaDiem, dienTich, sucChuaToiDa, diaChiChiTiet, viDo, kinhDo, thongTinPhapLy, loaiHoa, loaiOngPhuHop, khiHau, giaThueThang, hinhAnh } = req.body;
        const pool = await poolPromise;
        
        const query = `
            INSERT INTO diaDiemVuon (maChuDat, tenDiaDiem, viDo, kinhDo, dienTich, sucChuaToiDa, diaChiChiTiet, thongTinPhapLy, loaiHoa, loaiOngPhuHop, khiHau, giaThueThang, hinhAnh, trangThaiKiemDuyet)
            VALUES (@maChuDat, @tenDiaDiem, @viDo, @kinhDo, @dienTich, @sucChuaToiDa, @diaChiChiTiet, @thongTinPhapLy, @loaiHoa, @loaiOngPhuHop, @khiHau, @giaThueThang, @hinhAnh, 'DaDuyet')
        `;

        await pool.request()
            .input('maChuDat', sql.Int, maChuDat)
            .input('tenDiaDiem', sql.NVarChar, tenDiaDiem)
            .input('viDo', sql.Decimal(10, 8), viDo)
            .input('kinhDo', sql.Decimal(11, 8), kinhDo)
            .input('dienTich', sql.Float, dienTich)
            .input('sucChuaToiDa', sql.Int, sucChuaToiDa)
            .input('diaChiChiTiet', sql.NVarChar, diaChiChiTiet)
            .input('thongTinPhapLy', sql.NVarChar, thongTinPhapLy || null)
            .input('loaiHoa', sql.NVarChar, loaiHoa || null)
            .input('loaiOngPhuHop', sql.NVarChar, loaiOngPhuHop || null)
            .input('khiHau', sql.NVarChar, khiHau || null)
            .input('giaThueThang', sql.Decimal(18, 0), giaThueThang ? Number(giaThueThang) : null)
            .input('hinhAnh', sql.NVarChar, hinhAnh || null)
            .query(query);

        res.json({ success: true, message: 'Đã thêm địa điểm mới thành công!' });
    } catch (err) {
        console.error("Lỗi thêm địa điểm:", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ khi thêm địa điểm!' });
    }
};

// 6. Xử lý API Xóa địa điểm
exports.xoaDiaDiem = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;

        await pool.request()
            .input('maDiaDiem', sql.Int, id)
            .query(`DELETE FROM diaDiemVuon WHERE maDiaDiem = @maDiaDiem`);

        res.json({ success: true, message: 'Đã xóa địa điểm thành công!' });
    } catch (err) {
        console.error("Lỗi xóa địa điểm:", err);
        if (err.message.includes('REFERENCE constraint')) {
            res.status(400).json({
                success: false,
                message: 'Không thể xóa vì địa điểm này đang có dữ liệu hợp đồng hoặc yêu cầu thuê. Hãy chuyển trạng thái sang "Từ chối" thay vì xóa!'
            });
        } else {
            res.status(500).json({ success: false, message: 'Lỗi máy chủ khi xóa địa điểm!' });
        }
    }
};

// 7. Xử lý API Truy xuất nguồn gốc bằng QR Code
exports.truyXuatNguonGoc = async (req, res) => {
    try {
        const maDiaDiem = req.params.id;
        const pool = await poolPromise;

        const queryDiaDiem = `
            SELECT d.tenDiaDiem, d.diaChiChiTiet, d.dienTich, d.hinhAnh, n.hoTen AS tenChuDat, n.soDienThoai
            FROM diaDiemVuon d
            JOIN nguoiDung n ON d.maChuDat = n.maNguoiDung
            WHERE d.maDiaDiem = @id
        `;
        const resDiaDiem = await pool.request().input('id', sql.Int, maDiaDiem).query(queryDiaDiem);

        if (resDiaDiem.recordset.length === 0) {
            return res.status(404).send("Không tìm thấy thông tin địa điểm này.");
        }

        const querySanPham = `
            SELECT DISTINCT lo.tenLoaiOng, lo.sanPhamChuLuc
            FROM yeuCauDatCho y
            JOIN traiOng t ON y.maNguoiNuoiOng = t.maNguoiNuoiOng
            JOIN loaiOng lo ON t.maLoaiOng = lo.maLoaiOng
            WHERE y.maDiaDiem = @id AND y.trangThaiYeuCau = 'DaChapNhan'
        `;
        const resSanPham = await pool.request().input('id', sql.Int, maDiaDiem).query(querySanPham);

        res.render('truy-xuat', {
            diaDiem: resDiaDiem.recordset[0],
            danhSachSanPham: resSanPham.recordset,
            layout: false
        });
    } catch (err) {
        console.error("Lỗi truy xuất nguồn gốc:", err);
        res.status(500).send("Lỗi hệ thống khi tải trang truy xuất.");
    }
};