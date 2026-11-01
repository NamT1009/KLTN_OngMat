import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';
import 'services/api_service.dart';
import 'trace_lookup_screen.dart';
import 'widgets/common.dart';
import 'widgets/otp_dialog.dart';
import 'services/google_auth_service.dart';

String normalizeAppRole(String? rawRole) {
  final compact = (rawRole ?? '')
      .toLowerCase()
      .replaceAll('đ', 'd')
      .replaceAll(RegExp(r'[^a-z]'), '');
  if (compact == 'chudat' || compact == 'chudatrole') return 'chuDat';
  if (compact == 'admin' || compact == 'quantrivien') return 'admin';
  // Giá trị lạ được đưa về người nuôi ong để không mở nhầm giao diện quản trị / chủ đất.
  return 'nguoiNuoiOng';
}

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Không có .env vẫn chạy được với danh sách địa chỉ mặc định.
  }
  ApiService.onUnauthorized = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(sessionExpired: true),
      ),
      (_) => false,
    );
  };
  runApp(const OngMatApp());
}

class OngMatApp extends StatelessWidget {
  const OngMatApp({super.key, this.home});
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Truy Vết Ong Mật',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kHoney,
          primary: kHoneyDark,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: kBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kHoney, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade400),
          ),
          labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
          prefixIconColor: const Color(0xFF64748B),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: home ?? const SplashScreen(),
    );
  }
}

