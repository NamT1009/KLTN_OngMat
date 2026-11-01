const repo = require('../config/landownerRepository');
const beekeeping = require('../config/beekeepingRepository');
const {
    AppError, asyncHandler, text, requiredText, positiveNumber, optionalNumber, coordinates,
} = require('../utils/http');

exports.dashboard = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getLandownerDashboard(req.user.id) });
});

// ----- Địa điểm đặt ong -----

function detectClimate(viDo, kinhDo, diaChi = '') {
    const text = (diaChi || '').toLowerCase();
    if (text.includes('mộc châu') || text.includes('sơn la')) return 'Ôn đới mát mẻ (18-24°C)';
    if (text.includes('hà giang') || text.includes('mèo vạc') || text.includes('đồng văn')) return 'Cao nguyên đá lạnh, khô ráo';
    if (text.includes('đà lạt') || text.includes('lâm đồng')) return 'Ôn đới cao nguyên mát mẻ (16-22°C)';
    if (text.includes('đắk lắk') || text.includes('gia lai') || text.includes('buôn ma thuột') || text.includes('pleiku') || text.includes('kon tum')) return 'Cao nguyên ôn hòa (20-28°C)';
    if (text.includes('u minh') || text.includes('cà mau') || text.includes('bến tre') || text.includes('kiên giang')) return 'Nhiệt đới ẩm gió mùa (27-32°C)';
    if (text.includes('hưng yên') || text.includes('bắc giang') || text.includes('hải dương') || text.includes('hà nội')) return 'Nhiệt đới gió mùa có mùa đông lạnh';
    
    if (viDo != null) {
        const lat = Number(viDo);
        const lng = Number(kinhDo);
        if (lat >= 21.5) return 'Cao nguyên đá lạnh, khô ráo';
        if (lat >= 20.0 && lng < 105.5) return 'Ôn đới mát mẻ (18-24°C)';
        if (lat >= 19.5) return 'Nhiệt đới gió mùa có mùa đông lạnh';
        if (lat >= 11.5 && lat <= 15.5 && lng < 108.8) return 'Cao nguyên ôn hòa (20-28°C)';
        if (lat <= 11.0) return 'Nhiệt đới ẩm gió mùa (27-32°C)';
    }
    return 'Nhiệt đới gió mùa';
}

const locationPayload = (body) => {
    const coords = coordinates(body.viDo, body.kinhDo);
    const rawClimate = text(body.khiHau, 200);
    const khiHau = (rawClimate && rawClimate.trim().length > 0)
        ? rawClimate
        : detectClimate(coords.viDo, coords.kinhDo, body.diaChiChiTiet);

    return {
        tenDiaDiem: requiredText(body.tenDiaDiem, 'tên địa điểm', 200),
        ...coords,
        dienTich: positiveNumber(body.dienTich, 'Diện tích'),
        sucChuaToiDa: positiveNumber(body.sucChuaToiDa, 'Sức chứa tối đa', { integer: true }),
        diaChiChiTiet: requiredText(body.diaChiChiTiet, 'địa chỉ chi tiết', 500),
        thongTinPhapLy: text(body.thongTinPhapLy, 2000) || null,
        hinhAnh: body.hinhAnh || null,
        loaiHoa: text(body.loaiHoa, 200) || null,
        loaiOngPhuHop: text(body.loaiOngPhuHop, 200) || null,
        giaThueThang: optionalNumber(body.giaThueThang),
        khiHau: khiHau || 'Nhiệt đới gió mùa',
    };
};

exports.listLocations = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getLocations(req.user.id) });
});

exports.createLocation = asyncHandler(async (req, res) => {
    const location = await repo.createLocation(req.user.id, locationPayload(req.body || {}));
    res.status(201).json({ success: true, message: 'Đã đăng địa điểm. Vui lòng chờ quản trị viên kiểm duyệt.', data: location });
});

exports.updateLocation = asyncHandler(async (req, res) => {
    const id = positiveNumber(req.params.id, 'Mã địa điểm', { integer: true });
    const location = await repo.updateLocation(req.user.id, id, locationPayload(req.body || {}));
    res.json({ success: true, message: 'Đã cập nhật địa điểm, đang chờ kiểm duyệt lại.', data: location });
});

exports.deleteLocation = asyncHandler(async (req, res) => {
    const id = positiveNumber(req.params.id, 'Mã địa điểm', { integer: true });
    await repo.deleteLocation(req.user.id, id);
    res.json({ success: true, message: 'Đã xóa địa điểm.' });
});

// ----- Yêu cầu thuê -----

exports.listRequests = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await beekeeping.getRentalRequests({ ownerId: req.user.id }) });
});

exports.approveRequest = asyncHandler(async (req, res) => {
    const body = req.body || {};
    const giaThue = optionalNumber(body.giaThue);
    if (giaThue !== null && giaThue < 0) throw new AppError(400, 'Giá thuê không được âm.');
    const result = await beekeeping.approveRentalRequest(req.user.id, String(req.params.id), {
        giaThue,
        tenHopDong: text(body.tenHopDong, 300) || null,
        quyDinhBoiThuong: text(body.quyDinhBoiThuong, 1000) || null,
    });
    res.json({ success: true, message: 'Đã duyệt yêu cầu và tạo hợp đồng chờ người nuôi ong ký.', data: result });
});

exports.rejectRequest = asyncHandler(async (req, res) => {
    await beekeeping.rejectRentalRequest(req.user.id, String(req.params.id), text(req.body?.lyDo, 500));
    res.json({ success: true, message: 'Đã từ chối yêu cầu thuê.' });
});

// ----- Giám sát trên đất -----

exports.hivesOnLand = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getHivesOnLand(req.user.id) });
});

exports.productionOnLand = asyncHandler(async (req, res) => {
    res.json({ success: true, data: await repo.getProductionOnLand(req.user.id) });
});
