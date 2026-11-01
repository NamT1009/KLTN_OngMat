const { poolPromise, sql } = require('./db');
const { AppError } = require('../utils/http');

// Trạng thái dùng chung giữa web, mobile và CSDL.
const REQUEST_STATUS = { PENDING: 'ChoDuyet', WAITING_SIGN: 'ChoKhachKy', SIGNED: 'DaKy', REJECTED: 'TuChoi', CANCELLED: 'DaHuy' };
const CONTRACT_STATUS = { WAITING_SIGN: 'ChoKhachKy', SIGNED: 'DaKy', COMPLETED: 'HoanThanh', CANCELLED: 'DaHuy' };
const CARE_STATUS = { PLANNED: 'Lên lịch', DONE: 'Đã hoàn thành' };
const MOVE_STATUS = { PLANNED: 'Lên lịch', MOVING: 'Đang di chuyển', DONE: 'Hoàn thành', CANCELLED: 'Đã hủy' };

async function getPool() {
    const pool = await poolPromise;
    if (!pool) {
        const error = new Error('Database unavailable');
        error.code = 'DB_UNAVAILABLE';
        throw error;
    }
    return pool;
}

async function inTransaction(work) {
    const pool = await getPool();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();
    try {
        const result = await work(transaction);
        await transaction.commit();
        return result;
    } catch (error) {
        await transaction.rollback();
        throw error;
    }
}

const newCode = (prefix) => `${prefix}-${Date.now().toString(36).toUpperCase()}${Math.floor(Math.random() * 1296).toString(36).toUpperCase().padStart(2, '0')}`;

// Thời gian hiển thị theo giờ Việt Nam (UTC+7) dạng tương đối.
const relativeTime = (column) => `
    CASE WHEN DATEDIFF(MINUTE, ${column}, SYSUTCDATETIME()) < 1 THEN N'Vừa xong'
         WHEN DATEDIFF(MINUTE, ${column}, SYSUTCDATETIME()) < 60 THEN CONCAT(DATEDIFF(MINUTE, ${column}, SYSUTCDATETIME()), N' phút trước')
         WHEN DATEDIFF(HOUR, ${column}, SYSUTCDATETIME()) < 24 THEN CONCAT(DATEDIFF(HOUR, ${column}, SYSUTCDATETIME()), N' giờ trước')
         ELSE FORMAT(DATEADD(HOUR, 7, ${column}), 'dd/MM/yyyy HH:mm') END`;

// ================= THÔNG BÁO =================

const notify = (target, userId, tieuDe, noiDung, mucDo = 'Thấp') => {
    if (!userId) return Promise.resolve();
    return target.request()
        .input('maNguoiDung', sql.Int, userId)
        .input('tieuDe', sql.NVarChar(300), tieuDe)
        .input('noiDung', sql.NVarChar(1000), noiDung)
        .input('mucDo', sql.NVarChar(50), mucDo)
        .query('INSERT INTO dbo.thongBaoNuoiOng (maNguoiDung, tieuDe, noiDung, mucDo) VALUES (@maNguoiDung, @tieuDe, @noiDung, @mucDo)');
};

async function getNotifications(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT TOP 50 id, tieuDe, noiDung, mucDo, daDoc, ${relativeTime('thoiGian')} AS thoiGian
        FROM dbo.thongBaoNuoiOng
        WHERE (@uid IS NULL OR maNguoiDung = @uid)
        ORDER BY thoiGian DESC, id DESC`);
    return result.recordset;
}

async function markNotificationsRead(userId, id = null) {
    const pool = await getPool();
    await pool.request().input('uid', sql.Int, userId).input('id', sql.Int, id)
        .query('UPDATE dbo.thongBaoNuoiOng SET daDoc = 1 WHERE maNguoiDung = @uid AND daDoc = 0 AND (@id IS NULL OR id = @id)');
}

// ================= ĐÀN ONG & THÙNG ONG =================

const HIVE_SELECT = `
    SELECT d.maDanOng, d.maNguoiDung, d.tenDanOng, d.viTri, d.viDo, d.kinhDo, d.soThung, d.tinhTrang, d.cayTruoc,
           d.maDiaDiem, v.tenDiaDiem, n.hoTen AS tenNguoiNuoiOng, n.soDienThoai AS sdtNguoiNuoiOng,
           FORMAT(DATEADD(HOUR, 7, d.ngayCapNhat), 'dd/MM/yyyy HH:mm') AS ngayCapNhat
    FROM dbo.danOng d
    LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = d.maDiaDiem
    LEFT JOIN dbo.nguoiDung n ON n.maNguoiDung = d.maNguoiDung`;

async function getHives(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId)
        .query(`${HIVE_SELECT} WHERE (@uid IS NULL OR d.maNguoiDung = @uid) ORDER BY d.ngayCapNhat DESC, d.id DESC`);
    return result.recordset;
}

async function getOwnedHive(target, userId, maDanOng) {
    const result = await target.request().input('uid', sql.Int, userId).input('id', sql.NVarChar(50), maDanOng)
        .query(`${HIVE_SELECT} WHERE d.maDanOng = @id AND d.maNguoiDung = @uid`);
    const hive = result.recordset[0];
    if (!hive) throw new AppError(404, 'Không tìm thấy đàn ong của bạn.');
    return hive;
}

// Địa điểm người nuôi ong được phép đặt ong: có hợp đồng thuê đã ký.
async function getRentedLocations(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT v.maDiaDiem, v.tenDiaDiem, v.diaChiChiTiet, v.viDo, v.kinhDo, v.sucChuaToiDa,
               n.hoTen AS tenChuDat, n.maNguoiDung AS maChuDat,
               ISNULL((SELECT SUM(soThung) FROM dbo.danOng WHERE maDiaDiem = v.maDiaDiem), 0) AS soThungDangDat
        FROM dbo.diaDiemVuon v
        LEFT JOIN dbo.nguoiDung n ON n.maNguoiDung = v.maChuDat
        WHERE EXISTS (SELECT 1 FROM dbo.hopDongThueOng h
                      WHERE h.maDiaDiem = v.maDiaDiem AND h.maNguoiNuoiOng = @uid AND h.trangThai = '${CONTRACT_STATUS.SIGNED}')
        ORDER BY v.tenDiaDiem`);
    return result.recordset;
}

// Kiểm tra quyền đặt ong tại địa điểm và sức chứa còn lại; trả về thông tin địa điểm.
async function assertCanPlace(target, userId, maDiaDiem, soThung, excludeHive = null) {
    const result = await target.request()
        .input('uid', sql.Int, userId).input('loc', sql.Int, maDiaDiem).input('exclude', sql.NVarChar(50), excludeHive)
        .query(`
            SELECT v.maDiaDiem, v.tenDiaDiem, v.diaChiChiTiet, v.viDo, v.kinhDo, v.sucChuaToiDa, v.maChuDat,
                   ISNULL((SELECT SUM(soThung) FROM dbo.danOng WHERE maDiaDiem = v.maDiaDiem
                           AND (@exclude IS NULL OR maDanOng <> @exclude)), 0) AS soThungDangDat,
                   CASE WHEN EXISTS (SELECT 1 FROM dbo.hopDongThueOng h WHERE h.maDiaDiem = v.maDiaDiem
                        AND h.maNguoiNuoiOng = @uid AND h.trangThai = '${CONTRACT_STATUS.SIGNED}') THEN 1 ELSE 0 END AS duocThue
            FROM dbo.diaDiemVuon v WHERE v.maDiaDiem = @loc`);
    const location = result.recordset[0];
    if (!location) throw new AppError(404, 'Không tìm thấy địa điểm đặt ong.');
    if (!location.duocThue) throw new AppError(403, 'Bạn chỉ được đặt ong tại địa điểm đã ký hợp đồng thuê.');
    if (location.sucChuaToiDa && location.soThungDangDat + soThung > location.sucChuaToiDa) {
        const remaining = Math.max(0, location.sucChuaToiDa - location.soThungDangDat);
        throw new AppError(409, `${location.tenDiaDiem} chỉ còn chỗ cho ${remaining} thùng ong.`);
    }
    return location;
}

const syncBoxes = (target, maDanOng, soThung) => target.request()
    .input('ma', sql.NVarChar(50), maDanOng).input('soThung', sql.Int, soThung)
    .query(`
        DECLARE @i INT = 1;
        WHILE @i <= @soThung
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.thungOng WHERE maThungOng = CONCAT(@ma, N'-T', FORMAT(@i, '00')))
                INSERT INTO dbo.thungOng (maThungOng, maDanOng, soThuTu, tinhTrang)
                VALUES (CONCAT(@ma, N'-T', FORMAT(@i, '00')), @ma, @i, N'Đang hoạt động');
            SET @i += 1;
        END;
        DELETE FROM dbo.thungOng WHERE maDanOng = @ma AND soThuTu > @soThung;`);

