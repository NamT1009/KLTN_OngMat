const { sql } = require('./db');
const { getPool } = require('./beekeepingRepository');

let _cachedStats = null;
let _cachedStatsTime = 0;

// Thống kê toàn hệ thống cho quản trị viên (dashboard web và app mobile).
async function getSystemStats() {
    if (_cachedStats && (Date.now() - _cachedStatsTime < 15000)) {
        return _cachedStats;
    }
    try {
        const pool = await getPool();
        const [kpi, byMonth, byType, byStatus, topLocations, recent] = await Promise.all([
            pool.request().query(`
                SELECT
                    (SELECT COUNT(*) FROM nguoiDung) AS tongNguoiDung,
                    (SELECT COUNT(*) FROM nguoiDung WHERE vaiTro = 'nguoiNuoiOng') AS soNguoiNuoiOng,
                    (SELECT COUNT(*) FROM nguoiDung WHERE vaiTro = 'chuDat') AS soChuDat,
                    (SELECT COUNT(*) FROM nguoiDung WHERE trangThaiTaiKhoan = 'DaKhoa') AS soTaiKhoanKhoa,
                    (SELECT COUNT(*) FROM diaDiemVuon) AS tongDiaDiem,
                    (SELECT COUNT(*) FROM diaDiemVuon WHERE trangThaiKiemDuyet = 'DaDuyet') AS diaDiemDaDuyet,
                    (SELECT COUNT(*) FROM diaDiemVuon WHERE trangThaiKiemDuyet = 'ChoDiemDuyet') AS diaDiemChoDuyet,
                    (SELECT COUNT(*) FROM dbo.danOng) AS tongDanOng,
                    (SELECT ISNULL(SUM(soThung), 0) FROM dbo.danOng) AS tongThungOng,
                    (SELECT COUNT(*) FROM dbo.hopDongThueOng WHERE trangThai = 'DaKy') AS hopDongHieuLuc,
                    (SELECT COUNT(*) FROM dbo.yeuCauThueOng WHERE trangThai = 'ChoDuyet') AS yeuCauChoDuyet,
                    (SELECT ISNULL(SUM(sanLuong), 0) FROM dbo.sanLuongMatOng WHERE donVi = 'kg') AS tongSanLuongKg,
                    (SELECT ISNULL(SUM(sanLuong), 0) FROM dbo.sanLuongMatOng WHERE donVi = N'lít') AS tongSanLuongLit,
                    (SELECT COUNT(*) FROM dbo.truyXuatKhaiThacOng) AS soLoTruyXuat,
                    (SELECT COUNT(*) FROM dbo.lichChamSocOng WHERE trangThai <> N'Đã hoàn thành') AS lichChamSocChuaXong`),
        // 12 tháng gần nhất, kể cả tháng không có sản lượng
        pool.request().query(`
            WITH thang AS (
                SELECT 0 AS n, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1) AS dau
                UNION ALL SELECT n + 1, DATEADD(MONTH, -1, dau) FROM thang WHERE n < 11
            )
            SELECT FORMAT(t.dau, 'MM/yyyy') AS thang,
                   ISNULL(SUM(CASE WHEN s.donVi = 'kg' THEN s.sanLuong END), 0) AS kg
            FROM thang t
            LEFT JOIN dbo.sanLuongMatOng s ON s.ngay >= t.dau AND s.ngay < DATEADD(MONTH, 1, t.dau)
            GROUP BY t.dau ORDER BY t.dau`),
        pool.request().query(`
            SELECT TOP 6 loaiMat, SUM(sanLuong) AS kg FROM dbo.sanLuongMatOng
            WHERE donVi = 'kg' GROUP BY loaiMat ORDER BY kg DESC`),
        pool.request().query(`
            SELECT TOP 6 ISNULL(NULLIF(tinhTrang, ''), N'Chưa cập nhật') AS tinhTrang, COUNT(*) AS soDan, SUM(soThung) AS soThung
            FROM dbo.danOng GROUP BY ISNULL(NULLIF(tinhTrang, ''), N'Chưa cập nhật') ORDER BY soDan DESC`),
        pool.request().query(`
            SELECT TOP 5 v.maDiaDiem, v.tenDiaDiem, n.hoTen AS chuDat, SUM(s.sanLuong) AS kg
            FROM dbo.sanLuongMatOng s
            JOIN diaDiemVuon v ON v.maDiaDiem = s.maDiaDiem
            LEFT JOIN nguoiDung n ON n.maNguoiDung = v.maChuDat
            WHERE s.donVi = 'kg'
            GROUP BY v.maDiaDiem, v.tenDiaDiem, n.hoTen ORDER BY kg DESC`),
        pool.request().query(`
            SELECT TOP 10 t.id AS maLo, t.sanPham, t.sanLuongDuKien AS kg, t.tenDiaDiem, n.hoTen AS nguoiNuoiOng,
                   FORMAT(DATEADD(HOUR, 7, t.createdAt), 'dd/MM/yyyy HH:mm') AS thoiGian
            FROM dbo.truyXuatKhaiThacOng t LEFT JOIN nguoiDung n ON n.maNguoiDung = t.maNguoiDung
            ORDER BY t.createdAt DESC, t.id DESC`),
    ]);
        _cachedStats = {
            kpi: kpi.recordset[0] || {},
            sanLuongTheoThang: byMonth.recordset || [],
            sanLuongTheoLoaiMat: byType.recordset || [],
            danOngTheoTinhTrang: byStatus.recordset || [],
            diaDiemSanLuongCao: topLocations.recordset || [],
            loTruyXuatGanDay: recent.recordset || [],
        };
        _cachedStatsTime = Date.now();
        return _cachedStats;
    } catch (err) {
        console.warn('Lỗi getSystemStats:', err.message);
        if (_cachedStats) return _cachedStats;
        return {
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
            loTruyXuatGanDay: [],
        };
    }
}

