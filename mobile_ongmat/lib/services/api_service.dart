import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiConfig {
  static const _prefsKey = 'api_base_url';
  static String? _resolved;

  static List<String> get candidateBaseUrls {
    final urls = <String>[];
    final fromEnv = dotenv.isInitialized ? dotenv.env['API_BASE_URL'] : null;
    if (fromEnv != null && fromEnv.trim().isNotEmpty) urls.add(fromEnv.trim());
    urls.addAll(
      kIsWeb
          ? ['http://localhost:3000', 'http://127.0.0.1:3000']
          : [
              'http://10.0.2.2:3000',
              'http://192.168.1.169:3000',
              'http://127.0.0.1:3000',
              'http://localhost:3000',
              'http://192.168.88.73:3000',
              'http://192.168.1.25:3000',
              'http://192.168.0.25:3000',
              'http://192.168.1.10:3000',
              'http://192.168.0.10:3000',
              'http://192.168.43.1:3000',
              'http://172.20.10.2:3000',
            ],
    );
    return urls.toSet().toList();
  }

  static String get baseUrl => _resolved ?? candidateBaseUrls.first;

  // Thử song song tất cả địa chỉ, dùng địa chỉ phản hồi đầu tiên và ghi nhớ lại.
  static Future<String> resolve({bool force = false}) async {
    if (!force && _resolved != null) return _resolved!;
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final saved = prefs.getString(_prefsKey);
      if (saved != null && await _ping(saved)) return _resolved = saved;
    }

    final completer = Completer<String?>();
    var pending = candidateBaseUrls.length;
    for (final url in candidateBaseUrls) {
      _ping(url).then((ok) {
        pending--;
        if (ok && !completer.isCompleted) completer.complete(url);
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      });
    }
    final found = await completer.future;
    if (found == null) {
      throw ApiException(
        'Không kết nối được máy chủ tại ${candidateBaseUrls.first}. '
        'Hãy bật backend (npm start) và kiểm tra API_BASE_URL trong .env '
        '(điện thoại thật cần IP máy tính, cùng Wi-Fi, mở cổng 3000 trên tường lửa).',
      );
    }
    await prefs.setString(_prefsKey, found);
    return _resolved = found;
  }

  static Future<bool> _ping(String base) async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

typedef Json = Map<String, dynamic>;

class ApiService {
  static const _timeout = Duration(seconds: 15);

  /// Được gọi khi token hết hạn/không hợp lệ để ứng dụng quay về màn hình đăng nhập.
  static VoidCallback? onUnauthorized;