async function createHive(userId, data) {
    return inTransaction(async (tx) => {
        let location = null;
        if (data.maDiaDiem) location = await assertCanPlace(tx, userId, data.maDiaDiem, data.soThung);

        const maDanOng = newCode('DN');
        const viDo = data.viDo ?? location?.viDo ?? null;
        const kinhDo = data.kinhDo ?? location?.kinhDo ?? null;
        await tx.request()
            .input('maDanOng', sql.NVarChar(50), maDanOng)
            .input('uid', sql.Int, userId)
            .input('tenDanOng', sql.NVarChar(200), data.tenDanOng)
            .input('viTri', sql.NVarChar(300), data.viTri || location?.tenDiaDiem || 'Chưa cập nhật vị trí')
            .input('viDo', sql.Decimal(10, 7), viDo)
            .input('kinhDo', sql.Decimal(10, 7), kinhDo)
            .input('soThung', sql.Int, data.soThung)
            .input('tinhTrang', sql.NVarChar(200), data.tinhTrang || 'Mới tạo')
            .input('cayTruoc', sql.NVarChar(200), data.cayTruoc || null)
            .input('maDiaDiem', sql.Int, location?.maDiaDiem ?? null)
            .query(`INSERT INTO dbo.danOng (maDanOng, maNguoiDung, tenDanOng, viTri, viDo, kinhDo, soThung, tinhTrang, cayTruoc, maDiaDiem)
                    VALUES (@maDanOng, @uid, @tenDanOng, @viTri, @viDo, @kinhDo, @soThung, @tinhTrang, @cayTruoc, @maDiaDiem)`);
        await syncBoxes(tx, maDanOng, data.soThung);
        if (viDo != null && kinhDo != null) {
            await tx.request().input('ma', sql.NVarChar(50), maDanOng).input('viDo', sql.Decimal(10, 7), viDo)
                .input('kinhDo', sql.Decimal(10, 7), kinhDo).input('viTri', sql.NVarChar(300), data.viTri || location?.tenDiaDiem || null)
                .query('INSERT INTO dbo.lichSuGPSDanOng (maDanOng, viDo, kinhDo, viTri) VALUES (@ma, @viDo, @kinhDo, @viTri)');
        }
        await notify(tx, userId, 'Đã tạo đàn ong', `${data.tenDanOng} gồm ${data.soThung} thùng đã được thêm vào hệ thống.`);
        if (location) {
            await notify(tx, location.maChuDat, 'Có đàn ong mới trên đất của bạn', `${data.tenDanOng} (${data.soThung} thùng) đã được đặt tại ${location.tenDiaDiem}.`);
        }
        return getOwnedHive(tx, userId, maDanOng);
    });
}

async function updateHive(userId, maDanOng, data) {
    return inTransaction(async (tx) => {
        const current = await getOwnedHive(tx, userId, maDanOng);
        const soThung = data.soThung ?? current.soThung;
        const locationChanged = data.maDiaDiem !== undefined && (data.maDiaDiem || null) !== (current.maDiaDiem || null);

        let location = null;
        const targetLocation = data.maDiaDiem !== undefined ? data.maDiaDiem : current.maDiaDiem;
        if (targetLocation && (locationChanged || soThung !== current.soThung)) {
            location = await assertCanPlace(tx, userId, targetLocation, soThung, maDanOng);
        }

        const request = tx.request().input('ma', sql.NVarChar(50), maDanOng).input('uid', sql.Int, userId);
        const sets = [];
        const add = (column, type, value) => { request.input(column, type, value); sets.push(`${column} = @${column}`); };
        if (data.tenDanOng !== undefined) add('tenDanOng', sql.NVarChar(200), data.tenDanOng);
        if (data.soThung !== undefined) add('soThung', sql.Int, data.soThung);
        if (data.viTri !== undefined) add('viTri', sql.NVarChar(300), data.viTri);
        if (data.tinhTrang !== undefined) add('tinhTrang', sql.NVarChar(200), data.tinhTrang);
        if (data.cayTruoc !== undefined) add('cayTruoc', sql.NVarChar(200), data.cayTruoc);
        if (locationChanged) {
            add('maDiaDiem', sql.Int, location?.maDiaDiem ?? null);
            if (location) {
                add('viDo', sql.Decimal(10, 7), location.viDo);
                add('kinhDo', sql.Decimal(10, 7), location.kinhDo);
                if (data.viTri === undefined) add('viTri', sql.NVarChar(300), location.tenDiaDiem);
            }
        }
        if (sets.length) {
            await request.query(`UPDATE dbo.danOng SET ${sets.join(', ')}, ngayCapNhat = SYSUTCDATETIME() WHERE maDanOng = @ma AND maNguoiDung = @uid`);
        }
        if (data.soThung !== undefined && data.soThung !== current.soThung) await syncBoxes(tx, maDanOng, data.soThung);
        if (locationChanged && location) {
            await notify(tx, location.maChuDat, 'Có đàn ong mới trên đất của bạn', `${data.tenDanOng || current.tenDanOng} đã được chuyển tới ${location.tenDiaDiem}.`);
        }
        return getOwnedHive(tx, userId, maDanOng);
    });
}

async function deleteHive(userId, maDanOng) {
    return inTransaction(async (tx) => {
        await getOwnedHive(tx, userId, maDanOng);
        // Giữ lại lịch sử sản lượng/chăm sóc để phục vụ truy xuất nguồn gốc.
        await tx.request().input('ma', sql.NVarChar(50), maDanOng).input('uid', sql.Int, userId).query(`
            DELETE FROM dbo.thungOng WHERE maDanOng = @ma;
            DELETE FROM dbo.danOng WHERE maDanOng = @ma AND maNguoiDung = @uid;`);
    });
}

async function updateHiveLocation(userId, maDanOng, { viDo, kinhDo, viTri }) {
    return inTransaction(async (tx) => {
        const hive = await getOwnedHive(tx, userId, maDanOng);
        const label = viTri || hive.viTri;
        await tx.request()
            .input('ma', sql.NVarChar(50), maDanOng).input('uid', sql.Int, userId)
            .input('viDo', sql.Decimal(10, 7), viDo).input('kinhDo', sql.Decimal(10, 7), kinhDo)
            .input('viTri', sql.NVarChar(300), label)
            .query(`
                UPDATE dbo.danOng SET viDo = @viDo, kinhDo = @kinhDo, viTri = @viTri, ngayCapNhat = SYSUTCDATETIME()
                WHERE maDanOng = @ma AND maNguoiDung = @uid;
                INSERT INTO dbo.lichSuGPSDanOng (maDanOng, viDo, kinhDo, viTri) VALUES (@ma, @viDo, @kinhDo, @viTri);`);
        await notify(tx, userId, 'Đã cập nhật vị trí GPS', `${hive.tenDanOng}: ${Number(viDo).toFixed(5)}, ${Number(kinhDo).toFixed(5)}.`);
        return getOwnedHive(tx, userId, maDanOng);
    });
}

async function getGpsHistory(userId, maDanOng) {
    const pool = await getPool();
    await getOwnedHive(pool, userId, maDanOng);
    const result = await pool.request().input('ma', sql.NVarChar(50), maDanOng).query(`
        SELECT TOP 50 viDo, kinhDo, viTri, FORMAT(DATEADD(HOUR, 7, thoiGian), 'dd/MM/yyyy HH:mm') AS thoiGian
        FROM dbo.lichSuGPSDanOng WHERE maDanOng = @ma ORDER BY lichSuGPSDanOng.thoiGian DESC, id DESC`);
    return result.recordset;
}

// ================= LỊCH CHĂM SÓC =================

async function getCare(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT c.maLich, c.maDanOng, d.tenDanOng, c.tenCongViec, CONVERT(varchar(10), c.ngay, 23) AS ngay,
               CONVERT(varchar(5), c.gio, 108) AS gio, c.trangThai, c.diaDiem, c.ghiChu
        FROM dbo.lichChamSocOng c
        LEFT JOIN dbo.danOng d ON d.maDanOng = c.maDanOng
        WHERE (@uid IS NULL OR c.maNguoiDung = @uid)
        ORDER BY CASE WHEN c.trangThai = N'${CARE_STATUS.DONE}' THEN 1 ELSE 0 END,
                 CASE WHEN c.trangThai = N'${CARE_STATUS.DONE}' THEN DATEDIFF(DAY, c.ngay, '2100-01-01') ELSE DATEDIFF(DAY, '2000-01-01', c.ngay) END,
                 c.gio, c.id DESC`);
    return result.recordset;
}

async function createCare(userId, data) {
    const pool = await getPool();
    const hive = data.maDanOng ? await getOwnedHive(pool, userId, data.maDanOng) : null;
    const maLich = newCode('LC');
    await pool.request()
        .input('maLich', sql.NVarChar(50), maLich)
        .input('uid', sql.Int, userId)
        .input('maDanOng', sql.NVarChar(50), hive?.maDanOng ?? null)
        .input('tenCongViec', sql.NVarChar(300), data.tenCongViec)
        .input('ngay', sql.Date, data.ngay)
        .input('gio', sql.VarChar(5), data.gio || null)
        .input('trangThai', sql.NVarChar(100), data.trangThai || CARE_STATUS.PLANNED)
        .input('diaDiem', sql.NVarChar(300), data.diaDiem || hive?.viTri || null)
        .input('ghiChu', sql.NVarChar(500), data.ghiChu || null)
        .query(`INSERT INTO dbo.lichChamSocOng (maLich, maNguoiDung, maDanOng, tenCongViec, ngay, gio, trangThai, diaDiem, ghiChu)
                VALUES (@maLich, @uid, @maDanOng, @tenCongViec, @ngay, TRY_CONVERT(time(0), @gio), @trangThai, @diaDiem, @ghiChu)`);
    await notify(pool, userId, 'Đã tạo lịch chăm sóc', `${data.tenCongViec}${hive ? ` cho ${hive.tenDanOng}` : ''} vào ${data.ngay} ${data.gio || ''}.`.trim(), 'Trung bình');
    return { maLich };
}

async function updateCareStatus(userId, maLich, trangThai) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).input('ma', sql.NVarChar(50), maLich)
        .input('trangThai', sql.NVarChar(100), trangThai)
        .query('UPDATE dbo.lichChamSocOng SET trangThai = @trangThai WHERE maLich = @ma AND maNguoiDung = @uid');
    if (!result.rowsAffected[0]) throw new AppError(404, 'Không tìm thấy lịch chăm sóc.');
}

async function deleteCare(userId, maLich) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).input('ma', sql.NVarChar(50), maLich)
        .query('DELETE FROM dbo.lichChamSocOng WHERE maLich = @ma AND maNguoiDung = @uid');
    if (!result.rowsAffected[0]) throw new AppError(404, 'Không tìm thấy lịch chăm sóc.');
}

// ================= LỊCH DI CHUYỂN =================

async function getMoves(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT m.maDiChuyen, m.maDanOng, d.tenDanOng, m.bienSo, m.viTriDi, m.viTriDen, m.maDiaDiemDen,
               CONVERT(varchar(10), m.ngay, 23) AS ngay, m.trangThai, m.ghiChu
        FROM dbo.lichDiChuyenOng m
        LEFT JOIN dbo.danOng d ON d.maDanOng = m.maDanOng
        WHERE (@uid IS NULL OR m.maNguoiDung = @uid)
        ORDER BY CASE WHEN m.trangThai IN (N'${MOVE_STATUS.DONE}', N'${MOVE_STATUS.CANCELLED}') THEN 1 ELSE 0 END, m.ngay DESC, m.id DESC`);
    return result.recordset;
}

