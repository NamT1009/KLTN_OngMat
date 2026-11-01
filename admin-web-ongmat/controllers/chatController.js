const { poolPromise, sql } = require('../config/db');
const { touchUserOnline, isUserOnline, getOnlineUserIds } = require('../services/presenceService');

// 1. Lấy danh sách các cuộc trò chuyện gần đây kèm trạng thái online thực tế
exports.getDanhSachCuocTroChuyen = async (req, res) => {
    try {
        const maNguoiDung = Number(req.user?.id ?? req.session?.user?.maNguoiDung ?? 0);
        if (!maNguoiDung) {
            return res.status(400).json({ success: false, message: 'Thiếu mã người dùng.' });
        }

        // Đánh dấu người này đang trực tuyến
        touchUserOnline(maNguoiDung);

        const pool = await poolPromise;
        if (!pool) {
            const demoUsers = [
                { maDoiTac: 1, tenDoiTac: 'Admin Hệ Thống Ong Mật', vaiTro: 'admin', soDienThoai: '0901000003', tinNhanCuoi: 'Hỗ trợ khách hàng 24/7', soTinChuaDoc: 0, isOnline: isUserOnline(1) },
                { maDoiTac: 2, tenDoiTac: 'Chủ đất Demo', vaiTro: 'chuDat', soDienThoai: '0901000001', tinNhanCuoi: 'Giá thuê vườn cuối tháng cập nhật', soTinChuaDoc: 0, isOnline: isUserOnline(2) },
                { maDoiTac: 3, tenDoiTac: 'Lê Thị Bích (Vườn Bưởi)', vaiTro: 'chuDat', soDienThoai: '0901000004', tinNhanCuoi: 'Chúng ta sẽ ký hợp đồng vào tuần tới', soTinChuaDoc: 0, isOnline: isUserOnline(3) },
                { maDoiTac: 5, tenDoiTac: 'Người nuôi ong Demo', vaiTro: 'nguoiNuoiOng', soDienThoai: '0901000002', tinNhanCuoi: 'Đã chuyển 30 đàn ong tới điểm đặt', soTinChuaDoc: 0, isOnline: isUserOnline(5) }
            ].filter(u => u.maDoiTac !== maNguoiDung);
            return res.json({ success: true, data: demoUsers });
        }

        const result = await pool.request()
            .input('myId', sql.Int, maNguoiDung)
            .query(`
                WITH danhSach AS (
                    SELECT DISTINCT
                        CASE WHEN t.maNguoiGui = @myId THEN t.maNguoiNhan ELSE t.maNguoiGui END AS maDoiTac,
                        CASE WHEN t.maNguoiGui = @myId THEN nNguoiNhan.hoTen ELSE nNguoiGui.hoTen END AS tenDoiTac,
                        CASE WHEN t.maNguoiGui = @myId THEN nNguoiNhan.vaiTro ELSE nNguoiGui.vaiTro END AS vaiTro,
                        CASE WHEN t.maNguoiGui = @myId THEN nNguoiNhan.soDienThoai ELSE nNguoiGui.soDienThoai END AS soDienThoai,
                        CASE WHEN t.maNguoiGui = @myId THEN COALESCE(nNguoiNhan.anhDaiDien, nNguoiNhan.avatarUrl) ELSE COALESCE(nNguoiGui.anhDaiDien, nNguoiGui.avatarUrl) END AS anhDaiDien,
                        ROW_NUMBER() OVER (
                            PARTITION BY CASE WHEN t.maNguoiGui = @myId THEN t.maNguoiNhan ELSE t.maNguoiGui END
                            ORDER BY t.ngayGui DESC
                        ) AS rn,
                        CASE WHEN t.daThuHoi = 1 THEN N'Tin nhắn đã được thu hồi' ELSE t.noiDung END AS tinNhanCuoi,
                        t.ngayGui AS thoiGianCuoi,
                        (SELECT COUNT(*) FROM tinNhan tt WHERE tt.maNguoiGui = CASE WHEN t.maNguoiGui = @myId THEN t.maNguoiNhan ELSE t.maNguoiGui END AND tt.maNguoiNhan = @myId AND tt.daDoc = 0) AS soTinChuaDoc
                    FROM tinNhan t
                    LEFT JOIN nguoiDung nNguoiGui ON t.maNguoiGui = nNguoiGui.maNguoiDung
                    LEFT JOIN nguoiDung nNguoiNhan ON t.maNguoiNhan = nNguoiNhan.maNguoiDung
                    WHERE t.maNguoiGui = @myId OR t.maNguoiNhan = @myId
                )
                SELECT maDoiTac, tenDoiTac, vaiTro, soDienThoai, anhDaiDien, tinNhanCuoi, thoiGianCuoi, soTinChuaDoc
                FROM danhSach
                WHERE rn = 1
                ORDER BY thoiGianCuoi DESC
            `);

        let danhSach = (result.recordset || []).map((item) => ({
            maDoiTac: item.maDoiTac,
            tenDoiTac: item.tenDoiTac || 'Người dùng',
            vaiTro: item.vaiTro || 'nguoiNuoiOng',
            soDienThoai: item.soDienThoai || '',
            anhDaiDien: item.anhDaiDien || null,
            tinNhanCuoi: item.tinNhanCuoi || 'Bắt đầu cuộc trò chuyện',
            thoiGianCuoi: item.thoiGianCuoi,
            soTinChuaDoc: Number(item.soTinChuaDoc || 0),
            isOnline: isUserOnline(item.maDoiTac) // Chỉ người nào đang hoạt động thực tế mới online
        }));

        if (danhSach.length === 0) {
            const adminList = await pool.request().input('myId', sql.Int, maNguoiDung).query(`
                SELECT maNguoiDung, hoTen, vaiTro, soDienThoai, COALESCE(anhDaiDien, avatarUrl) AS anhDaiDien
                FROM nguoiDung
                WHERE maNguoiDung <> @myId
                  AND vaiTro IN ('admin', 'chuDat', 'nguoiNuoiOng')
                ORDER BY CASE WHEN vaiTro = 'admin' THEN 0 ELSE 1 END, maNguoiDung ASC
            `);

            danhSach = (adminList.recordset || []).map((item) => ({
                maDoiTac: item.maNguoiDung,
                tenDoiTac: item.hoTen,
                vaiTro: item.vaiTro,
                soDienThoai: item.soDienThoai || '',
                anhDaiDien: item.anhDaiDien || null,
                tinNhanCuoi: item.vaiTro === 'admin' ? 'Kênh hỗ trợ trực tuyến từ Quản trị viên' : 'Bắt đầu cuộc trò chuyện mới',
                soTinChuaDoc: 0,
                isOnline: isUserOnline(item.maNguoiDung)
            }));
        }

        return res.json({ success: true, data: danhSach });
    } catch (error) {
        console.error('Lỗi lấy danh sách cuộc trò chuyện:', error);
        return res.status(500).json({ success: false, message: 'Lỗi server' });
    }
};

