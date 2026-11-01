const rentalRequests = [];
const harvestReports = [];
const beekeepingRepository = require('../config/beekeepingRepository');
const contractRecords = [
    {
        contractId: 'HD-1001',
        maHopDong: 'HD-1001',
        tenHopDong: 'Hợp đồng thuê vườn',
        doiTac: 'Chủ đất Demo',
        giaThue: '3.500.000 đ / tháng',
        thoiHan: '6 tháng',
        quyDinhBoiThuong: 'Bồi thường 100% nếu có rủi ro do người nuôi ong gây ra',
        ngayKy: '2026-01-15',
        trangThai: 'ChoKhachKy',
        filePdf: '/api/hop-dong/pdf/HD-1001',
    },
    {
        contractId: 'HD-1002',
        maHopDong: 'HD-1002',
        tenHopDong: 'Hợp đồng chăm sóc đàn ong',
        doiTac: 'Người nuôi ong Demo',
        giaThue: '2.800.000 đ / tháng',
        thoiHan: '4 tháng',
        quyDinhBoiThuong: 'Đảm bảo kiểm soát dịch bệnh và tuân thủ quy trình an toàn',
        ngayKy: '2026-02-20',
        trangThai: 'DaKy',
        filePdf: '/api/hop-dong/pdf/HD-1002',
    },
];

const buildDefaultFarmList = () => [
    {
        maDiaDiem: 1,
        tenDiaDiem: 'Vườn Nhãn 12',
        diaChiChiTiet: 'Bãi A, Hương Thủy',
        viDo: 16.0196,
        kinhDo: 108.2326,
        dienTich: 1200,
        sucChuaToiDa: 60,
        maChuDat: 2,
        tenChuDat: 'Chủ đất Demo',
        sdtChuDat: '0901000001',
        trangThai: 'Đang khai thác',
        loaiMat: 'Mật nhãn',
        sanLuong: 240,
    },
    {
        maDiaDiem: 2,
        tenDiaDiem: 'Vườn Bưởi 68',
        diaChiChiTiet: 'Bãi C, Quảng Nam',
        viDo: 15.9688,
        kinhDo: 108.143,
        dienTich: 900,
        sucChuaToiDa: 45,
        tenChuDat: 'Chủ đất Demo',
        sdtChuDat: '0901000001',
        trangThai: 'Sẵn sàng',
        loaiMat: 'Mật bưởi',
        sanLuong: 180,
    },
];

