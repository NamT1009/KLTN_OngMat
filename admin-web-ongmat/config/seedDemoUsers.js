const { sql, poolPromise } = require('./db');

const demoUsers = [
    {
        hoTen: 'Chủ đất Demo',
        email: 'chudat@ongmat.com',
        soDienThoai: '0901000001',
        matKhauHash: 'nam123',
        vaiTro: 'chuDat',
        trangThaiTaiKhoan: 'HoatDong'
    },
    {
        hoTen: 'Người nuôi ong Demo',
        email: 'nuoiong@ongmat.com',
        soDienThoai: '0901000002',
        matKhauHash: 'nuoi123',
        vaiTro: 'nguoiNuoiOng',
        trangThaiTaiKhoan: 'HoatDong'
    },
    {
        hoTen: 'Quản trị viên Demo',
        email: 'admin@ongmat.com',
        soDienThoai: '0901000003',
        matKhauHash: 'admin123',
        vaiTro: 'admin',
        trangThaiTaiKhoan: 'HoatDong'
    }
];

async function ensureDemoUsers() {
    try {
        const pool = await poolPromise;
        const existingUsers = await pool.request().query('SELECT maNguoiDung, email, soDienThoai, matKhauHash, vaiTro, trangThaiTaiKhoan, hoTen FROM nguoiDung');
        const existingMap = new Map(
            (existingUsers.recordset || []).map(user => [String(user.email || '').trim().toLowerCase(), user])
        );

        for (const user of demoUsers) {
            const key = String(user.email).trim().toLowerCase();
            const existing = existingMap.get(key);

            if (existing) {
                const needsUpdate =
                    String(existing.vaiTro || '').trim().toLowerCase() !== user.vaiTro.toLowerCase() ||
                    String(existing.matKhauHash || '').trim() !== user.matKhauHash ||
                    String(existing.trangThaiTaiKhoan || '').trim() !== user.trangThaiTaiKhoan ||
                    String(existing.hoTen || '').trim() !== user.hoTen ||
                    String(existing.soDienThoai || '').trim() !== user.soDienThoai;

                if (needsUpdate) {
                    await pool.request()
                        .input('hoTen', sql.NVarChar, user.hoTen)
                        .input('email', sql.VarChar, user.email)
                        .input('soDienThoai', sql.VarChar, user.soDienThoai)
                        .input('matKhauHash', sql.VarChar, user.matKhauHash)
                        .input('vaiTro', sql.VarChar, user.vaiTro)
                        .input('trangThaiTaiKhoan', sql.VarChar, user.trangThaiTaiKhoan)
                        .query(`
                            UPDATE nguoiDung
                            SET hoTen = @hoTen,
                                soDienThoai = @soDienThoai,
                                matKhauHash = @matKhauHash,
                                vaiTro = @vaiTro,
                                trangThaiTaiKhoan = @trangThaiTaiKhoan
                            WHERE email = @email
                        `);

                    console.log(`✅ Đã cập nhật tài khoản demo: ${user.email} (${user.vaiTro})`);
                }

                continue;
            }

            await pool.request()
                .input('hoTen', sql.NVarChar, user.hoTen)
                .input('email', sql.VarChar, user.email)
                .input('soDienThoai', sql.VarChar, user.soDienThoai)
                .input('matKhauHash', sql.VarChar, user.matKhauHash)
                .input('vaiTro', sql.VarChar, user.vaiTro)
                .input('trangThaiTaiKhoan', sql.VarChar, user.trangThaiTaiKhoan)
                .query(`
                    INSERT INTO nguoiDung (hoTen, email, soDienThoai, matKhauHash, vaiTro, trangThaiTaiKhoan, ngayTao)
                    VALUES (@hoTen, @email, @soDienThoai, @matKhauHash, @vaiTro, @trangThaiTaiKhoan, GETDATE())
                `);

            existingMap.set(key, user);
            console.log(`✅ Đã tạo tài khoản demo: ${user.email} (${user.vaiTro})`);
        }
    } catch (err) {
        console.error('❌ Không thể tạo/cập nhật tài khoản demo:', err.message);
    }
}

module.exports = {
    ensureDemoUsers,
    demoUsers,
};