// 2. API Tìm kiếm người dùng có trong database phục vụ nhắn tin
exports.timKiemNguoiDung = async (req, res) => {
    try {
        const maNguoiDung = Number(req.user?.id || req.session?.user?.maNguoiDung || 0);
        if (maNguoiDung) touchUserOnline(maNguoiDung);

        const q = String(req.query.q || '').trim();
        const pool = await poolPromise;

        if (!pool) {
            const demoUsers = [
                { maNguoiDung: 1, hoTen: 'Admin Hệ Thống Ong Mật', soDienThoai: '0901000003', email: 'admin@ongmat.com', vaiTro: 'admin' },
                { maNguoiDung: 2, hoTen: 'Chủ đất Demo - Trần Văn Nam', soDienThoai: '0901000001', email: 'chudat@ongmat.com', vaiTro: 'chuDat' },
                { maNguoiDung: 3, hoTen: 'Lê Thị Bích (Vườn Bưởi)', soDienThoai: '0901000004', email: 'bich@ongmat.com', vaiTro: 'chuDat' },
                { maNguoiDung: 4, hoTen: 'BQL Kiểm Duyệt Vườn Nuôi', soDienThoai: '0901000005', email: 'kiemduyet@ongmat.com', vaiTro: 'admin' },
                { maNguoiDung: 5, hoTen: 'Người nuôi ong Demo - Nguyễn Văn Hùng', soDienThoai: '0901000002', email: 'nuoiong@ongmat.com', vaiTro: 'nguoiNuoiOng' }
            ];
            const filtered = demoUsers
                .filter(u => u.maNguoiDung !== maNguoiDung)
                .filter(u => !q || u.hoTen.toLowerCase().includes(q.toLowerCase()) || u.soDienThoai.includes(q) || u.vaiTro.toLowerCase().includes(q.toLowerCase()))
                .map(u => ({ ...u, isOnline: isUserOnline(u.maNguoiDung) }));
            return res.json({ success: true, data: filtered });
        }

        const request = pool.request().input('myId', sql.Int, maNguoiDung);
        let query = `
            SELECT TOP 40
                maNguoiDung,
                hoTen,
                soDienThoai,
                email,
                vaiTro,
                COALESCE(anhDaiDien, avatarUrl) AS anhDaiDien,
                trangThaiTaiKhoan
            FROM nguoiDung
            WHERE maNguoiDung <> @myId
              AND (trangThaiTaiKhoan IS NULL OR trangThaiTaiKhoan <> 'DaKhoa')
        `;

        if (q) {
            request.input('keyword', sql.NVarChar, `%${q}%`);
            query += ` AND (hoTen LIKE @keyword OR soDienThoai LIKE @keyword OR email LIKE @keyword OR vaiTro LIKE @keyword) `;
        }

        query += `
            ORDER BY 
                CASE WHEN vaiTro = 'admin' THEN 0 ELSE 1 END,
                hoTen ASC
        `;

        const result = await request.query(query);
        const data = (result.recordset || []).map(u => ({
            maNguoiDung: u.maNguoiDung,
            hoTen: u.hoTen || 'Người dùng',
            soDienThoai: u.soDienThoai || '',
            email: u.email || '',
            vaiTro: u.vaiTro || 'nguoiNuoiOng',
            anhDaiDien: u.anhDaiDien || null,
            isOnline: isUserOnline(u.maNguoiDung)
        }));

        return res.json({ success: true, data });
    } catch (error) {
        console.error('Lỗi tìm kiếm người dùng trong database:', error);
        return res.status(500).json({ success: false, message: 'Lỗi server khi tìm kiếm' });
    }
};

