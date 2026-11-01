const repo = require('../config/beekeepingRepository');
const {
    AppError, asyncHandler, text, requiredText, positiveNumber, optionalNumber, coordinates, isoDate,
} = require('../utils/http');

const { CARE_STATUS, MOVE_STATUS } = repo;
const today = () => new Date(Date.now() + 7 * 3600 * 1000).toISOString().slice(0, 10);

exports.dashboard = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getBeekeeperDashboard(req.user.id) });
});

// ----- Đàn ong -----

exports.listHives = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getHives(req.user.id) });
});

exports.listRentedLocations = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getRentedLocations(req.user.id) });
});

const hivePayload = (body, partial) => {
    const data = {};
    if (!partial || body.tenDanOng !== undefined) data.tenDanOng = requiredText(body.tenDanOng, 'tên đàn ong', 200);
    if (!partial || body.soThung !== undefined) data.soThung = positiveNumber(body.soThung, 'Số thùng ong', { integer: true });
    if (data.soThung > 500) throw new AppError(400, 'Số thùng ong tối đa 500 cho một đàn.');
    for (const [key, max] of [['viTri', 300], ['tinhTrang', 200], ['cayTruoc', 200]]) {
        if (body[key] !== undefined) data[key] = text(body[key], max) || null;
    }
    if (body.maDiaDiem !== undefined) data.maDiaDiem = optionalNumber(body.maDiaDiem);
    if (!partial && body.viDo != null && body.kinhDo != null && body.viDo !== '' && body.kinhDo !== '') {
        Object.assign(data, coordinates(body.viDo, body.kinhDo));
    }
    return data;
};

exports.createHive = asyncHandler(async (req, res) => {
    const hive = await repo.createHive(req.user.id, hivePayload(req.body || {}, false));
    res.status(201).json({ success: true, message: 'Đã tạo đàn ong và các thùng ong.', data: hive });
});

exports.updateHive = asyncHandler(async (req, res) => {
    const hive = await repo.updateHive(req.user.id, String(req.params.id), hivePayload(req.body || {}, true));
    res.json({ success: true, message: 'Đã cập nhật đàn ong.', data: hive });
});

exports.deleteHive = asyncHandler(async (req, res) => {
    await repo.deleteHive(req.user.id, String(req.params.id));
    res.json({ success: true, message: 'Đã xóa đàn ong và các thùng ong.' });
});

exports.updateLocation = asyncHandler(async (req, res) => {
    const body = req.body || {};
    const hiveId = requiredText(req.params.id || body.maDanOng, 'mã đàn ong', 50);
    const hive = await repo.updateHiveLocation(req.user.id, hiveId, { ...coordinates(body.viDo, body.kinhDo), viTri: text(body.viTri, 300) });
    res.json({ success: true, message: 'Đã cập nhật vị trí GPS đàn ong.', data: hive });
});

exports.gpsHistory = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getGpsHistory(req.user.id, String(req.params.id)) });
});

// ----- Chăm sóc -----

exports.listCare = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getCare(req.user.id) });
});

exports.createCare = asyncHandler(async (req, res) => {
    const body = req.body || {};
    const gio = text(body.gio, 5);
    if (gio && !/^([01]\d|2[0-3]):[0-5]\d$/.test(gio)) throw new AppError(400, 'Giờ phải có dạng HH:mm.');
    const trangThai = body.trangThai === CARE_STATUS.DONE ? CARE_STATUS.DONE : CARE_STATUS.PLANNED;
    const record = await repo.createCare(req.user.id, {
        maDanOng: text(body.maDanOng, 50) || null,
        tenCongViec: requiredText(body.tenCongViec, 'công việc chăm sóc', 300),
        ngay: body.ngay ? isoDate(body.ngay, 'Ngày chăm sóc') : today(),
        gio: gio || null,
        trangThai,
        diaDiem: text(body.diaDiem, 300) || null,
        ghiChu: text(body.ghiChu, 500) || null,
    });
    res.status(201).json({ success: true, message: 'Đã lưu lịch chăm sóc.', data: record });
});

exports.updateCareStatus = asyncHandler(async (req, res) => {
    const trangThai = String(req.body?.trangThai || '');
    if (!Object.values(CARE_STATUS).includes(trangThai)) throw new AppError(400, 'Trạng thái chăm sóc không hợp lệ.');
    await repo.updateCareStatus(req.user.id, String(req.params.id), trangThai);
    res.json({ success: true, message: trangThai === CARE_STATUS.DONE ? 'Đã đánh dấu hoàn thành.' : 'Đã chuyển về lên lịch.' });
});

exports.deleteCare = asyncHandler(async (req, res) => {
    await repo.deleteCare(req.user.id, String(req.params.id));
    res.json({ success: true, message: 'Đã xóa lịch chăm sóc.' });
});

