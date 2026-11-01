const { sql } = require('./db');
const { AppError } = require('../utils/http');
const {
    REQUEST_STATUS, CONTRACT_STATUS, getPool, inTransaction,
    getNotifications, getRentalRequests, getContracts,
} = require('./beekeepingRepository');

const LOCATION_SELECT = `
    SELECT v.maDiaDiem, v.maChuDat, v.tenDiaDiem, v.viDo, v.kinhDo, v.dienTich, v.sucChuaToiDa, v.diaChiChiTiet, v.thongTinPhapLy,
           v.trangThaiKiemDuyet, v.lyDoTuChoi, v.hinhAnh, FORMAT(v.ngayTao, 'dd/MM/yyyy') AS ngayTao,
           v.loaiHoa, v.loaiOngPhuHop, v.giaThueThang, v.khiHau,
           ISNULL((
               SELECT SUM(y.soDanOng)
               FROM dbo.hopDongThueOng h
               JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
               WHERE h.maDiaDiem = v.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
           ), 0) AS soDanDaThue,
           CASE 
               WHEN v.sucChuaToiDa - ISNULL((
                   SELECT SUM(y.soDanOng)
                   FROM dbo.hopDongThueOng h
                   JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                   WHERE h.maDiaDiem = v.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
               ), 0) < 0 THEN 0
               ELSE v.sucChuaToiDa - ISNULL((
                   SELECT SUM(y.soDanOng)
                   FROM dbo.hopDongThueOng h
                   JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                   WHERE h.maDiaDiem = v.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
               ), 0)
           END AS sucChuaConLai,
           (SELECT COUNT(*) FROM dbo.danOng d WHERE d.maDiaDiem = v.maDiaDiem) AS soDanOng,
           ISNULL((SELECT SUM(d.soThung) FROM dbo.danOng d WHERE d.maDiaDiem = v.maDiaDiem), 0) AS soThung,
           (SELECT COUNT(*) FROM dbo.yeuCauThueOng y WHERE y.maDiaDiem = v.maDiaDiem AND y.trangThai = '${REQUEST_STATUS.PENDING}') AS yeuCauChoDuyet,
           (SELECT TOP 1 n.hoTen FROM dbo.hopDongThueOng h JOIN dbo.nguoiDung n ON n.maNguoiDung = h.maNguoiNuoiOng
             WHERE h.maDiaDiem = v.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}' ORDER BY h.ngayKy DESC) AS nguoiThue,
           ISNULL((SELECT SUM(s.sanLuong) FROM dbo.sanLuongMatOng s WHERE s.maDiaDiem = v.maDiaDiem AND s.donVi = 'kg'), 0) AS sanLuongKg
    FROM dbo.diaDiemVuon v`;

async function getLocations(ownerId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, ownerId)
        .query(`${LOCATION_SELECT} WHERE v.maChuDat = @uid ORDER BY v.ngayTao DESC, v.maDiaDiem DESC`);
    return result.recordset;
}

async function getOwnedLocation(target, ownerId, maDiaDiem) {
    const result = await target.request().input('uid', sql.Int, ownerId).input('id', sql.Int, maDiaDiem)
        .query(`${LOCATION_SELECT} WHERE v.maDiaDiem = @id AND v.maChuDat = @uid`);
    const location = result.recordset[0];
    if (!location) throw new AppError(404, 'Không tìm thấy địa điểm của bạn.');
    return location;
}

const bindLocation = (request, data) => request
    .input('tenDiaDiem', sql.NVarChar(200), data.tenDiaDiem)
    .input('viDo', sql.Decimal(10, 7), data.viDo)
    .input('kinhDo', sql.Decimal(10, 7), data.kinhDo)
    .input('dienTich', sql.Float, data.dienTich)
    .input('sucChuaToiDa', sql.Int, data.sucChuaToiDa)
    .input('diaChiChiTiet', sql.NVarChar(500), data.diaChiChiTiet)
    .input('thongTinPhapLy', sql.NVarChar(sql.MAX), data.thongTinPhapLy || null)
    .input('hinhAnh', sql.NVarChar(sql.MAX), data.hinhAnh || null)
    .input('loaiHoa', sql.NVarChar(200), data.loaiHoa || null)
    .input('loaiOngPhuHop', sql.NVarChar(200), data.loaiOngPhuHop || null)
    .input('giaThueThang', sql.Decimal(14, 2), data.giaThueThang || null)
    .input('khiHau', sql.NVarChar(200), data.khiHau || null);

