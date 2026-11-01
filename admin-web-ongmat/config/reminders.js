const { poolPromise } = require('./db');

// Nhắc lịch: định kỳ tạo thông báo cho các việc chăm sóc / di chuyển diễn ra
// trong vòng 24 giờ tới (theo giờ Việt Nam) mà chưa được nhắc.
const INTERVAL_MS = 15 * 60 * 1000;

async function sendDueReminders() {
    const pool = await poolPromise;
    if (!pool) return { care: 0, moves: 0 };
    const result = await pool.request().batch(`
        DECLARE @now DATETIME2 = DATEADD(HOUR, 7, SYSUTCDATETIME());
        DECLARE @care TABLE (id INT);
        DECLARE @moves TABLE (id INT);

        UPDATE dbo.lichChamSocOng SET daNhacNho = 1
        OUTPUT INSERTED.id INTO @care
        WHERE daNhacNho = 0 AND trangThai <> N'Đã hoàn thành' AND maNguoiDung IS NOT NULL
          AND DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME), ISNULL(gio, CAST('07:00' AS TIME))), CAST(ngay AS DATETIME2))
              <= DATEADD(HOUR, 24, @now);

        INSERT INTO dbo.thongBaoNuoiOng (maNguoiDung, tieuDe, noiDung, mucDo)
        SELECT c.maNguoiDung,
               CASE WHEN c.ngay < CAST(@now AS DATE) THEN N'Lịch chăm sóc quá hạn' ELSE N'Sắp tới lịch chăm sóc' END,
               CONCAT(c.tenCongViec, ISNULL(N' – ' + d.tenDanOng, N''), N' lúc ', FORMAT(c.ngay, 'dd/MM/yyyy'), N' ', ISNULL(CONVERT(varchar(5), c.gio, 108), N'')),
               N'Cao'
        FROM dbo.lichChamSocOng c
        JOIN @care x ON x.id = c.id
        LEFT JOIN dbo.danOng d ON d.maDanOng = c.maDanOng;

        UPDATE dbo.lichDiChuyenOng SET daNhacNho = 1
        OUTPUT INSERTED.id INTO @moves
        WHERE daNhacNho = 0 AND trangThai = N'Lên lịch' AND maNguoiDung IS NOT NULL
          AND ngay <= CAST(DATEADD(HOUR, 24, @now) AS DATE);

        INSERT INTO dbo.thongBaoNuoiOng (maNguoiDung, tieuDe, noiDung, mucDo)
        SELECT m.maNguoiDung, N'Sắp tới lịch di chuyển',
               CONCAT(ISNULL(d.tenDanOng, N'Đàn ong'), N': ', m.viTriDi, N' → ', m.viTriDen, N' ngày ', FORMAT(m.ngay, 'dd/MM/yyyy')),
               N'Cao'
        FROM dbo.lichDiChuyenOng m
        JOIN @moves x ON x.id = m.id
        LEFT JOIN dbo.danOng d ON d.maDanOng = m.maDanOng;

        SELECT (SELECT COUNT(*) FROM @care) AS care, (SELECT COUNT(*) FROM @moves) AS moves;
    `);
    return result.recordset[0];
}

function startReminderJob() {
    const run = () => sendDueReminders()
        .then((sent) => { if (sent.care || sent.moves) console.log(`Đã gửi nhắc lịch: ${sent.care} chăm sóc, ${sent.moves} di chuyển.`); })
        .catch((error) => console.warn('Lỗi gửi nhắc lịch:', error.message));
    run();
    return setInterval(run, INTERVAL_MS);
}

module.exports = { sendDueReminders, startReminderJob };
