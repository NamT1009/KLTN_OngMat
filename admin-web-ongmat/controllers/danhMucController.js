const { poolPromise, sql } = require('../config/db');

// Lấy danh sách loài hoa
exports.getDanhMucHoa = async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query('SELECT * FROM loaiHoa ORDER BY maLoaiHoa DESC');
        
        // Render ra file view 'danh-muc-hoa'
        res.render('danh-muc-hoa', { 
            danhSachHoa: result.recordset, 
            path: '/danh-muc-hoa' 
        });
    } catch (err) {
        console.error("Lỗi lấy danh mục hoa: ", err);
        res.status(500).send("Lỗi hệ thống!");
    }
};

// Xử lý thêm loài hoa mới
exports.themLoaiHoa = async (req, res) => {
    try {
        const { tenLoaiHoa, moTaMatDo } = req.body;
        const pool = await poolPromise;
        const sqlRequest = pool.request();
        
        sqlRequest.input('tenLoaiHoa', sql.NVarChar, tenLoaiHoa);
        sqlRequest.input('moTaMatDo', sql.NVarChar, moTaMatDo);
        
        await sqlRequest.query(`
            INSERT INTO loaiHoa (tenLoaiHoa, moTaMatDo) 
            VALUES (@tenLoaiHoa, @moTaMatDo)
        `);
        
        // Thêm xong thì tự động load lại trang danh mục
        res.redirect('/danh-muc-hoa');
    } catch (err) {
        console.error(err);
        res.status(500).send("Lỗi khi thêm hoa mới");
    }
};
// Xóa loài hoa
exports.xoaLoaiHoa = async (req, res) => {
    try {
        const { id } = req.body;
        const pool = await poolPromise;
        await pool.request()
            .input('maLoaiHoa', sql.Int, id)
            .query('DELETE FROM loaiHoa WHERE maLoaiHoa = @maLoaiHoa');
            
        res.json({ success: true, message: 'Đã xóa loài hoa thành công!' });
    } catch (err) {
        console.error(err);
        // Nếu hoa đang được sử dụng ở bảng muaVuHoa, SQL sẽ báo lỗi khóa ngoại
        res.status(500).json({ success: false, message: 'Không thể xóa! Dữ liệu này có thể đang được sử dụng.' });
    }
};

// Sửa loài hoa
exports.suaLoaiHoa = async (req, res) => {
    try {
        const { id, tenLoaiHoa, moTaMatDo } = req.body;
        const pool = await poolPromise;
        const sqlRequest = pool.request();
        
        sqlRequest.input('maLoaiHoa', sql.Int, id);
        sqlRequest.input('tenLoaiHoa', sql.NVarChar, tenLoaiHoa);
        sqlRequest.input('moTaMatDo', sql.NVarChar, moTaMatDo);
        
        await sqlRequest.query(`
            UPDATE loaiHoa 
            SET tenLoaiHoa = @tenLoaiHoa, moTaMatDo = @moTaMatDo 
            WHERE maLoaiHoa = @maLoaiHoa
        `);
        
        res.json({ success: true, message: 'Cập nhật thông tin thành công!' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: 'Lỗi khi cập nhật dữ liệu' });
    }
};