// Địa điểm mới luôn chờ quản trị viên kiểm duyệt trước khi hiển thị cho người nuôi ong.
async function createLocation(ownerId, data) {
    const pool = await getPool();
    const result = await bindLocation(pool.request().input('uid', sql.Int, ownerId), data).query(`
        INSERT INTO dbo.diaDiemVuon (maChuDat, tenDiaDiem, viDo, kinhDo, dienTich, sucChuaToiDa, diaChiChiTiet, thongTinPhapLy, trangThaiKiemDuyet, hinhAnh, loaiHoa, loaiOngPhuHop, giaThueThang, khiHau, ngayTao)
        OUTPUT INSERTED.maDiaDiem
        VALUES (@uid, @tenDiaDiem, @viDo, @kinhDo, @dienTich, @sucChuaToiDa, @diaChiChiTiet, @thongTinPhapLy, 'ChoDiemDuyet', @hinhAnh, @loaiHoa, @loaiOngPhuHop, @giaThueThang, @khiHau, GETDATE())`);
    return getOwnedLocation(pool, ownerId, result.recordset[0].maDiaDiem);
}

async function updateLocation(ownerId, maDiaDiem, data) {
    return inTransaction(async (tx) => {
        const current = await getOwnedLocation(tx, ownerId, maDiaDiem);
        if (current.nguoiThue) throw new AppError(409, 'Địa điểm đang có hợp đồng thuê hiệu lực, không thể chỉnh sửa.');
        if (data.sucChuaToiDa < current.soThung) throw new AppError(400, `Sức chứa không được nhỏ hơn số thùng ong đang đặt (${current.soThung}).`);

        await bindLocation(tx.request().input('ownerId', sql.Int, ownerId).input('id', sql.Int, maDiaDiem), data)
            .query(`
                UPDATE dbo.diaDiemVuon
                SET tenDiaDiem = @tenDiaDiem,
                    diaChiChiTiet = @diaChiChiTiet,
                    dienTich = @dienTich,
                    sucChuaToiDa = @sucChuaToiDa,
                    thongTinPhapLy = @thongTinPhapLy,
                    viDo = @viDo,
                    kinhDo = @kinhDo,
                    loaiHoa = @loaiHoa,
                    loaiOngPhuHop = @loaiOngPhuHop,
                    giaThueThang = @giaThueThang,
                    khiHau = @khiHau,
                    hinhAnh = COALESCE(@hinhAnh, hinhAnh),
                    trangThaiKiemDuyet = 'ChoDiemDuyet'
                WHERE maDiaDiem = @id AND maChuDat = @ownerId
            `);

        return getOwnedLocation(tx, ownerId, maDiaDiem);
    });
}

async function deleteLocation(ownerId, maDiaDiem) {
    return inTransaction(async (tx) => {
        const current = await getOwnedLocation(tx, ownerId, maDiaDiem);
        const usage = await tx.request().input('id', sql.Int, maDiaDiem).query(`
            SELECT (SELECT COUNT(*) FROM dbo.hopDongThueOng WHERE maDiaDiem = @id) AS hopDong,
                   (SELECT COUNT(*) FROM dbo.yeuCauThueOng WHERE maDiaDiem = @id AND trangThai IN ('${REQUEST_STATUS.PENDING}', '${REQUEST_STATUS.WAITING_SIGN}')) AS yeuCau`);
        const { hopDong, yeuCau } = usage.recordset[0];
        if (current.soDanOng || hopDong || yeuCau) {
            throw new AppError(409, 'Địa điểm đã phát sinh yêu cầu thuê, hợp đồng hoặc đang có đàn ong nên không thể xóa.');
        }
        try {
            await tx.request().input('id', sql.Int, maDiaDiem).input('uid', sql.Int, ownerId).query(`
                DELETE FROM dbo.yeuCauThueOng WHERE maDiaDiem = @id;
                DELETE FROM dbo.diaDiemVuon WHERE maDiaDiem = @id AND maChuDat = @uid;`);
        } catch (error) {
            if (error.number === 547) throw new AppError(409, 'Địa điểm đang được sử dụng ở dữ liệu khác (mùa vụ, lịch trình...) nên không thể xóa.');
            throw error;
        }
    });
}

