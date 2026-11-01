const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildRentalRequestRecord,
  signContractRecord,
  buildBeekeepingDashboard,
  addCareLog,
  addHiveMove,
  addProductionUpdate,
} = require('../controllers/mobileApiController');

test('mobile rental request keeps the required beekeeping fields and status', () => {
  const record = buildRentalRequestRecord({
    tenDiaDiem: 'Vườn Nhãn 12',
    maDiaDiem: 7,
    maNguoiNuoiOng: 15,
    soDanOng: 25,
    thoiGianBatDau: '2026-10-15',
    thoiGianKetThuc: '2027-03-15',
    giaThueDuKien: 3500000,
    ghiChu: 'Yêu cầu chốt giá theo mùa hoa nhãn',
  });

  assert.equal(record.tenDiaDiem, 'Vườn Nhãn 12');
  assert.equal(record.maDiaDiem, 7);
  assert.equal(record.soDanOng, 25);
  assert.equal(record.giaThueDuKien, 3500000);
  assert.equal(record.trangThai, 'ChoDuyet');
});

test('signing the contract moves it to DaKy and validates the OTP gate', () => {
  const records = [
    {
      contractId: 'HD-1001',
      tenHopDong: 'Hợp đồng thuê vườn',
      giaThue: '3.500.000 đ / tháng',
      trangThai: 'ChoKhachKy',
      filePdf: '/api/hop-dong/pdf/HD-1001',
    },
  ];

  const updated = signContractRecord(records, 'HD-1001', '123456');
  assert.equal(updated[0].trangThai, 'DaKy');
  assert.equal(updated[0].otpVerified, true);
  assert.equal(updated[0].filePdf, '/api/hop-dong/pdf/HD-1001');

  assert.throws(() => {
    signContractRecord(records, 'HD-1001', '');
  }, /OTP/i);
});

test('beekeeping dashboard aggregates hive, care, movement and production data', () => {
  const dashboard = buildBeekeepingDashboard({
    hives: [
      { maDanOng: 'DN-01', tenDanOng: 'Đàn 01', viTri: 'Bãi A', tinhTrang: 'Sức khỏe ổn định' },
    ],
    care: [
      { maLich: 'LC-01', tenCongViec: 'Kiểm tra thùng ong', ngay: '2026-10-11' },
    ],
    moves: [
      { maDiChuyen: 'DC-01', viTriDen: 'Bãi C', trangThai: 'Đã di chuyển' },
    ],
    production: [
      { maSanLuong: 'SL-01', sanLuong: 180, donVi: 'kg' },
    ],
  });

  assert.equal(dashboard.summary.totalHives, 1);
  assert.equal(dashboard.summary.totalCareTasks, 1);
  assert.equal(dashboard.summary.totalMoves, 1);
  assert.equal(dashboard.summary.totalProductionKg, 180);
  assert.equal(dashboard.alerts[0].title, 'Lịch chăm sóc');
});

test('care, move and production updates are stored with valid status', () => {
  const care = addCareLog({ tenCongViec: 'Bổ sung thức ăn', ngay: '2026-10-12' });
  const move = addHiveMove({ viTriDen: 'Bãi D', trangThai: 'Đang di chuyển' });
  const production = addProductionUpdate({ sanLuong: 220, donVi: 'kg' });

  assert.equal(care.trangThai, 'Lên lịch');
  assert.equal(move.trangThai, 'Đang di chuyển');
  assert.equal(production.sanLuong, 220);
  assert.equal(production.donVi, 'kg');
});