/// Kiểm tra phiên đăng nhập đã lưu để vào thẳng trang chủ.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final loggedIn = await ApiService.hasSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => loggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55F59E0B),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.hive_rounded,
                size: 54,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'TRUY VẾT ONG MẬT',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hệ Thống Chuỗi Cung Ứng & Giám Sát Tổ Ong',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Ambient Warm Honey Glow Orbs
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF59E0B).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFD97706).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      // Honeybee Badge Logo
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFD97706)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x35F59E0B),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.hive_rounded,
                          size: 46,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x08000000),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.sessionExpired = false});
  final bool sessionExpired;

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taiKhoanController = TextEditingController();
  final _matKhauController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.sessionExpired) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showSnack(
          context,
          'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.',
        ),
      );
    }
  }

  @override
  void dispose() {
    _taiKhoanController.dispose();
    _matKhauController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.login(
        taiKhoan: _taiKhoanController.text.trim(),
        matKhau: _matKhauController.text,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'vaiTro',
        normalizeAppRole(data['user']?['vaiTro']?.toString()),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final account = await GoogleAuthService.signIn();
      if (account == null) {
        setState(() => _isGoogleLoading = false);
        if (mounted) {
          showSnack(
            context,
            'Tài khoản Gmail không tồn tại hoặc bạn chưa chọn tài khoản.',
            error: true,
          );
        }
        return;
      }

      final data = await ApiService.loginWithGoogle(
        email: account.email,
        hoTen: account.displayName ?? account.email.split('@')[0],
        googleId: account.id,
        avatarUrl: account.photoUrl,
        vaiTro: 'nguoiNuoiOng',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'vaiTro',
        normalizeAppRole(data['user']?['vaiTro']?.toString()),
      );

      if (!mounted) return;
      showSnack(context, 'Đăng nhập bằng tài khoản Google thành công!');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (mounted) {
        final err = errorText(e);
        if (err.contains('ApiException: 10') || err.contains('10:')) {
          _showGoogleSetupGuide(context);
        } else if (err.toLowerCase().contains('sign_in_canceled') ||
            err.toLowerCase().contains('not found') ||
            err.toLowerCase().contains('canceled')) {
          showSnack(
            context,
            'Tài khoản Gmail không tồn tại hoặc bạn đã hủy đăng nhập.',
            error: true,
          );
        } else {
          showSnack(context, 'Lỗi đăng nhập Google: $err', error: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Đăng Nhập Hệ Thống',
      subtitle: 'Ứng Dụng Chuỗi Cung Ứng & Truy Vết Ong Mật',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _taiKhoanController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email hoặc số điện thoại',
                hintText: 'admin@ongmat.vn hoặc số điện thoại',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Nhập email hoặc số điện thoại'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _matKhauController,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                hintText: 'Nhập mật khẩu của bạn',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Nhập mật khẩu' : null,
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3DF59E0B),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (_isLoading || _isGoogleLoading) ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF0F172A),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'ĐĂNG NHẬP',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              ),
              child: RichText(
                text: const TextSpan(
                  text: 'Chưa có tài khoản đối tác? ',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                  children: [
                    TextSpan(
                      text: 'Đăng ký ngay',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'HOẶC',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade400,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey.shade300)),
              ],
            ),
            const SizedBox(height: 14),
            _GoogleSignInButton(
              label: 'Đăng nhập nhanh bằng Google',
              isLoading: _isGoogleLoading,
              onPressed: (_isLoading || _isGoogleLoading) ? null : _loginWithGoogle,
            ),
            const Divider(height: 28),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TraceLookupScreen()),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF16A34A), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Khách hàng: Tra cứu nguồn gốc mật ong',
                          style: TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'nguoiNuoiOng';
  bool _loading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final phone = _phone.text.replaceAll(' ', '').trim();
    final email = _email.text.trim().toLowerCase();

    // 1. Kiểm tra tính hợp lệ của Gmail
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      showSnack(context, 'Tài khoản Gmail không tồn tại hoặc không đúng định dạng', error: true);
      return;
    }
    if (email.endsWith('@gmail.com')) {
      final namePart = email.split('@')[0];
      if (namePart.length < 6 || namePart.length > 30 || !RegExp(r'^[a-z0-9.]+$').hasMatch(namePart) || namePart.startsWith('.') || namePart.endsWith('.') || namePart.contains('..')) {
        showSnack(context, 'Tài khoản Gmail không tồn tại hoặc không đúng định dạng', error: true);
        return;
      }
    }

    // 2. Hiện loading khi gửi mã OTP qua Gmail
    setState(() => _loading = true);

    try {
      final sendRes = await ApiService.sendOtp(
        email: email,
        soDienThoai: phone,
        loaiHanhDong: 'DANG_KY',
      );

      setState(() => _loading = false);

      if (sendRes['success'] != true) {
        if (mounted) {
          showSnack(
            context,
            sendRes['message'] ?? 'Tài khoản Gmail không tồn tại hoặc không gửi được mã xác thực.',
            error: true,
          );
        }
        return;
      }

      // 3. Mở Dialog nhập mã xác thực OTP gửi về Gmail
      if (!mounted) return;
      final isOtpValid = await showOtpDialog(
        context: context,
        email: email,
        soDienThoai: phone,
        loaiHanhDong: 'DANG_KY',
      );

      // 4. Nếu nhập đúng OTP -> Tiến hành đăng ký tài khoản
      if (isOtpValid == true) {
        setState(() => _loading = true);

        final data = await ApiService.register(
          hoTen: _name.text.trim(),
          email: email,
          soDienThoai: phone,
          matKhau: _password.text,
          vaiTro: _role,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'vaiTro',
          normalizeAppRole(data['user']?['vaiTro']?.toString()),
        );

        if (!mounted) return;
        showSnack(context, 'Chúc mừng bạn! Đăng ký tài khoản thành công.');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final err = errorText(e);
        if (err.contains('550') ||
            err.contains('5.1.1') ||
            err.toLowerCase().contains('không tồn tại') ||
            err.toLowerCase().contains('not found') ||
            err.toLowerCase().contains('does not exist')) {
          showSnack(
            context,
            'Tài khoản Gmail không tồn tại. Vui lòng kiểm tra lại!',
            error: true,
          );
        } else {
          showSnack(context, err, error: true);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final account = await GoogleAuthService.signIn();
      if (account == null) {
        setState(() => _isGoogleLoading = false);
        if (mounted) {
          showSnack(
            context,
            'Tài khoản Gmail không tồn tại hoặc bạn chưa chọn tài khoản.',
            error: true,
          );
        }
        return;
      }

      final data = await ApiService.loginWithGoogle(
        email: account.email,
        hoTen: account.displayName ?? account.email.split('@')[0],
        googleId: account.id,
        avatarUrl: account.photoUrl,
        vaiTro: _role,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'vaiTro',
        normalizeAppRole(data['user']?['vaiTro']?.toString()),
      );

      if (!mounted) return;
      showSnack(context, 'Đăng ký tài khoản Google thành công!');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        final err = errorText(e);
        if (err.contains('ApiException: 10') || err.contains('10:')) {
          _showGoogleSetupGuide(context);
        } else if (err.toLowerCase().contains('sign_in_canceled') ||
            err.toLowerCase().contains('not found') ||
            err.toLowerCase().contains('canceled')) {
          showSnack(
            context,
            'Tài khoản Gmail không tồn tại hoặc thao tác đã bị hủy.',
            error: true,
          );
        } else {
          showSnack(context, 'Lỗi đăng ký bằng Google: $err', error: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Tạo tài khoản',
      subtitle: 'Dành cho chủ đất và người nuôi ong',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'nguoiNuoiOng',
                  icon: Icon(Icons.hive_outlined),
                  label: Text('Nuôi ong'),
                ),
                ButtonSegment(
                  value: 'chuDat',
                  icon: Icon(Icons.landscape_outlined),
                  label: Text('Chủ đất'),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (value) =>
                  setState(() => _role = value.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Họ tên',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Nhập họ tên' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ Gmail (nhận mã OTP)',
                hintText: 'vidu@gmail.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return 'Vui lòng nhập địa chỉ Gmail';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(val)) {
                  return 'Tài khoản Gmail không tồn tại hoặc không đúng định dạng';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) =>
                  RegExp(r'^0\d{9,10}$').hasMatch((v ?? '').replaceAll(' ', ''))
                  ? null
                  : 'Số điện thoại 10-11 số, bắt đầu bằng 0',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              validator: (v) => (v ?? '').trim().length < 6
                  ? 'Mật khẩu tối thiểu 6 ký tự'
                  : null,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3DF59E0B),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (_loading || _isGoogleLoading) ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF0F172A),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'ĐĂNG KÝ (XÁC THỰC GMAIL)',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: RichText(
                text: const TextSpan(
                  text: 'Đã có tài khoản? ',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                  children: [
                    TextSpan(
                      text: 'Đăng nhập ngay',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'HOẶC',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey.shade300)),
              ],
            ),
            const SizedBox(height: 14),
            _GoogleSignInButton(
              label: 'Đăng ký nhanh bằng Google',
              isLoading: _isGoogleLoading,
              onPressed: (_loading || _isGoogleLoading) ? null : _registerWithGoogle,
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút bấm Google Sign-In chuẩn Material với logo Google 4 màu
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F2937),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGoogleIcon(),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            fontFamily: 'sans-serif',
            foreground: Paint()
              ..shader = const LinearGradient(
                colors: [
                  Color(0xFF4285F4),
                  Color(0xFFEA4335),
                  Color(0xFFFBBC05),
                  Color(0xFF34A853),
                ],
              ).createShader(const Rect.fromLTWH(0, 0, 20, 20)),
          ),
        ),
      ),
    );
  }
}

/// Hộp thoại thông báo khi Google Sign-In trên thiết bị Android cần cấu hình SHA-1
void _showGoogleSetupGuide(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFFD97706)),
          SizedBox(width: 8),
          Expanded(child: Text('Cấu hình Google Sign-In')),
        ],
      ),
      content: const Text(
        'Tính năng Đăng nhập bằng Google trên Android yêu cầu thêm mã SHA-1 fingerprint của máy tính vào dự án Firebase Console / Google Cloud Console.\n\n'
        'Hiện tại bạn hoàn toàn có thể đăng ký bằng Gmail và nhận mã xác thực OTP gửi về hòm thư Gmail ngay lập tức!',
        style: TextStyle(fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );
}