async function getHivesOnLand(ownerId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, ownerId).query(`
        SELECT d.maDanOng, d.tenDanOng, d.soThung, d.tinhTrang, d.cayTruoc, d.viTri, d.viDo, d.kinhDo,
               d.maDiaDiem, v.tenDiaDiem, n.hoTen AS tenNguoiNuoiOng, n.soDienThoai AS sdtNguoiNuoiOng, n.maNguoiDung AS maNguoiNuoiOng,
               FORMAT(DATEADD(HOUR, 7, d.ngayCapNhat), 'dd/MM/yyyy HH:mm') AS ngayCapNhat
        FROM dbo.danOng d
        JOIN dbo.diaDiemVuon v ON v.maDiaDiem = d.maDiaDiem
        LEFT JOIN dbo.nguoiDung n ON n.maNguoiDung = d.maNguoiDung
        WHERE v.maChuDat = @uid
        ORDER BY v.tenDiaDiem, d.tenDanOng`);
    return result.recordset;
}

async function getProductionOnLand(ownerId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, ownerId).query(`
        SELECT TOP 100 s.maSanLuong, s.sanLuong, s.donVi, CONVERT(varchar(10), s.ngay, 23) AS ngay, s.loaiMat, s.maTruyXuat,
               v.tenDiaDiem, d.tenDanOng, n.hoTen AS tenNguoiNuoiOng
        FROM dbo.sanLuongMatOng s
        JOIN dbo.diaDiemVuon v ON v.maDiaDiem = s.maDiaDiem
        LEFT JOIN dbo.danOng d ON d.maDanOng = s.maDanOng
        LEFT JOIN dbo.nguoiDung n ON n.maNguoiDung = s.maNguoiDung
        WHERE v.maChuDat = @uid
        ORDER BY s.ngay DESC, s.id DESC`);
    return result.recordset;
}

async function getLandownerDashboard(ownerId) {
    const user = { id: ownerId, vaiTro: 'chudat' };
    const [locations, requests, contracts, hives, production, notifications] = await Promise.all([
        getLocations(ownerId), getRentalRequests({ ownerId }), getContracts(user),
        getHivesOnLand(ownerId), getProductionOnLand(ownerId), getNotifications(ownerId),
    ]);
    const kg = production.filter((item) => String(item.donVi).toLowerCase() === 'kg').reduce((sum, item) => sum + Number(item.sanLuong || 0), 0);
    return {
        summary: {
            totalLocations: locations.length,
            approvedLocations: locations.filter((item) => item.trangThaiKiemDuyet === 'DaDuyet').length,
            waitingReview: locations.filter((item) => item.trangThaiKiemDuyet === 'ChoDiemDuyet').length,
            pendingRequests: requests.filter((item) => item.trangThai === REQUEST_STATUS.PENDING).length,
            contractsWaitingSign: contracts.filter((item) => item.trangThai === CONTRACT_STATUS.WAITING_SIGN).length,
            activeContracts: contracts.filter((item) => item.trangThai === CONTRACT_STATUS.SIGNED).length,
            hivesOnLand: hives.length,
            boxesOnLand: hives.reduce((sum, hive) => sum + Number(hive.soThung || 0), 0),
            productionKg: Math.round(kg * 100) / 100,
            unreadNotifications: notifications.filter((item) => !item.daDoc).length,
        },
        locations, requests, contracts, hives, production, notifications,
    };
}

module.exports = {
    getLocations, createLocation, updateLocation, deleteLocation,
    getHivesOnLand, getProductionOnLand, getLandownerDashboard,
};