// 3. Heartbeat giữ trạng thái trực tuyến
exports.heartbeat = async (req, res) => {
    try {
        const maNguoiDung = Number(req.user?.id || req.session?.user?.maNguoiDung || 0);
        if (maNguoiDung) {
            touchUserOnline(maNguoiDung);
        }
        return res.json({ success: true, isOnline: true, userId: maNguoiDung });
    } catch (error) {
        return res.status(500).json({ success: false });
    }
};

// 4. Kiểm tra trạng thái online của một hoặc nhiều người dùng
exports.checkOnlineStatus = async (req, res) => {
    try {
        const targetId = Number(req.params.id || req.query.id || 0);
        return res.json({
            success: true,
            userId: targetId,
            isOnline: isUserOnline(targetId)
        });
    } catch (error) {
        return res.status(500).json({ success: false });
    }
};

// 5. API Lấy lịch sử tin nhắn và Đánh dấu đã đọc
exports.getLichSuChat = async (req, res) => {
    try {
        const maNguoiGui = Number(req.user?.id ?? req.session?.user?.maNguoiDung ?? 0);
        const maNguoiNhan = Number(req.query.maNguoiNhan ?? 0);
        if (!maNguoiNhan) return res.status(400).json({ success: false, message: 'Thiếu người nhận.' });

        touchUserOnline(maNguoiGui);
        const pool = await poolPromise;

        if (!pool) {
            const demoUsers = {
                1: { maNguoiDung: 1, hoTen: 'Admin Hệ Thống Ong Mật', soDienThoai: '0901000003', vaiTro: 'admin' },
                2: { maNguoiDung: 2, hoTen: 'Trần Văn Nam (Chủ Vườn Nhãn)', soDienThoai: '0901000001', vaiTro: 'chuDat' },
                3: { maNguoiDung: 3, hoTen: 'Lê Thị Bích (Vườn Bưởi)', soDienThoai: '0901000004', vaiTro: 'chuDat' },
                5: { maNguoiDung: 5, hoTen: 'Nguyễn Văn Hùng (Người nuôi ong)', soDienThoai: '0901000002', vaiTro: 'nguoiNuoiOng' },
            };
            const p = demoUsers[maNguoiNhan] || { maNguoiDung: maNguoiNhan, hoTen: 'Đối tác ' + maNguoiNhan, soDienThoai: '0901000001', vaiTro: 'chuDat' };
            p.isOnline = isUserOnline(maNguoiNhan);
            return res.json({
                success: true,
                partnerOnline: isUserOnline(maNguoiNhan),
                partner: p,
                data: []
            });
        }

        await pool.request()
            .input('maNguoiGui', sql.Int, maNguoiGui)
            .input('maNguoiNhan', sql.Int, maNguoiNhan)
            .query(`UPDATE tinNhan SET daDoc = 1 WHERE maNguoiGui = @maNguoiNhan AND maNguoiNhan = @maNguoiGui AND daDoc = 0`);

        // Đánh dấu đã đọc các thông báo tin nhắn từ người này trong bảng thông báo
        try {
            await pool.request()
                .input('myId', sql.Int, maNguoiGui)
                .input('partnerId', sql.Int, maNguoiNhan)
                .query(`
                    UPDATE dbo.thongBaoNuoiOng 
                    SET daDoc = 1 
                    WHERE maNguoiDung = @myId 
                      AND daDoc = 0 
                      AND (tieuDe LIKE N'%Tin nhắn mới%' OR tieuDe LIKE N'%tin nhắn%')
                `);
        } catch (_) {}

        const query = `
            SELECT t.*, n.hoTen AS tenNguoiGui 
            FROM tinNhan t
            JOIN nguoiDung n ON t.maNguoiGui = n.maNguoiDung
            WHERE (t.maNguoiGui = @maNguoiGui AND t.maNguoiNhan = @maNguoiNhan)
               OR (t.maNguoiGui = @maNguoiNhan AND t.maNguoiNhan = @maNguoiGui)
            ORDER BY t.ngayGui ASC
        `;
        const result = await pool.request()
            .input('maNguoiGui', sql.Int, maNguoiGui)
            .input('maNguoiNhan', sql.Int, maNguoiNhan)
            .query(query);

        // Lấy thông tin đối tác chat kèm số điện thoại để gọi trực tiếp
        let partner = null;
        try {
            const pRes = await pool.request()
                .input('pId', sql.Int, maNguoiNhan)
                .query(`SELECT maNguoiDung, hoTen, soDienThoai, vaiTro, COALESCE(anhDaiDien, avatarUrl) AS anhDaiDien FROM nguoiDung WHERE maNguoiDung = @pId`);
            if (pRes.recordset && pRes.recordset.length > 0) {
                partner = pRes.recordset[0];
            }
        } catch (_) {}

        if (!partner) {
            partner = {
                maNguoiDung: maNguoiNhan,
                hoTen: 'Đối tác',
                soDienThoai: '',
                vaiTro: 'nguoiNuoiOng',
                anhDaiDien: null
            };
        }
        partner.isOnline = isUserOnline(maNguoiNhan);

        res.json({
            success: true,
            partnerOnline: isUserOnline(maNguoiNhan),
            partner: partner,
            data: (result.recordset || []).map(m => ({
                ...m,
                daThuHoi: m.daThuHoi === 1 || m.daThuHoi === true
            }))
        });
    } catch (error) {
        console.error('Lỗi lấy lịch sử chat:', error);
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
};

// 6. API Gửi tin nhắn mới
exports.guiTinNhan = async (req, res) => {
    try {
        const maNguoiGui = Number(req.user?.id ?? req.session?.user?.maNguoiDung ?? 0);
        const { maNguoiNhan, noiDung } = req.body;

        if (!maNguoiGui || !maNguoiNhan) {
            return res.status(400).json({ success: false, message: 'Thiếu thông tin người gửi hoặc người nhận.' });
        }

        if (!noiDung || String(noiDung).trim() === '') {
            return res.status(400).json({ success: false, message: 'Nội dung rỗng' });
        }

        touchUserOnline(maNguoiGui);

        const pool = await poolPromise;
        if (!pool) {
            return res.json({ success: true, message: 'Gửi tin nhắn thành công (chế độ demo).' });
        }

        await pool.request()
            .input('maNguoiGui', sql.Int, Number(maNguoiGui))
            .input('maNguoiNhan', sql.Int, Number(maNguoiNhan))
            .input('noiDung', sql.NVarChar, noiDung)
            .query(`INSERT INTO tinNhan (maNguoiGui, maNguoiNhan, noiDung, daDoc) VALUES (@maNguoiGui, @maNguoiNhan, @noiDung, 0)`);

        // Tự động tạo thông báo trong hệ thống cho người nhận
        try {
            const senderResult = await pool.request()
                .input('senderId', sql.Int, Number(maNguoiGui))
                .query('SELECT hoTen FROM nguoiDung WHERE maNguoiDung = @senderId');
            const senderName = senderResult.recordset[0]?.hoTen || 'Đối tác';

            let preview = (noiDung || '').trim();
            if (preview.startsWith('[HÌNH_ẢNH]:') || preview.startsWith('📷')) {
                preview = '📷 [Đã gửi một hình ảnh]';
            } else if (preview.startsWith('📍')) {
                preview = '📍 [Đã chia sẻ vị trí vườn ong]';
            } else if (preview.length > 80) {
                preview = preview.substring(0, 80) + '...';
            }

            await pool.request()
                .input('maNguoiDung', sql.Int, Number(maNguoiNhan))
                .input('tieuDe', sql.NVarChar, `Tin nhắn mới từ ${senderName}`)
                .input('noiDung', sql.NVarChar, preview)
                .input('mucDo', sql.NVarChar, 'Trung bình')
                .query(`
                    INSERT INTO dbo.thongBaoNuoiOng (maNguoiDung, tieuDe, noiDung, mucDo, thoiGian, daDoc) 
                    VALUES (@maNguoiDung, @tieuDe, @noiDung, @mucDo, GETDATE(), 0)
                `);
        } catch (tbErr) {
            console.error('Lỗi tự động tạo thông báo tin nhắn:', tbErr);
        }

        res.json({ success: true, message: 'Gửi tin nhắn thành công.' });
    } catch (error) {
        console.error('Lỗi gửi tin nhắn:', error);
        res.status(500).json({ success: false, message: 'Lỗi server' });
    }
};

// 7. API Tải ảnh đính kèm tin nhắn chat
exports.uploadAnhChat = async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ success: false, message: 'Chưa có file ảnh được tải lên.' });
        }
        const fileUrl = `/uploads/chat/${req.file.filename}`;
        const host = req.get('host');
        const protocol = req.protocol;
        const fullUrl = `${protocol}://${host}${fileUrl}`;
        return res.json({
            success: true,
            imageUrl: fileUrl,
            fullUrl: fullUrl,
            fileName: req.file.filename
        });
    } catch (error) {
        console.error('Lỗi upload ảnh chat:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ khi tải ảnh lên.' });
    }
};

