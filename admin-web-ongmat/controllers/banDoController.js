const { sql, poolPromise } = require('../config/db');

exports.getBanDoGIS = async (req, res) => {
    try {
        const pool = await poolPromise;
        
        // Truy vấn các địa điểm đã duyệt, có tọa độ hợp lệ
        const query = `
            SELECT 
                d.maDiaDiem, d.tenDiaDiem, d.dienTich, d.sucChuaToiDa, 
                d.diaChiChiTiet, d.hinhAnh, d.viDo, d.kinhDo, 
                n.hoTen AS tenChuDat
            FROM diaDiemVuon d
            INNER JOIN nguoiDung n ON d.maChuDat = n.maNguoiDung
            WHERE d.trangThaiKiemDuyet = 'DaDuyet' 
              AND d.viDo IS NOT NULL 
              AND d.kinhDo IS NOT NULL
        `;
        
        const result = await pool.request().query(query);
        const hivesResult = await pool.request().query(`
            SELECT d.maDanOng, d.tenDanOng, d.viTri, d.viDo, d.kinhDo,
                   d.soThung, d.tinhTrang, n.hoTen AS tenNguoiNuoi
            FROM dbo.danOng d
            LEFT JOIN nguoiDung n ON d.maNguoiDung = n.maNguoiDung
            WHERE d.viDo IS NOT NULL AND d.kinhDo IS NOT NULL
        `);
        
        res.render('ban-do', {
            // Chuyển mảng dữ liệu thành chuỗi JSON để Javascript trên EJS có thể đọc được
            danhSachDiaDiem: JSON.stringify(result.recordset),
            danhSachDanOng: JSON.stringify(hivesResult.recordset),
            path: '/ban-do'
        });
    } catch (err) {
        console.error("Lỗi tải dữ liệu bản đồ GIS: ", err);
        res.status(500).send("Lỗi máy chủ khi tải bản đồ.");
    }
};
