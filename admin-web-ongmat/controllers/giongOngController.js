const { sql, poolPromise } = require('../config/db');

exports.getDanhSachGiongOng = async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query('SELECT * FROM loaiOng ORDER BY maLoaiOng DESC');
        
        res.render('giong-ong', {
            danhSachGiongOng: result.recordset,
            path: '/giong-ong'
        });
    } catch (err) {
        console.error("Lỗi lấy danh sách giống ong: ", err);
        res.status(500).send("Lỗi máy chủ");
    }
};

exports.themGiongOng = async (req, res) => {
    try {
        const { tenLoaiOng, nguonGocVaTapTinh, dacDiemSinhHoc, nangSuatTrungBinh, sanPhamChuLuc, khiHauThichHop } = req.body;
        const pool = await poolPromise;
        
        await pool.request()
            .input('tenLoaiOng', sql.NVarChar, tenLoaiOng)
            .input('nguonGocVaTapTinh', sql.NVarChar, nguonGocVaTapTinh)
            .input('dacDiemSinhHoc', sql.NVarChar, dacDiemSinhHoc)
            .input('nangSuatTrungBinh', sql.NVarChar, nangSuatTrungBinh)
            .input('sanPhamChuLuc', sql.NVarChar, sanPhamChuLuc)
            .input('khiHauThichHop', sql.NVarChar, khiHauThichHop)
            .query(`
                INSERT INTO loaiOng (tenLoaiOng, nguonGocVaTapTinh, dacDiemSinhHoc, nangSuatTrungBinh, sanPhamChuLuc, khiHauThichHop) 
                VALUES (@tenLoaiOng, @nguonGocVaTapTinh, @dacDiemSinhHoc, @nangSuatTrungBinh, @sanPhamChuLuc, @khiHauThichHop)
            `);

        res.json({ success: true, message: 'Thêm giống ong thành công!' });
    } catch (err) {
        console.error("Lỗi thêm giống ong: ", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ khi thêm dữ liệu!' });
    }
};
// Sửa thông tin giống ong
exports.suaGiongOng = async (req, res) => {
    try {
        const { maLoaiOng, tenLoaiOng, nguonGocVaTapTinh, dacDiemSinhHoc, nangSuatTrungBinh, sanPhamChuLuc, khiHauThichHop } = req.body;
        const pool = await poolPromise;
        
        await pool.request()
            .input('maLoaiOng', sql.Int, maLoaiOng)
            .input('tenLoaiOng', sql.NVarChar, tenLoaiOng)
            .input('nguonGocVaTapTinh', sql.NVarChar, nguonGocVaTapTinh)
            .input('dacDiemSinhHoc', sql.NVarChar, dacDiemSinhHoc)
            .input('nangSuatTrungBinh', sql.NVarChar, nangSuatTrungBinh)
            .input('sanPhamChuLuc', sql.NVarChar, sanPhamChuLuc)
            .input('khiHauThichHop', sql.NVarChar, khiHauThichHop)
            .query(`
                UPDATE loaiOng 
                SET tenLoaiOng = @tenLoaiOng, 
                    nguonGocVaTapTinh = @nguonGocVaTapTinh, 
                    dacDiemSinhHoc = @dacDiemSinhHoc, 
                    nangSuatTrungBinh = @nangSuatTrungBinh, 
                    sanPhamChuLuc = @sanPhamChuLuc, 
                    khiHauThichHop = @khiHauThichHop
                WHERE maLoaiOng = @maLoaiOng
            `);

        res.json({ success: true, message: 'Cập nhật giống ong thành công!' });
    } catch (err) {
        console.error("Lỗi sửa giống ong: ", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ khi cập nhật dữ liệu!' });
    }
};

// Xóa giống ong
exports.xoaGiongOng = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;
        
        await pool.request()
            .input('maLoaiOng', sql.Int, id)
            .query('DELETE FROM loaiOng WHERE maLoaiOng = @maLoaiOng');

        res.json({ success: true, message: 'Xóa giống ong thành công!' });
    } catch (err) {
        console.error("Lỗi xóa giống ong: ", err);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ khi xóa dữ liệu!' });
    }
};