// 8. Hiển thị trang Giao diện Chat độc lập
exports.trangChat = async (req, res) => {
    try {
        const maNguoiGuiHienTai = Number(req.session?.user?.maNguoiDung ?? 1);
        touchUserOnline(maNguoiGuiHienTai);

        const maDoiTac = Number(req.params.id);
        const pool = await poolPromise;
        
        let doiTac = null;
        if (pool) {
            const result = await pool.request()
                .input('id', sql.Int, maDoiTac)
                .query(`SELECT maNguoiDung, hoTen, vaiTro, soDienThoai, COALESCE(anhDaiDien, avatarUrl) AS anhDaiDien FROM nguoiDung WHERE maNguoiDung = @id`);
            if (result.recordset.length > 0) {
                doiTac = result.recordset[0];
            }
        }

        if (!doiTac) {
            doiTac = {
                maNguoiDung: maDoiTac,
                hoTen: 'Người dùng ' + maDoiTac,
                vaiTro: 'chuDat',
                soDienThoai: ''
            };
        }

        doiTac.isOnline = isUserOnline(doiTac.maNguoiDung);

        res.render('chat', { 
            doiTac,
            nguoiGuiHienTai: maNguoiGuiHienTai
        });
    } catch (error) {
        console.error('Lỗi tải trang chat:', error);
        res.status(500).send("Lỗi tải trang chat");
    }
};