  // ================= HẠ TẦNG =================

  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    bool retried = false,
  }) async {
    final base = await ApiConfig.resolve();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    final headers = {
      'Content-Type': 'application/json',
      if (auth && token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
    final request = http.Request(method, Uri.parse('$base$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await request.send().timeout(_timeout),
      );
    } on TimeoutException {
      throw ApiException('Máy chủ phản hồi quá lâu, vui lòng thử lại.');
    } catch (_) {
      // Địa chỉ đã lưu có thể đổi (đổi mạng wifi...): dò lại một lần.
      if (!retried) {
        await ApiConfig.resolve(force: true);
        return _send(method, path, body: body, auth: auth, retried: true);
      }
      throw ApiException('Không kết nối được máy chủ.');
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final message = decoded is Map ? decoded['message']?.toString() : null;

    if (response.statusCode == 401 && auth) {
      await clearSession();
      onUnauthorized?.call();
      throw ApiException(
        message ?? 'Phiên đăng nhập đã hết hạn.',
        statusCode: 401,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        message ?? 'Yêu cầu thất bại (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  static Future<dynamic> get(String path, {bool auth = true}) {
    return _send('GET', path, auth: auth);
  }

  static Future<dynamic> put(String path, Object? body, {bool auth = true}) {
    return _send('PUT', path, body: body, auth: auth);
  }

  static Future<dynamic> post(String path, Object? body, {bool auth = true}) {
    return _send('POST', path, body: body, auth: auth);
  }

  static Future<dynamic> delete(String path, {Object? body, bool auth = true}) {
    return _send('DELETE', path, body: body, auth: auth);
  }

  static Future<dynamic> _data(
    String method,
    String path, {
    Object? body,
  }) async {
    final decoded = await _send(method, path, body: body);
    return decoded is Map ? decoded['data'] : decoded;
  }

  static Future<String> _action(
    String method,
    String path, {
    Object? body,
  }) async {
    final decoded = await _send(method, path, body: body);
    return decoded is Map
        ? (decoded['message']?.toString() ?? 'Thành công')
        : 'Thành công';
  }

  static List<Json> _list(dynamic data) => data is List
      ? data.whereType<Map>().map((e) => Json.from(e)).toList()
      : <Json>[];

  static Json _map(dynamic data) =>
      data is Map ? Json.from(data) : <String, dynamic>{};

  static String _id(Object id) => Uri.encodeComponent(id.toString());

  // ================= XÁC THỰC MÃ OTP QUA GMAIL =================

  /// Gửi mã OTP xác thực tới hộp thư Gmail hoặc số điện thoại
  /// [loaiHanhDong]: 'DANG_KY' hoặc 'KY_HOP_DONG'
  static Future<Json> sendOtp({
    required String email,
    String? soDienThoai,
    required String loaiHanhDong,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'email': email.trim().toLowerCase(),
        'loaiHanhDong': loaiHanhDong,
      };

      if (soDienThoai != null && soDienThoai.trim().isNotEmpty) {
        body['soDienThoai'] = soDienThoai.replaceAll(' ', '').trim();
      }

      final decoded = await _send(
        'POST',
        '/api/otp/send',
        body: body,
        auth: false,
      );
      return _map(decoded);
    } catch (e) {
      return {
        'success': false,
        'message': (e is ApiException) ? e.message : e.toString()
      };
    }
  }

  /// Xác thực mã OTP người dùng nhập vào
  static Future<Map<String, dynamic>> verifyOtp({
    required String maOtp,
    String? email,
    String? soDienThoai,
    String loaiHanhDong = 'DANG_KY',
  }) async {
    try {
      final decoded = await _send(
        'POST',
        '/api/otp/verify',
        body: {
          'email': email?.trim().toLowerCase(),
          'soDienThoai': soDienThoai?.replaceAll(' ', '').trim(),
          'maOtp': maOtp.trim(),
          'loaiHanhDong': loaiHanhDong,
        },
        auth: false,
      );
      return _map(decoded);
    } catch (e) {
      return {'success': false, 'message': (e is ApiException) ? e.message : e.toString()};
    }
  }

  /// Kiểm tra xem email hoặc số điện thoại đã tồn tại trong hệ thống chưa
  static Future<Map<String, dynamic>> checkAccount({
    String? email,
    String? soDienThoai,
  }) async {
    try {
      final decoded = await _send(
        'POST',
        '/api/auth/check-account',
        body: {
          'email': email?.trim().toLowerCase(),
          'soDienThoai': soDienThoai?.replaceAll(' ', '').trim(),
        },
        auth: false,
      );
      return _map(decoded);
    } catch (e) {
      return {'success': false, 'message': (e is ApiException) ? e.message : e.toString()};
    }
  }

  // ================= PHIÊN ĐĂNG NHẬP & GOOGLE AUTH =================

  static Future<Json> _saveSession(dynamic decoded) async {
    final data = _map(decoded);
    final user = _map(data['user']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', data['token']?.toString() ?? '');
    await prefs.setString('vaiTro', user['vaiTro']?.toString() ?? '');
    await prefs.setString('hoTen', user['hoTen']?.toString() ?? 'Người dùng');
    await prefs.setInt('user_id', int.tryParse('${user['id']}') ?? 0);
    return data;
  }

  static Future<Json> login({
    required String taiKhoan,
    required String matKhau,
  }) async {
    final decoded = await _send(
      'POST',
      '/api/auth/login',
      body: {'taiKhoan': taiKhoan, 'matKhau': matKhau},
      auth: false,
    );
    return _saveSession(decoded);
  }

  /// Đăng nhập hoặc đăng ký nhanh bằng tài khoản Google hiện có
  static Future<Json> loginWithGoogle({
    required String email,
    required String hoTen,
    String? googleId,
    String? avatarUrl,
    String? vaiTro,
  }) async {
    final decoded = await _send(
      'POST',
      '/api/auth/google',
      body: {
        'email': email.trim().toLowerCase(),
        'hoTen': hoTen.trim(),
        'googleId': googleId,
        'avatarUrl': avatarUrl,
        'vaiTro': vaiTro ?? 'nguoiNuoiOng',
      },
      auth: false,
    );
    return _saveSession(decoded);
  }

  static Future<Json> register({
    required String hoTen,
    required String email,
    required String soDienThoai,
    required String matKhau,
    required String vaiTro,
  }) async {
    final decoded = await _send(
      'POST',
      '/api/auth/register',
      body: {
        'hoTen': hoTen,
        'email': email,
        'soDienThoai': soDienThoai,
        'matKhau': matKhau,
        'vaiTro': vaiTro,
      },
      auth: false,
    );
    return _saveSession(decoded);
  }

  static Future<bool> hasSession() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('jwt_token') ?? '').isNotEmpty;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['jwt_token', 'vaiTro', 'hoTen', 'user_id']) {
      await prefs.remove(key);
    }
  }

  static Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  static Future<Json> getProfile() async =>
      _map(await _data('GET', '/api/mobile/profile'));

  // ================= THÔNG BÁO & HỢP ĐỒNG (dùng chung) =================

  static Future<Map<String, dynamic>> getSpeciesCatalog() async {
    try {
      final res = await _data('GET', '/api/mobile/catalog/species');
      if (res is Map<String, dynamic>) return res;
      if (res is Map) return Map<String, dynamic>.from(res);
      return {};
    } catch (_) {
      try {
        final decoded = await _send('GET', '/api/public/catalog/species', auth: false);
        final data = decoded is Map ? decoded['data'] : null;
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
      } catch (_) {}
      return {};
    }
  }

  static Future<List<Json>> getNotifications() async =>
      _list(await _data('GET', '/api/mobile/notifications'));

  static Future<void> markNotificationsRead({int? id}) =>
      _send('PUT', '/api/mobile/notifications/read', body: {'id': ?id});

  static Future<List<Json>> getContracts() async =>
      _list(await _data('GET', '/api/mobile/contracts'));

  static Future<Json> requestContractOtp(String contractId) async {
    final decoded = await _send(
      'POST',
      '/api/mobile/contracts/${_id(contractId)}/otp',
    );
    return _map(decoded);
  }

  static Future<String> signContract({
    required String contractId,
    required String otp,
  }) => _action(
    'PUT',
    '/api/mobile/contracts/${_id(contractId)}/sign',
    body: {'otp': otp},
  );

  static Future<String> completeContract(String contractId) => _action(
    'PUT',
    '/api/mobile/contracts/${_id(contractId)}/complete',
  );

  static Future<List<Json>> getContractReviews(String contractId) async =>
      _list(await _data('GET', '/api/mobile/contracts/${_id(contractId)}/reviews'));

  static Future<String> submitContractReview({
    required String contractId,
    required int soSao,
    int? tieuChi1,
    int? tieuChi2,
    String? nhanXet,
  }) => _action(
    'POST',
    '/api/mobile/contracts/${_id(contractId)}/review',
    body: {
      'soSao': soSao,
      'tieuChi1': ?tieuChi1,
      'tieuChi2': ?tieuChi2,
      if (nhanXet != null && nhanXet.isNotEmpty) 'nhanXet': nhanXet,
    },
  );

  static Future<Json> getLocationReviews(int locationId) async =>
      _map(await _data('GET', '/api/mobile/locations/$locationId/reviews'));

  static String getContractPdfUrl(String contractId) =>
      '${ApiConfig.baseUrl}/api/hop-dong/pdf/${_id(contractId)}';

  // ================= NGƯỜI NUÔI ONG =================

  static const _bk = '/api/mobile/beekeeping';

  static Future<Json> getBeekeepingDashboard() async =>
      _map(await _data('GET', '$_bk/dashboard'));

  static Future<List<Json>> getRentedLocations() async =>
      _list(await _data('GET', '$_bk/rented-locations'));

  static Future<String> createHive(Json payload) =>
      _action('POST', '$_bk/hives', body: payload);

  static Future<String> updateHive(String hiveId, Json payload) =>
      _action('PUT', '$_bk/hives/${_id(hiveId)}', body: payload);

  static Future<String> deleteHive(String hiveId) =>
      _action('DELETE', '$_bk/hives/${_id(hiveId)}');

  static Future<String> updateHiveLocation({
    required String hiveId,
    required double latitude,
    required double longitude,
    String? locationName,
  }) => _action(
    'PUT',
    '$_bk/hives/${_id(hiveId)}/location',
    body: {'viDo': latitude, 'kinhDo': longitude, 'viTri': ?locationName},
  );

  static Future<List<Json>> getGpsHistory(String hiveId) async =>
      _list(await _data('GET', '$_bk/hives/${_id(hiveId)}/gps-history'));

  static Future<String> addCareLog(Json payload) =>
      _action('POST', '$_bk/care-log', body: payload);

  static Future<String> updateCareStatus(String id, String status) => _action(
    'PUT',
    '$_bk/care-log/${_id(id)}/status',
    body: {'trangThai': status},
  );

  static Future<String> deleteCareLog(String id) =>
      _action('DELETE', '$_bk/care-log/${_id(id)}');

  static Future<String> addHiveMove(Json payload) =>
      _action('POST', '$_bk/move', body: payload);

  static Future<String> updateMoveStatus(String id, String status) => _action(
    'PUT',
    '$_bk/move/${_id(id)}/status',
    body: {'trangThai': status},
  );

  static Future<String> addProduction(Json payload) =>
      _action('POST', '$_bk/production', body: payload);

  static Future<List<Json>> getTraces() async =>
      _list(await _data('GET', '$_bk/traces'));

  static Future<List<Json>> getAvailableLocations() async =>
      _list(await _data('GET', '$_bk/locations'));

  static Future<List<Json>> getMyRentalRequests() async =>
      _list(await _data('GET', '$_bk/rental-requests'));

  static Future<String> createRentalRequest(Json payload) =>
      _action('POST', '$_bk/rental-requests', body: payload);

  static Future<String> cancelRentalRequest(String id) =>
      _action('PUT', '$_bk/rental-requests/${_id(id)}/cancel');

  // ================= CHỦ ĐẤT =================

  static const _lo = '/api/mobile/landowner';

  static Future<Json> getLandownerDashboard() async =>
      _map(await _data('GET', '$_lo/dashboard'));

  static Future<String> createLocation(Json payload) =>
      _action('POST', '$_lo/locations', body: payload);

  static Future<String> updateLocation(int id, Json payload) =>
      _action('PUT', '$_lo/locations/$id', body: payload);

  static Future<String> deleteLocation(int id) =>
      _action('DELETE', '$_lo/locations/$id');

  static Future<String> approveRentalRequest(
    String id, {
    num? giaThue,
    String? quyDinh,
  }) => _action(
    'PUT',
    '$_lo/rental-requests/${_id(id)}/approve',
    body: {'giaThue': ?giaThue, 'quyDinhBoiThuong': ?quyDinh},
  );

  static Future<String> rejectRentalRequest(String id, String reason) =>
      _action(
        'PUT',
        '$_lo/rental-requests/${_id(id)}/reject',
        body: {'lyDo': reason},
      );

  // Trả về baseUrl từ bộ giải quyết IP tự động ApiConfig
  static String get baseUrl => ApiConfig.baseUrl;

  // Hàm upload avatar hỗ trợ cả Web lẫn Android/iOS
  Future<bool> uploadAvatarBytes(Uint8List bytes, String filename) async {
    final base = await ApiConfig.resolve();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    final uri = Uri.parse('$base/api/mobile/profile/avatar');
    var request = http.MultipartRequest('POST', uri);

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Xác định mime-type dựa vào đuôi file
    String subType = 'jpeg';
    if (filename.toLowerCase().endsWith('.png')) {
      subType = 'png';
    } else if (filename.toLowerCase().endsWith('.webp')) {
      subType = 'webp';
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: filename,
        contentType: MediaType('image', subType),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return true;
    } else {
      throw ApiException('Lỗi upload avatar: ${response.body}');
    }
  }

  // ================= QUẢN TRỊ VIÊN =================

  static Future<Json> getAdminOverview() async =>
      _map(await _data('GET', '/api/mobile/admin/overview'));

  // ================= KHÁCH HÀNG (công khai, không cần đăng nhập) =================

  static Future<Json> getPublicTrace(int id) async {
    final decoded = await _send(
      'GET',
      '/api/public/truy-xuat/$id',
      auth: false,
    );
    return _map(decoded is Map ? decoded['data'] : null);
  }

  static Future<List<Json>> searchProducts(String keyword) async {
    final decoded = await _send(
      'GET',
      '/api/public/san-pham?q=${Uri.encodeQueryComponent(keyword)}',
      auth: false,
    );
    return _list(decoded is Map ? decoded['data'] : null);
  }

  /// Lấy mã lô từ nội dung QR: đường dẫn ".../truy-xuat-qr?ma=12" hoặc chỉ "12" / "#12".
  static int? parseTraceCode(String raw) {
    final text = raw.trim();
    final fromUrl = RegExp(r'[?&](?:ma|id)=(\d+)').firstMatch(text);
    if (fromUrl != null) return int.tryParse(fromUrl.group(1)!);
    final plain = RegExp(r'^#?(\d+)$').firstMatch(text);
    return plain == null ? null : int.tryParse(plain.group(1)!);
  }

  static String publicTraceUrl(int id) =>
      '${ApiConfig.baseUrl}/truy-xuat-qr?ma=$id';

  // ================= TIN NHẮN =================
  // Máy chủ xác định người gửi từ token; senderId chỉ giữ để tương thích màn hình chat.

  static Future<List<Json>> getChatConversations({required int userId}) async =>
      _list(await _data('GET', '/api/chat/danh-sach'));

  static Future<List<Json>> getChatHistory({
    required int senderId,
    required int receiverId,
  }) async =>
      _list(await _data('GET', '/api/chat/lich-su?maNguoiNhan=$receiverId'));

  static Future<String> sendChatMessage({
    required int senderId,
    required int receiverId,
    required String message,
  }) => _action(
    'POST',
    '/api/chat/gui',
    body: {'maNguoiNhan': receiverId, 'noiDung': message},
  );

  /// Lấy toàn bộ phản hồi lịch sử chat kèm thông tin đối tác
  static Future<Map<String, dynamic>?> getChatHistoryFull({
    required int receiverId,
  }) async {
    try {
      final decoded = await _send('GET', '/api/chat/lich-su?maNguoiNhan=$receiverId');
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Lấy thông tin chi tiết đối tác chat (SĐT, tên, vai trò, avatar, online)
  static Future<Json?> getPartnerInfo(int partnerId) async {
    try {
      final res = await _data('GET', '/api/chat/partner/$partnerId');
      return _map(res);
    } catch (_) {
      return null;
    }
  }

  /// Thu hồi tin nhắn chat đã gửi
  static Future<String> revokeChatMessage(int messageId) => _action(
    'POST',
    '/api/chat/thu-hoi/$messageId',
    body: {'maTinNhan': messageId},
  );

  /// Tải ảnh chat lên máy chủ và trả về đường dẫn tương đối (ví dụ: /uploads/chat/chat-xxx.jpg)
  static Future<String> uploadChatImage(Uint8List bytes, String filename) async {
    final base = await ApiConfig.resolve();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    final uri = Uri.parse('$base/api/chat/upload-anh');
    final request = http.MultipartRequest('POST', uri);

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Làm sạch tên file và bảo đảm có đuôi mở rộng hợp lệ (tránh ký tự ':' trên Android MediaStore)
    String cleanName = filename.split('/').last.split('\\').last.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    if (cleanName.isEmpty) {
      cleanName = 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }

    String subType = 'jpeg';
    final lowerName = cleanName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      subType = 'png';
    } else if (lowerName.endsWith('.webp')) {
      subType = 'webp';
    } else if (lowerName.endsWith('.gif')) {
      subType = 'gif';
    } else {
      if (!lowerName.endsWith('.jpg') && !lowerName.endsWith('.jpeg')) {
        cleanName = '$cleanName.jpg';
      }
      subType = 'jpeg';
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: cleanName,
        contentType: MediaType('image', subType),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true && decoded['imageUrl'] != null) {
        return decoded['imageUrl'].toString();
      }
      throw ApiException(decoded['message']?.toString() ?? 'Tải ảnh thất bại');
    } else {
      try {
        final errJson = jsonDecode(response.body);
        if (errJson is Map && errJson['message'] != null) {
          throw ApiException(errJson['message'].toString());
        }
      } catch (_) {}
      throw ApiException('Lỗi tải ảnh lên máy chủ (mã lỗi ${response.statusCode})');
    }
  }

  /// Lấy tổng số tin nhắn chưa đọc của người dùng hiện tại
  static Future<int> getTotalUnreadChatCount() async {
    try {
      final currentUserId = await getCurrentUserId();
      if (currentUserId == null) return 0;
      final conversations = await getChatConversations(userId: currentUserId);
      int unread = 0;
      for (final conv in conversations) {
        unread += int.tryParse('${conv['soTinChuaDoc']}') ?? 0;
      }
      return unread;
    } catch (_) {
      return 0;
    }
  }

  /// Tìm kiếm người dùng có trong database phục vụ nhắn tin
  static Future<List<Json>> searchChatUsers(String query) async {
    try {
      final res = await _data('GET', '/api/chat/tim-kiem-nguoi-dung?q=${Uri.encodeComponent(query)}');
      return _list(res);
    } catch (_) {
      return [];
    }
  }

  /// Gửi tín hiệu trực tuyến (heartbeat) giữ kết nối online
  static Future<void> sendChatHeartbeat() async {
    try {
      await _data('POST', '/api/chat/heartbeat');
    } catch (_) {}
  }

  /// Tra cứu địa chỉ từ toạ độ (Reverse Geocode Proxy không bị chặn CORS)
  static Future<String?> reverseGeocode(double lat, double lon) async {
    try {
      final res = await get('/api/public/reverse-geocode?lat=$lat&lon=$lon', auth: false);
      if (res is Map && res['success'] == true) {
        return res['data']?['display_name']?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// Tìm kiếm địa điểm, địa chỉ theo từ khoá (Geocode Proxy không bị chặn CORS)
  static Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      final res = await get('/api/public/geocode?q=${Uri.encodeComponent(query)}', auth: false);
      if (res is Map && res['success'] == true) {
        final list = res['data'] as List? ?? [];
        return list.map((item) {
          final lat = double.tryParse('${item['lat']}') ?? 0.0;
          final lon = double.tryParse('${item['lon']}') ?? 0.0;
          return {
            'display_name': item['display_name']?.toString() ?? '',
            'lat': lat,
            'lon': lon,
          };
        }).where((e) => (e['display_name'] as String).isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Lấy thông tin thời tiết nhiệt độ & độ ẩm qua backend proxy (tránh CORS trên Web)
  static Future<Map<String, dynamic>?> getWeather(double lat, double lon) async {
    try {
      final res = await get('/api/public/weather?lat=$lat&lon=$lon', auth: false);
      if (res is Map && res['success'] == true) {
        return res['data']?['current'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }
}

