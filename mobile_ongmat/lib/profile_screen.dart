import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'services/api_service.dart';
import 'widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService apiService = ApiService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String? _avatarBase64;
  String? _avatarUrl;
  String _roleCode = '';
  String _roleName = 'Khách hàng';
  String _accountStatus = 'HoatDong';
  String _createdAt = '';
  int? _userId;
  Map<String, dynamic> _stats = {};

  num? _rating;
  int _reviewCount = 0;
  bool _isNew = true;
  List<Map<String, dynamic>> _reviews = [];

  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _enablePasswordChange = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Tải dữ liệu cá nhân từ Database thông qua ApiService
  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.get('/api/mobile/profile');

      if (res != null) {
        Map<String, dynamic> data = {};
        if (res is Map<String, dynamic>) {
          data = (res.containsKey('data') && res['data'] is Map<String, dynamic>)
              ? res['data']
              : res;
        }

        setState(() {
          _userId = int.tryParse('${data['maNguoiDung']}');
          _nameController.text = (data['hoTen'] ?? data['tenNguoiDung'] ?? '').toString();
          _phoneController.text = (data['soDienThoai'] ?? data['sdt'] ?? '').toString();
          _emailController.text = (data['email'] ?? '').toString();
          _accountStatus = (data['trangThaiTaiKhoan'] ?? 'HoatDong').toString();
          _createdAt = (data['ngayTao'] ?? '').toString();

          final role = (data['vaiTro'] ?? '').toString().toLowerCase();
          _roleCode = role;
          if (role == 'chudat' || role == 'chu_dat') {
            _roleName = 'Chủ đất & Vườn cây';
          } else if (role == 'nguoinuoiong' || role == 'nuoiong' || role == 'nuoi_ong') {
            _roleName = 'Người nuôi ong';
          } else if (role == 'admin') {
            _roleName = 'Quản trị viên hệ thống';
          } else {
            _roleName = 'Thành viên';
          }

          if (data['stats'] is Map<String, dynamic>) {
            _stats = Map<String, dynamic>.from(data['stats']);
          }

          _avatarUrl = (data['anhDaiDien'] ?? data['avatar'])?.toString();

          // Lấy thông tin đánh giá sao uy tín
          _rating = num.tryParse('${data['uyTin']}');
          _reviewCount = int.tryParse('${data['tongDanhGia']}') ?? 0;
          _isNew = data['laNguoiMoi'] == 1 ||
              data['laNguoiMoi'] == true ||
              _reviewCount == 0 ||
              _rating == null;

          if (data['danhSachDanhGia'] is List) {
            _reviews = List<Map<String, dynamic>>.from(
              (data['danhSachDanhGia'] as List).whereType<Map>(),
            );
          } else {
            _reviews = [];
          }
        });
      }
    } catch (e) {
      debugPrint('>>> LOI PROFILE: $e');
      if (mounted) showSnack(context, 'Lỗi tải hồ sơ: ${errorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Cập nhật dữ liệu cá nhân và mật khẩu
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final oldPass = _oldPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    // Nếu người dùng bật đổi mật khẩu hoặc đã nhập một trong các ô mật khẩu
    if (_enablePasswordChange || oldPass.isNotEmpty || newPass.isNotEmpty || confirmPass.isNotEmpty) {
      if (oldPass.isEmpty) {
        showSnack(context, 'Vui lòng nhập mật khẩu cũ (mật khẩu hiện tại)!', error: true);
        return;
      }
      if (newPass.isEmpty) {
        showSnack(context, 'Vui lòng nhập mật khẩu mới!', error: true);
        return;
      }
      if (newPass.length < 6) {
        showSnack(context, 'Mật khẩu mới phải có ít nhất 6 ký tự!', error: true);
        return;
      }
      if (newPass != confirmPass) {
        showSnack(context, 'Xác nhận mật khẩu mới không trùng khớp!', error: true);
        return;
      }
      if (oldPass == newPass) {
        showSnack(context, 'Mật khẩu mới không được trùng với mật khẩu cũ!', error: true);
        return;
      }
    }

    setState(() => _isSaving = true);

    final Map<String, dynamic> body = {
      'hoTen': _nameController.text.trim(),
      'soDienThoai': _phoneController.text.trim(),
      'email': _emailController.text.trim(),
    };

    if (newPass.isNotEmpty) {
      body['matKhauCu'] = oldPass;
      body['matKhauMoi'] = newPass;
    }

    if (_avatarBase64 != null) {
      body['anhDaiDien'] = _avatarBase64;
    }

    try {
      final res = await ApiService.put('/api/mobile/profile', body);
      _hasChanged = true;

      // Xóa mật khẩu đã nhập để bảo mật
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() => _enablePasswordChange = false);

      if (!mounted) return;
      final msg = res is Map && res['message'] != null
          ? res['message'].toString()
          : (newPass.isNotEmpty
              ? 'Cập nhật thông tin & đổi mật khẩu thành công!'
              : 'Cập nhật thông tin cá nhân thành công!');

      showSnack(context, msg);
      await _loadUserProfile();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Chọn ảnh và tải lên server
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() => _isLoading = true);
      try {
        final bytes = await pickedFile.readAsBytes();
        final filename = pickedFile.name.isNotEmpty
            ? pickedFile.name
            : 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';

        bool success = await apiService.uploadAvatarBytes(bytes, filename);

        if (success) {
          _hasChanged = true;
          if (!mounted) return;
          showSnack(context, 'Đã cập nhật ảnh đại diện thành công!');
          await _loadUserProfile();
        }
      } catch (e) {
        if (!mounted) return;
        showSnack(context, 'Lỗi cập nhật ảnh: ${errorText(e)}', error: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // Xác định nguồn ảnh đại diện (Base64 / Network)
  ImageProvider? _getAvatarProvider() {
    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      return MemoryImage(base64Decode(_avatarBase64!.split(',').last));
    }
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      if (_avatarUrl!.startsWith('data:image')) {
        return MemoryImage(base64Decode(_avatarUrl!.split(',').last));
      }

      String fullUrl = _avatarUrl!;
      if (!fullUrl.startsWith('http://') && !fullUrl.startsWith('https://')) {
        final host = ApiConfig.baseUrl;
        if (host.endsWith('/') && fullUrl.startsWith('/')) {
          fullUrl = '$host${fullUrl.substring(1)}';
        } else if (!host.endsWith('/') && !fullUrl.startsWith('/')) {
          fullUrl = '$host/$fullUrl';
        } else {
          fullUrl = '$host$fullUrl';
        }
      }
      return NetworkImage(
        '$fullUrl${fullUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    return null;
  }

  String _formatDisplayDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Chưa xác định';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _hasChanged);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFD97706)),
              )
            : CustomScrollView(
                slivers: [
                  _buildSliverHeader(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildQuickStatsCard(),
                            const SizedBox(height: 20),
                            _buildRatingAndReviewsCard(),
                            const SizedBox(height: 20),
                            _buildContactInfoCard(),
                            const SizedBox(height: 20),
                            _buildSecurityCard(),
                            const SizedBox(height: 20),
                            _buildSystemInfoCard(),
                            const SizedBox(height: 28),
                            _buildSaveButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Header nghệ thuật với Gradient mật ong, Avatar và Thanh Sao Uy Tín
  Widget _buildSliverHeader() {
    final displayName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Người Dùng';
    final email = _emailController.text.trim();

    return SliverAppBar(
      expandedHeight: 310,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFFD97706),
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: const Color.fromRGBO(255, 255, 255, 0.25),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context, _hasChanged),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: const Color.fromRGBO(255, 255, 255, 0.25),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              tooltip: 'Tải lại thông tin',
              onPressed: _loadUserProfile,
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFB45309), // Hổ phách đậm
                Color(0xFFD97706), // Vàng mật ong
                Color(0xFFF59E0B), // Cam ấm
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Vòng trang trí nền nhẹ nhàng
                Positioned(
                  top: -40,
                  right: -40,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.fromRGBO(255, 255, 255, 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -30,
                  left: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.fromRGBO(255, 255, 255, 0.06),
                    ),
                  ),
                ),

                // Nội dung Avatar, Tên và Sao Uy Tín
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    // Avatar với Glow border
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(0, 0, 0, 0.25),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: const Color(0xFFFEF3C7),
                            backgroundImage: _getAvatarProvider(),
                            child: _getAvatarProvider() == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 56,
                                    color: Color(0xFFD97706),
                                  )
                                : null,
                          ),
                        ),
                        // Nút chụp ảnh Camera Badge
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: InkWell(
                            onTap: _pickImage,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, 0.3),
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 17,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Họ tên
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color.fromRGBO(255, 255, 255, 0.85),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Hàng huy hiệu: Vai trò & Sao Đánh Giá Uy Tín
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        // Vai trò Chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 255, 255, 0.22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color.fromRGBO(255, 255, 255, 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _roleCode.contains('chu')
                                    ? Icons.landscape_rounded
                                    : (_roleCode.contains('nuoi')
                                        ? Icons.hive_rounded
                                        : Icons.admin_panel_settings_rounded),
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _roleName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Huy hiệu Sao Đánh Giá Uy Tín (Ngay trên thanh cá nhân)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: _isNew
                                ? const Color.fromRGBO(16, 185, 129, 0.28)
                                : const Color.fromRGBO(245, 158, 11, 0.32),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _isNew
                                  ? const Color.fromRGBO(16, 185, 129, 0.6)
                                  : const Color.fromRGBO(254, 240, 138, 0.7),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isNew ? Icons.eco_rounded : Icons.star_rounded,
                                color: _isNew ? const Color(0xFFA7F3D0) : const Color(0xFFFEF08A),
                                size: 15,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isNew
                                    ? 'Người mới'
                                    : '${_rating?.toStringAsFixed(1) ?? '5.0'} ★ ($_reviewCount ĐG)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // 5 Ngôi sao vàng trực tiếp lấp lánh trên thanh header
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 1; i <= 5; i++)
                          Icon(
                            _isNew
                                ? Icons.star_border_rounded
                                : (i <= (_rating ?? 5).floor()
                                    ? Icons.star_rounded
                                    : (i - (_rating ?? 5) < 1
                                        ? Icons.star_half_rounded
                                        : Icons.star_border_rounded)),
                            color: const Color(0xFFFEF08A),
                            size: 16,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          _isNew ? 'Chưa có sao' : '${_rating?.toStringAsFixed(1) ?? '5.0'}/5.0',
                          style: const TextStyle(
                            color: Color(0xFFFEF08A),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Thẻ thống kê nhanh nổi bật (Quick Stats)
  Widget _buildQuickStatsCard() {
    final isLandowner = _roleCode.contains('chu');
    final isBeekeeper = _roleCode.contains('nuoi');

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.04),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(
            icon: Icons.verified_rounded,
            iconColor: Colors.green,
            label: 'Trạng thái',
            value: _accountStatus == 'HoatDong' ? 'Đang hoạt động' : _accountStatus,
          ),
          Container(width: 1, height: 35, color: Colors.grey.shade200),
          if (isLandowner) ...[
            _statItem(
              icon: Icons.park_rounded,
              iconColor: const Color(0xFFD97706),
              label: 'Vườn đất',
              value: '${_stats['tongDiaDiem'] ?? 0} khu',
            ),
          ] else if (isBeekeeper) ...[
            _statItem(
              icon: Icons.hive_rounded,
              iconColor: const Color(0xFFD97706),
              label: 'Tổng đàn ong',
              value: '${_stats['tongDanOng'] ?? 0} đàn',
            ),
          ] else ...[
            _statItem(
              icon: Icons.security_rounded,
              iconColor: Colors.indigo,
              label: 'Quyền hạn',
              value: 'Toàn quyền',
            ),
          ],
          Container(width: 1, height: 35, color: Colors.grey.shade200),
          _statItem(
            icon: Icons.star_rounded,
            iconColor: Colors.amber,
            label: 'Đánh giá uy tín',
            value: _isNew ? 'Người mới' : '${_rating?.toStringAsFixed(1) ?? '5.0'} ★',
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // Thẻ Đánh Giá & Uy Tín Cá Nhân (Hiển thị chi tiết số sao của người dùng)
  Widget _buildRatingAndReviewsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.04),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đánh Giá & Điểm Sao Uy Tín',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Điểm đánh giá sao từ các đối tác trên hệ thống',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Khung điểm sao nổi bật
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Text(
                      _isNew ? '🌱' : (_rating?.toStringAsFixed(1) ?? '5.0'),
                      style: TextStyle(
                        fontSize: _isNew ? 32 : 36,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFB45309),
                      ),
                    ),
                    if (!_isNew)
                      const Text(
                        'trên 5.0',
                        style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                      ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (int i = 1; i <= 5; i++)
                            Icon(
                              _isNew
                                  ? Icons.star_border_rounded
                                  : (i <= (_rating ?? 5).floor()
                                      ? Icons.star_rounded
                                      : (i - (_rating ?? 5) < 1
                                          ? Icons.star_half_rounded
                                          : Icons.star_border_rounded)),
                              color: const Color(0xFFD97706),
                              size: 24,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isNew
                            ? 'Tài khoản mới chưa có lượt đánh giá nào.'
                            : '$_reviewCount lượt đánh giá uy tín được ghi nhận.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_isNew) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF059669), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Khi bạn hoàn thành các hợp đồng thuê vườn hoặc khai thác đàn ong, đối tác sẽ gửi đánh giá sao cho bạn!',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF047857)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_reviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Nhận xét gần đây:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 8),
            ..._reviews.map((rv) {
              final stars = int.tryParse('${rv['soSao']}') ?? 5;
              final reviewer = show(rv['nguoiDanhGia'], 'Đối tác');
              final date = show(rv['ngayTao']);
              final comment = show(rv['nhanXet'], 'Không có nhận xét');

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          reviewer,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Row(
                          children: [
                            for (int i = 0; i < stars; i++)
                              const Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 14),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comment,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          date,
                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // Thẻ Thông Tin Liên Hệ
  Widget _buildContactInfoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.04),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Thông Tin Cá Nhân',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Họ và tên
          TextFormField(
            controller: _nameController,
            decoration: _inputDecoration(
              label: 'Họ và tên *',
              hint: 'Nhập họ và tên đầy đủ',
              prefixIcon: Icons.person_outline_rounded,
            ),
            validator: (val) => (val == null || val.trim().isEmpty)
                ? 'Vui lòng nhập họ và tên'
                : null,
          ),
          const SizedBox(height: 16),

          // Số điện thoại
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration(
              label: 'Số điện thoại *',
              hint: 'Nhập số điện thoại liên hệ',
              prefixIcon: Icons.phone_iphone_rounded,
            ),
            validator: (val) => (val == null || val.trim().isEmpty)
                ? 'Vui lòng nhập số điện thoại'
                : null,
          ),
          const SizedBox(height: 16),

          // Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration(
              label: 'Địa chỉ Email *',
              hint: 'example@gmail.com',
              prefixIcon: Icons.alternate_email_rounded,
            ),
            validator: (val) => (val == null || !val.contains('@'))
                ? 'Địa chỉ email không hợp lệ'
                : null,
          ),
          const SizedBox(height: 16),

          // Vai trò (Readonly card)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vai trò hệ thống',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Text(
                        _roleName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.lock_rounded, size: 16, color: Colors.grey.shade400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Thẻ Bảo Mật & Đổi Mật Khẩu (Được thiết kế rất trực quan theo đúng yêu cầu)
  Widget _buildSecurityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.04),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bảo Mật & Mật Khẩu',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Đổi mật khẩu truy cập tài khoản an toàn',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              // Nút bật/tắt chế độ đổi mật khẩu
              Switch.adaptive(
                value: _enablePasswordChange,
                activeTrackColor: const Color(0xFFF59E0B),
                activeThumbColor: const Color(0xFFD97706),
                onChanged: (val) {
                  setState(() {
                    _enablePasswordChange = val;
                    if (!val) {
                      _oldPasswordController.clear();
                      _newPasswordController.clear();
                      _confirmPasswordController.clear();
                    }
                  });
                },
              ),
            ],
          ),

          if (!_enablePasswordChange) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gạt công tắc phía trên nếu bạn muốn cập nhật mật khẩu mới.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            // Hướng dẫn bảo mật
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_clock_outlined, size: 18, color: Color(0xFFD97706)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bắt buộc nhập chính xác Mật khẩu cũ (mật khẩu hiện tại) để xác thực chủ tài khoản trước khi đổi mật khẩu mới.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. MẬT KHẨU CŨ (HIỆN TẠI)
            TextFormField(
              controller: _oldPasswordController,
              obscureText: _obscureOldPassword,
              decoration: _inputDecoration(
                label: 'Mật khẩu cũ (hiện tại) *',
                hint: 'Nhập mật khẩu bạn đang dùng',
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOldPassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureOldPassword = !_obscureOldPassword),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. MẬT KHẨU MỚI
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscureNewPassword,
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration(
                label: 'Mật khẩu mới *',
                hint: 'Tối thiểu 6 ký tự',
                prefixIcon: Icons.key_rounded,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. XÁC NHẬN MẬT KHẨU MỚI
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration(
                label: 'Xác nhận mật khẩu mới *',
                hint: 'Nhập lại mật khẩu mới',
                prefixIcon: Icons.lock_reset_rounded,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Checklist yêu cầu mật khẩu
            _buildPasswordChecklist(),
          ],
        ],
      ),
    );
  }

  // Checklist trực quan kiểm tra độ dài và độ khớp của mật khẩu
  Widget _buildPasswordChecklist() {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;
    final isLongEnough = newPass.length >= 6;
    final isMatching = newPass.isNotEmpty && newPass == confirmPass;

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isLongEnough ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 15,
                color: isLongEnough ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                'Mật khẩu có ít nhất 6 ký tự',
                style: TextStyle(
                  fontSize: 12,
                  color: isLongEnough ? Colors.green.shade700 : Colors.grey.shade600,
                  fontWeight: isLongEnough ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isMatching ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 15,
                color: isMatching ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                'Mật khẩu xác nhận trùng khớp',
                style: TextStyle(
                  fontSize: 12,
                  color: isMatching ? Colors.green.shade700 : Colors.grey.shade600,
                  fontWeight: isMatching ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Thẻ thông tin tài khoản (ID, ngày tạo)
  Widget _buildSystemInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Mã ID tài khoản', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text(
                _userId != null ? '#${_userId.toString().padLeft(4, '0')}' : '#0000',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
              ),
            ],
          ),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ngày đăng ký tham gia', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text(
                _formatDisplayDate(_createdAt),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Nút Lưu Thay Đổi dạng Gradient
  Widget _buildSaveButton() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(245, 158, 11, 0.35),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Lưu Thay Đổi',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Style viền input chung hiện đại
  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(prefixIcon, color: const Color(0xFFD97706), size: 20),
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.8),
      ),
    );
  }
}