// Dữ liệu bản đồ toàn hệ thống: địa điểm đã duyệt và đàn ong có tọa độ.
async function getSystemMap() {
    const pool = await getPool();
    const [locations, hives] = await Promise.all([
        pool.request().query(`
            SELECT v.maDiaDiem, v.tenDiaDiem, v.viDo, v.kinhDo, v.sucChuaToiDa, v.diaChiChiTiet, n.hoTen AS tenChuDat,
                   ISNULL((SELECT SUM(soThung) FROM dbo.danOng d WHERE d.maDiaDiem = v.maDiaDiem), 0) AS soThung,
                   (SELECT TOP 1 nn.hoTen FROM dbo.hopDongThueOng h JOIN nguoiDung nn ON nn.maNguoiDung = h.maNguoiNuoiOng
                     WHERE h.maDiaDiem = v.maDiaDiem AND h.trangThai = 'DaKy') AS nguoiThue
            FROM diaDiemVuon v LEFT JOIN nguoiDung n ON n.maNguoiDung = v.maChuDat
            WHERE v.trangThaiKiemDuyet = 'DaDuyet'`),
        pool.request().query(`
            SELECT d.maDanOng, d.tenDanOng, d.viTri, d.viDo, d.kinhDo, d.soThung, d.tinhTrang, n.hoTen AS tenNguoiNuoiOng,
                   FORMAT(DATEADD(HOUR, 7, d.ngayCapNhat), 'dd/MM/yyyy HH:mm') AS ngayCapNhat
            FROM dbo.danOng d LEFT JOIN nguoiDung n ON n.maNguoiDung = d.maNguoiDung
            WHERE d.viDo IS NOT NULL AND d.kinhDo IS NOT NULL`),
    ]);
    return { locations: locations.recordset, hives: hives.recordset };
}

// Tra cứu công khai cho khách hàng: theo mã lô, tên sản phẩm, nơi khai thác hoặc nhà sản xuất.
async function searchPublicProducts(keyword) {
    const pool = await getPool();
    const q = String(keyword || '').trim().replace(/^#/, '');
    const result = await pool.request()
        .input('q', sql.NVarChar(200), q ? `%${q}%` : null)
        .input('id', sql.Int, /^\d+$/.test(q) ? Number(q) : null)
        .query(`
            SELECT TOP 30 t.id AS maLo, t.sanPham, t.sanLuongDuKien AS kg, t.loaiOng, t.tenDiaDiem, n.hoTen AS nguoiNuoiOng,
                   FORMAT(DATEADD(HOUR, 7, t.createdAt), 'dd/MM/yyyy') AS ngay
            FROM dbo.truyXuatKhaiThacOng t LEFT JOIN nguoiDung n ON n.maNguoiDung = t.maNguoiDung
            WHERE @q IS NULL OR t.id = @id OR t.sanPham LIKE @q OR t.tenDiaDiem LIKE @q OR n.hoTen LIKE @q
            ORDER BY t.createdAt DESC, t.id DESC`);
    return result.recordset;
}

module.exports = { getSystemStats, getSystemMap, searchPublicProducts };
