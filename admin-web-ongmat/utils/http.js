// Lỗi nghiệp vụ có mã HTTP rõ ràng, controller ném ra để trả về JSON thống nhất.
class AppError extends Error {
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}

const asyncHandler = (handler) => async (req, res, next) => {
    try {
        await handler(req, res, next);
    } catch (error) {
        if (error instanceof AppError) {
            return res.status(error.status).json({ success: false, message: error.message });
        }
        if (error.code === 'DB_UNAVAILABLE') {
            return res.status(503).json({ success: false, message: 'Không kết nối được cơ sở dữ liệu. Vui lòng thử lại sau.' });
        }
        console.error(`Lỗi ${req.method} ${req.originalUrl}:`, error);
        return res.status(500).json({ success: false, message: 'Lỗi máy chủ nội bộ' });
    }
};

const text = (value, max = 300) => String(value ?? '').trim().slice(0, max);

const requiredText = (value, label, max = 300) => {
    const result = text(value, max);
    if (!result) throw new AppError(400, `Vui lòng nhập ${label}.`);
    return result;
};

const positiveNumber = (value, label, { integer = false, allowZero = false } = {}) => {
    const number = Number(value);
    const valid = Number.isFinite(number) && (allowZero ? number >= 0 : number > 0) && (!integer || Number.isInteger(number));
    if (!valid) throw new AppError(400, `${label} phải là ${integer ? 'số nguyên' : 'số'} ${allowZero ? 'không âm' : 'lớn hơn 0'}.`);
    return number;
};

const optionalNumber = (value) => {
    if (value === null || value === undefined || value === '') return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
};

const coordinates = (lat, lng) => {
    const viDo = Number(lat);
    const kinhDo = Number(lng);
    if (!Number.isFinite(viDo) || !Number.isFinite(kinhDo) || viDo < -90 || viDo > 90 || kinhDo < -180 || kinhDo > 180) {
        throw new AppError(400, 'Tọa độ GPS không hợp lệ.');
    }
    return { viDo, kinhDo };
};

const isoDate = (value, label) => {
    const result = text(value, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(result) || Number.isNaN(Date.parse(result))) {
        throw new AppError(400, `${label} phải có dạng yyyy-mm-dd.`);
    }
    return result;
};

module.exports = { AppError, asyncHandler, text, requiredText, positiveNumber, optionalNumber, coordinates, isoDate };
