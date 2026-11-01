require('dotenv').config(); 
const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const session = require('express-session');
const app = express();

const diaDiemController = require('./controllers/diaDiemController');
const { ensureDemoUsers } = require('./config/seedDemoUsers');
const { ensureBeekeepingSchema } = require('./config/beekeepingSchema');
const { startReminderJob } = require('./config/reminders');
const authController = require('./controllers/authController');
const { requireAuth } = require('./middleware/auth'); // Đưa lên đầu để dùng được cho tất cả các route bên dưới

app.use(cors({ origin: true, credentials: true }));
const port = process.env.PORT || 3000;

app.set('view engine', 'ejs');
app.set('views', './views');

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use(express.static('public'));

// Tự động tạo thư mục uploads nếu chưa có
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}
app.use('/uploads', express.static(uploadDir));

app.use('/api/otp', require('./routes/otpRoutes'));

// Tuyến đường OTP & Ký hợp đồng
app.post('/api/mobile/contracts/:id/otp', requireAuth, authController.requestContractOtp);
app.post('/api/mobile/contracts/otp', requireAuth, authController.requestContractOtp);

app.post('/api/mobile/contracts/sign', requireAuth, authController.signContractWithOtp);
app.put('/api/mobile/contracts/sign', requireAuth, authController.signContractWithOtp);
app.post('/api/mobile/contracts/:id/sign', requireAuth, authController.signContractWithOtp);
app.put('/api/mobile/contracts/:id/sign', requireAuth, authController.signContractWithOtp);
app.post('/api/mobile/contracts/:id/ky', requireAuth, authController.signContractWithOtp);
app.put('/api/mobile/contracts/:id/ky', requireAuth, authController.signContractWithOtp);

// =========================================================
// 1. CẤU HÌNH SESSION (DÀNH RIÊNG CHO WEB ADMIN)
// =========================================================
app.use(session({
    secret: 'ongmat_session_secret_2026',
    resave: false,
    saveUninitialized: false,
    cookie: { maxAge: 24 * 60 * 60 * 1000 }
}));

// =========================================================
// 2. CÁC API DÀNH CHO MOBILE APP
// =========================================================
const authRoutes = require('./routes/auth');
const mobileRoutes = require('./routes/mobile');
const sharedController = require('./controllers/sharedController');

app.get('/api/health', (req, res) => res.json({ success: true, time: new Date().toISOString() }));
app.use('/api/auth', authRoutes);
app.use('/api/mobile', mobileRoutes);

// Công khai: khách hàng quét QR xem nguồn gốc; PDF hợp đồng mở bằng trình duyệt
app.get('/truy-xuat-qr', sharedController.publicTrace);
app.get('/api/hop-dong/pdf/:id', sharedController.contractPdf);
const publicController = require('./controllers/publicController');
app.get('/tra-cuu', publicController.lookupPage);
app.get('/api/public/truy-xuat/:id', publicController.traceJson);
app.get('/api/public/san-pham', publicController.searchProducts);
app.get('/api/public/catalog/species', sharedController.getCatalogSpecies);
app.get('/api/public/catalog/flowers', sharedController.getCatalogFlowers);
app.get('/api/public/catalog/bees', sharedController.getCatalogBees);

// Geocoding Proxy công khai chống lỗi CORS trên Flutter Web (Chrome)
const axios = require('axios');
app.get('/api/public/reverse-geocode', async (req, res) => {
    try {
        const { lat, lon } = req.query;
        if (!lat || !lon) return res.json({ success: false, message: 'Thiếu toạ độ' });
        const r = await axios.get(`https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&accept-language=vi`, {
            headers: { 'User-Agent': 'MobileOngMatApp/1.0' },
            timeout: 5000
        });
        return res.json({ success: true, data: r.data });
    } catch (err) {
        return res.json({ success: false, message: err.message });
    }
});

