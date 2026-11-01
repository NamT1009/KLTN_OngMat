import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const [
      'email',
      'profile',
    ],
  );

  /// Mở giao diện chọn tài khoản Google trên thiết bị
  static Future<GoogleSignInAccount?> signIn() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      return await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('>>> [GoogleAuthService] Lỗi khi đăng nhập bằng Google: $e');
      rethrow;
    }
  }

  /// Đăng xuất khỏi Google
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  /// Kiểm tra xem người dùng hiện tại đã đăng nhập tài khoản Google chưa
  static Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (_) {
      return false;
    }
  }
}