// ----- Di chuyển -----

exports.listMoves = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getMoves(req.user.id) });
});

exports.createMove = asyncHandler(async (req, res) => {
    const body = req.body || {};
    const record = await repo.createMove(req.user.id, {
        maDanOng: requiredText(body.maDanOng, 'đàn ong cần di chuyển', 50),
        maDiaDiemDen: optionalNumber(body.maDiaDiemDen),
        viTriDi: text(body.viTriDi, 300) || null,
        viTriDen: text(body.viTriDen, 300) || null,
        ngay: body.ngay ? isoDate(body.ngay, 'Ngày di chuyển') : today(),
        bienSo: text(body.bienSo, 50) || null,
        ghiChu: text(body.ghiChu, 500) || null,
    });
    res.status(201).json({ success: true, message: 'Đã lên lịch di chuyển đàn ong.', data: record });
});

exports.updateMoveStatus = asyncHandler(async (req, res) => {
    const trangThai = String(req.body?.trangThai || '');
    if (![MOVE_STATUS.MOVING, MOVE_STATUS.DONE, MOVE_STATUS.CANCELLED].includes(trangThai)) {
        throw new AppError(400, 'Trạng thái di chuyển không hợp lệ.');
    }
    await repo.updateMoveStatus(req.user.id, String(req.params.id), trangThai);
    const messages = {
        [MOVE_STATUS.MOVING]: 'Đã bắt đầu di chuyển.',
        [MOVE_STATUS.DONE]: 'Đã hoàn thành di chuyển và cập nhật vị trí đàn ong.',
        [MOVE_STATUS.CANCELLED]: 'Đã hủy lịch di chuyển.',
    };
    res.json({ success: true, message: messages[trangThai] });
});

// ----- Sản lượng & truy xuất -----

exports.listProduction = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getProduction(req.user.id) });
});

exports.createProduction = asyncHandler(async (req, res) => {
    const body = req.body || {};
    const donVi = text(body.donVi, 20) || 'kg';
    if (!['kg', 'lít'].includes(donVi)) throw new AppError(400, 'Đơn vị chỉ nhận kg hoặc lít.');
    const record = await repo.createProduction(req.user.id, {
        maDanOng: requiredText(body.maDanOng, 'đàn ong thu hoạch', 50),
        sanLuong: positiveNumber(body.sanLuong, 'Sản lượng'),
        donVi,
        ngay: body.ngay ? isoDate(body.ngay, 'Ngày thu hoạch') : today(),
        loaiMat: requiredText(body.loaiMat, 'loại mật', 200),
        loaiOng: text(body.loaiOng, 200) || null,
        ghiChu: text(body.ghiChu, 500) || null,
    });
    res.status(201).json({ success: true, message: 'Đã ghi nhận sản lượng và tạo mã truy xuất.', data: record });
});

exports.listTraces = asyncHandler(async (req, res) => {
    const baseUrl = process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
    const traces = await repo.getTraceList(req.user.id);
    res.json({ success: true, data: traces.map((item) => ({ ...item, qrUrl: `${baseUrl}/truy-xuat-qr?ma=${item.id}` })) });
});

// ----- Thuê đất -----

exports.availableLocations = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getAvailableLocations(req.user.id, req.user.vaiTro) });
});

exports.listRequests = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getRentalRequests({ beekeeperId: req.user.id }) });
});

exports.createRequest = asyncHandler(async (req, res) => {
    const body = req.body || {};
    const thoiGianBatDau = isoDate(body.thoiGianBatDau, 'Ngày bắt đầu');
    const thoiGianKetThuc = isoDate(body.thoiGianKetThuc, 'Ngày kết thúc');
    if (thoiGianKetThuc <= thoiGianBatDau) throw new AppError(400, 'Ngày kết thúc phải sau ngày bắt đầu.');
    const gia = optionalNumber(body.giaThueDuKien);
    if (gia !== null && gia < 0) throw new AppError(400, 'Giá thuê không được âm.');
    const record = await repo.createRentalRequest(req.user.id, {
        maDiaDiem: positiveNumber(body.maDiaDiem, 'Mã địa điểm', { integer: true }),
        thoiGianBatDau,
        thoiGianKetThuc,
        soDanOng: positiveNumber(body.soDanOng, 'Số đàn ong', { integer: true }),
        giaThueDuKien: gia,
        ghiChu: text(body.ghiChu, 1000) || null,
    });
    res.status(201).json({ success: true, message: 'Đã gửi yêu cầu thuê cho chủ đất.', data: record });
});

exports.cancelRequest = asyncHandler(async (req, res) => {
    await repo.cancelRentalRequest(req.user.id, String(req.params.id));
    res.json({ success: true, message: 'Đã hủy yêu cầu thuê.' });
});