// 9. Hiển thị trang Danh Sách Hỗ Trợ (Trung Tâm Nhắn Tin Admin)
exports.trangHoTro = async (req, res) => {
    try {
        const maNguoiDungHienTai = Number(req.session?.user?.maNguoiDung ?? 1);
        touchUserOnline(maNguoiDungHienTai);

        const pool = await poolPromise;
        let danhSachChat = [];

        if (pool) {
            const query = `
                SELECT 
                    n.maNguoiDung, n.hoTen, n.vaiTro, n.soDienThoai, COALESCE(n.anhDaiDien, n.avatarUrl) as anhDaiDien,
                    MAX(t.ngayGui) as thoiGianCuoi,
                    (SELECT TOP 1 CASE WHEN daThuHoi = 1 THEN N'Tin nhắn đã được thu hồi' ELSE noiDung END FROM tinNhan WHERE (maNguoiGui = n.maNguoiDung AND maNguoiNhan = @myId) OR (maNguoiGui = @myId AND maNguoiNhan = n.maNguoiDung) ORDER BY ngayGui DESC) as tinCuoi,
                    (SELECT COUNT(*) FROM tinNhan WHERE maNguoiGui = n.maNguoiDung AND maNguoiNhan = @myId AND daDoc = 0) as tinChuaDoc
                FROM nguoiDung n
                JOIN tinNhan t ON n.maNguoiDung = t.maNguoiGui OR n.maNguoiDung = t.maNguoiNhan
                WHERE n.maNguoiDung != @myId
                GROUP BY n.maNguoiDung, n.hoTen, n.vaiTro, n.soDienThoai, COALESCE(n.anhDaiDien, n.avatarUrl)
                ORDER BY thoiGianCuoi DESC
            `;
            const result = await pool.request().input('myId', sql.Int, maNguoiDungHienTai).query(query);
            danhSachChat = (result.recordset || []).map(u => ({
                ...u,
                isOnline: isUserOnline(u.maNguoiDung)
            }));

            // Nếu danh sách rỗng, gợi ý các người dùng từ CSDL để admin có thể nhắn trước
            if (danhSachChat.length === 0) {
                const allUsers = await pool.request().input('myId', sql.Int, maNguoiDungHienTai).query(`
                    SELECT TOP 20 maNguoiDung, hoTen, vaiTro, soDienThoai, COALESCE(anhDaiDien, avatarUrl) AS anhDaiDien
                    FROM nguoiDung
                    WHERE maNguoiDung <> @myId
                    ORDER BY maNguoiDung ASC
                `);
                danhSachChat = (allUsers.recordset || []).map(u => ({
                    ...u,
                    tinCuoi: 'Chưa có cuộc trò chuyện. Nhấp để bắt đầu hỗ trợ.',
                    thoiGianCuoi: null,
                    tinChuaDoc: 0,
                    isOnline: isUserOnline(u.maNguoiDung)
                }));
            }
        }

        const initialPartnerId = Number(req.query.partnerId || 0);

        res.render('ho-tro', { 
            danhSachChat,
            nguoiGuiHienTai: maNguoiDungHienTai,
            currentUser: req.session.user,
            initialPartnerId,
            path: '/ho-tro'
        });
    } catch (error) {
        console.error('Lỗi tải trang hỗ trợ:', error);
        res.status(500).send("Lỗi tải trang hỗ trợ");
    }
};

