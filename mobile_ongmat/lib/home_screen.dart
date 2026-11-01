import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';
import 'beekeeping_dashboard_screen.dart';
import 'chat_hub_screen.dart';
import 'contract_screen.dart';
import 'landowner_screen.dart';
import 'main.dart';
import 'map_screen.dart';
import 'notifications_screen.dart';
import 'qr_sync_screen.dart';
import 'rental_request_screen.dart';
import 'services/api_service.dart';
import 'trace_lookup_screen.dart';
import 'widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class _MenuItem {
  const _MenuItem(
    this.title,
    this.icon,
    this.color,
    this.builder, {
    this.badge = 0,
  });
  final String title;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  final int badge;
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _vaiTro = '';
  String _tenNguoiDung = 'Người dùng';
  String? _avatarUrl;
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;
  int _unreadChatCount = 0;
  Timer? _chatCheckTimer;
  int _navIndex = 0;
  final ScrollController _scrollController = ScrollController();
  num? _uyTin;
  int _tongDanhGia = 0;
  bool _laNguoiMoi = true;

  bool get _isLandowner => _vaiTro == 'chuDat';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();

    // Định kỳ kiểm tra tin nhắn mới và hiển thị thông báo
    _chatCheckTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      try {
        final chatUnread = await ApiService.getTotalUnreadChatCount();
        if (mounted && chatUnread != _unreadChatCount) {
          if (chatUnread > _unreadChatCount) {
            HapticFeedback.mediumImpact();
            showTopNotification(
              context,
              title: 'Tin nhắn mới',
              message: 'Bạn có $chatUnread tin nhắn mới chưa đọc!',
              icon: Icons.mark_chat_unread_rounded,
              iconColor: const Color(0xFF38BDF8),
              actionLabel: 'Xem',
              onAction: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatHubScreen()),
                );
              },
            );
          }
          setState(() {
            _unreadChatCount = chatUnread;
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _chatCheckTimer?.cancel();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mở lại ứng dụng thì đồng bộ số liệu mới nhất (thay đổi từ web hoặc người dùng khác).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _vaiTro.isNotEmpty &&
        _vaiTro != 'admin') {
      _load();
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _vaiTro = normalizeAppRole(prefs.getString('vaiTro'));
      _tenNguoiDung = prefs.getString('hoTen') ?? 'Người dùng';
      _avatarUrl = prefs.getString('anhDaiDien') ?? prefs.getString('avatar');
    });
    if (_vaiTro != 'admin') await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1. Tải số liệu thống kê Dashboard theo vai trò
      final data = _isLandowner
          ? await ApiService.getLandownerDashboard()
          : await ApiService.getBeekeepingDashboard();

      // 2. Tải thông tin cá nhân mới nhất để lấy Avatar và Tên
      final profileRes = await ApiService.get('/api/mobile/profile');
      Map<String, dynamic> profileData = {};
      if (profileRes != null) {
        if (profileRes is Map<String, dynamic>) {
          profileData =
              (profileRes.containsKey('data') &&
                  profileRes['data'] is Map<String, dynamic>)
              ? profileRes['data']
              : profileRes;
        }
      }

      // 3. Tải tổng số tin nhắn chưa đọc
      final chatUnread = await ApiService.getTotalUnreadChatCount();

      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
        _unreadChatCount = chatUnread;
        if (profileData.isNotEmpty) {
          final ten = (profileData['hoTen'] ?? profileData['tenNguoiDung'])
              ?.toString();
          if (ten != null && ten.isNotEmpty) _tenNguoiDung = ten;
          _avatarUrl = (profileData['anhDaiDien'] ?? profileData['avatar'])
              ?.toString();
          _uyTin = num.tryParse('${profileData['uyTin']}');
          _tongDanhGia = int.tryParse('${profileData['tongDanhGia']}') ?? 0;
          _laNguoiMoi = profileData['laNguoiMoi'] == 1 ||
              profileData['laNguoiMoi'] == true ||
              _tongDanhGia == 0 ||
              _uyTin == null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _n(String key) => int.tryParse('${_summary[key] ?? 0}') ?? 0;

  Future<void> _open(WidgetBuilder builder) async {
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    if (mounted) {
      _load(); // số liệu luôn cập nhật sau khi thao tác ở màn hình con
    }
  }

  Future<void> _onBottomNavSelected(int index) async {
    if (index == 0) {
      if (_navIndex != 0) {
        setState(() => _navIndex = 0);
      }
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    setState(() => _navIndex = index);
    try {
      if (index == 1) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
      } else if (index == 2) {
        if (_isLandowner) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LandownerScreen()),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BeekeepingDashboardScreen()),
          );
        }
      } else if (index == 3) {
        if (_isLandowner) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LandownerScreen(initialTab: 1),
            ),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContractScreen()),
          );
        }
      } else if (index == 4) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _navIndex = 0);
        _load();
      }
    }
  }

  Future<void> _logout() async {
    if (!await confirmDialog(
      context,
      title: 'Đăng xuất?',
      message: 'Bạn sẽ cần đăng nhập lại để tiếp tục.',
      confirmLabel: 'Đăng xuất',
    )) {
      return;
    }
    await ApiService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // Widget hiển thị avatar tối ưu, chống cache và hỗ trợ icon dự phòng
  Widget _buildAvatar(
    String? avatarPath, {
    required double radius,
    required IconData fallbackIcon,
  }) {
    if (avatarPath != null && avatarPath.isNotEmpty) {
      String fullUrl = avatarPath;
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

      final cacheBustedUrl =
          '$fullUrl${fullUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';

      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(cacheBustedUrl),
        onBackgroundImageError: (_, _) {},
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withValues(alpha: 0.9),
      child: Icon(
        fallbackIcon,
        size: radius * 1.1,
        color: const Color(0xFFB07D00),
      ),
    );
  }

  List<_MenuItem> _menu() {
    final trace = _MenuItem(
      'Tra cứu nguồn gốc',
      Icons.qr_code_scanner_rounded,
      const Color(0xFF0EA5E9),
      (_) => const TraceLookupScreen(),
    );
    final notifications = _MenuItem(
      'Thông báo',
      Icons.notifications_active_rounded,
      const Color(0xFFEF4444),
      (_) => const NotificationsScreen(),
      badge: _n('unreadNotifications'),
    );

    if (_isLandowner) {
      // =========================================================
      // LUỒNG 2: NGHIỆP VỤ CHÍNH DÀNH CHO "CHỦ ĐẤT" (LANDLORD)
      // =========================================================
      return [
        _MenuItem(
          'Khu đất của tôi',
          Icons.landscape_rounded,
          const Color(0xFFEA580C),
          (_) => const LandownerScreen(),
        ),
        _MenuItem(
          'Duyệt yêu cầu thuê',
          Icons.rule_folder_rounded,
          const Color(0xFFEF4444),
          (_) => const LandownerScreen(initialTab: 1),
          badge: _n('pendingRequests'),
        ),
        _MenuItem(
          'Hợp đồng cho thuê',
          Icons.handshake_rounded,
          const Color(0xFF3B82F6),
          (_) => const ContractScreen(),
          badge: _n('contractsWaitingSign'),
        ),
        _MenuItem(
          'Giám sát đàn ong',
          Icons.hive_rounded,
          const Color(0xFFF59E0B),
          (_) => const LandownerScreen(initialTab: 2),
        ),
        _MenuItem(
          'Doanh thu & Sản lượng',
          Icons.payments_rounded,
          const Color(0xFF10B981),
          (_) => const LandownerScreen(initialTab: 3),
        ),
        _MenuItem(
          'Tin nhắn thợ ong',
          Icons.chat_bubble_rounded,
          const Color(0xFFF97316),
          (_) => const ChatHubScreen(),
          badge: _unreadChatCount,
        ),
        notifications,
        trace,
      ];
    }

    // =========================================================
    // LUỒNG 1: NGHIỆP VỤ CHÍNH DÀNH CHO "NGƯỜI NUÔI ONG" (BEEKEEPER)
    // =========================================================
    return [
      _MenuItem(
        'Tìm đất đặt ong',
        Icons.travel_explore_rounded,
        const Color(0xFF1E7B5F),
        (_) => const MapScreen(),
      ),
      _MenuItem(
        'Yêu cầu thuê đất',
        Icons.request_quote_rounded,
        const Color(0xFF0EA5E9),
        (_) => const MyRentalRequestsScreen(),
        badge: _n('pendingRequests'),
      ),
      _MenuItem(
        'Hợp đồng thuê đất',
        Icons.handshake_rounded,
        const Color(0xFF3B82F6),
        (_) => const ContractScreen(),
        badge: _n('contractsToSign'),
      ),
      _MenuItem(
        'Đàn ong & Thùng',
        Icons.hive_rounded,
        const Color(0xFFF59E0B),
        (_) => const BeekeepingDashboardScreen(),
      ),
      _MenuItem(
        'Lịch chăm sóc',
        Icons.calendar_month_rounded,
        const Color(0xFF22C55E),
        (_) => const BeekeepingDashboardScreen(initialTab: 1),
        badge: _n('careDueSoon'),
      ),
      _MenuItem(
        'Di chuyển đàn ong',
        Icons.route_rounded,
        const Color(0xFFF97316),
        (_) => const BeekeepingDashboardScreen(initialTab: 2),
        badge: _n('activeMoves'),
      ),
      _MenuItem(
        'Mã QR truy xuất',
        Icons.qr_code_2_rounded,
        const Color(0xFFFB7185),
        (_) => const QrSyncScreen(),
      ),
      _MenuItem(
        'Tin nhắn chủ đất',
        Icons.chat_bubble_rounded,
        const Color(0xFF14B8A6),
        (_) => const ChatHubScreen(),
        badge: _unreadChatCount,
      ),
      _MenuItem(
        'Sản lượng mật',
        Icons.bar_chart_rounded,
        const Color(0xFF8B5CF6),
        (_) => const BeekeepingDashboardScreen(initialTab: 3),
      ),
      notifications,
      trace,
    ];
  }

  List<Widget> _stats() {
    if (_isLandowner) {
      // THỐNG KÊ 2X2 DÀNH CHO CHỦ ĐẤT
      return [
        StatTile(
          label: 'Khu đất của tôi',
          value: '${_n('totalLocations')}',
          icon: Icons.landscape_rounded,
          color: const Color(0xFFEA580C),
        ),
        StatTile(
          label: 'Trại ong trên đất',
          value: '${_n('boxesOnLand')} thùng',
          icon: Icons.hive_rounded,
          color: const Color(0xFFF59E0B),
        ),
        StatTile(
          label: 'Yêu cầu chờ duyệt',
          value: '${_n('pendingRequests')}',
          icon: Icons.pending_actions_rounded,
          color: const Color(0xFFEF4444),
        ),
        StatTile(
          label: 'Hợp đồng hiệu lực',
          value: '${_n('activeContracts')}',
          icon: Icons.verified_rounded,
          color: const Color(0xFF3B82F6),
        ),
      ];
    }
    // THỐNG KÊ 2X2 DÀNH CHO NGƯỜI NUÔI ONG
    return [
      StatTile(
        label: 'Đàn ong',
        value: '${_n('totalHives')}',
        icon: Icons.hive_rounded,
        color: const Color(0xFFF59E0B),
      ),
      StatTile(
        label: 'Thùng ong',
        value: '${_n('totalBoxes')}',
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF1E7B5F),
      ),
      StatTile(
        label: 'Việc chăm sóc 48h',
        value: '${_n('careDueSoon')}',
        icon: Icons.event_note_rounded,
        color: const Color(0xFF22C55E),
      ),
      StatTile(
        label: 'Tổng sản lượng',
        value: '${formatNumber(_summary['totalProductionKg'])} kg',
        icon: Icons.water_drop_rounded,
        color: const Color(0xFF6366F1),
      ),
    ];
  }

  Widget? _alert() {
    final (text, icon, builder) = _isLandowner
        ? (_n('pendingRequests') > 0
              ? (
                  '🔔 Có ${_n('pendingRequests')} yêu cầu thuê đất mới đang chờ bạn duyệt.',
                  Icons.notification_important_rounded,
                  (BuildContext _) => const LandownerScreen(initialTab: 1),
                )
              : _n('waitingReview') > 0
              ? (
                  '⏳ ${_n('waitingReview')} địa điểm đất vườn đang chờ Admin kiểm duyệt.',
                  Icons.hourglass_top_rounded,
                  (BuildContext _) => const LandownerScreen(),
                )
              : _n('contractsWaitingSign') > 0
              ? (
                  '📝 Có ${_n('contractsWaitingSign')} hợp đồng thuê đất đang chờ ký kết.',
                  Icons.draw_rounded,
                  (BuildContext _) => const ContractScreen(),
                )
              : (null, null, null))
        : (_n('careDueSoon') > 0
              ? (
                  '⏰ Nhắc nhở: Có ${_n('careDueSoon')} việc chăm sóc đàn ong cần làm trong 48 giờ tới.',
                  Icons.alarm_on_rounded,
                  (BuildContext _) =>
                      const BeekeepingDashboardScreen(initialTab: 1),
                )
              : _n('contractsToSign') > 0
              ? (
                  '📝 Có ${_n('contractsToSign')} hợp đồng thuê đất đã duyệt, đang chờ bạn ký.',
                  Icons.draw_rounded,
                  (BuildContext _) => const ContractScreen(),
                )
              : (null, null, null));
    if (text == null) return null;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(builder!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFFD97706), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Color(0xFFB45309),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_vaiTro == 'admin') return const AdminHomeScreen();
    final alert = _alert();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _isLandowner
                        ? const Color(0xFFFFEDD5)
                        : const Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isLandowner
                        ? Icons.landscape_rounded
                        : Icons.hive_rounded,
                    color: _isLandowner
                        ? const Color(0xFFEA580C)
                        : const Color(0xFFD97706),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'QL_OngMat',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const Text(
              'Hệ thống Quản lý & Truy vết Đặt Ong Mật',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          // 1. NÚT AVATAR MỞ TRANG THÔNG TIN CÁ NHÂN (APPBAR)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
                if (changed == true || mounted) {
                  _load(); // Tải lại avatar và thông tin mới nhất
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isLandowner
                        ? const Color(0xFFF97316)
                        : const Color(0xFFF59E0B),
                    width: 1.8,
                  ),
                ),
                child: _buildAvatar(
                  _avatarUrl,
                  radius: 17,
                  fallbackIcon: Icons.person,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 2. NÚT ĐĂNG XUẤT
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B)),
            tooltip: 'Đăng xuất',
            onPressed: _logout,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: _isLandowner ? const Color(0xFFEA580C) : const Color(0xFFF59E0B),
        onRefresh: _load,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            // KHUNG CHÀO MỪNG THEO VAI TRÒ (MÀU SẮC NHẬN DIỆN VÀNG CAM ẤM ÁP)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isLandowner
                      ? [const Color(0xFFF59E0B), const Color(0xFFEA580C)] // Vàng cam ấm áp cho Chủ đất
                      : [const Color(0xFFF59E0B), const Color(0xFFD97706)], // Vàng mật ong ấm áp cho Thợ nuôi ong
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (_isLandowner
                            ? const Color(0xFFEA580C)
                            : const Color(0xFFF59E0B))
                        .withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildAvatar(
                      _avatarUrl,
                      radius: 30,
                      fallbackIcon: _isLandowner
                          ? Icons.landscape_rounded
                          : Icons.hive_rounded,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xin chào, $_tenNguoiDung',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isLandowner
                                        ? Icons.landscape_rounded
                                        : Icons.hive_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isLandowner
                                        ? 'Chủ đất'
                                        : 'Người nuôi ong',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            UserReputationBadge(
                              isNew: _laNguoiMoi,
                              rating: _uyTin,
                              reviewCount: _tongDanhGia,
                              fontSize: 11,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // TIÊU ĐỀ PHÂN MỤC 1: TỔNG QUAN HOẠT ĐỘNG
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _isLandowner
                        ? const Color(0xFFEA580C)
                        : const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isLandowner
                      ? 'Tổng quan vườn rẫy'
                      : 'Tổng quan quy mô trại ong',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_error != null && _summary.isEmpty)
              Card(
                color: Colors.red.shade50,
                child: ListTile(
                  leading: const Icon(Icons.cloud_off, color: Colors.red),
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Thử lại'),
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.3,
                children: _loading && _summary.isEmpty
                    ? List.generate(
                        4,
                        (_) => Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                        ),
                      )
                    : _stats(),
              ),
            if (alert != null) ...[const SizedBox(height: 14), alert],
            const SizedBox(height: 20),

            // TIÊU ĐỀ PHÂN MỤC 2: CHỨC NĂNG NGHIỆP VỤ
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Chức năng nghiệp vụ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.94,
              children: _menu().map(_menuTile).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _onBottomNavSelected,
          height: 66,
          backgroundColor: const Color(0xFFFFFBF5),
          indicatorColor: _isLandowner
              ? const Color(0xFFFFEDD5)
              : const Color(0xFFFEF3C7),
          elevation: 0,
          destinations: _isLandowner
              ? [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon:
                        Icon(Icons.home_rounded, color: Color(0xFFEA580C)),
                    label: 'Trang chủ',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon:
                        Icon(Icons.map_rounded, color: Color(0xFFEA580C)),
                    label: 'Bản đồ',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.landscape_outlined),
                    selectedIcon:
                        Icon(Icons.landscape_rounded, color: Color(0xFFEA580C)),
                    label: 'Khu đất',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: _n('pendingRequests') > 0,
                      label: Text('${_n('pendingRequests')}'),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.rule_folder_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: _n('pendingRequests') > 0,
                      label: Text('${_n('pendingRequests')}'),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.rule_folder_rounded,
                          color: Color(0xFFEA580C)),
                    ),
                    label: 'Yêu cầu',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon:
                        Icon(Icons.person_rounded, color: Color(0xFFEA580C)),
                    label: 'Cá nhân',
                  ),
                ]
              : [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon:
                        Icon(Icons.home_rounded, color: Color(0xFFD97706)),
                    label: 'Trang chủ',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon:
                        Icon(Icons.map_rounded, color: Color(0xFFD97706)),
                    label: 'Bản đồ',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.hive_outlined),
                    selectedIcon:
                        Icon(Icons.hive_rounded, color: Color(0xFFD97706)),
                    label: 'Đàn ong',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: _n('contractsToSign') > 0,
                      label: Text('${_n('contractsToSign')}'),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.handshake_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: _n('contractsToSign') > 0,
                      label: Text('${_n('contractsToSign')}'),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.handshake_rounded,
                          color: Color(0xFFD97706)),
                    ),
                    label: 'Hợp đồng',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon:
                        Icon(Icons.person_rounded, color: Color(0xFFD97706)),
                    label: 'Cá nhân',
                  ),
                ],
        ),
      ),
    );
  }

  Widget _menuTile(_MenuItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(item.builder),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: item.badge > 0,
                  label: Text('${item.badge}'),
                  backgroundColor: const Color(0xFFEF4444),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          item.color.withValues(alpha: 0.18),
                          item.color.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(item.icon, color: item.color, size: 26),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