app.get('/api/public/geocode', async (req, res) => {
    try {
        const { q } = req.query;
        if (!q || !q.trim()) return res.json({ success: false, data: [] });

        const clean = q.trim();
        // 1. Tạo các cấp độ địa chỉ thông minh (bỏ số nhà / hẻm / ngõ)
        const candidates = [];
        const stripped = clean
            .replace(/^[0-9]+[A-Za-z]?(\/[0-9]+[A-Za-z]?)*\s*,?\s*/i, '')
            .replace(/^(số|số nhà|nhà số|hẻm|ngõ|ngách|thửa|lô)\s+[0-9A-Za-z\/\.\-]+\s*,?\s*/i, '')
            .trim();
        if (stripped && stripped !== clean) candidates.push(stripped);

        const parts = clean.split(',').map(p => p.trim()).filter(Boolean);
        if (parts.length >= 3) {
            const withoutFirst = parts.slice(1).join(', ');
            if (!candidates.includes(withoutFirst)) candidates.push(withoutFirst);

            if (parts.length >= 4) {
                const pStreet = parts[0].replace(/^[0-9]+[A-Za-z]?(\/[0-9]+[A-Za-z]?)*\s*/i, '').trim();
                const streetDistCity = [pStreet, parts[parts.length - 2], parts[parts.length - 1]].join(', ');
                if (!candidates.includes(streetDistCity)) candidates.push(streetDistCity);
                const communeDistCity = parts.slice(parts.length - 3).join(', ');
                if (!candidates.includes(communeDistCity)) candidates.push(communeDistCity);
            }
            const distCity = parts.slice(parts.length - 2).join(', ');
            if (!candidates.includes(distCity)) candidates.push(distCity);
        }
        if (!candidates.includes(clean)) candidates.push(clean);

        // 2. Thử Photon Komoot OSM cho từng candidate
        for (const c of candidates) {
            try {
                const pRes = await axios.get(`https://photon.komoot.io/api/?q=${encodeURIComponent(c)}&limit=5`, { timeout: 3500 });
                if (pRes.data && pRes.data.features && pRes.data.features.length) {
                    const results = [];
                    for (const f of pRes.data.features) {
                        const [lon, lat] = f.geometry.coordinates;
                        if (lat > 8.0 && lat < 24.0 && lon > 102.0 && lon < 110.0) {
                            const p = f.properties || {};
                            const title = [p.name, p.district, p.city].filter(Boolean).join(', ');
                            results.push({
                                display_name: title || p.name || c,
                                lat: lat.toString(),
                                lon: lon.toString()
                            });
                        }
                    }
                    if (results.length > 0) {
                        return res.json({ success: true, data: results });
                    }
                }
            } catch (_) {}
        }

        // 3. Fallback Nominatim
        for (const c of candidates) {
            try {
                const r = await axios.get(`https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(c + ', Vietnam')}&format=json&limit=5&accept-language=vi`, {
                    headers: { 'User-Agent': 'MobileOngMatApp/1.0' },
                    timeout: 3500
                });
                if (Array.isArray(r.data) && r.data.length > 0) {
                    return res.json({ success: true, data: r.data });
                }
            } catch (_) {}
        }

        return res.json({ success: true, data: [] });
    } catch (err) {
        return res.json({ success: false, message: err.message, data: [] });
    }
});