async function createMove(userId, data) {
    return inTransaction(async (tx) => {
        const hive = await getOwnedHive(tx, userId, data.maDanOng);
        let destination = data.viTriDen;
        if (data.maDiaDiemDen) {
            const location = await assertCanPlace(tx, userId, data.maDiaDiemDen, hive.soThung, hive.maDanOng);
            destination = location.tenDiaDiem;
        }
        if (!destination) throw new AppError(400, 'Vui lòng chọn hoặc nhập vị trí đến.');

        const maDiChuyen = newCode('DC');
        await tx.request()
            .input('maDiChuyen', sql.NVarChar(50), maDiChuyen)
            .input('uid', sql.Int, userId)
            .input('maDanOng', sql.NVarChar(50), hive.maDanOng)
            .input('bienSo', sql.NVarChar(50), data.bienSo || null)
            .input('viTriDi', sql.NVarChar(300), data.viTriDi || hive.viTri || 'Chưa xác định')
            .input('viTriDen', sql.NVarChar(300), destination)
            .input('maDiaDiemDen', sql.Int, data.maDiaDiemDen || null)
            .input('ngay', sql.Date, data.ngay)
            .input('trangThai', sql.NVarChar(100), MOVE_STATUS.PLANNED)
            .input('ghiChu', sql.NVarChar(500), data.ghiChu || null)
            .query(`INSERT INTO dbo.lichDiChuyenOng (maDiChuyen, maNguoiDung, maDanOng, bienSo, viTriDi, viTriDen, maDiaDiemDen, ngay, trangThai, ghiChu)
                    VALUES (@maDiChuyen, @uid, @maDanOng, @bienSo, @viTriDi, @viTriDen, @maDiaDiemDen, @ngay, @trangThai, @ghiChu)`);
        await notify(tx, userId, 'Đã lên lịch di chuyển', `${hive.tenDanOng}: ${hive.viTri || '?'} → ${destination} ngày ${data.ngay}.`, 'Trung bình');
        return { maDiChuyen };
    });
}

// Hoàn thành di chuyển sẽ cập nhật vị trí đàn ong và ghi lịch sử GPS.
async function updateMoveStatus(userId, maDiChuyen, trangThai) {
    return inTransaction(async (tx) => {
        const result = await tx.request().input('uid', sql.Int, userId).input('ma', sql.NVarChar(50), maDiChuyen)
            .query('SELECT * FROM dbo.lichDiChuyenOng WITH (UPDLOCK) WHERE maDiChuyen = @ma AND maNguoiDung = @uid');
        const move = result.recordset[0];
        if (!move) throw new AppError(404, 'Không tìm thấy lịch di chuyển.');
        if ([MOVE_STATUS.DONE, MOVE_STATUS.CANCELLED].includes(move.trangThai)) {
            throw new AppError(409, 'Lịch di chuyển này đã kết thúc.');
        }

        await tx.request().input('ma', sql.NVarChar(50), maDiChuyen).input('trangThai', sql.NVarChar(100), trangThai)
            .query('UPDATE dbo.lichDiChuyenOng SET trangThai = @trangThai WHERE maDiChuyen = @ma');

        if (trangThai === MOVE_STATUS.DONE && move.maDanOng) {
            const hive = await getOwnedHive(tx, userId, move.maDanOng);
            const location = move.maDiaDiemDen
                ? await assertCanPlace(tx, userId, move.maDiaDiemDen, hive.soThung, hive.maDanOng)
                : null;
            await tx.request()
                .input('ma', sql.NVarChar(50), move.maDanOng)
                .input('viTri', sql.NVarChar(300), move.viTriDen)
                .input('maDiaDiem', sql.Int, location?.maDiaDiem ?? null)
                .input('viDo', sql.Decimal(10, 7), location?.viDo ?? null)
                .input('kinhDo', sql.Decimal(10, 7), location?.kinhDo ?? null)
                .query(`
                    UPDATE dbo.danOng SET viTri = @viTri, maDiaDiem = @maDiaDiem,
                           viDo = COALESCE(@viDo, viDo), kinhDo = COALESCE(@kinhDo, kinhDo), ngayCapNhat = SYSUTCDATETIME()
                    WHERE maDanOng = @ma;
                    IF @viDo IS NOT NULL
                        INSERT INTO dbo.lichSuGPSDanOng (maDanOng, viDo, kinhDo, viTri) VALUES (@ma, @viDo, @kinhDo, @viTri);`);
            await notify(tx, userId, 'Đàn ong đã tới nơi', `${hive.tenDanOng} đã được chuyển tới ${move.viTriDen}.`);
            if (location) await notify(tx, location.maChuDat, 'Có đàn ong mới trên đất của bạn', `${hive.tenDanOng} (${hive.soThung} thùng) đã được chuyển tới ${location.tenDiaDiem}.`);
        }
    });
}

// ================= SẢN LƯỢNG & TRUY XUẤT =================

async function getProduction(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT s.maSanLuong, s.maDanOng, d.tenDanOng, s.maDiaDiem, v.tenDiaDiem, s.sanLuong, s.donVi,
               CONVERT(varchar(10), s.ngay, 23) AS ngay, s.loaiMat, s.ghiChu, s.maTruyXuat
        FROM dbo.sanLuongMatOng s
        LEFT JOIN dbo.danOng d ON d.maDanOng = s.maDanOng
        LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = s.maDiaDiem
        WHERE (@uid IS NULL OR s.maNguoiDung = @uid)
        ORDER BY s.ngay DESC, s.id DESC`);
    return result.recordset;
}

// Ghi sản lượng đồng thời tạo bản ghi truy xuất để sinh mã QR cho lô mật.
async function createProduction(userId, data) {
    return inTransaction(async (tx) => {
        const hive = await getOwnedHive(tx, userId, data.maDanOng);
        const place = hive.tenDiaDiem || hive.viTri || 'Bãi đặt ong';
        const trace = await tx.request()
            .input('maDanOng', sql.NVarChar(50), hive.maDanOng)
            .input('uid', sql.Int, userId)
            .input('maDiaDiem', sql.Int, hive.maDiaDiem ?? null)
            .input('tenDiaDiem', sql.NVarChar(300), place)
            .input('loaiOng', sql.NVarChar(200), data.loaiOng || 'Ong mật')
            .input('sanPham', sql.NVarChar(500), data.loaiMat)
            .input('sanLuong', sql.Decimal(12, 2), data.sanLuong)
            .input('ghiChu', sql.NVarChar(1000), data.ghiChu || `${data.sanLuong} ${data.donVi} từ ${hive.tenDanOng}`)
            .query(`INSERT INTO dbo.truyXuatKhaiThacOng (maDanOng, maNguoiDung, maDiaDiem, tenDiaDiem, loaiOng, sanPham, sanLuongDuKien, ghiChu, trangThai)
                    OUTPUT INSERTED.id
                    VALUES (@maDanOng, @uid, @maDiaDiem, @tenDiaDiem, @loaiOng, @sanPham, @sanLuong, @ghiChu, N'Đã thu hoạch')`);
        const maTruyXuat = trace.recordset[0].id;

        const maSanLuong = newCode('SL');
        await tx.request()
            .input('maSanLuong', sql.NVarChar(50), maSanLuong)
            .input('uid', sql.Int, userId)
            .input('maDanOng', sql.NVarChar(50), hive.maDanOng)
            .input('maDiaDiem', sql.Int, hive.maDiaDiem ?? null)
            .input('sanLuong', sql.Decimal(12, 2), data.sanLuong)
            .input('donVi', sql.NVarChar(20), data.donVi)
            .input('ngay', sql.Date, data.ngay)
            .input('loaiMat', sql.NVarChar(200), data.loaiMat)
            .input('ghiChu', sql.NVarChar(500), data.ghiChu || null)
            .input('maTruyXuat', sql.Int, maTruyXuat)
            .query(`INSERT INTO dbo.sanLuongMatOng (maSanLuong, maNguoiDung, maDanOng, maDiaDiem, sanLuong, donVi, ngay, loaiMat, ghiChu, maTruyXuat)
                    VALUES (@maSanLuong, @uid, @maDanOng, @maDiaDiem, @sanLuong, @donVi, @ngay, @loaiMat, @ghiChu, @maTruyXuat)`);

        await notify(tx, userId, 'Đã ghi nhận sản lượng', `${data.sanLuong} ${data.donVi} ${data.loaiMat} từ ${hive.tenDanOng}. Mã QR truy xuất #${maTruyXuat} đã sẵn sàng.`);
        if (hive.maDiaDiem) {
            const owner = await tx.request().input('loc', sql.Int, hive.maDiaDiem).query('SELECT maChuDat FROM dbo.diaDiemVuon WHERE maDiaDiem = @loc');
            await notify(tx, owner.recordset[0]?.maChuDat, 'Thu hoạch trên đất của bạn', `${hive.tenNguoiNuoiOng || 'Người nuôi ong'} đã thu ${data.sanLuong} ${data.donVi} ${data.loaiMat} tại ${place}.`);
        }
        return { maSanLuong, maTruyXuat };
    });
}