// 10. API Lấy thông tin đối tác chat (SĐT, Họ tên, Vai trò, Avatar, Online)
exports.getPartnerInfo = async (req, res) => {
    try {
        const partnerId = Number(req.params.id || req.query.id || 0);
        if (!partnerId) {
            return res.status(400).json({ success: false, message: 'Thiếu mã đối tác.' });
        }

        const pool = await poolPromise;
        if (!pool) {
            const demoUsers = {
                1: { maNguoiDung: 1, hoTen: 'Admin Hệ Thống Ong Mật', soDienThoai: '0901000003', vaiTro: 'admin' },
                2: { maNguoiDung: 2, hoTen: 'Trần Văn Nam (Chủ Vườn Nhãn)', soDienThoai: '0901000001', vaiTro: 'chuDat' },
                3: { maNguoiDung: 3, hoTen: 'Lê Thị Bích (Vườn Bưởi)', soDienThoai: '0901000004', vaiTro: 'chuDat' },
                5: { maNguoiDung: 5, hoTen: 'Nguyễn Văn Hùng (Người nuôi ong)', soDienThoai: '0901000002', vaiTro: 'nguoiNuoiOng' },
            };
            const p = demoUsers[partnerId] || { maNguoiDung: partnerId, hoTen: 'Đối tác ' + partnerId, soDienThoai: '0901000001', vaiTro: 'chuDat' };
            p.isOnline = isUserOnline(partnerId);
            return res.json({ success: true, data: p });
        }

        const result = await pool.request()
            .input('id', sql.Int, partnerId)
            .query(`SELECT maNguoiDung, hoTen, soDienThoai, vaiTro, COALESCE(anhDaiDien, avatarUrl) AS anhDaiDien FROM nguoiDung WHERE maNguoiDung = @id`);

        if (!result.recordset || result.recordset.length === 0) {
            return res.status(404).json({ success: false, message: 'Không tìm thấy người dùng này.' });
        }

        const partner = result.recordset[0];
        partner.isOnline = isUserOnline(partnerId);
        return res.json({ success: true, data: partner });
    } catch (error) {
        console.error('Lỗi lấy thông tin đối tác:', error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
    }
};

// 11. API Thu hồi tin nhắn chat (Người gửi hoặc Admin có thể thu hồi)
exports.thuHoiTinNhan = async (req, res) => {
    try {
        const maNguoiDung = Number(req.user?.id ?? req.session?.user?.maNguoiDung ?? 0);
        const maTinNhan = Number(req.params.id || req.body.maTinNhan || 0);

        if (!maNguoiDung || !maTinNhan) {
            return res.status(400).json({ success: false, message: 'Thiếu thông tin người dùng hoặc tin nhắn cần thu hồi.' });
        }

        touchUserOnline(maNguoiDung);

        const pool = await poolPromise;
        if (!pool) {
            return res.json({ success: true, message: 'Đã thu hồi tin nhắn thành công (chế độ demo).' });
        }

        // Kiểm tra quyền: chỉ người gửi tin nhắn hoặc Admin mới được phép thu hồi
        const checkRes = await pool.request()
            .input('id', sql.Int, maTinNhan)
            .query(`SELECT maTinNhan, maNguoiGui, maNguoiNhan, noiDung, daThuHoi FROM tinNhan WHERE maTinNhan = @id`);

        if (!checkRes.recordset || checkRes.recordset.length === 0) {
            return res.status(404).json({ success: false, message: 'Không tìm thấy tin nhắn cần thu hồi.' });
        }

        const msg = checkRes.recordset[0];
        const userRole = String(req.user?.vaiTro || req.session?.user?.vaiTro || '').toLowerCase();

        if (msg.maNguoiGui !== maNguoiDung && userRole !== 'admin') {
            return res.status(403).json({ success: false, message: 'Bạn chỉ có quyền thu hồi tin nhắn do chính mình gửi.' });
        }

        if (msg.daThuHoi) {
            return res.json({ success: true, message: 'Tin nhắn đã được thu hồi trước đó.' });
        }

        await pool.request()
            .input('id', sql.Int, maTinNhan)
            .query(`UPDATE tinNhan SET daThuHoi = 1 WHERE maTinNhan = @id`);

        return res.json({ success: true, message: 'Đã thu hồi tin nhắn thành công.' });
    } catch (error) {
        console.error('Lỗi thu hồi tin nhắn:', error);
        return res.status(500).json({ success: false, message: 'Lỗi server khi thu hồi tin nhắn.' });
    }
};