app.get('/api/public/weather', async (req, res) => {
    try {
        const { lat, lon } = req.query;
        if (!lat || !lon) return res.json({ success: false, message: 'Thiếu toạ độ' });
        const r = await axios.get(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m`, {
            timeout: 5000
        });
        return res.json({ success: true, data: r.data });
    } catch (err) {
        return res.json({ success: false, message: err.message });
    }
});

// =========================================================
// 3. LUỒNG XÁC THỰC DÀNH CHO WEB ADMIN & CHAT
// =========================================================
const chatController = require('./controllers/chatController');

// Chat dùng chung cho mobile (JWT) và web admin (session)
const multer = require('multer');
const chatUploadDir = path.join(__dirname, 'uploads/chat');
if (!fs.existsSync(chatUploadDir)) {
    fs.mkdirSync(chatUploadDir, { recursive: true });
}
const chatStorage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, chatUploadDir);
    },
    filename: function (req, file, cb) {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        let ext = path.extname(file.originalname || '').toLowerCase();
        if (!ext || ext === '.' || !['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif'].includes(ext)) {
            ext = '.jpg';
        }
        cb(null, 'chat-' + uniqueSuffix + ext);
    }
});
const uploadChat = multer({
    storage: chatStorage,
    limits: { fileSize: 15 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        const ext = path.extname(file.originalname || '').toLowerCase();
        if (!file.mimetype || file.mimetype.startsWith('image/') || ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif'].includes(ext)) {
            cb(null, true);
        } else {
            cb(new Error('Chỉ chấp nhận file hình ảnh!'), false);
        }
    }
});

const handleChatUpload = (req, res, next) => {
    uploadChat.single('image')(req, res, (err) => {
        if (err) {
            console.error('Lỗi tải ảnh chat (Multer):', err.message);
            return res.status(400).json({ success: false, message: err.message || 'Lỗi tải ảnh lên máy chủ' });
        }
        next();
    });
};

app.get('/api/chat/danh-sach', requireAuth, chatController.getDanhSachCuocTroChuyen);
app.get('/api/chat/lich-su', requireAuth, chatController.getLichSuChat);
app.post('/api/chat/gui', requireAuth, chatController.guiTinNhan);
app.post('/api/chat/upload-anh', requireAuth, handleChatUpload, chatController.uploadAnhChat);
app.post('/api/mobile/chat/upload-anh', requireAuth, handleChatUpload, chatController.uploadAnhChat);
app.get('/api/chat/tim-kiem-nguoi-dung', requireAuth, chatController.timKiemNguoiDung);
app.get('/api/mobile/chat/tim-kiem-nguoi-dung', requireAuth, chatController.timKiemNguoiDung);
app.post('/api/chat/heartbeat', requireAuth, chatController.heartbeat);
app.post('/api/mobile/chat/heartbeat', requireAuth, chatController.heartbeat);
app.get('/api/chat/trang-thai-online/:id', requireAuth, chatController.checkOnlineStatus);
app.post('/api/chat/thu-hoi/:id', requireAuth, chatController.thuHoiTinNhan);
app.post('/api/chat/thu-hoi', requireAuth, chatController.thuHoiTinNhan);
app.post('/api/mobile/chat/thu-hoi/:id', requireAuth, chatController.thuHoiTinNhan);
app.post('/api/mobile/chat/thu-hoi', requireAuth, chatController.thuHoiTinNhan);
app.get('/api/chat/partner/:id', requireAuth, chatController.getPartnerInfo);
app.get('/api/mobile/chat/partner/:id', requireAuth, chatController.getPartnerInfo);

// Hiển thị và xử lý form đăng nhập Admin
app.get('/login', authController.getLoginAdmin);
app.post('/login', authController.postLoginAdmin);
app.get('/logout', authController.logoutAdmin);
app.get('/dang-ky', authController.getDangKyWeb);
app.post('/dang-ky', authController.postDangKyWeb);

// Cổng web cho người nuôi ong và chủ đất
app.get('/portal', (req, res) => {
    const user = req.session.user;
    if (!user) return res.redirect('/login');
    if (user.vaiTro === 'admin') return res.redirect('/');
    res.render('portal', {
        user: {
            id: user.maNguoiDung,
            hoTen: user.hoTen,
            vaiTro: user.vaiTro,
            email: user.email || '',
            soDienThoai: user.soDienThoai || '',
            anhDaiDien: user.anhDaiDien || user.avatarUrl || null
        }
    });
});

// Middleware kiểm tra quyền Admin
const requireAdmin = async (req, res, next) => {
    if (req.session.user && req.session.user.vaiTro === 'admin') {
        res.locals.currentUser = req.session.user; 

        try {
            const { poolPromise } = require('./config/db');
            const pool = await poolPromise;
            const result = await pool.request()
                .query("SELECT COUNT(*) AS SoLuong FROM diaDiemVuon WHERE trangThaiKiemDuyet = 'ChoDiemDuyet'");
            
            res.locals.soThongBao = result.recordset[0].SoLuong;
        } catch (err) {
            console.error("Lỗi đếm thông báo:", err);
            res.locals.soThongBao = 0;
        }

        next();
    } else {
        if (req.session.user) {
            if (req.originalUrl.startsWith('/api')) {
                return res.status(403).json({ success: false, message: 'Chức năng này chỉ dành cho quản trị viên.' });
            }
            return res.redirect('/portal');
        }
        if (req.originalUrl.startsWith('/api')) {
            return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập bằng tài khoản quản trị viên.' });
        }
        res.redirect('/login');
    }
};

// Đường dẫn công cộng
app.get('/truy-xuat/:id', diaDiemController.truyXuatNguonGoc);

// =========================================================
// 4. ROUTER QUẢN TRỊ ADMIN
// =========================================================
const adminRoutes = require('./routes/admin');
app.use('/', requireAdmin, adminRoutes); 

// =========================================================
// KHỞI ĐỘNG SERVER
// =========================================================
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', async () => {
    console.log(`🚀 Server đang chạy tại: http://localhost:${PORT}`);
    try {
        await ensureBeekeepingSchema();
        await ensureDemoUsers();
        startReminderJob();
    } catch (err) {
        console.error('Lỗi khởi tạo CSDL/nhắc nhở:', err);
    }
});