async function getTraceList(userId) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT TOP 50 t.id, t.maDanOng, d.tenDanOng, t.tenDiaDiem, t.loaiOng, t.sanPham, t.sanLuongDuKien, t.trangThai,
               FORMAT(DATEADD(HOUR, 7, t.createdAt), 'dd/MM/yyyy HH:mm') AS thoiGian
        FROM dbo.truyXuatKhaiThacOng t LEFT JOIN dbo.danOng d ON d.maDanOng = t.maDanOng
        WHERE t.maNguoiDung = @uid ORDER BY t.createdAt DESC, t.id DESC`);
    return result.recordset;
}

// Dữ liệu công khai cho khách hàng quét QR: lô mật, nơi khai thác, người sản xuất và hành trình đàn ong.
async function getPublicTrace(id) {
    const pool = await getPool();
    const head = await pool.request().input('id', sql.Int, id).query(`
        SELECT TOP 1 t.id, t.maDanOng, t.tenDiaDiem, t.loaiOng, t.sanPham, t.sanLuongDuKien, t.ghiChu, t.trangThai,
               FORMAT(DATEADD(HOUR, 7, t.createdAt), 'dd/MM/yyyy HH:mm') AS thoiGian,
               d.tenDanOng, d.soThung, d.cayTruoc,
               v.tenDiaDiem AS tenVuon, v.diaChiChiTiet, v.viDo, v.kinhDo, v.dienTich,
               nn.hoTen AS nguoiNuoiOng, nn.soDienThoai AS sdtNguoiNuoiOng, cd.hoTen AS chuDat
        FROM dbo.truyXuatKhaiThacOng t
        LEFT JOIN dbo.danOng d ON d.maDanOng = t.maDanOng
        LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = COALESCE(t.maDiaDiem, d.maDiaDiem)
        LEFT JOIN dbo.nguoiDung nn ON nn.maNguoiDung = t.maNguoiDung
        LEFT JOIN dbo.nguoiDung cd ON cd.maNguoiDung = v.maChuDat
        WHERE (@id IS NULL OR t.id = @id)
        ORDER BY t.createdAt DESC, t.id DESC`);
    const trace = head.recordset[0];
    if (!trace) return null;
    if (!trace.maDanOng) return { ...trace, hanhTrinh: [] };

    const journey = await pool.request().input('ma', sql.NVarChar(50), trace.maDanOng).query(`
        SELECT TOP 30 * FROM (
            SELECT ngayTao AS moc, N'Di chuyển' AS loai, CONCAT(viTriDi, N' → ', viTriDen, N' (', trangThai, N')') AS noiDung
            FROM dbo.lichDiChuyenOng WHERE maDanOng = @ma
            UNION ALL
            SELECT ngayTao, N'Chăm sóc', CONCAT(tenCongViec, N' – ', trangThai) FROM dbo.lichChamSocOng WHERE maDanOng = @ma
            UNION ALL
            SELECT thoiGian, N'Định vị GPS', CONCAT(ISNULL(viTri, N'Vị trí'), N' (', FORMAT(viDo, 'N5'), N', ', FORMAT(kinhDo, 'N5'), N')')
            FROM dbo.lichSuGPSDanOng WHERE maDanOng = @ma
            UNION ALL
            SELECT ngayTao, N'Thu hoạch', CONCAT(FORMAT(sanLuong, 'G'), ' ', donVi, ' ', loaiMat) FROM dbo.sanLuongMatOng WHERE maDanOng = @ma
        ) x ORDER BY moc DESC`);
    return {
        ...trace,
        hanhTrinh: journey.recordset.map((row) => ({
            thoiGian: new Date(new Date(row.moc).getTime() + 7 * 3600 * 1000).toISOString().slice(0, 16).replace('T', ' '),
            loai: row.loai,
            noiDung: row.noiDung,
        })),
    };
}

// ================= THUÊ ĐẤT (phía người nuôi ong) =================

async function getAvailableLocations(userId, userRole = null) {
    const pool = await getPool();
    const isLandowner = userRole === 'chuDat' || userRole === 'chudat' || userRole === 'admin';
    const excludeSelf = isLandowner ? '' : 'AND d.maChuDat <> @uid';
    const result = await pool.request().input('uid', sql.Int, userId).query(`
        SELECT d.maDiaDiem, d.tenDiaDiem, d.dienTich, d.sucChuaToiDa, d.diaChiChiTiet, d.viDo, d.kinhDo, d.hinhAnh,
               d.loaiHoa, d.loaiOngPhuHop, d.giaThueThang, d.khiHau,
               COALESCE(d.maChuDat, n.maNguoiDung) AS maChuDat, n.hoTen AS tenChuDat, n.soDienThoai AS sdtChuDat,
               
               -- Tổng số đàn ong đã ký hợp đồng hiệu lực
               ISNULL((
                   SELECT SUM(y.soDanOng)
                   FROM dbo.hopDongThueOng h
                   JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                   WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
               ), 0) AS soDanDaThue,

               -- Số đàn còn trống có thể thuê tiếp
               CASE 
                   WHEN d.sucChuaToiDa - ISNULL((
                       SELECT SUM(y.soDanOng)
                       FROM dbo.hopDongThueOng h
                       JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                       WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
                   ), 0) < 0 THEN 0
                   ELSE d.sucChuaToiDa - ISNULL((
                       SELECT SUM(y.soDanOng)
                       FROM dbo.hopDongThueOng h
                       JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                       WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
                   ), 0)
               END AS sucChuaConLai,

               -- Đánh dấu đã hết chỗ
               CASE 
                   WHEN d.sucChuaToiDa <= ISNULL((
                       SELECT SUM(y.soDanOng)
                       FROM dbo.hopDongThueOng h
                       JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                       WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
                   ), 0) THEN 1 
                   ELSE 0 
               END AS daHetCho,

               (SELECT TOP 1 trangThai FROM dbo.yeuCauThueOng y WHERE y.maDiaDiem = d.maDiaDiem AND y.maNguoiNuoiOng = @uid
                   AND y.trangThai IN ('${REQUEST_STATUS.PENDING}', '${REQUEST_STATUS.WAITING_SIGN}') ORDER BY y.ngayTao DESC) AS trangThaiYeuCauCuaToi,
               (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = d.maChuDat) AS tongDanhGiaChuDat,
               (SELECT CAST(ROUND(AVG(CAST(dg.soSao AS FLOAT)), 1) AS DECIMAL(3,1)) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = d.maChuDat) AS uyTinChuDat,
               CASE WHEN (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = d.maChuDat) = 0 THEN 1 ELSE 0 END AS laNguoiMoiChuDat
        FROM dbo.diaDiemVuon d
        LEFT JOIN dbo.nguoiDung n ON d.maChuDat = n.maNguoiDung
        WHERE d.trangThaiKiemDuyet = 'DaDuyet'
          ${excludeSelf}
        ORDER BY d.ngayTao DESC`);
    return result.recordset;
}

const REQUEST_SELECT = `
    SELECT y.maYeuCau, y.maDiaDiem, y.tenDiaDiem, y.thoiGianBatDau, y.thoiGianKetThuc, y.soDanOng, y.giaThueDuKien,
           y.ghiChu, y.trangThai, y.lyDoTuChoi, FORMAT(DATEADD(HOUR, 7, y.ngayTao), 'dd/MM/yyyy HH:mm') AS ngayTao,
           y.maNguoiNuoiOng, nn.hoTen AS tenNguoiNuoiOng, nn.soDienThoai AS sdtNguoiNuoiOng,
           v.maChuDat, cd.hoTen AS tenChuDat, cd.soDienThoai AS sdtChuDat, v.diaChiChiTiet, v.sucChuaToiDa,
           (SELECT TOP 1 maHopDong FROM dbo.hopDongThueOng h WHERE h.maYeuCau = y.maYeuCau) AS maHopDong,
           (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = y.maNguoiNuoiOng) AS tongDanhGiaNguoiNuoiOng,
           (SELECT CAST(ROUND(AVG(CAST(dg.soSao AS FLOAT)), 1) AS DECIMAL(3,1)) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = y.maNguoiNuoiOng) AS uyTinNguoiNuoiOng,
           CASE WHEN (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = y.maNguoiNuoiOng) = 0 THEN 1 ELSE 0 END AS laNguoiMoiNuoiOng,
           (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = v.maChuDat) AS tongDanhGiaChuDat,
           (SELECT CAST(ROUND(AVG(CAST(dg.soSao AS FLOAT)), 1) AS DECIMAL(3,1)) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = v.maChuDat) AS uyTinChuDat,
           CASE WHEN (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = v.maChuDat) = 0 THEN 1 ELSE 0 END AS laNguoiMoiChuDat
    FROM dbo.yeuCauThueOng y
    LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = y.maDiaDiem
    LEFT JOIN dbo.nguoiDung nn ON nn.maNguoiDung = y.maNguoiNuoiOng
    LEFT JOIN dbo.nguoiDung cd ON cd.maNguoiDung = v.maChuDat`;

const REQUEST_ORDER = `ORDER BY CASE y.trangThai WHEN '${REQUEST_STATUS.PENDING}' THEN 0 WHEN '${REQUEST_STATUS.WAITING_SIGN}' THEN 1 ELSE 2 END, y.ngayTao DESC`;

// scope: { beekeeperId } | { ownerId } | {} (admin xem tất cả)
async function getRentalRequests({ beekeeperId = null, ownerId = null } = {}) {
    const pool = await getPool();
    const result = await pool.request().input('bk', sql.Int, beekeeperId).input('owner', sql.Int, ownerId).query(`
        ${REQUEST_SELECT}
        WHERE (@bk IS NULL OR y.maNguoiNuoiOng = @bk) AND (@owner IS NULL OR v.maChuDat = @owner)
        ${REQUEST_ORDER}`);
    return result.recordset;
}

async function createRentalRequest(userId, data) {
    return inTransaction(async (tx) => {
        const locResult = await tx.request().input('loc', sql.Int, data.maDiaDiem).query(`
            SELECT maDiaDiem, maChuDat, tenDiaDiem, sucChuaToiDa, trangThaiKiemDuyet,
                   ISNULL((
                       SELECT SUM(y.soDanOng)
                       FROM dbo.hopDongThueOng h
                       JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                       WHERE h.maDiaDiem = @loc AND h.trangThai = '${CONTRACT_STATUS.SIGNED}'
                   ), 0) AS soDanDaThue
            FROM dbo.diaDiemVuon WHERE maDiaDiem = @loc`);
        const location = locResult.recordset[0];
        if (!location || location.trangThaiKiemDuyet !== 'DaDuyet') throw new AppError(404, 'Địa điểm không tồn tại hoặc chưa được duyệt.');
        if (location.maChuDat === userId) throw new AppError(400, 'Bạn không thể thuê địa điểm của chính mình.');

        const sucChuaConLai = Math.max(0, (location.sucChuaToiDa || 0) - location.soDanDaThue);
        if (sucChuaConLai <= 0) {
            throw new AppError(400, `Địa điểm này đã hết chỗ đặt ong (đã kín ${location.sucChuaToiDa}/${location.sucChuaToiDa} đàn).`);
        }
        if (data.soDanOng > sucChuaConLai) {
            throw new AppError(400, `Địa điểm chỉ còn trống tối đa ${sucChuaConLai} đàn (yêu cầu: ${data.soDanOng} đàn, đã thuê: ${location.soDanDaThue}/${location.sucChuaToiDa}).`);
        }

        const duplicate = await tx.request().input('loc', sql.Int, data.maDiaDiem).input('uid', sql.Int, userId).query(`
            SELECT 1 FROM dbo.yeuCauThueOng WHERE maDiaDiem = @loc AND maNguoiNuoiOng = @uid
            AND trangThai IN ('${REQUEST_STATUS.PENDING}', '${REQUEST_STATUS.WAITING_SIGN}')`);
        if (duplicate.recordset.length) throw new AppError(409, 'Bạn đã có yêu cầu đang xử lý cho địa điểm này.');

        const maYeuCau = newCode('YC');
        await tx.request()
            .input('maYeuCau', sql.NVarChar(50), maYeuCau)
            .input('maDiaDiem', sql.Int, location.maDiaDiem)
            .input('uid', sql.Int, userId)
            .input('tenDiaDiem', sql.NVarChar(300), location.tenDiaDiem)
            .input('batDau', sql.NVarChar(100), data.thoiGianBatDau)
            .input('ketThuc', sql.NVarChar(100), data.thoiGianKetThuc)
            .input('soDanOng', sql.Int, data.soDanOng)
            .input('gia', sql.Decimal(14, 2), data.giaThueDuKien)
            .input('ghiChu', sql.NVarChar(1000), data.ghiChu || null)
            .query(`INSERT INTO dbo.yeuCauThueOng (maYeuCau, maDiaDiem, maNguoiNuoiOng, tenDiaDiem, thoiGianBatDau, thoiGianKetThuc, soDanOng, giaThueDuKien, ghiChu, trangThai)
                    VALUES (@maYeuCau, @maDiaDiem, @uid, @tenDiaDiem, @batDau, @ketThuc, @soDanOng, @gia, @ghiChu, '${REQUEST_STATUS.PENDING}')`);
        await notify(tx, location.maChuDat, 'Yêu cầu thuê đất mới', `Có yêu cầu thuê ${location.tenDiaDiem} cho ${data.soDanOng} đàn ong từ ${data.thoiGianBatDau} đến ${data.thoiGianKetThuc}.`, 'Cao');
        return { maYeuCau };
    });
}

async function cancelRentalRequest(userId, maYeuCau) {
    return inTransaction(async (tx) => {
        const found = await tx.request().input('ma', sql.NVarChar(50), maYeuCau).input('uid', sql.Int, userId)
            .query(`${REQUEST_SELECT} WHERE y.maYeuCau = @ma AND y.maNguoiNuoiOng = @uid`);
        const request = found.recordset[0];
        if (!request) throw new AppError(404, 'Không tìm thấy yêu cầu thuê.');
        if (request.trangThai !== REQUEST_STATUS.PENDING) throw new AppError(409, 'Chỉ hủy được yêu cầu đang chờ chủ đất duyệt.');
        await tx.request().input('ma', sql.NVarChar(50), maYeuCau)
            .query(`UPDATE dbo.yeuCauThueOng SET trangThai = '${REQUEST_STATUS.CANCELLED}', ngayCapNhat = SYSUTCDATETIME() WHERE maYeuCau = @ma`);
        await notify(tx, request.maChuDat, 'Yêu cầu thuê đã bị hủy', `${request.tenNguoiNuoiOng} đã hủy yêu cầu thuê ${request.tenDiaDiem}.`);
    });
}

// ownerId = null nghĩa là quản trị viên duyệt thay chủ đất.
async function approveRentalRequest(ownerId, maYeuCau, contract = {}) {
    return inTransaction(async (tx) => {
        const found = await tx.request().input('ma', sql.NVarChar(50), maYeuCau)
            .query(`${REQUEST_SELECT} WHERE y.maYeuCau = @ma`);
        const request = found.recordset[0];
        if (!request || (ownerId !== null && request.maChuDat !== ownerId)) throw new AppError(404, 'Không tìm thấy yêu cầu thuê trên đất của bạn.');
        if (request.trangThai !== REQUEST_STATUS.PENDING) throw new AppError(409, 'Yêu cầu không còn ở trạng thái chờ duyệt.');

        const maHopDong = newCode('HD');
        const thoiHan = request.thoiGianKetThuc ? `${request.thoiGianBatDau} → ${request.thoiGianKetThuc}` : request.thoiGianBatDau;
        await tx.request()
            .input('maHopDong', sql.NVarChar(50), maHopDong)
            .input('maYeuCau', sql.NVarChar(50), maYeuCau)
            .input('maDiaDiem', sql.Int, request.maDiaDiem)
            .input('maNguoiNuoiOng', sql.Int, request.maNguoiNuoiOng)
            .input('maChuDat', sql.Int, request.maChuDat)
            .input('tenHopDong', sql.NVarChar(300), contract.tenHopDong || `Hợp đồng thuê ${request.tenDiaDiem}`)
            .input('doiTac', sql.NVarChar(300), request.tenNguoiNuoiOng || null)
            .input('giaThue', sql.Decimal(14, 2), contract.giaThue ?? request.giaThueDuKien ?? null)
            .input('thoiHan', sql.NVarChar(100), thoiHan)
            .input('quyDinh', sql.NVarChar(1000), contract.quyDinhBoiThuong || 'Bồi thường theo thỏa thuận nếu gây thiệt hại cho cây trồng hoặc tài sản trên đất.')
            .input('filePdf', sql.NVarChar(500), `/api/hop-dong/pdf/${maHopDong}`)
            .query(`INSERT INTO dbo.hopDongThueOng (maHopDong, maYeuCau, maDiaDiem, maNguoiNuoiOng, maChuDat, tenHopDong, doiTac, giaThue, thoiHan, quyDinhBoiThuong, trangThai, filePdf)
                    VALUES (@maHopDong, @maYeuCau, @maDiaDiem, @maNguoiNuoiOng, @maChuDat, @tenHopDong, @doiTac, @giaThue, @thoiHan, @quyDinh, '${CONTRACT_STATUS.WAITING_SIGN}', @filePdf)`);
        await tx.request().input('ma', sql.NVarChar(50), maYeuCau)
            .query(`UPDATE dbo.yeuCauThueOng SET trangThai = '${REQUEST_STATUS.WAITING_SIGN}', ngayCapNhat = SYSUTCDATETIME() WHERE maYeuCau = @ma`);
        await notify(tx, request.maNguoiNuoiOng, 'Yêu cầu thuê đã được duyệt', `${request.tenChuDat || 'Chủ đất'} đã đồng ý cho thuê ${request.tenDiaDiem}. Vui lòng vào mục Hợp đồng để ký xác nhận.`, 'Cao');
        return { maHopDong };
    });
}

async function rejectRentalRequest(ownerId, maYeuCau, lyDo) {
    return inTransaction(async (tx) => {
        const found = await tx.request().input('ma', sql.NVarChar(50), maYeuCau)
            .query(`${REQUEST_SELECT} WHERE y.maYeuCau = @ma`);
        const request = found.recordset[0];
        if (!request || (ownerId !== null && request.maChuDat !== ownerId)) throw new AppError(404, 'Không tìm thấy yêu cầu thuê trên đất của bạn.');
        if (request.trangThai !== REQUEST_STATUS.PENDING) throw new AppError(409, 'Yêu cầu không còn ở trạng thái chờ duyệt.');
        await tx.request().input('ma', sql.NVarChar(50), maYeuCau).input('lyDo', sql.NVarChar(500), lyDo || null)
            .query(`UPDATE dbo.yeuCauThueOng SET trangThai = '${REQUEST_STATUS.REJECTED}', lyDoTuChoi = @lyDo, ngayCapNhat = SYSUTCDATETIME() WHERE maYeuCau = @ma`);
        await notify(tx, request.maNguoiNuoiOng, 'Yêu cầu thuê bị từ chối', `Yêu cầu thuê ${request.tenDiaDiem} bị từ chối${lyDo ? `: ${lyDo}` : '.'}`, 'Trung bình');
    });
}

// ================= HỢP ĐỒNG =================

const CONTRACT_SELECT = `
    SELECT h.id, h.maHopDong, h.maYeuCau, h.maDiaDiem, v.tenDiaDiem, v.diaChiChiTiet, h.tenHopDong, h.giaThue, h.thoiHan,
           h.quyDinhBoiThuong, h.trangThai, h.otpVerified, h.filePdf,
           FORMAT(DATEADD(HOUR, 7, h.ngayKy), 'dd/MM/yyyy HH:mm') AS ngayKy,
           FORMAT(DATEADD(HOUR, 7, h.ngayTao), 'dd/MM/yyyy HH:mm') AS ngayTao,
           FORMAT(DATEADD(HOUR, 7, h.ngayHoanThanh), 'dd/MM/yyyy HH:mm') AS ngayHoanThanh,
           h.maNguoiNuoiOng, nn.hoTen AS tenNguoiNuoiOng, nn.soDienThoai AS sdtNguoiNuoiOng,
           COALESCE(nn.anhDaiDien, nn.avatarUrl) AS avatarNguoiNuoiOng,
           COALESCE(h.maChuDat, v.maChuDat) AS maChuDat, cd.hoTen AS tenChuDat, cd.soDienThoai AS sdtChuDat,
           COALESCE(cd.anhDaiDien, cd.avatarUrl) AS avatarChuDat,
           (SELECT TOP 1 dg.soSao FROM dbo.danhGiaThueOng dg WHERE dg.maHopDong = h.maHopDong AND dg.vaiTroDanhGia = 'nguoiNuoiOng') AS saoNguoiNuoiOngDanhGia,
           (SELECT TOP 1 dg.nhanXet FROM dbo.danhGiaThueOng dg WHERE dg.maHopDong = h.maHopDong AND dg.vaiTroDanhGia = 'nguoiNuoiOng') AS nhanXetNguoiNuoiOng,
           (SELECT TOP 1 dg.soSao FROM dbo.danhGiaThueOng dg WHERE dg.maHopDong = h.maHopDong AND dg.vaiTroDanhGia = 'chuDat') AS saoChuDatDanhGia,
           (SELECT TOP 1 dg.nhanXet FROM dbo.danhGiaThueOng dg WHERE dg.maHopDong = h.maHopDong AND dg.vaiTroDanhGia = 'chuDat') AS nhanXetChuDat,
           (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maHopDong = h.maHopDong) AS soLuongDanhGia,
           (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = h.maNguoiNuoiOng) AS tongDanhGiaNguoiNuoiOng,
           (SELECT CAST(ROUND(AVG(CAST(dg.soSao AS FLOAT)), 1) AS DECIMAL(3,1)) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = h.maNguoiNuoiOng) AS uyTinNguoiNuoiOng,
           CASE WHEN (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = h.maNguoiNuoiOng) = 0 THEN 1 ELSE 0 END AS laNguoiMoiNuoiOng,
           (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = COALESCE(h.maChuDat, v.maChuDat)) AS tongDanhGiaChuDat,
           (SELECT CAST(ROUND(AVG(CAST(dg.soSao AS FLOAT)), 1) AS DECIMAL(3,1)) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = COALESCE(h.maChuDat, v.maChuDat)) AS uyTinChuDat,
           CASE WHEN (SELECT COUNT(*) FROM dbo.danhGiaThueOng dg WHERE dg.maNguoiDuocDanhGia = COALESCE(h.maChuDat, v.maChuDat)) = 0 THEN 1 ELSE 0 END AS laNguoiMoiChuDat
    FROM dbo.hopDongThueOng h
    LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = h.maDiaDiem
    LEFT JOIN dbo.nguoiDung nn ON nn.maNguoiDung = h.maNguoiNuoiOng
    LEFT JOIN dbo.nguoiDung cd ON cd.maNguoiDung = COALESCE(h.maChuDat, v.maChuDat)`;

// Lọc hợp đồng theo vai trò: người nuôi ong, chủ đất hoặc admin (tất cả).
const contractScope = (user) => {
    if (!user || user.vaiTro === 'admin') return '1 = 1';
    if (user.vaiTro === 'chudat') return 'COALESCE(h.maChuDat, v.maChuDat) = @uid';
    return 'h.maNguoiNuoiOng = @uid';
};

async function getContracts(user) {
    const pool = await getPool();
    const result = await pool.request().input('uid', sql.Int, user?.id ?? null)
        .query(`${CONTRACT_SELECT} WHERE ${contractScope(user)} ORDER BY CASE h.trangThai WHEN '${CONTRACT_STATUS.WAITING_SIGN}' THEN 0 ELSE 1 END, h.ngayTao DESC`);
    return result.recordset;
}

async function getContract(user, maHopDong, target = null) {
    const runner = target || await getPool();
    const result = await runner.request().input('uid', sql.Int, user?.id ?? null).input('ma', sql.NVarChar(50), maHopDong)
        .query(`${CONTRACT_SELECT} WHERE h.maHopDong = @ma AND ${contractScope(user)}`);
    const contract = result.recordset[0];
    if (!contract) throw new AppError(404, 'Không tìm thấy hợp đồng.');
    return contract;
}

async function signContract(user, maHopDong) {
    return inTransaction(async (tx) => {
        const contract = await getContract(user, maHopDong, tx);
        if (contract.maNguoiNuoiOng !== user.id) throw new AppError(403, 'Chỉ người nuôi ong trong hợp đồng mới được ký xác nhận.');
        if (contract.trangThai !== CONTRACT_STATUS.WAITING_SIGN) throw new AppError(409, 'Hợp đồng không ở trạng thái chờ ký.');

        // Lấy số đàn ong của yêu cầu thuê này
        const reqResult = await tx.request().input('yc', sql.NVarChar(50), contract.maYeuCau).query(`
            SELECT soDanOng FROM dbo.yeuCauThueOng WHERE maYeuCau = @yc`);
        const contractSoDan = reqResult.recordset[0]?.soDanOng || 0;

        // Kiểm tra sức chứa hiện tại của địa điểm
        const locResult = await tx.request().input('loc', sql.Int, contract.maDiaDiem).input('hd', sql.NVarChar(50), maHopDong).query(`
            SELECT d.sucChuaToiDa,
                   ISNULL((
                       SELECT SUM(y.soDanOng)
                       FROM dbo.hopDongThueOng h
                       JOIN dbo.yeuCauThueOng y ON h.maYeuCau = y.maYeuCau
                       WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = '${CONTRACT_STATUS.SIGNED}' AND h.maHopDong <> @hd
                   ), 0) AS soDanDaThue
            FROM dbo.diaDiemVuon d WHERE d.maDiaDiem = @loc`);
        const loc = locResult.recordset[0];
        const currentActive = loc ? loc.soDanDaThue : 0;
        const maxCapacity = loc ? loc.sucChuaToiDa : 0;
        const available = Math.max(0, maxCapacity - currentActive);

        if (contractSoDan > available) {
            throw new AppError(409, `Địa điểm không còn đủ chỗ chứa (yêu cầu ${contractSoDan} đàn nhưng chỉ còn trống ${available} đàn).`);
        }

        await tx.request().input('ma', sql.NVarChar(50), maHopDong).input('yc', sql.NVarChar(50), contract.maYeuCau)
            .query(`
                UPDATE dbo.hopDongThueOng SET trangThai = '${CONTRACT_STATUS.SIGNED}', otpVerified = 1, ngayKy = SYSUTCDATETIME() WHERE maHopDong = @ma;
                UPDATE dbo.yeuCauThueOng SET trangThai = '${REQUEST_STATUS.SIGNED}', ngayCapNhat = SYSUTCDATETIME() WHERE maYeuCau = @yc;`);

        // Số chỗ trống còn lại sau khi ký hợp đồng này
        const newRemaining = Math.max(0, available - contractSoDan);

        // Nếu đã hết sạch chỗ -> từ chối các yêu cầu đang chờ khác
        if (newRemaining <= 0) {
            const others = await tx.request().input('loc', sql.Int, contract.maDiaDiem).input('yc', sql.NVarChar(50), contract.maYeuCau).query(`
                UPDATE dbo.yeuCauThueOng SET trangThai = '${REQUEST_STATUS.REJECTED}', lyDoTuChoi = N'Địa điểm đã hết chỗ đặt ong', ngayCapNhat = SYSUTCDATETIME()
                OUTPUT INSERTED.maNguoiNuoiOng
                WHERE maDiaDiem = @loc AND maYeuCau <> @yc AND trangThai = '${REQUEST_STATUS.PENDING}'`);
            for (const row of others.recordset) {
                await notify(tx, row.maNguoiNuoiOng, 'Yêu cầu thuê bị từ chối', `${contract.tenDiaDiem} đã hết chỗ đặt đàn ong.`, 'Trung bình');
            }
        } else {
            // Còn dư chỗ -> chỉ từ chối các yêu cầu có số đàn lớn hơn số chỗ còn lại
            const others = await tx.request().input('loc', sql.Int, contract.maDiaDiem).input('yc', sql.NVarChar(50), contract.maYeuCau).input('rem', sql.Int, newRemaining).query(`
                UPDATE dbo.yeuCauThueOng SET trangThai = '${REQUEST_STATUS.REJECTED}', lyDoTuChoi = N'Địa điểm không còn đủ chỗ cho số đàn bạn yêu cầu', ngayCapNhat = SYSUTCDATETIME()
                OUTPUT INSERTED.maNguoiNuoiOng
                WHERE maDiaDiem = @loc AND maYeuCau <> @yc AND trangThai = '${REQUEST_STATUS.PENDING}' AND soDanOng > @rem`);
            for (const row of others.recordset) {
                await notify(tx, row.maNguoiNuoiOng, 'Yêu cầu thuê bị từ chối', `${contract.tenDiaDiem} chỉ còn ${newRemaining} chỗ trống, không đủ cho số đàn bạn yêu cầu.`, 'Trung bình');
            }
        }

        await notify(tx, contract.maChuDat, 'Hợp đồng đã được ký', `${contract.tenNguoiNuoiOng} đã ký hợp đồng thuê ${contract.tenDiaDiem} (${contractSoDan} đàn).`, 'Cao');
        await notify(tx, user.id, 'Ký hợp đồng thành công', `Bạn có thể đặt ${contractSoDan} đàn ong tại ${contract.tenDiaDiem}.`);
        return getContract(user, maHopDong, tx);
    });
}

// Hoàn tất hợp đồng thuê (người nuôi ong, chủ đất hoặc admin kết thúc đợt thuê)
async function completeContract(user, maHopDong) {
    return inTransaction(async (tx) => {
        const contract = await getContract(user, maHopDong, tx);
        const isNuoiOng = contract.maNguoiNuoiOng === user?.id;
        const isChuDat = contract.maChuDat === user?.id;
        const isAdmin = user?.vaiTro === 'admin';
        if (!isNuoiOng && !isChuDat && !isAdmin) {
            throw new AppError(403, 'Chỉ các bên tham gia hợp đồng hoặc quản trị viên mới có quyền hoàn tất.');
        }
        if (contract.trangThai === CONTRACT_STATUS.COMPLETED) {
            return contract;
        }
        if (contract.trangThai !== CONTRACT_STATUS.SIGNED) {
            throw new AppError(400, 'Chỉ hợp đồng đã ký có hiệu lực mới có thể hoàn tất.');
        }

        await tx.request().input('ma', sql.NVarChar(50), maHopDong)
            .query(`UPDATE dbo.hopDongThueOng SET trangThai = '${CONTRACT_STATUS.COMPLETED}', ngayHoanThanh = SYSUTCDATETIME() WHERE maHopDong = @ma`);

        const senderName = user?.hoTen || (isNuoiOng ? 'Người nuôi ong' : 'Chủ đất');
        const notifyTarget = isNuoiOng ? contract.maChuDat : contract.maNguoiNuoiOng;
        if (notifyTarget) {
            await notify(tx, notifyTarget, 'Hợp đồng thuê đã hoàn thành', `${senderName} đã xác nhận hoàn tất hợp đồng thuê ${contract.tenDiaDiem}. Hãy để lại đánh giá về đối tác!`, 'Trung bình');
        }
        if (user?.id) {
            await notify(tx, user.id, 'Hoàn tất hợp đồng', `Bạn đã hoàn tất hợp đồng thuê ${contract.tenDiaDiem}. Hãy gửi đánh giá về đối tác và địa điểm!`);
        }

        return getContract(user, maHopDong, tx);
    });
}

// Gửi hoặc cập nhật đánh giá (Người nuôi ong đánh giá Chủ đất & Vườn, Chủ đất đánh giá Người nuôi ong)
async function submitReview(user, maHopDong, data) {
    return inTransaction(async (tx) => {
        const contract = await getContract(user, maHopDong, tx);
        const isNuoiOng = contract.maNguoiNuoiOng === user?.id;
        const isChuDat = contract.maChuDat === user?.id;
        if (!isNuoiOng && !isChuDat) {
            throw new AppError(403, 'Chỉ người nuôi ong hoặc chủ đất trong hợp đồng mới có quyền gửi đánh giá.');
        }

        const soSao = parseInt(data.soSao, 10);
        if (isNaN(soSao) || soSao < 1 || soSao > 5) {
            throw new AppError(400, 'Số sao đánh giá phải từ 1 đến 5 sao.');
        }

        const tieuChi1 = data.tieuChi1 != null ? Math.max(1, Math.min(5, parseInt(data.tieuChi1, 10) || 5)) : null;
        const tieuChi2 = data.tieuChi2 != null ? Math.max(1, Math.min(5, parseInt(data.tieuChi2, 10) || 5)) : null;
        const nhanXet = data.nhanXet ? String(data.nhanXet).trim().slice(0, 1000) : null;

        const vaiTroDanhGia = isNuoiOng ? 'nguoiNuoiOng' : 'chuDat';
        const maNguoiDuocDanhGia = isNuoiOng ? contract.maChuDat : contract.maNguoiNuoiOng;

        // Nếu hợp đồng đang ở trạng thái DaKy, tự động chuyển sang HoanThanh
        if (contract.trangThai === CONTRACT_STATUS.SIGNED) {
            await tx.request().input('ma', sql.NVarChar(50), maHopDong)
                .query(`UPDATE dbo.hopDongThueOng SET trangThai = '${CONTRACT_STATUS.COMPLETED}', ngayHoanThanh = SYSUTCDATETIME() WHERE maHopDong = @ma`);
        }

        // Upsert đánh giá của người dùng cho hợp đồng này
        await tx.request()
            .input('maHopDong', sql.NVarChar(50), maHopDong)
            .input('maDiaDiem', sql.Int, contract.maDiaDiem)
            .input('uid', sql.Int, user.id)
            .input('vaiTro', sql.NVarChar(50), vaiTroDanhGia)
            .input('targetUid', sql.Int, maNguoiDuocDanhGia)
            .input('soSao', sql.Int, soSao)
            .input('tieuChi1', sql.Int, tieuChi1)
            .input('tieuChi2', sql.Int, tieuChi2)
            .input('nhanXet', sql.NVarChar(1000), nhanXet)
            .query(`
                IF EXISTS (SELECT 1 FROM dbo.danhGiaThueOng WHERE maHopDong = @maHopDong AND maNguoiDanhGia = @uid)
                BEGIN
                    UPDATE dbo.danhGiaThueOng
                    SET soSao = @soSao,
                        tieuChi1 = @tieuChi1,
                        tieuChi2 = @tieuChi2,
                        nhanXet = @nhanXet,
                        ngayCapNhat = SYSUTCDATETIME()
                    WHERE maHopDong = @maHopDong AND maNguoiDanhGia = @uid;
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.danhGiaThueOng (maHopDong, maDiaDiem, maNguoiDanhGia, vaiTroDanhGia, maNguoiDuocDanhGia, soSao, tieuChi1, tieuChi2, nhanXet)
                    VALUES (@maHopDong, @maDiaDiem, @uid, @vaiTro, @targetUid, @soSao, @tieuChi1, @tieuChi2, @nhanXet);
                END
            `);

        if (maNguoiDuocDanhGia) {
            const reviewerName = user.hoTen || (isNuoiOng ? 'Người nuôi ong' : 'Chủ đất');
            await notify(tx, maNguoiDuocDanhGia, 'Đánh giá mới từ đối tác', `${reviewerName} đã gửi đánh giá (${soSao} ⭐) cho hợp đồng thuê ${contract.tenDiaDiem}.`, 'Trung bình');
        }

        return getContractReviews(user, maHopDong, tx);
    });
}

// Lấy danh sách đánh giá của 1 hợp đồng
async function getContractReviews(user, maHopDong, target = null) {
    const runner = target || await getPool();
    const result = await runner.request()
        .input('ma', sql.NVarChar(50), maHopDong)
        .query(`
            SELECT dg.id, dg.maHopDong, dg.maDiaDiem, dg.maNguoiDanhGia, dg.vaiTroDanhGia, dg.maNguoiDuocDanhGia,
                   dg.soSao, dg.tieuChi1, dg.tieuChi2, dg.nhanXet, dg.phanHoi,
                   FORMAT(DATEADD(HOUR, 7, dg.ngayTao), 'dd/MM/yyyy HH:mm') AS ngayTao,
                   FORMAT(DATEADD(HOUR, 7, dg.ngayCapNhat), 'dd/MM/yyyy HH:mm') AS ngayCapNhat,
                   ndg.hoTen AS tenNguoiDanhGia,
                   COALESCE(ndg.anhDaiDien, ndg.avatarUrl) AS avatarNguoiDanhGia,
                   ndd.hoTen AS tenNguoiDuocDanhGia,
                   COALESCE(ndd.anhDaiDien, ndd.avatarUrl) AS avatarNguoiDuocDanhGia
            FROM dbo.danhGiaThueOng dg
            LEFT JOIN dbo.nguoiDung ndg ON ndg.maNguoiDung = dg.maNguoiDanhGia
            LEFT JOIN dbo.nguoiDung ndd ON ndd.maNguoiDung = dg.maNguoiDuocDanhGia
            WHERE dg.maHopDong = @ma
            ORDER BY dg.ngayTao ASC
        `);
    return result.recordset;
}

// Lấy đánh giá của một địa điểm vườn (dành cho người nuôi ong tham khảo trước khi thuê)
async function getLocationReviews(maDiaDiem) {
    const pool = await getPool();
    const result = await pool.request()
        .input('loc', sql.Int, maDiaDiem)
        .query(`
            SELECT dg.id, dg.maHopDong, dg.maDiaDiem, dg.maNguoiDanhGia, dg.vaiTroDanhGia,
                   dg.soSao, dg.tieuChi1, dg.tieuChi2, dg.nhanXet,
                   FORMAT(DATEADD(HOUR, 7, dg.ngayTao), 'dd/MM/yyyy') AS ngayTao,
                   ndg.hoTen AS tenNguoiDanhGia,
                   COALESCE(ndg.anhDaiDien, ndg.avatarUrl) AS avatarNguoiDanhGia
            FROM dbo.danhGiaThueOng dg
            LEFT JOIN dbo.nguoiDung ndg ON ndg.maNguoiDung = dg.maNguoiDanhGia
            WHERE dg.maDiaDiem = @loc AND dg.vaiTroDanhGia = 'nguoiNuoiOng'
            ORDER BY dg.ngayTao DESC
        `);
    const reviews = result.recordset;
    const total = reviews.length;
    const avg = total > 0 ? (reviews.reduce((s, r) => s + r.soSao, 0) / total).toFixed(1) : 0;
    return { reviews, totalReviews: total, averageRating: Number(avg) };
}

// Lấy tất cả đánh giá phục vụ admin quản trị
async function getAllReviews() {
    const pool = await getPool();
    const result = await pool.request().query(`
        SELECT dg.id, dg.maHopDong, dg.maDiaDiem, v.tenDiaDiem, dg.maNguoiDanhGia, dg.vaiTroDanhGia,
               dg.soSao, dg.tieuChi1, dg.tieuChi2, dg.nhanXet,
               FORMAT(DATEADD(HOUR, 7, dg.ngayTao), 'dd/MM/yyyy HH:mm') AS ngayTao,
               ndg.hoTen AS tenNguoiDanhGia, COALESCE(ndg.anhDaiDien, ndg.avatarUrl) AS avatarNguoiDanhGia,
               ndd.hoTen AS tenNguoiDuocDanhGia, COALESCE(ndd.anhDaiDien, ndd.avatarUrl) AS avatarNguoiDuocDanhGia
        FROM dbo.danhGiaThueOng dg
        LEFT JOIN dbo.diaDiemVuon v ON v.maDiaDiem = dg.maDiaDiem
        LEFT JOIN dbo.nguoiDung ndg ON ndg.maNguoiDung = dg.maNguoiDanhGia
        LEFT JOIN dbo.nguoiDung ndd ON ndd.maNguoiDung = dg.maNguoiDuocDanhGia
        ORDER BY dg.ngayTao DESC
    `);
    return result.recordset;
}

// ================= TỔNG HỢP =================

async function getBeekeeperDashboard(userId) {
    const pool = await getPool();
    const [hives, care, moves, production, notifications, rentedLocations, stats] = await Promise.all([
        getHives(userId), getCare(userId), getMoves(userId), getProduction(userId), getNotifications(userId), getRentedLocations(userId),
        pool.request().input('uid', sql.Int, userId).query(`
            SELECT
                (SELECT COUNT(*) FROM dbo.yeuCauThueOng WHERE maNguoiNuoiOng = @uid AND trangThai = '${REQUEST_STATUS.PENDING}') AS yeuCauChoDuyet,
                (SELECT COUNT(*) FROM dbo.hopDongThueOng WHERE maNguoiNuoiOng = @uid AND trangThai = '${CONTRACT_STATUS.WAITING_SIGN}') AS hopDongChoKy,
                (SELECT COUNT(*) FROM dbo.hopDongThueOng WHERE maNguoiNuoiOng = @uid AND trangThai = '${CONTRACT_STATUS.SIGNED}') AS hopDongHieuLuc,
                (SELECT COUNT(*) FROM dbo.lichChamSocOng WHERE maNguoiDung = @uid AND trangThai <> N'${CARE_STATUS.DONE}'
                    AND ngay <= CAST(DATEADD(DAY, 2, DATEADD(HOUR, 7, SYSUTCDATETIME())) AS date)) AS chamSocSapToi`),
    ]);
    const extra = stats.recordset[0];
    const kg = production.filter((item) => String(item.donVi).toLowerCase() === 'kg').reduce((sum, item) => sum + Number(item.sanLuong || 0), 0);
    return {
        summary: {
            totalHives: hives.length,
            totalBoxes: hives.reduce((sum, hive) => sum + Number(hive.soThung || 0), 0),
            totalCareTasks: care.filter((item) => item.trangThai !== CARE_STATUS.DONE).length,
            careDueSoon: extra.chamSocSapToi,
            activeMoves: moves.filter((item) => ![MOVE_STATUS.DONE, MOVE_STATUS.CANCELLED].includes(item.trangThai)).length,
            totalProductionKg: Math.round(kg * 100) / 100,
            unreadNotifications: notifications.filter((item) => !item.daDoc).length,
            pendingRequests: extra.yeuCauChoDuyet,
            contractsToSign: extra.hopDongChoKy,
            activeContracts: extra.hopDongHieuLuc,
        },
        hives, careSchedule: care, movements: moves, production, notifications, rentedLocations,
    };
}


// ================= ĐĂNG KÝ VÀ QUẢN LÝ ĐỊA ĐIỂM (CHỦ ĐẤT) =================

async function createLocation(userId, data) {
    const pool = await getPool();
    const result = await pool.request()
        .input('uid', sql.Int, userId)
        .input('ten', sql.NVarChar(150), data.tenDiaDiem)
        .input('viDo', sql.Decimal(10, 8), data.viDo)
        .input('kinhDo', sql.Decimal(11, 8), data.kinhDo)
        .input('dienTich', sql.Float, data.dienTich)
        .input('sucChua', sql.Int, data.sucChuaToiDa)
        .input('chiTiet', sql.NVarChar(sql.MAX), data.diaChiChiTiet)
        .input('phapLy', sql.NVarChar(sql.MAX), data.thongTinPhapLy || null)
        .input('hinhAnh', sql.NVarChar(sql.MAX), data.hinhAnh || null)
        .query(`
            INSERT INTO dbo.diaDiemVuon 
            (maChuDat, tenDiaDiem, viDo, kinhDo, dienTich, sucChuaToiDa, diaChiChiTiet, thongTinPhapLy, trangThaiKiemDuyet, hinhAnh)
            VALUES 
            (@uid, @ten, @viDo, @kinhDo, @dienTich, @sucChua, @chiTiet, @phapLy, 'ChoDiemDuyet', @hinhAnh);
            SELECT SCOPE_IDENTITY() AS maDiaDiem;
        `);
    return { maDiaDiem: result.recordset[0].maDiaDiem };
}

async function updateLocation(userId, locationId, data) {
    const pool = await getPool();
    await pool.request()
        .input('locId', sql.Int, locationId)
        .input('uid', sql.Int, userId)
        .input('ten', sql.NVarChar(150), data.tenDiaDiem)
        .input('viDo', sql.Decimal(10, 8), data.viDo)
        .input('kinhDo', sql.Decimal(11, 8), data.kinhDo)
        .input('dienTich', sql.Float, data.dienTich)
        .input('sucChua', sql.Int, data.sucChuaToiDa)
        .input('chiTiet', sql.NVarChar(sql.MAX), data.diaChiChiTiet)
        .input('phapLy', sql.NVarChar(sql.MAX), data.thongTinPhapLy || null)
        // Nếu data.hinhAnh không có, ta truyền null. Câu truy vấn COALESCE sẽ giữ lại ảnh cũ
        .input('hinhAnh', sql.NVarChar(sql.MAX), data.hinhAnh || null)
        .query(`
            UPDATE dbo.diaDiemVuon 
            SET tenDiaDiem = @ten, 
                viDo = @viDo, 
                kinhDo = @kinhDo, 
                dienTich = @dienTich, 
                sucChuaToiDa = @sucChua, 
                diaChiChiTiet = @chiTiet, 
                thongTinPhapLy = @phapLy,
                -- QUAN TRỌNG: Nếu ảnh gửi lên là NULL thì giữ nguyên ảnh cũ (hinhAnh = hinhAnh)
                hinhAnh = COALESCE(@hinhAnh, hinhAnh),
                trangThaiKiemDuyet = 'ChoDiemDuyet'
            WHERE maDiaDiem = @locId AND maChuDat = @uid
        `);
}
module.exports = {
    REQUEST_STATUS, CONTRACT_STATUS, CARE_STATUS, MOVE_STATUS,
    getPool, inTransaction, notify, relativeTime,
    getNotifications, markNotificationsRead,
    getHives, getRentedLocations, createHive, updateHive, deleteHive, updateHiveLocation, getGpsHistory,
    getCare, createCare, updateCareStatus, deleteCare,
    getMoves, createMove, updateMoveStatus,
    getProduction, createProduction, getTraceList, getPublicTrace,
    getAvailableLocations, getRentalRequests, createRentalRequest, cancelRentalRequest, approveRentalRequest, rejectRentalRequest,
    getContracts, getContract, signContract, completeContract,
    submitReview, getContractReviews, getLocationReviews, getAllReviews,
    getBeekeeperDashboard,
    createLocation, updateLocation,
};