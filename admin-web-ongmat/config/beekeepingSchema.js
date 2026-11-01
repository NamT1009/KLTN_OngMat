const { poolPromise } = require('./db');

async function ensureBeekeepingSchema() {
    const pool = await poolPromise;
    if (!pool) return false;

    await pool.request().batch(`
        IF OBJECT_ID(N'dbo.danOng', N'U') IS NULL
        CREATE TABLE dbo.danOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maDanOng NVARCHAR(50) NOT NULL UNIQUE,
            maNguoiDung INT NULL,
            tenDanOng NVARCHAR(200) NOT NULL,
            viTri NVARCHAR(300) NULL,
            viDo DECIMAL(10,7) NULL,
            kinhDo DECIMAL(10,7) NULL,
            soThung INT NOT NULL DEFAULT 0,
            tinhTrang NVARCHAR(200) NULL,
            cayTruoc NVARCHAR(200) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            ngayCapNhat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.thungOng', N'U') IS NULL
        CREATE TABLE dbo.thungOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maThungOng NVARCHAR(50) NOT NULL UNIQUE,
            maDanOng NVARCHAR(50) NOT NULL,
            soThuTu INT NOT NULL,
            tinhTrang NVARCHAR(200) NULL,
            ghiChu NVARCHAR(500) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.lichChamSocOng', N'U') IS NULL
        CREATE TABLE dbo.lichChamSocOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maLich NVARCHAR(50) NOT NULL UNIQUE,
            maDanOng NVARCHAR(50) NULL,
            tenCongViec NVARCHAR(300) NOT NULL,
            ngay DATE NOT NULL,
            gio TIME(0) NULL,
            trangThai NVARCHAR(100) NOT NULL,
            diaDiem NVARCHAR(300) NULL,
            ghiChu NVARCHAR(500) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.lichDiChuyenOng', N'U') IS NULL
        CREATE TABLE dbo.lichDiChuyenOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maDiChuyen NVARCHAR(50) NOT NULL UNIQUE,
            maDanOng NVARCHAR(50) NULL,
            bienSo NVARCHAR(50) NULL,
            viTriDi NVARCHAR(300) NOT NULL,
            viTriDen NVARCHAR(300) NOT NULL,
            ngay DATE NOT NULL,
            trangThai NVARCHAR(100) NOT NULL,
            ghiChu NVARCHAR(500) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.sanLuongMatOng', N'U') IS NULL
        CREATE TABLE dbo.sanLuongMatOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maSanLuong NVARCHAR(50) NOT NULL UNIQUE,
            maDanOng NVARCHAR(50) NULL,
            sanLuong DECIMAL(12,2) NOT NULL,
            donVi NVARCHAR(20) NOT NULL,
            ngay DATE NOT NULL,
            loaiMat NVARCHAR(200) NOT NULL,
            ghiChu NVARCHAR(500) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.thongBaoNuoiOng', N'U') IS NULL
        CREATE TABLE dbo.thongBaoNuoiOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            tieuDe NVARCHAR(300) NOT NULL,
            noiDung NVARCHAR(1000) NOT NULL,
            mucDo NVARCHAR(50) NOT NULL,
            thoiGian DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            daDoc BIT NOT NULL DEFAULT 0
        );
        IF OBJECT_ID(N'dbo.lichSuGPSDanOng', N'U') IS NULL
        CREATE TABLE dbo.lichSuGPSDanOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maDanOng NVARCHAR(50) NOT NULL,
            viDo DECIMAL(10,7) NOT NULL,
            kinhDo DECIMAL(10,7) NOT NULL,
            viTri NVARCHAR(300) NULL,
            thoiGian DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.truyXuatKhaiThacOng', N'U') IS NULL
        CREATE TABLE dbo.truyXuatKhaiThacOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maDanOng NVARCHAR(50) NULL,
            maNguoiDung INT NULL,
            tenDiaDiem NVARCHAR(300) NOT NULL,
            loaiOng NVARCHAR(200) NOT NULL,
            sanPham NVARCHAR(500) NOT NULL,
            sanLuongDuKien DECIMAL(12,2) NULL,
            ghiChu NVARCHAR(1000) NULL,
            trangThai NVARCHAR(100) NOT NULL,
            createdAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.yeuCauThueOng', N'U') IS NULL
        CREATE TABLE dbo.yeuCauThueOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maYeuCau NVARCHAR(50) NOT NULL UNIQUE,
            maDiaDiem INT NULL,
            maNguoiNuoiOng INT NULL,
            tenDiaDiem NVARCHAR(300) NOT NULL,
            thoiGianBatDau NVARCHAR(100) NOT NULL,
            thoiGianKetThuc NVARCHAR(100) NULL,
            soDanOng INT NOT NULL DEFAULT 0,
            giaThueDuKien DECIMAL(14,2) NULL,
            ghiChu NVARCHAR(1000) NULL,
            trangThai NVARCHAR(50) NOT NULL DEFAULT 'ChoDuyet',
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            ngayCapNhat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF OBJECT_ID(N'dbo.hopDongThueOng', N'U') IS NULL
        CREATE TABLE dbo.hopDongThueOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maHopDong NVARCHAR(50) NOT NULL UNIQUE,
            maYeuCau NVARCHAR(50) NOT NULL,
            maDiaDiem INT NULL,
            maNguoiNuoiOng INT NULL,
            tenHopDong NVARCHAR(300) NOT NULL,
            doiTac NVARCHAR(300) NULL,
            giaThue DECIMAL(14,2) NULL,
            thoiHan NVARCHAR(100) NULL,
            quyDinhBoiThuong NVARCHAR(1000) NULL,
            trangThai NVARCHAR(50) NOT NULL DEFAULT 'ChoKhachKy',
            otpVerified BIT NOT NULL DEFAULT 0,
            ngayKy DATETIME2 NULL,
            filePdf NVARCHAR(500) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
    `);

    // Bổ sung cột phục vụ phân quyền theo chủ sở hữu và liên kết địa điểm của chủ đất.
    // ALTER phải chạy ở batch riêng trước khi các câu lệnh khác tham chiếu cột mới.
    await pool.request().batch(`
        IF COL_LENGTH('dbo.danOng', 'maDiaDiem') IS NULL ALTER TABLE dbo.danOng ADD maDiaDiem INT NULL;
        IF COL_LENGTH('dbo.lichChamSocOng', 'maNguoiDung') IS NULL ALTER TABLE dbo.lichChamSocOng ADD maNguoiDung INT NULL;
        IF COL_LENGTH('dbo.lichDiChuyenOng', 'maNguoiDung') IS NULL ALTER TABLE dbo.lichDiChuyenOng ADD maNguoiDung INT NULL;
        IF COL_LENGTH('dbo.lichDiChuyenOng', 'maDiaDiemDen') IS NULL ALTER TABLE dbo.lichDiChuyenOng ADD maDiaDiemDen INT NULL;
        IF COL_LENGTH('dbo.sanLuongMatOng', 'maNguoiDung') IS NULL ALTER TABLE dbo.sanLuongMatOng ADD maNguoiDung INT NULL;
        IF COL_LENGTH('dbo.sanLuongMatOng', 'maDiaDiem') IS NULL ALTER TABLE dbo.sanLuongMatOng ADD maDiaDiem INT NULL;
        IF COL_LENGTH('dbo.sanLuongMatOng', 'maTruyXuat') IS NULL ALTER TABLE dbo.sanLuongMatOng ADD maTruyXuat INT NULL;
        IF COL_LENGTH('dbo.thongBaoNuoiOng', 'maNguoiDung') IS NULL ALTER TABLE dbo.thongBaoNuoiOng ADD maNguoiDung INT NULL;
        IF COL_LENGTH('dbo.yeuCauThueOng', 'lyDoTuChoi') IS NULL ALTER TABLE dbo.yeuCauThueOng ADD lyDoTuChoi NVARCHAR(500) NULL;
        IF COL_LENGTH('dbo.hopDongThueOng', 'maChuDat') IS NULL ALTER TABLE dbo.hopDongThueOng ADD maChuDat INT NULL;
        IF COL_LENGTH('dbo.hopDongThueOng', 'ngayHoanThanh') IS NULL ALTER TABLE dbo.hopDongThueOng ADD ngayHoanThanh DATETIME2 NULL;
        IF COL_LENGTH('dbo.truyXuatKhaiThacOng', 'maDiaDiem') IS NULL ALTER TABLE dbo.truyXuatKhaiThacOng ADD maDiaDiem INT NULL;
        IF COL_LENGTH('dbo.lichChamSocOng', 'daNhacNho') IS NULL ALTER TABLE dbo.lichChamSocOng ADD daNhacNho BIT NOT NULL CONSTRAINT DF_lichChamSocOng_daNhacNho DEFAULT 0;
        IF COL_LENGTH('dbo.lichDiChuyenOng', 'daNhacNho') IS NULL ALTER TABLE dbo.lichDiChuyenOng ADD daNhacNho BIT NOT NULL CONSTRAINT DF_lichDiChuyenOng_daNhacNho DEFAULT 0;
        IF COL_LENGTH('dbo.nguoiDung', 'ngayHoatDongCuoi') IS NULL ALTER TABLE dbo.nguoiDung ADD ngayHoatDongCuoi DATETIME2 NULL;
        IF COL_LENGTH('dbo.nguoiDung', 'googleId') IS NULL ALTER TABLE dbo.nguoiDung ADD googleId NVARCHAR(150) NULL;
        IF COL_LENGTH('dbo.nguoiDung', 'avatarUrl') IS NULL ALTER TABLE dbo.nguoiDung ADD avatarUrl NVARCHAR(500) NULL;
        IF COL_LENGTH('dbo.diaDiemVuon', 'loaiHoa') IS NULL ALTER TABLE dbo.diaDiemVuon ADD loaiHoa NVARCHAR(200) NULL;
        IF COL_LENGTH('dbo.diaDiemVuon', 'loaiOngPhuHop') IS NULL ALTER TABLE dbo.diaDiemVuon ADD loaiOngPhuHop NVARCHAR(200) NULL;
        IF COL_LENGTH('dbo.diaDiemVuon', 'giaThueThang') IS NULL ALTER TABLE dbo.diaDiemVuon ADD giaThueThang DECIMAL(14,2) NULL;
        IF COL_LENGTH('dbo.diaDiemVuon', 'khiHau') IS NULL ALTER TABLE dbo.diaDiemVuon ADD khiHau NVARCHAR(200) NULL;

        IF OBJECT_ID(N'dbo.danhGiaThueOng', N'U') IS NULL
        CREATE TABLE dbo.danhGiaThueOng (
            id INT IDENTITY(1,1) PRIMARY KEY,
            maHopDong NVARCHAR(50) NOT NULL,
            maDiaDiem INT NULL,
            maNguoiDanhGia INT NOT NULL,
            vaiTroDanhGia NVARCHAR(50) NOT NULL,
            maNguoiDuocDanhGia INT NOT NULL,
            soSao INT NOT NULL,
            tieuChi1 INT NULL,
            tieuChi2 INT NULL,
            nhanXet NVARCHAR(1000) NULL,
            phanHoi NVARCHAR(1000) NULL,
            ngayTao DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            ngayCapNhat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_danhGia_hopDong_nguoiDanhGia')
            CREATE UNIQUE INDEX UQ_danhGia_hopDong_nguoiDanhGia ON dbo.danhGiaThueOng (maHopDong, maNguoiDanhGia);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_danhGia_maDiaDiem')
            CREATE INDEX IX_danhGia_maDiaDiem ON dbo.danhGiaThueOng (maDiaDiem);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_danhGia_maNguoiDuocDanhGia')
            CREATE INDEX IX_danhGia_maNguoiDuocDanhGia ON dbo.danhGiaThueOng (maNguoiDuocDanhGia);

        IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_hopDongThueOng_trangThai')
        BEGIN
            ALTER TABLE dbo.hopDongThueOng DROP CONSTRAINT CK_hopDongThueOng_trangThai;
            ALTER TABLE dbo.hopDongThueOng ADD CONSTRAINT CK_hopDongThueOng_trangThai CHECK (trangThai IN ('ChoKhachKy', 'DaKy', 'HoanThanh', 'DaHuy'));
        END;
    `);

    // Dữ liệu cũ chưa có chủ sở hữu được gán cho tài khoản người nuôi ong demo.
    await pool.request().batch(`
        DECLARE @demo INT = (SELECT TOP 1 maNguoiDung FROM dbo.nguoiDung WHERE email = 'nuoiong@ongmat.com');
        IF @demo IS NOT NULL
        BEGIN
            UPDATE dbo.danOng SET maNguoiDung = @demo WHERE maNguoiDung IS NULL OR maNguoiDung = 0;
            UPDATE dbo.lichChamSocOng SET maNguoiDung = @demo WHERE maNguoiDung IS NULL;
            UPDATE dbo.lichDiChuyenOng SET maNguoiDung = @demo WHERE maNguoiDung IS NULL;
            UPDATE dbo.sanLuongMatOng SET maNguoiDung = @demo WHERE maNguoiDung IS NULL;
            UPDATE dbo.thongBaoNuoiOng SET maNguoiDung = @demo WHERE maNguoiDung IS NULL;
            UPDATE dbo.yeuCauThueOng SET maNguoiNuoiOng = @demo WHERE maNguoiNuoiOng IS NULL OR maNguoiNuoiOng = 0;
            UPDATE dbo.truyXuatKhaiThacOng SET maNguoiDung = @demo WHERE maNguoiDung IS NULL OR maNguoiDung = 0;
        END;
        UPDATE h SET h.maChuDat = d.maChuDat
        FROM dbo.hopDongThueOng h JOIN dbo.diaDiemVuon d ON d.maDiaDiem = h.maDiaDiem
        WHERE h.maChuDat IS NULL;

        UPDATE dbo.diaDiemVuon
        SET loaiHoa = CASE 
                WHEN tenDiaDiem LIKE N'%Mận%' OR diaChiChiTiet LIKE N'%Sơn La%' OR diaChiChiTiet LIKE N'%Mộc Châu%' THEN N'Hoa mận, Hoa mơ'
                WHEN tenDiaDiem LIKE N'%Bạc Hà%' OR diaChiChiTiet LIKE N'%Hà Giang%' OR diaChiChiTiet LIKE N'%Mèo Vạc%' THEN N'Hoa bạc hà đá'
                WHEN tenDiaDiem LIKE N'%Cà Phê%' OR diaChiChiTiet LIKE N'%Gia Lai%' OR diaChiChiTiet LIKE N'%Đắk Lắk%' THEN N'Hoa cà phê'
                WHEN tenDiaDiem LIKE N'%Nhãn%' OR diaChiChiTiet LIKE N'%Hưng Yên%' THEN N'Hoa nhãn lồng'
                WHEN tenDiaDiem LIKE N'%Vải%' OR diaChiChiTiet LIKE N'%Bắc Giang%' THEN N'Hoa vải thiều'
                WHEN tenDiaDiem LIKE N'%Tràm%' OR diaChiChiTiet LIKE N'%U Minh%' OR diaChiChiTiet LIKE N'%Cà Mau%' THEN N'Hoa tràm'
                ELSE N'Hoa tự nhiên, đa hoa'
            END,
            loaiOngPhuHop = CASE
                WHEN tenDiaDiem LIKE N'%Mận%' OR diaChiChiTiet LIKE N'%Mộc Châu%' THEN N'Ong nội (Apis cerana)'
                WHEN tenDiaDiem LIKE N'%Bạc Hà%' OR diaChiChiTiet LIKE N'%Mèo Vạc%' THEN N'Ong nội (Apis cerana)'
                WHEN tenDiaDiem LIKE N'%Cà Phê%' OR diaChiChiTiet LIKE N'%Đắk Lắk%' THEN N'Ong Ý (Apis mellifera)'
                WHEN tenDiaDiem LIKE N'%Nhãn%' OR diaChiChiTiet LIKE N'%Hưng Yên%' THEN N'Ong Ý & Ong nội'
                ELSE N'Mọi loài ong'
            END,
            khiHau = CASE
                WHEN diaChiChiTiet LIKE N'%Sơn La%' OR diaChiChiTiet LIKE N'%Mộc Châu%' THEN N'Ôn đới mát mẻ (18-24°C)'
                WHEN diaChiChiTiet LIKE N'%Hà Giang%' OR diaChiChiTiet LIKE N'%Mèo Vạc%' THEN N'Cao nguyên đá lạnh, khô ráo'
                WHEN diaChiChiTiet LIKE N'%Đắk Lắk%' OR diaChiChiTiet LIKE N'%Gia Lai%' THEN N'Cao nguyên ôn hòa (20-28°C)'
                WHEN diaChiChiTiet LIKE N'%Cà Mau%' OR diaChiChiTiet LIKE N'%Bến Tre%' THEN N'Nhiệt đới ẩm gió mùa (27-32°C)'
                ELSE N'Nhiệt đới gió mùa'
            END,
            giaThueThang = CASE
                WHEN giaThueThang IS NOT NULL AND giaThueThang > 0 THEN giaThueThang
                WHEN tenDiaDiem LIKE N'%Mận%' THEN 1200000
                WHEN tenDiaDiem LIKE N'%Bạc Hà%' THEN 1500000
                WHEN tenDiaDiem LIKE N'%Cà Phê%' THEN 800000
                WHEN tenDiaDiem LIKE N'%Nhãn%' THEN 1000000
                ELSE 600000
            END
        WHERE loaiHoa IS NULL OR khiHau IS NULL;

        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_danOng_maNguoiDung')
            CREATE INDEX IX_danOng_maNguoiDung ON dbo.danOng (maNguoiDung);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_danOng_maDiaDiem')
            CREATE INDEX IX_danOng_maDiaDiem ON dbo.danOng (maDiaDiem);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_lichChamSocOng_maNguoiDung')
            CREATE INDEX IX_lichChamSocOng_maNguoiDung ON dbo.lichChamSocOng (maNguoiDung, ngay);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_lichDiChuyenOng_maNguoiDung')
            CREATE INDEX IX_lichDiChuyenOng_maNguoiDung ON dbo.lichDiChuyenOng (maNguoiDung, ngay);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_sanLuongMatOng_maNguoiDung')
            CREATE INDEX IX_sanLuongMatOng_maNguoiDung ON dbo.sanLuongMatOng (maNguoiDung, ngay);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_thongBaoNuoiOng_maNguoiDung')
            CREATE INDEX IX_thongBaoNuoiOng_maNguoiDung ON dbo.thongBaoNuoiOng (maNguoiDung, thoiGian);
        IF NOT EXISTS (SELECT 1 FROM dbo.loaiHoa WHERE tenLoaiHoa LIKE N'%Mận%')
            INSERT INTO dbo.loaiHoa (tenLoaiHoa, moTaMatDo) VALUES (N'Hoa Mận, Hoa Mơ', N'Đặc sản Mộc Châu, Sơn La vào tháng 1-2, mật thơm mát màu vàng nhạt.');
        IF NOT EXISTS (SELECT 1 FROM dbo.loaiHoa WHERE tenLoaiHoa LIKE N'%Bạc Hà%')
            INSERT INTO dbo.loaiHoa (tenLoaiHoa, moTaMatDo) VALUES (N'Hoa Bạc Hà Đá', N'Mọc tự nhiên trên cao nguyên đá Hà Giang (tháng 9-12), mật đặc biệt giá trị cao.');
        IF NOT EXISTS (SELECT 1 FROM dbo.loaiHoa WHERE tenLoaiHoa LIKE N'%Rừng%')
            INSERT INTO dbo.loaiHoa (tenLoaiHoa, moTaMatDo) VALUES (N'Hoa Rừng Tự Nhiên', N'Nguồn hoa đa dạng phong phú quanh năm tại các bìa rừng và vùng đồi núi.');

        IF NOT EXISTS (SELECT 1 FROM dbo.loaiOng WHERE tenLoaiOng LIKE N'%dú%')
            INSERT INTO dbo.loaiOng (tenLoaiOng, nguonGocVaTapTinh, dacDiemSinhHoc, nangSuatTrungBinh, sanPhamChuLuc, khiHauThichHop)
            VALUES (N'Ong dú (Stingless bee)', N'Ong không ngòi đốt, tính hiền, làm tổ trong bọng cây, hốc tường.', N'Kích thước nhỏ bé, tính thích nghi cao, mật có tính dược liệu rất cao.', N'1 - 3 kg/đàn/năm', N'Mật ong dú dược liệu, Keo ong nguyên chất', N'Nhiệt đới ẩm');
        IF NOT EXISTS (SELECT 1 FROM dbo.loaiOng WHERE tenLoaiOng LIKE N'%Mọi loài%')
            INSERT INTO dbo.loaiOng (tenLoaiOng, nguonGocVaTapTinh, dacDiemSinhHoc, nangSuatTrungBinh, sanPhamChuLuc, khiHauThichHop)
            VALUES (N'Mọi loài ong', N'Địa điểm phù hợp với nhiều loại ong khác nhau.', N'Đa dạng nguồn mật và phấn hoa.', N'Đa dạng', N'Mật ong, Phấn hoa', N'Mọi vùng khí hậu');
    `);

    return true;
}

module.exports = { ensureBeekeepingSchema };
