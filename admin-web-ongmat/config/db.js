const sql = require('mssql');

const hasSqlConfig = Boolean(
    process.env.DB_USER &&
    process.env.DB_PASSWORD &&
    process.env.DB_SERVER &&
    process.env.DB_NAME
);

const dbConfig = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    server: process.env.DB_SERVER,
    port: Number(process.env.DB_PORT || 1433),
    database: process.env.DB_NAME,
    options: {
        encrypt: false,
        trustServerCertificate: true,
        requestTimeout: 30000,
        enableArithAbort: true
    },
    pool: {
        max: 25,
        min: 2,
        idleTimeoutMillis: 30000
    }
};

const poolPromise = hasSqlConfig
    ? new sql.ConnectionPool(dbConfig)
        .connect()
        .then(pool => {
            console.log('✅ Kết nối CSDL QL_OngMat trên SQL Server thành công!');
            return pool;
        })
        .catch(err => {
            console.warn('⚠️ Không thể kết nối SQL Server, chuyển sang chế độ demo:', err.message);
            return null;
        })
    : Promise.resolve(null);

if (!hasSqlConfig) {
    console.warn('⚠️ Chưa cấu hình biến môi trường SQL Server, backend sẽ chạy ở chế độ demo cho mobile app.');
}

module.exports = { sql, poolPromise };