const toNumber = (value, fallback = 0) => {
    const parsed = Number(value ?? fallback);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const safeQuery = async (pool, query) => {
    if (!pool) {
        return { recordset: [] };
    }

    try {
        return await pool.request().query(query);
    } catch (error) {
        console.warn('Query mobile fallback:', error.message);
        return { recordset: [] };
    }
};

const normalizeStatus = (value) => {
    const text = String(value ?? '').trim();
    if (!text) return 'Đang hoạt động';
    const normalized = text.toLowerCase();
    if (normalized.includes('dang') || normalized.includes('hoat')) return 'Đang khai thác';
    if (normalized.includes('san')) return 'Sẵn sàng';
    if (normalized.includes('duyet')) return 'Đã duyệt';
    return text;
};

const buildRentalRequestRecord = (payload = {}) => {
    const tenDiaDiem = String(payload.tenDiaDiem ?? payload.tenVuon ?? '').trim();
    const thoiGianBatDau = String(payload.thoiGianBatDau ?? payload.thoiGianThue ?? payload.ngayBatDau ?? '').trim();
    const soDanOng = toNumber(payload.soDanOng ?? payload.soDan ?? 0, 0);
    const giaThueDuKien = toNumber(payload.giaThueDuKien ?? payload.giaThue ?? payload.giaDeXuat ?? 0, 0);

    return {
        id: Date.now() + Math.floor(Math.random() * 1000),
        maYeuCau: String(payload.maYeuCau ?? `YC-${Date.now()}`),
        maDiaDiem: payload.maDiaDiem ?? 0,
        maNguoiNuoiOng: payload.maNguoiNuoiOng ?? payload.userId ?? 0,
        tenDiaDiem,
        thoiGianBatDau,
        thoiGianKetThuc: String(payload.thoiGianKetThuc ?? '').trim(),
        soDanOng,
        giaThueDuKien,
        ghiChu: String(payload.ghiChu ?? '').trim(),
        trangThai: String(payload.trangThai ?? 'ChoDuyet').trim(),
        createdAt: new Date().toISOString(),
    };
};

const buildContractDetail = (contractId, detail = {}) => ({
    id: detail.id ?? contractId,
    contractId,
    maHopDong: detail.maHopDong ?? contractId,
    tenHopDong: detail.tenHopDong ?? 'Hợp đồng thuê vườn',
    doiTac: detail.doiTac ?? 'Chủ đất Demo',
    giaThue: detail.giaThue ?? '3.500.000 đ / tháng',
    thoiHan: detail.thoiHan ?? '6 tháng',
    ngayKy: detail.ngayKy ?? new Date().toISOString().slice(0, 10),
    quyDinhBoiThuong: detail.quyDinhBoiThuong ?? 'Bồi thường 100% nếu có thiệt hại do người thuê gây ra.',
    trangThai: detail.trangThai ?? 'ChoKhachKy',
    filePdf: detail.filePdf ?? `/api/hop-dong/pdf/${contractId}`,
    noiDung: detail.noiDung ?? 'Hợp đồng thuê bãi đặt ong theo điều khoản đã thỏa thuận giữa hai bên.',
});

const beekeepingHives = [
    {
        maDanOng: 'DN-01',
        tenDanOng: 'Đàn ong Bãi A',
        viTri: 'Bãi A, Hương Thủy',
        viDo: 16.0196,
        kinhDo: 108.2326,
        soThung: 18,
        tinhTrang: 'Sức khỏe ổn định',
        cayTruoc: 'Mật hoa nhãn',
    },
    {
        maDanOng: 'DN-02',
        tenDanOng: 'Đàn ong Bãi B',
        viTri: 'Bãi B, Quảng Nam',
        viDo: 15.9688,
        kinhDo: 108.143,
        soThung: 14,
        tinhTrang: 'Cần bổ sung thức ăn',
        cayTruoc: 'Mật bưởi',
    },
];

const careSchedules = [
    {
        maLich: 'LC-101',
        tenCongViec: 'Kiểm tra sức khỏe thùng ong',
        ngay: '2026-10-11',
        gio: '07:30',
        trangThai: 'Lên lịch',
        diaDiem: 'Bãi A',
    },
    {
        maLich: 'LC-102',
        tenCongViec: 'Bổ sung thức ăn và nước',
        ngay: '2026-10-13',
        gio: '06:00',
        trangThai: 'Lên lịch',
        diaDiem: 'Bãi B',
    },
];

const movementSchedules = [
    {
        maDiChuyen: 'DC-201',
        bienSo: 'QN-76A-1123',
        viTriDi: 'Bãi A',
        viTriDen: 'Bãi C',
        ngay: '2026-10-12',
        trangThai: 'Đang di chuyển',
    },
];

const productionRecords = [
    {
        maSanLuong: 'SL-301',
        sanLuong: 180,
        donVi: 'kg',
        ngay: '2026-10-11',
        loaiMat: 'Mật hoa nhãn',
    },
    {
        maSanLuong: 'SL-302',
        sanLuong: 210,
        donVi: 'kg',
        ngay: '2026-10-10',
        loaiMat: 'Mật bưởi',
    },
];

const beekeepingNotifications = [
    {
        tieuDe: 'Lịch chăm sóc gần tới',
        noiDung: 'Đàn ong Bãi A cần kiểm tra sức khỏe thùng ong vào 07:30 ngày 11/10.',
        mucDo: 'Cao',
        thoiGian: '1 giờ trước',
    },
    {
        tieuDe: 'Khai thác mùa hoa nhãn',
        noiDung: 'Sản lượng dự kiến tăng nhanh trong 48 giờ tới, cần cập nhật hàng ngày.',
        mucDo: 'Trung bình',
        thoiGian: 'Hôm nay',
    },
];

const signContractRecord = (contracts, contractId, otp) => {
    const normalizedOtp = String(otp ?? '').trim();
    const updated = contracts.map((item) => ({ ...item }));
    const target = updated.find((item) => String(item.contractId ?? item.maHopDong ?? item.id) === String(contractId));

    if (!target) {
        return updated;
    }

    if (!normalizedOtp) {
        throw new Error('Vui lòng nhập mã OTP để xác nhận ký số.');
    }

    target.trangThai = 'DaKy';
    target.otpVerified = true;
    target.daKyNgay = new Date().toISOString();
    target.filePdf = target.filePdf || `/api/hop-dong/pdf/${target.contractId ?? contractId}`;
    return updated;
};

const buildBeekeepingDashboard = ({
    hives = beekeepingHives,
    care = careSchedules,
    moves = movementSchedules,
    production = productionRecords,
    notificationsList = beekeepingNotifications,
} = {}) => {
    const totalHives = Array.isArray(hives) ? hives.length : 0;
    const totalCareTasks = Array.isArray(care) ? care.length : 0;
    const totalMoves = Array.isArray(moves) ? moves.length : 0;
    const totalProductionKg = (Array.isArray(production) ? production : []).reduce((sum, item) => {
        const value = Number(item?.sanLuong ?? 0);
        return sum + (Number.isFinite(value) ? value : 0);
    }, 0);

    return {
        summary: {
            totalHives,
            totalCareTasks,
            totalMoves,
            totalProductionKg,
        },
        hives: Array.isArray(hives) ? hives : [],
        careSchedule: Array.isArray(care) ? care : [],
        movements: Array.isArray(moves) ? moves : [],
        production: Array.isArray(production) ? production : [],
        notifications: Array.isArray(notificationsList) ? notificationsList : [],
        alerts: [
            {
                title: 'Lịch chăm sóc',
                detail: `${Math.max(totalCareTasks, 1)} công việc cần được lên lịch và thực hiện trong 48 giờ.`,
            },
            {
                title: 'Vị trí đàn ong',
                detail: `${Math.max(totalHives, 1)} đàn ong đang được cập nhật GPS theo thời gian thực.`,
            },
        ],
    };
};

const addCareLog = (payload = {}) => {
    const record = {
        maLich: payload.maLich || `LC-${Date.now()}`,
        tenCongViec: payload.tenCongViec || 'Kiểm tra đàn ong',
        ngay: payload.ngay || new Date().toISOString().slice(0, 10),
        gio: payload.gio || '07:00',
        trangThai: payload.trangThai || 'Lên lịch',
        diaDiem: payload.diaDiem || 'Bãi A',
    };
    careSchedules.unshift(record);
    return record;
};

const addHiveMove = (payload = {}) => {
    const record = {
        maDiChuyen: payload.maDiChuyen || `DC-${Date.now()}`,
        bienSo: payload.bienSo || 'QN-76A-0000',
        viTriDi: payload.viTriDi || 'Bãi A',
        viTriDen: payload.viTriDen || 'Bãi C',
        ngay: payload.ngay || new Date().toISOString().slice(0, 10),
        trangThai: payload.trangThai || 'Đang di chuyển',
    };
    movementSchedules.unshift(record);
    return record;
};

const addProductionUpdate = (payload = {}) => {
    const record = {
        maSanLuong: payload.maSanLuong || `SL-${Date.now()}`,
        maDanOng: payload.maDanOng || null,
        tenDiaDiem: payload.tenDiaDiem || payload.viTri || 'Bai dat ong',
        sanLuong: Number(payload.sanLuong ?? 0),
        donVi: payload.donVi || 'kg',
        ngay: payload.ngay || new Date().toISOString().slice(0, 10),
        loaiMat: payload.loaiMat || 'Mật hoa nhãn',
    };
    productionRecords.unshift(record);
    return record;
};

exports.buildRentalRequestRecord = buildRentalRequestRecord;
exports.buildContractDetail = buildContractDetail;
exports.buildBeekeepingDashboard = buildBeekeepingDashboard;
exports.addCareLog = addCareLog;
exports.addHiveMove = addHiveMove;
exports.addProductionUpdate = addProductionUpdate;
exports.signContractRecord = signContractRecord;

exports.getBeekeepingDashboard = async (req, res) => {
    try {
        const [hives, care, moves, production, notifications] = await Promise.all([
            beekeepingRepository.getHives(),
            beekeepingRepository.getCare(),
            beekeepingRepository.getMoves(),
            beekeepingRepository.getProduction(),
            beekeepingRepository.getNotifications(),
        ]);
        const hasDatabase = [hives, care, moves, production, notifications].every((value) => value !== null);
        return res.json({
            success: true,
            data: hasDatabase
                ? buildBeekeepingDashboard({ hives, care, moves, production, notificationsList: notifications })
                : buildBeekeepingDashboard(),
        });
    } catch (error) {
        console.error('Lỗi dashboard người nuôi ong:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getHiveManagement = async (req, res) => {
    try {
        const data = await beekeepingRepository.getHives();
        return res.json({ success: true, data: data ?? beekeepingHives });
    } catch (error) {
        console.error('Lỗi quản lý đàn ong:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.createHive = async (req, res) => {
    try {
        const payload = req.body || {};
        const name = String(payload.tenDanOng || '').trim();
        const hiveCount = Number(payload.soThung ?? 0);
        if (!name || !Number.isFinite(hiveCount) || hiveCount < 1) {
            return res.status(400).json({ success: false, message: 'Vui lòng nhập tên đàn ong và số thùng lớn hơn 0.' });
        }

        const record = {
            maDanOng: payload.maDanOng || `DN-${String(Date.now()).slice(-6)}`,
            tenDanOng: name,
            viTri: payload.viTri || 'Chưa cập nhật vị trí',
            viDo: Number(payload.viDo ?? 0),
            kinhDo: Number(payload.kinhDo ?? 0),
            soThung: hiveCount,
            tinhTrang: payload.tinhTrang || 'Mới tạo',
            cayTruoc: payload.cayTruoc || 'Chưa cập nhật',
        };
        const saved = await beekeepingRepository.createHive(record);
        if (saved === null) beekeepingHives.unshift(record);
        await beekeepingRepository.insertNotification({
            tieuDe: 'Đàn ong mới đã được tạo',
            noiDung: `${record.tenDanOng} gồm ${record.soThung} thùng ong đã được thêm vào hệ thống.`,
            mucDo: 'Thấp',
        });
        beekeepingNotifications.unshift({
            tieuDe: 'Đàn ong mới đã được tạo',
            noiDung: `${record.tenDanOng} gồm ${record.soThung} thùng ong đã được thêm vào hệ thống.`,
            mucDo: 'Thấp',
            thoiGian: 'Vừa xong',
        });
        return res.status(201).json({ success: true, message: 'Đã tạo đàn ong.', data: record });
    } catch (error) {
        console.error('Lỗi tạo đàn ong:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.updateHive = async (req, res) => {
    try {
        const hiveId = String(req.params.id || '').trim();
        const databaseHives = await beekeepingRepository.getHives();
        const target = (databaseHives ?? beekeepingHives).find((item) => item.maDanOng === hiveId);
        if (!target) return res.status(404).json({ success: false, message: 'Không tìm thấy đàn ong.' });

        const payload = req.body || {};
        const saved = await beekeepingRepository.updateHive(hiveId, payload);
        if (saved === true) {
            const updated = (await beekeepingRepository.getHives() || []).find((item) => item.maDanOng === hiveId);
            return res.json({ success: true, message: 'Đã cập nhật đàn ong và thùng ong.', data: updated || target });
        }
        if (payload.tenDanOng != null) target.tenDanOng = String(payload.tenDanOng).trim();
        if (payload.soThung != null) target.soThung = Number(payload.soThung);
        if (payload.tinhTrang != null) target.tinhTrang = String(payload.tinhTrang);
        if (payload.cayTruoc != null) target.cayTruoc = String(payload.cayTruoc);
        if (payload.viTri != null) target.viTri = String(payload.viTri);
        return res.json({ success: true, message: 'Đã cập nhật đàn ong và thùng ong.', data: target });
    } catch (error) {
        console.error('Lỗi cập nhật đàn ong:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.deleteHive = async (req, res) => {
    try {
        const hiveId = String(req.params.id || '').trim();
        const databaseHives = await beekeepingRepository.getHives();
        const source = databaseHives ?? beekeepingHives;
        const index = source.findIndex((item) => String(item.maDanOng) === hiveId);
        if (index < 0) return res.status(404).json({ success: false, message: 'Không tìm thấy đàn ong.' });
        const deleted = await beekeepingRepository.deleteHive(hiveId);
        if (deleted === null) beekeepingHives.splice(index, 1);
        return res.json({ success: true, message: 'Đã xóa đàn ong và các thùng ong.' });
    } catch (error) {
        console.error('Lỗi xóa đàn ong:', error);
        return res.status(500).json({ success: false, message: 'Không thể xóa đàn ong.' });
    }
};

exports.getCareSchedule = async (req, res) => {
    try {
        const data = await beekeepingRepository.getCare();
        return res.json({ success: true, data: data ?? careSchedules });
    } catch (error) {
        console.error('Lỗi lịch chăm sóc:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getMovementSchedule = async (req, res) => {
    try {
        const data = await beekeepingRepository.getMoves();
        return res.json({ success: true, data: data ?? movementSchedules });
    } catch (error) {
        console.error('Lỗi lịch di chuyển:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getProductionRecords = async (req, res) => {
    try {
        const data = await beekeepingRepository.getProduction();
        return res.json({ success: true, data: data ?? productionRecords });
    } catch (error) {
        console.error('Lỗi sản lượng mật ong:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getBeekeepingNotifications = async (req, res) => {
    try {
        const data = await beekeepingRepository.getNotifications();
        return res.json({ success: true, data: data ?? beekeepingNotifications });
    } catch (error) {
        console.error('Lỗi thông báo người nuôi ong:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.updateHiveLocation = async (req, res) => {
    try {
        const payload = req.body || {};
        const hiveId = String(payload.maDanOng || payload.hiveId || '').trim();
        const latitude = Number(payload.viDo);
        const longitude = Number(payload.kinhDo);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            return res.status(400).json({ success: false, message: 'Tọa độ GPS không hợp lệ.' });
        }
        const databaseHives = await beekeepingRepository.getHives();
        let target = (databaseHives ?? beekeepingHives).find((item) => item.maDanOng === hiveId);

        if (!target) {
            return res.status(404).json({ success: false, message: 'Không tìm thấy đàn ong.' });
        }

        const saved = await beekeepingRepository.updateLocation(hiveId, {
            viDo: latitude,
            kinhDo: longitude,
            viTri: payload.viTri,
            hinhAnh: payload.hinhAnh
        });
        if (saved) target = saved;
        target.viDo = latitude;
        target.kinhDo = longitude;
        if (payload.viTri) target.viTri = payload.viTri;

        await beekeepingRepository.insertNotification({
            tieuDe: 'Vị trí đàn ong đã được cập nhật',
            noiDung: `${target.tenDanOng} đang ở ${target.viTri}.`,
            mucDo: 'Thấp',
        });

        beekeepingNotifications.unshift({
            tieuDe: 'Vị trí đàn ong đã được cập nhật',
            noiDung: `${target.tenDanOng} đang ở ${target.viTri}.`,
            mucDo: 'Thấp',
            thoiGian: 'Vừa xong',
        });

        return res.json({ success: true, message: 'Cập nhật vị trí GPS đàn ong thành công.', data: target });
    } catch (error) {
        console.error('Lỗi cập nhật vị trí GPS:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.createCareLog = async (req, res) => {
    try {
        const record = addCareLog(req.body || {});
        await beekeepingRepository.insertCare(record);
        await beekeepingRepository.insertNotification({
            tieuDe: 'Đã tạo lịch chăm sóc',
            noiDung: `${record.tenCongViec} tại ${record.diaDiem} vào ${record.ngay} ${record.gio}.`,
            mucDo: 'Trung bình',
        });
        beekeepingNotifications.unshift({
            tieuDe: 'Đã tạo lịch chăm sóc',
            noiDung: `${record.tenCongViec} tại ${record.diaDiem} vào ${record.ngay} ${record.gio}.`,
            mucDo: 'Trung bình',
            thoiGian: 'Vừa xong',
        });
        return res.status(201).json({ success: true, message: 'Ghi nhận chăm sóc đã được lưu.', data: record });
    } catch (error) {
        console.error('Lỗi lưu lịch chăm sóc:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.createHiveMove = async (req, res) => {
    try {
        const record = addHiveMove(req.body || {});
        await beekeepingRepository.insertMove(record);
        await beekeepingRepository.insertNotification({
            tieuDe: 'Đã tạo lịch di chuyển',
            noiDung: `Di chuyển đàn ong từ ${record.viTriDi} đến ${record.viTriDen} vào ${record.ngay}.`,
            mucDo: 'Trung bình',
        });
        beekeepingNotifications.unshift({
            tieuDe: 'Đã tạo lịch di chuyển',
            noiDung: `Di chuyển đàn ong từ ${record.viTriDi} đến ${record.viTriDen} vào ${record.ngay}.`,
            mucDo: 'Trung bình',
            thoiGian: 'Vừa xong',
        });
        return res.status(201).json({ success: true, message: 'Lịch di chuyển đàn ong đã được cập nhật.', data: record });
    } catch (error) {
        console.error('Lỗi lưu lịch di chuyển:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.createProductionUpdate = async (req, res) => {
    try {
        const record = addProductionUpdate(req.body || {});
        if (!Number.isFinite(record.sanLuong) || record.sanLuong <= 0) {
            return res.status(400).json({ success: false, message: 'Sản lượng phải lớn hơn 0.' });
        }
        const saved = await beekeepingRepository.insertProduction(record);
        if (saved === null) return res.status(503).json({ success: false, message: 'Không thể lưu sản lượng vào SQL Server.' });
        const qrSaved = await beekeepingRepository.insertHarvest({
            maDanOng: record.maDanOng,
            tenDiaDiem: record.tenDiaDiem,
            loaiOng: req.body.loaiOng || 'Ong mat',
            sanPham: record.loaiMat,
            sanLuongDuKien: record.sanLuong,
            ghiChu: req.body.ghiChu || `San luong ${record.sanLuong} ${record.donVi}`,
            trangThai: 'Da cap nhat',
        });
        if (qrSaved === null) return res.status(503).json({ success: false, message: 'Đã lưu sản lượng nhưng chưa đồng bộ được dữ liệu QR.' });
        await beekeepingRepository.insertNotification({
            tieuDe: 'Đã cập nhật sản lượng',
            noiDung: `${record.sanLuong} ${record.donVi} ${record.loaiMat} đã được ghi nhận.`,
            mucDo: 'Thấp',
        });
        harvestReports.unshift({
            id: Date.now(),
            tenDiaDiem: record.viTri || 'Bãi đặt ong',
            loaiOng: record.loaiMat,
            sanPham: record.loaiMat,
            sanLuongDuKien: record.sanLuong,
            trangThai: 'Đã cập nhật',
            createdAt: new Date().toISOString(),
        });
        beekeepingNotifications.unshift({
            tieuDe: 'Đã cập nhật sản lượng',
            noiDung: `${record.sanLuong} ${record.donVi} ${record.loaiMat} đã được ghi nhận.`,
            mucDo: 'Thấp',
            thoiGian: 'Vừa xong',
        });
        return res.status(201).json({ success: true, message: 'Cập nhật sản lượng mật ong thành công.', data: record });
    } catch (error) {
        console.error('Lỗi lưu sản lượng:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getRentalRequests = async (req, res) => {
    try {
        const saved = await beekeepingRepository.getRentalRequests();
        return res.json({ success: true, data: saved ?? rentalRequests });
    } catch (error) {
        console.error('Lỗi lấy yêu cầu thuê:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.createRentalRequest = async (req, res) => {
    try {
        const payload = req.body || {};
        const record = buildRentalRequestRecord(payload);

        if (!record.tenDiaDiem || !record.thoiGianBatDau) {
            return res.status(400).json({ success: false, message: 'Thiếu tên vườn hoặc thời gian thuê.' });
        }

        const saved = await beekeepingRepository.insertRentalRequest(record);
        if (saved === null) rentalRequests.push(record);
        return res.status(201).json({ success: true, message: 'Yêu cầu thuê đã được gửi cho chủ đất.', data: record });
    } catch (error) {
        console.error('Lỗi tạo yêu cầu thuê:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.approveRentalRequest = async (req, res) => {
    try {
        const requestId = String(req.params.id || '').trim();
        const payload = req.body || {};
        const saved = await beekeepingRepository.approveRentalRequest(requestId, payload);
        if (saved?.error) return res.status(409).json({ success: false, message: saved.error });
        if (saved) return res.json({ success: true, message: 'Đã duyệt yêu cầu và tạo hợp đồng.', data: saved });

        const request = rentalRequests.find((item) => String(item.maYeuCau) === requestId || String(item.id) === requestId);
        if (!request) return res.status(404).json({ success: false, message: 'Không tìm thấy yêu cầu.' });
        request.trangThai = 'ChoKhachKy';
        const contract = buildContractDetail(payload.maHopDong || `HD-${Date.now()}`, {
            maYeuCau: request.maYeuCau,
            maDiaDiem: request.maDiaDiem,
            tenHopDong: payload.tenHopDong || `Hợp đồng thuê ${request.tenDiaDiem}`,
            giaThue: payload.giaThue || request.giaThueDuKien,
            thoiHan: payload.thoiHan || request.thoiGianBatDau,
            trangThai: 'ChoKhachKy',
        });
        contractRecords.unshift(contract);
        return res.json({ success: true, message: 'Đã duyệt yêu cầu và tạo hợp đồng.', data: contract });
    } catch (error) {
        console.error('Lỗi duyệt yêu cầu thuê:', error);
        return res.status(500).json({ success: false, message: 'Không thể duyệt yêu cầu.' });
    }
};

exports.submitHarvestInfo = async (req, res) => {
    try {
        const payload = req.body || {};
        const tenDiaDiem = String(payload.tenDiaDiem ?? '').trim();
        const loaiOng = String(payload.loaiOng ?? payload.loaiMat ?? '').trim();

        if (!tenDiaDiem || !loaiOng) {
            return res.status(400).json({ success: false, message: 'Thiếu thông tin vườn hoặc loại ong.' });
        }

        const record = {
            id: Date.now(),
            userId: payload.userId ?? 0,
            tenDiaDiem,
            loaiOng,
            sanPham: payload.sanPham ?? 'Mật hoa nhãn',
            sanLuongDuKien: payload.sanLuongDuKien ?? 1200,
            ghiChu: payload.ghiChu ?? 'Dữ liệu khai thác được đồng bộ từ người nuôi ong',
            trangThai: 'Đã đồng bộ',
            createdAt: new Date().toISOString(),
        };

        await beekeepingRepository.insertHarvest(record);
        harvestReports.unshift(record);
        return res.status(201).json({ success: true, message: 'Dữ liệu khai thác đã được đồng bộ thành công.', data: record });
    } catch (error) {
        console.error('Lỗi cập nhật khai thác:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getLatestQrSyncInfo = async (req, res) => {
    try {
        const latest = await beekeepingRepository.getLatestHarvest() || harvestReports[0] || {
            tenDiaDiem: 'Vườn Nhãn 12',
            loaiOng: 'Ong mật ruệ',
            sanPham: 'Mật hoa nhãn',
            sanLuongDuKien: 1200,
            trangThai: 'Đã đồng bộ',
            createdAt: new Date().toISOString(),
        };

        const baseUrl = process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
        return res.json({
            success: true,
            data: { ...latest, qrUrl: `${baseUrl}/truy-xuat-qr` },
        });
    } catch (error) {
        console.error('Lỗi lấy dữ liệu QR sync:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

// Trang truy xuất công khai dùng trực tiếp từ mã QR, không yêu cầu đăng nhập.
exports.getPublicQrTrace = async (req, res) => {
    try {
        const latest = await beekeepingRepository.getLatestHarvest() || harvestReports[0];
        if (!latest) return res.status(404).send('Chưa có dữ liệu truy xuất nguồn gốc.');

        const escapeHtml = (value) => String(value ?? '')
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        const rows = [
            ['Địa điểm', latest.tenDiaDiem],
            ['Loại ong', latest.loaiOng],
            ['Sản phẩm', latest.sanPham],
            ['Sản lượng dự kiến', `${latest.sanLuongDuKien ?? 0} kg`],
            ['Trạng thái', latest.trangThai],
            ['Cập nhật lúc', latest.createdAt],
        ].map(([label, value]) => `<p><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</p>`).join('');

        res.type('html').send(`<!doctype html><html lang="vi"><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Truy xuất nguồn gốc Ong Mật</title>
            <body style="font-family:Arial,sans-serif;max-width:680px;margin:30px auto;padding:20px">
            <h1>Truy xuất nguồn gốc Ong Mật</h1><section>${rows}</section></body></html>`);
    } catch (error) {
        console.error('Lỗi trang truy xuất QR:', error);
        res.status(500).send('Không thể tải dữ liệu truy xuất nguồn gốc.');
    }
};

exports.getDanhSachDiaDiemChoMobile = async (req, res) => {
    try {
        const { poolPromise } = require('../config/db');
        const pool = await poolPromise;
        const result = await safeQuery(pool, `
            SELECT TOP 20
                d.maDiaDiem, d.tenDiaDiem, d.dienTich, d.sucChuaToiDa,
                d.diaChiChiTiet, d.viDo, d.kinhDo,
                d.trangThaiKiemDuyet,
                d.maChuDat,
                n.hoTen AS tenChuDat, n.soDienThoai AS sdtChuDat
            FROM diaDiemVuon d
            LEFT JOIN nguoiDung n ON d.maChuDat = n.maNguoiDung
            WHERE d.trangThaiKiemDuyet = 'DaDuyet'
              AND NOT EXISTS (
                  SELECT 1 FROM yeuCauDatCho y
                  WHERE y.maDiaDiem = d.maDiaDiem
                    AND y.trangThaiYeuCau = 'DaChapNhan'
              )
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.hopDongThueOng h
                  WHERE h.maDiaDiem = d.maDiaDiem AND h.trangThai = 'DaKy'
              )
            ORDER BY d.ngayTao DESC
        `);

        const data = (result.recordset || []).length > 0
            ? result.recordset.map((item) => ({
                ...item,
                trangThai: normalizeStatus(item.trangThaiKiemDuyet),
            }))
            : buildDefaultFarmList();

        res.json({ success: true, data });
    } catch (err) {
        console.error('Lỗi lấy danh sách địa điểm mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getMobileDashboard = async (req, res) => {
    try {
        const { poolPromise } = require('../config/db');
        const pool = await poolPromise;
        const locationsQuery = await safeQuery(pool, `
            SELECT TOP 20 *
            FROM diaDiemVuon
            ORDER BY ngayTao DESC
        `);

        const userCount = await safeQuery(pool, `SELECT COUNT(*) AS total FROM nguoiDung`);
        const farmCount = await safeQuery(pool, `SELECT COUNT(*) AS total FROM diaDiemVuon`);
        const rows = locationsQuery.recordset || [];

        const totalProduction = rows.reduce((sum, row) => {
            return sum + toNumber(row.sanLuong ?? row.sanLuongTong ?? row.tongSanLuong ?? row.dungTich, 0);
        }, 0);

        const activeFarms = rows.filter((row) => {
            const status = String(row.trangThaiKiemDuyet ?? row.trangThai ?? '').toLowerCase();
            return status.includes('dang') || status.includes('hoat') || status.includes('duyet');
        }).length;

        const dashboard = {
            summary: {
                tongNguoiDung: toNumber(userCount.recordset?.[0]?.total, rows.length || 0),
                tongVuon: toNumber(farmCount.recordset?.[0]?.total, rows.length || buildDefaultFarmList().length),
                dangKhaiThac: activeFarms || Math.max(1, Math.round((rows.length || buildDefaultFarmList().length) * 0.6)),
                sanLuongTong: totalProduction || 420,
            },
            locationCount: rows.length || buildDefaultFarmList().length,
            locations: rows.length > 0 ? rows.map((item) => ({
                ...item,
                trangThai: normalizeStatus(item.trangThaiKiemDuyet),
            })) : buildDefaultFarmList(),
            alerts: [
                { title: 'Cảnh báo thời tiết', detail: 'Mưa lớn dự báo trong 48h tới' },
                { title: 'Lịch chăm sóc', detail: `${Math.max(1, activeFarms || 3)} vườn cần kiểm tra thùng ong` },
            ],
        };

        res.json({ success: true, data: dashboard });
    } catch (err) {
        console.error('Lỗi dashboard mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getHarvestMonitoring = async (req, res) => {
    try {
        const { poolPromise } = require('../config/db');
        const pool = await poolPromise;
        const result = await safeQuery(pool, `
            SELECT TOP 10 *
            FROM diaDiemVuon
            ORDER BY maDiaDiem DESC
        `);

        const data = (result.recordset || []).length > 0
            ? result.recordset.map((item) => ({
                tenVuon: item.tenDiaDiem || 'Vườn Ong',
                khachHang: item.tenChuDat || 'Người nuôi ong Demo',
                loaiMat: item.loaiMat || 'Mật nhãn',
                sanLuong: `${toNumber(item.sanLuong ?? item.sanLuongTong ?? item.tongSanLuong ?? 240, 240)} kg`,
                trangThai: normalizeStatus(item.trangThaiKiemDuyet),
                capNhat: '2 phút trước',
                diemDinh: `${item.diaChiChiTiet || 'Bãi A'} • Dữ liệu đồng bộ từ backend`,
            }))
            : buildDefaultFarmList().map((item) => ({
                tenVuon: item.tenDiaDiem,
                khachHang: item.tenChuDat,
                loaiMat: item.loaiMat,
                sanLuong: `${item.sanLuong} kg`,
                trangThai: item.trangThai,
                capNhat: '2 phút trước',
                diemDinh: `${item.diaChiChiTiet} • Dữ liệu đồng bộ từ backend`,
            }));

        res.json({ success: true, data });
    } catch (err) {
        console.error('Lỗi harvest monitoring mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getContracts = async (req, res) => {
    try {
        const stored = await beekeepingRepository.getContracts();
        const source = stored ?? contractRecords;
        const transformed = source.map((item) => ({
            contractId: item.contractId || item.maHopDong,
            id: item.contractId || item.maHopDong,
            maHopDong: item.maHopDong || item.contractId,
            tenHopDong: item.tenHopDong,
            giaThue: item.giaThue,
            trangThai: item.trangThai,
            filePdf: item.filePdf,
            doiTac: item.doiTac,
            ngayKy: item.ngayKy,
        }));

        res.json({ success: true, data: transformed });
    } catch (err) {
        console.error('Lỗi contracts mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getContractDetail = async (req, res) => {
    try {
        const contractId = String(req.params.id || '').trim();
        const stored = await beekeepingRepository.getContract(contractId);
        const raw = stored || contractRecords.find((item) => String(item.contractId ?? item.maHopDong) === contractId);
        const detail = raw ? buildContractDetail(contractId, raw) : buildContractDetail(contractId, {
            contractId,
            tenHopDong: 'Hợp đồng thuê vườn',
            doiTac: 'Chủ đất Demo',
            giaThue: '3.500.000 đ / tháng',
            thoiHan: '6 tháng',
            trangThai: 'ChoKhachKy',
            filePdf: `/api/hop-dong/pdf/${contractId}`,
        });

        return res.json({ success: true, data: detail });
    } catch (error) {
        console.error('Lỗi lấy chi tiết hợp đồng:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.signContract = async (req, res) => {
    try {
        const payload = req.body || {};
        const contractId = String(payload.contractId ?? '').trim();
        const otp = String(payload.otp ?? '').trim();

        if (!contractId) {
            return res.status(400).json({ success: false, message: 'Không tìm thấy hợp đồng cần ký.' });
        }

        if (!otp) return res.status(400).json({ success: false, message: 'Vui lòng nhập mã OTP để xác nhận ký số.' });
        const storedResult = await beekeepingRepository.signContract(contractId);
        if (storedResult) {
            const target = storedResult.recordsets?.[1]?.[0] || storedResult.recordsets?.[0]?.[0];
            if (!target || target.trangThai !== 'DaKy') {
                return res.status(409).json({ success: false, message: 'Hợp đồng không ở trạng thái chờ ký.' });
            }
            return res.json({ success: true, message: 'Hợp đồng đã được ký xác nhận thành công.', data: buildContractDetail(contractId, target) });
        }

        const signed = signContractRecord(contractRecords, contractId, otp);
        const target = signed.find((item) => String(item.contractId ?? item.maHopDong ?? item.id) === contractId);

        if (!target) {
            return res.status(404).json({ success: false, message: 'Hợp đồng không tồn tại trong hệ thống.' });
        }

        const index = contractRecords.findIndex((item) => String(item.contractId ?? item.maHopDong ?? item.id) === contractId);
        if (index >= 0) {
            contractRecords[index] = target;
        }

        return res.json({
            success: true,
            message: 'Hợp đồng đã được ký xác nhận thành công.',
            data: target,
        });
    } catch (error) {
        console.error('Lỗi ký hợp đồng:', error);
        return res.status(400).json({ success: false, message: error.message || 'Ký hợp đồng thất bại.' });
    }
};

exports.getMapData = async (req, res) => {
    try {
        const { poolPromise } = require('../config/db');
        const pool = await poolPromise;
        const result = await safeQuery(pool, `SELECT TOP 20 maDiaDiem, tenDiaDiem, diaChiChiTiet, viDo, kinhDo FROM diaDiemVuon ORDER BY maDiaDiem DESC`);
        const data = (result.recordset || []).length > 0 ? result.recordset : buildDefaultFarmList();

        res.json({ success: true, data });
    } catch (err) {
        console.error('Lỗi map data mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

exports.getUserProfile = async (req, res) => {
    try {
        const { userId } = req.query;
        const { poolPromise } = require('../config/db');
        const pool = await poolPromise;
        const result = await safeQuery(pool, `SELECT maNguoiDung, hoTen, email, vaiTro, soDienThoai, trangThaiTaiKhoan FROM nguoiDung WHERE maNguoiDung = ${userId || 3}`);

        res.json({
            success: true,
            data: result.recordset && result.recordset.length > 0
                ? result.recordset[0]
                : { maNguoiDung: 3, hoTen: 'Người nuôi ong Demo', vaiTro: 'nguoiNuoiOng' },
        });
    } catch (err) {
        console.error('Lỗi profile mobile: ', err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};
