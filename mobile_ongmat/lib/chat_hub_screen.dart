import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'home_screen.dart';
import 'services/api_service.dart';
import 'widgets/common.dart';

// ==========================================
// XỬ LÝ HÌNH ẢNH & NỘI DUNG TIN NHẮN
// ==========================================

class _ParsedMessageContent {
  final bool isImage;
  final String? imageUrl;
  final String? caption;
  final bool isLocation;
  final String? locationUrl;

  const _ParsedMessageContent({
    this.isImage = false,
    this.imageUrl,
    this.caption,
    this.isLocation = false,
    this.locationUrl,
  });
}

bool _hasImageExtension(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp');
}

_ParsedMessageContent _parseMessageContent(String rawText) {
  final text = rawText.trim();
  if (text.isEmpty) return const _ParsedMessageContent();

  // 1. Tag chuẩn: [HÌNH_ẢNH]: <url> hoặc [IMAGE]: <url>
  if (text.startsWith('[HÌNH_ẢNH]:') ||
      text.startsWith('[IMAGE]:') ||
      text.startsWith('📷 [Ảnh]:') ||
      text.startsWith('📷 [Hình ảnh]:') ||
      text.startsWith('[Ảnh]:')) {
    final colonIdx = text.indexOf(':');
    final afterPrefix = text.substring(colonIdx + 1).trim();
    String imgUrl = afterPrefix;
    String? caption;
    if (afterPrefix.contains('\n')) {
      final idx = afterPrefix.indexOf('\n');
      imgUrl = afterPrefix.substring(0, idx).trim();
      caption = afterPrefix.substring(idx + 1).trim();
    } else if (afterPrefix.contains(' | ')) {
      final idx = afterPrefix.indexOf(' | ');
      imgUrl = afterPrefix.substring(0, idx).trim();
      caption = afterPrefix.substring(idx + 3).trim();
    }
    return _ParsedMessageContent(
      isImage: true,
      imageUrl: imgUrl,
      caption: caption,
    );
  }

  // 2. Tiền tố cũ hoặc gửi từ máy: '📷 [Đã gửi ảnh hiện trạng vườn]: <url>' hoặc '📷 [Đã gửi ảnh]: <url>'
  if (text.startsWith('📷 [Đã gửi ảnh') || text.startsWith('[Đã gửi ảnh')) {
    final colonIdx = text.indexOf(':');
    if (colonIdx != -1) {
      final target = text.substring(colonIdx + 1).trim();
      if (target.startsWith('http://') ||
          target.startsWith('https://') ||
          target.startsWith('/uploads/') ||
          target.contains('/uploads/') ||
          _hasImageExtension(target)) {
        return _ParsedMessageContent(
          isImage: true,
          imageUrl: target,
          caption: text.substring(0, colonIdx).trim(),
        );
      }
    }
  }

  // 3. Tìm link ảnh trực tiếp (http/https hoặc /uploads/...)
  final imgRegex = RegExp(
    r'(https?:\/\/[^\s]+\.(?:jpg|jpeg|png|gif|webp|bmp)(?:\?[^\s]*)?|\/uploads\/[^\s]+)',
    caseSensitive: false,
  );
  final match = imgRegex.firstMatch(text);
  if (match != null) {
    final imgUrl = match.group(0)!;
    String caption = text.replaceFirst(imgUrl, '').trim();
    caption = caption.replaceAll(RegExp(r'^[:\-\s]+|[:\-\s]+$'), '');
    return _ParsedMessageContent(
      isImage: true,
      imageUrl: imgUrl,
      caption: caption.isNotEmpty ? caption : null,
    );
  }

  // 4. Nếu toàn bộ chuỗi là đường dẫn /uploads/...
  if (text.startsWith('/uploads/') || (text.startsWith('http') && text.contains('/uploads/'))) {
    return _ParsedMessageContent(
      isImage: true,
      imageUrl: text,
    );
  }

  // 5. Kiểm tra vị trí GPS
  if (text.contains('maps.google.com') || text.startsWith('📍')) {
    final locRegex = RegExp(r'https?:\/\/maps\.google\.com[^\s]+');
    final locMatch = locRegex.firstMatch(text);
    if (locMatch != null) {
      return _ParsedMessageContent(
        isLocation: true,
        locationUrl: locMatch.group(0),
      );
    }
  }

  return const _ParsedMessageContent();
}

String _resolveImageUrl(String url) {
  final clean = url.trim();
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    return clean;
  }
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  final path = clean.startsWith('/') ? clean : '/$clean';
  return '$base$path';
}

void _showFullScreenImage(BuildContext context, String imageUrl, String? caption) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            caption != null && caption.isNotEmpty ? caption : 'Hình ảnh',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFB800)),
                );
              },
              errorBuilder: (ctx, error, stackTrace) => const Center(
                child: Text('Không thể tải hình ảnh này', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ==========================================
// MÔ HÌNH DỮ LIỆU CHAT
// ==========================================

class ChatMessage {
  final int? id;
  final bool isMe;
  final String text;
  final DateTime? time;
  final bool isRead;
  final bool isRevoked;

  ChatMessage({
    this.id,
    required this.isMe,
    required this.text,
    this.time,
    this.isRead = true,
    this.isRevoked = false,
  });
}

class ChatConversation {
  final String name;
  final String lastMessage;
  final String time;
  final int unread;
  final bool isAdmin;
  final int partnerId;
  final String role;
  final bool isOnline;
  final String phone;
  final String? avatar;
  final DateTime? lastMessageAt;
  final List<ChatMessage> messages;

  ChatConversation({
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.isAdmin,
    required this.partnerId,
    this.role = '',
    this.isOnline = false,
    this.phone = '',
    this.avatar,
    this.lastMessageAt,
    required this.messages,
  });

  ChatConversation copyWith({
    String? name,
    String? lastMessage,
    String? time,
    int? unread,
    bool? isAdmin,
    int? partnerId,
    String? role,
    bool? isOnline,
    String? phone,
    String? avatar,
    DateTime? lastMessageAt,
    List<ChatMessage>? messages,
  }) {
    return ChatConversation(
      name: name ?? this.name,
      lastMessage: lastMessage ?? this.lastMessage,
      time: time ?? this.time,
      unread: unread ?? this.unread,
      isAdmin: isAdmin ?? this.isAdmin,
      partnerId: partnerId ?? this.partnerId,
      role: role ?? this.role,
      isOnline: isOnline ?? this.isOnline,
      phone: phone ?? this.phone,
      avatar: avatar ?? this.avatar,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messages: messages ?? this.messages,
    );
  }
}

// ==========================================
// CÁC HÀM TIỆN ÍCH ĐỊNH DẠNG THỜI GIAN
// ==========================================

String _formatChatTime(DateTime? dt) {
  if (dt == null) return '';
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatConversationTime(DateTime? dt, String fallback) {
  if (dt == null) return fallback;
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'Vừa xong';
  if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
    return _formatChatTime(dt);
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == dt.year &&
      yesterday.month == dt.month &&
      yesterday.day == dt.day) {
    return 'Hôm qua';
  }
  if (diff.inDays < 7) {
    final weekdayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return weekdayNames[(dt.weekday - 1).clamp(0, 6)];
  }
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
}

String _formatDateSeparator(DateTime dt) {
  final now = DateTime.now();
  if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
    return 'Hôm nay';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == dt.year &&
      yesterday.month == dt.month &&
      yesterday.day == dt.day) {
    return 'Hôm qua';
  }
  return '${dt.day} tháng ${dt.month}, ${dt.year}';
}

// ==========================================
// MÀN HÌNH CHÍNH: CHAT HUB SCREEN
// ==========================================

class ChatHubScreen extends StatefulWidget {
  const ChatHubScreen({
    super.key,
    this.initialPartnerId,
    this.initialPartnerName,
    this.initialPartnerRole,
    this.initialPartnerPhone,
  });

  final int? initialPartnerId;
  final String? initialPartnerName;
  final String? initialPartnerRole;
  final String? initialPartnerPhone;

  @override
  State<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends State<ChatHubScreen> {
  List<ChatConversation> _allConversations = [];

  int _selectedTabIndex = 0; // 0: Tất cả, 1: Khách hàng/Vườn, 2: BQL/Admin
  int _selectedMasterIndex = 0;
  String _searchQuery = '';
  List<Map<String, dynamic>> _databaseUsers = [];
  bool _isSearchingDatabase = false;
  Timer? _searchDebounce;
  bool _isLoading = false;
  Timer? _pollingTimer;
  int _lastTotalUnread = -1;

  @override
  void initState() {
    super.initState();
    _loadConversationHistory();
    ApiService.sendChatHeartbeat();
    // Tự động đồng bộ danh sách định kỳ nhẹ nhàng 6 giây/lần kèm heartbeat
    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) {
        _loadConversationHistory(silent: true);
        ApiService.sendChatHeartbeat();
      }
    });

    // Nếu mở màn hình với đối tác cụ thể được chỉ định trước
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialPartnerId != null) {
        _openDirectPartner(
          widget.initialPartnerId!,
          widget.initialPartnerName ?? 'Đối tác',
          widget.initialPartnerRole ?? '',
          phone: widget.initialPartnerPhone ?? '',
        );
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    final query = val.trim();
    if (query.isEmpty) {
      setState(() {
        _databaseUsers = [];
        _isSearchingDatabase = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isSearchingDatabase = true);
      try {
        final results = await ApiService.searchChatUsers(query);
        if (mounted && _searchQuery.trim() == query) {
          setState(() {
            _databaseUsers = results;
            _isSearchingDatabase = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingDatabase = false);
      }
    });
  }

  void _openDirectPartner(
    int partnerId,
    String name,
    String role, {
    bool isOnline = false,
    String phone = '',
  }) {
    final existingIndex = _allConversations.indexWhere(
      (c) => c.partnerId == partnerId,
    );
    ChatConversation target;
    if (existingIndex >= 0) {
      target = _allConversations[existingIndex];
      bool needsUpdate = false;
      // Cập nhật tên nếu tên được cung cấp cụ thể và chính xác hơn tên cũ
      if (name.isNotEmpty && name != 'Đối tác' && name != 'Chủ đất' && name != 'Người nuôi ong' && target.name != name) {
        target = target.copyWith(name: name);
        needsUpdate = true;
      }
      if (isOnline != target.isOnline) {
        target = target.copyWith(isOnline: isOnline);
        needsUpdate = true;
      }
      if (phone.isNotEmpty && (target.phone.isEmpty || target.phone != phone)) {
        target = target.copyWith(phone: phone);
        needsUpdate = true;
      }
      if (role.isNotEmpty && target.role.isEmpty) {
        target = target.copyWith(role: role);
        needsUpdate = true;
      }
      if (needsUpdate) {
        _allConversations[existingIndex] = target;
      }
    } else {
      target = ChatConversation(
        name: name.isNotEmpty ? name : 'Chủ đất',
        lastMessage: 'Bắt đầu cuộc trò chuyện mới',
        time: 'Vừa xong',
        unread: 0,
        isAdmin: role.toLowerCase() == 'admin',
        partnerId: partnerId,
        role: role,
        isOnline: isOnline,
        phone: phone,
        messages: const [],
      );
      setState(() {
        _allConversations.insert(0, target);
      });
    }

    final isWide = MediaQuery.of(context).size.width >= 768;
    if (!isWide) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversation: target,
            onMessageSent: (newMsg) => _handleNewMessage(target, newMsg),
          ),
        ),
      );
    }
  }

  Future<void> _loadConversationHistory({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final currentUserId = await ApiService.getCurrentUserId() ?? 1;
      final contactList = await ApiService.getChatConversations(
        userId: currentUserId,
      );

      if (contactList.isNotEmpty) {
        final List<ChatConversation> nextList = [];

        for (final contact in contactList) {
          final partnerId = int.tryParse('${contact['maDoiTac']}') ?? 1;
          final partnerName = (contact['tenDoiTac'] ?? 'Đối tác').toString();
          final lastMessage = (contact['tinNhanCuoi'] ?? '').toString();
          final unread = int.tryParse('${contact['soTinChuaDoc']}') ?? 0;
          final role = (contact['vaiTro'] ?? '').toString();
          final isAdmin = role.toLowerCase() == 'admin';
          final isOnline = contact['isOnline'] == true ||
              contact['isOnline'] == 1 ||
              '${contact['isOnline']}'.toLowerCase() == 'true';

          final phone = (contact['soDienThoai'] ?? '').toString();

          // Giữ lại messages cache nếu có để không giật lag
          final existing = _allConversations.cast<ChatConversation?>().firstWhere(
            (c) => c?.partnerId == partnerId,
            orElse: () => null,
          );

          nextList.add(
            ChatConversation(
              name: partnerName,
              lastMessage: lastMessage.isNotEmpty
                  ? lastMessage
                  : (existing?.lastMessage ?? 'Bắt đầu cuộc trò chuyện'),
              time: existing?.time ?? 'Now',
              unread: unread,
              isAdmin: isAdmin,
              partnerId: partnerId,
              role: role,
              isOnline: isOnline,
              phone: phone.isNotEmpty ? phone : (existing?.phone ?? ''),
              lastMessageAt: existing?.lastMessageAt,
              messages: existing?.messages ?? const [],
            ),
          );
        }

        int currentTotalUnread = 0;
        for (final c in nextList) {
          currentTotalUnread += c.unread;
        }

        // Báo rung và hiện thông báo nếu có tin nhắn mới tới khi đang ở màn hình danh sách
        if (silent && _lastTotalUnread >= 0 && currentTotalUnread > _lastTotalUnread && mounted) {
          final newConv = nextList.firstWhere(
            (c) => c.unread > 0,
            orElse: () => nextList.first,
          );
          HapticFeedback.heavyImpact();
          String preview = newConv.lastMessage;
          if (preview.startsWith('[HÌNH_ẢNH]:') || preview.startsWith('📷')) {
            preview = '📷 [Đã gửi một hình ảnh]';
          } else if (preview.startsWith('📍')) {
            preview = '📍 [Đã chia sẻ vị trí vườn ong]';
          } else if (preview.length > 50) {
            preview = '${preview.substring(0, 50)}...';
          }

          showTopNotification(
            context,
            title: 'Tin nhắn mới từ ${newConv.name}',
            message: preview,
            icon: Icons.chat_bubble_rounded,
            iconColor: const Color(0xFFFBBF24),
            actionLabel: 'Mở chat',
            onAction: () {
              _openDirectPartner(newConv.partnerId, newConv.name, newConv.role);
            },
          );
        }
        _lastTotalUnread = currentTotalUnread;

        if (mounted) {
          setState(() {
            _allConversations = nextList;
          });
        }
      }
    } catch (_) {
      // Giữ dữ liệu hiện tại khi mất mạng hoặc backend bận
    } finally {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleNewMessage(ChatConversation conv, ChatMessage newMsg) {
    setState(() {
      final idx = _allConversations.indexWhere(
        (c) => c.partnerId == conv.partnerId,
      );
      if (idx >= 0) {
        final current = _allConversations[idx];
        final updatedMsgs = List<ChatMessage>.from(current.messages)..add(newMsg);
        _allConversations[idx] = current.copyWith(
          lastMessage: newMsg.text,
          time: 'Vừa xong',
          lastMessageAt: DateTime.now(),
          messages: updatedMsgs,
        );
      }
    });
  }

  List<ChatConversation> get _filteredConversations {
    return _allConversations.where((item) {
      // Lọc theo Tab
      if (_selectedTabIndex == 1 && item.isAdmin) return false;
      if (_selectedTabIndex == 2 && !item.isAdmin) return false;

      // Lọc theo Từ khóa tìm kiếm
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = item.name.toLowerCase().contains(q);
        final matchMsg = item.lastMessage.toLowerCase().contains(q);
        return matchName || matchMsg;
      }
      return true;
    }).toList();
  }

  int get _totalUnreadCount =>
      _allConversations.fold(0, (sum, item) => sum + item.unread);

  int get _customerUnreadCount => _allConversations
      .where((item) => !item.isAdmin)
      .fold(0, (sum, item) => sum + item.unread);

  int get _adminUnreadCount => _allConversations
      .where((item) => item.isAdmin)
      .fold(0, (sum, item) => sum + item.unread);

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    final conversations = _filteredConversations;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: isWide
          ? _buildWideDualPaneLayout(conversations)
          : _buildMobileLayout(conversations),
    );
  }

  // ==========================================
  // GIAO DIỆN DI ĐỘNG (MOBILE LAYOUT)
  // ==========================================

  Widget _buildMobileLayout(List<ChatConversation> conversations) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeaderBar(),
          // Chỗ hỗ trợ của Admin trên đầu màn hình chat
          _buildAdminSupportCard(),
          if (_searchQuery.isEmpty) ...[
            _buildActiveUsersRow(),
            _buildFilterTabs(),
          ],
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResultsView(conversations)
                : RefreshIndicator(
                    onRefresh: () => _loadConversationHistory(),
                    color: kHoney,
                    child: conversations.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: conversations.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final conv = conversations[index];
                              return _ConversationCard(
                                conversation: conv,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatDetailScreen(
                                        conversation: conv,
                                        onMessageSent: (msg) =>
                                            _handleNewMessage(conv, msg),
                                      ),
                                    ),
                                  );
                                  _loadConversationHistory(silent: true);
                                },
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // GIAO DIỆN TABLET / MÀN RỘNG (DUAL PANE)
  // ==========================================

  Widget _buildWideDualPaneLayout(List<ChatConversation> conversations) {
    final currentConv = conversations.isEmpty
        ? null
        : conversations[_selectedMasterIndex.clamp(
            0,
            conversations.length - 1,
          )];

    return SafeArea(
      child: Row(
        children: [
          SizedBox(
            width: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: Colors.grey.shade200, width: 1.5),
                ),
              ),
              child: Column(
                children: [
                  _buildHeaderBar(isCompact: true),
                  _buildAdminSupportCard(),
                  if (_searchQuery.isEmpty) ...[
                    _buildActiveUsersRow(),
                    _buildFilterTabs(),
                  ],
                  Expanded(
                    child: _searchQuery.isNotEmpty
                        ? _buildSearchResultsView(conversations)
                        : (conversations.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                itemCount: conversations.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final conv = conversations[index];
                                  final isSelected = index == _selectedMasterIndex;
                                  return _ConversationCard(
                                    conversation: conv,
                                    isSelected: isSelected,
                                    onTap: () {
                                      setState(() => _selectedMasterIndex = index);
                                    },
                                  );
                                },
                              )),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: currentConv == null
                ? const Center(
                    child: EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      message: 'Chọn một cuộc trò chuyện để bắt đầu nhắn tin',
                    ),
                  )
                : ChatDetailScreen(
                    key: ValueKey(currentConv.partnerId),
                    conversation: currentConv,
                    isEmbedded: true,
                    onMessageSent: (msg) =>
                        _handleNewMessage(currentConv, msg),
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CÁC KHỐI GIAO DIỆN CON DÙNG CHUNG
  // ==========================================

  Widget _buildAdminSupportCard() {
    final adminConv = _allConversations.cast<ChatConversation?>().firstWhere(
      (c) => c != null && (c.isAdmin || c.role.toLowerCase() == 'admin'),
      orElse: () => null,
    );
    final isOnline = adminConv?.isOnline ?? false;
    final unread = adminConv?.unread ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isOnline ? const Color(0xFF10B981).withValues(alpha: 0.6) : const Color(0xFF334155),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (adminConv != null) {
              _openDirectPartner(
                adminConv.partnerId,
                adminConv.name,
                adminConv.role,
                isOnline: adminConv.isOnline,
              );
            } else {
              _openDirectPartner(
                1,
                'Admin Hệ Thống Ong Mật',
                'admin',
                isOnline: isOnline,
              );
            }
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    if (isOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF0F172A), width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              adminConv?.name ?? 'Ban Quản Lý & Admin Hỗ Trợ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                color: Color(0xFFFBBF24),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 6.5,
                            height: 6.5,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF10B981) : Colors.grey.shade500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isOnline ? 'Đang trực tuyến · Phản hồi ngay' : 'Ngoại tuyến · Để lại tin nhắn',
                            style: TextStyle(
                              color: isOnline ? const Color(0xFF34D399) : Colors.grey.shade400,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unread mới',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Hỗ trợ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsView(List<ChatConversation> conversations) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        if (_isSearchingDatabase) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                ),
                SizedBox(width: 12),
                Text(
                  'Đang tìm người dùng trong database...',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Danh sách người dùng tìm được từ database
        if (_databaseUsers.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.storage_rounded, size: 16, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              Text(
                'NGƯỜI DÙNG TRONG DATABASE (${_databaseUsers.length})',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._databaseUsers.map((user) {
            final uid = int.tryParse('${user['maNguoiDung']}') ?? 0;
            final name = (user['hoTen'] ?? 'Người dùng').toString();
            final role = (user['vaiTro'] ?? 'chuDat').toString();
            final phone = (user['soDienThoai'] ?? '').toString();
            final isOnline = user['isOnline'] == true ||
                user['isOnline'] == 1 ||
                '${user['isOnline']}'.toLowerCase() == 'true';
            final isAdmin = role.toLowerCase() == 'admin';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Stack(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isAdmin
                              ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                              : (role.toLowerCase() == 'chudat'
                                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                  : [const Color(0xFFFFB800), const Color(0xFFF59E0B)]),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isAdmin ? Icons.support_agent_rounded : Icons.person_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    if (isOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isAdmin
                            ? const Color(0xFFDBEAFE)
                            : (role.toLowerCase() == 'chudat'
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFFEF3C7)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isAdmin
                            ? 'Admin'
                            : (role.toLowerCase() == 'chudat' ? 'Chủ Vườn' : 'Nuôi Ong'),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isAdmin
                              ? const Color(0xFF1E40AF)
                              : (role.toLowerCase() == 'chudat'
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF92400E)),
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Row(
                  children: [
                    if (phone.isNotEmpty) ...[
                      const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      Text(phone, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      isOnline ? 'Đang online' : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOnline ? const Color(0xFF10B981) : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () {
                    _openDirectPartner(uid, name, role, isOnline: isOnline, phone: phone);
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 13),
                  label: const Text('Nhắn tin', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
        ],

        // Phần các cuộc trò chuyện phù hợp
        if (conversations.isNotEmpty) ...[
          const Row(
            children: [
              Icon(Icons.chat_rounded, size: 16, color: Color(0xFFD97706)),
              SizedBox(width: 6),
              Text(
                'CUỘC HỘI THOẠI PHÙ HỢP',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...conversations.map((conv) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ConversationCard(
                  conversation: conv,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          conversation: conv,
                          onMessageSent: (msg) => _handleNewMessage(conv, msg),
                        ),
                      ),
                    );
                    _loadConversationHistory(silent: true);
                  },
                ),
              )),
        ],

        if (!_isSearchingDatabase && _databaseUsers.isEmpty && conversations.isEmpty)
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildHeaderBar({bool isCompact = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF1E293B),
                  size: 20,
                ),
                tooltip: 'Về màn hình chính',
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  }
                },
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB800), Color(0xFFFFA000)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hive_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Tin nhắn Ong Mật',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (_totalUnreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_totalUnreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isLoading ? 'Đang cập nhật...' : 'Đang trực tuyến',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF475569)),
                tooltip: 'Làm mới',
                onPressed: () => _loadConversationHistory(),
              ),
              IconButton(
                icon: const Icon(Icons.home_rounded, color: Color(0xFFD97706), size: 22),
                tooltip: 'Về màn hình chính',
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Khung tìm kiếm người dùng trong database
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm đối tác, người dùng database...',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade500,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Colors.grey.shade500,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => _onSearchChanged(''),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveUsersRow() {
    final activeList = _allConversations.where((c) => c.isOnline).toList();
    if (activeList.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Đang hoạt động (${activeList.length})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: activeList.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, idx) {
                final item = activeList[idx];
                final shortName = item.name.split(' ').last;
                return GestureDetector(
                  onTap: () {
                    final isWide = MediaQuery.of(context).size.width >= 768;
                    if (isWide) {
                      setState(() {
                        _selectedMasterIndex = _allConversations.indexOf(item);
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatDetailScreen(
                            conversation: item,
                            onMessageSent: (msg) =>
                                _handleNewMessage(item, msg),
                          ),
                        ),
                      );
                    }
                  },
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: item.isAdmin
                                    ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                                    : [const Color(0xFFFFB800), const Color(0xFFF59E0B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              item.isAdmin
                                  ? Icons.support_agent_rounded
                                  : Icons.person_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 58,
                        child: Text(
                          shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          _TabPill(
            label: 'Tất cả',
            count: _totalUnreadCount,
            isSelected: _selectedTabIndex == 0,
            onTap: () => setState(() => _selectedTabIndex = 0),
          ),
          const SizedBox(width: 8),
          _TabPill(
            label: 'Chủ vườn & Đối tác',
            count: _customerUnreadCount,
            isSelected: _selectedTabIndex == 1,
            onTap: () => setState(() => _selectedTabIndex = 1),
          ),
          const SizedBox(width: 8),
          _TabPill(
            label: 'BQL & Kỹ thuật',
            count: _adminUnreadCount,
            isSelected: _selectedTabIndex == 2,
            onTap: () => setState(() => _selectedTabIndex = 2),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFDE68A), width: 2),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Không tìm thấy kết quả phù hợp'
                  : 'Chưa có cuộc trò chuyện nào',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Vui lòng kiểm tra lại từ khóa hoặc chuyển tab lọc.'
                  : 'Mọi trao đổi với chủ vườn và ban quản lý sẽ hiển thị tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// THÀNH PHẦN: NÚT TAB PILL LỌC
// ==========================================

class _TabPill extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFB800) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// THÀNH PHẦN: THẺ CUỘC TRÒ CHUYỆN (CARD)
// ==========================================

class _ConversationCard extends StatelessWidget {
  final ChatConversation conversation;
  final bool isSelected;
  final VoidCallback onTap;

  const _ConversationCard({
    required this.conversation,
    this.isSelected = false,
    required this.onTap,
  });

  String _getRoleLabel(String role, bool isAdmin) {
    if (isAdmin) return 'BQL Quản Trị';
    final r = role.toLowerCase();
    if (r == 'chudat') return 'Chủ Vườn';
    if (r == 'nguoinuoiong') return 'Nuôi Ong';
    return 'Đối Tác';
  }

  Color _getRoleColor(String role, bool isAdmin) {
    if (isAdmin) return const Color(0xFF2563EB);
    final r = role.toLowerCase();
    if (r == 'chudat') return const Color(0xFF059669);
    if (r == 'nguoinuoiong') return const Color(0xFFD97706);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _getRoleColor(conversation.role, conversation.isAdmin);
    final roleLabel = _getRoleLabel(conversation.role, conversation.isAdmin);
    final hasUnread = conversation.unread > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFFFBEB)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFFFB800)
                  : Colors.grey.shade100,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar đẹp với biểu tượng trạng thái
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: conversation.isAdmin
                            ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                            : [const Color(0xFFFFB800), const Color(0xFFF59E0B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      conversation.isAdmin
                          ? Icons.admin_panel_settings_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  if (conversation.isOnline)
                    Positioned(
                      bottom: 1,
                      right: 1,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Thông tin đối tác và tin nhắn cuối
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatConversationTime(
                            conversation.lastMessageAt,
                            conversation.time,
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                            color: hasUnread
                                ? const Color(0xFFD97706)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            roleLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: roleColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final parsed = _parseMessageContent(conversation.lastMessage);
                              final isRevoked = conversation.lastMessage == 'Tin nhắn đã được thu hồi';
                              String preview = conversation.lastMessage;
                              if (parsed.isImage) {
                                preview = parsed.caption != null && parsed.caption!.isNotEmpty
                                    ? '📷 [Hình ảnh]: ${parsed.caption}'
                                    : '📷 [Hình ảnh]';
                              } else if (parsed.isLocation) {
                                preview = '📍 [Vị trí GPS đã chia sẻ]';
                              }
                              return Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: isRevoked ? FontStyle.italic : FontStyle.normal,
                                  fontWeight:
                                      hasUnread ? FontWeight.w600 : FontWeight.normal,
                                  color: hasUnread
                                      ? const Color(0xFF0F172A)
                                      : (isRevoked ? Colors.grey.shade500 : Colors.grey.shade600),
                                ),
                              );
                            },
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${conversation.unread}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MÀN HÌNH CHI TIẾT CUỘC TRÒ CHUYỆN (CHAT DETAIL)
// ==========================================

class ChatDetailScreen extends StatefulWidget {
  final ChatConversation conversation;
  final bool isEmbedded;
  final ValueChanged<ChatMessage>? onMessageSent;

  const ChatDetailScreen({
    super.key,
    required this.conversation,
    this.isEmbedded = false,
    this.onMessageSent,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  late List<ChatMessage> _messages;
  late String _partnerPhone;
  late String _partnerName;
  bool _isFetchingPartner = false;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollingTimer;
  bool _isSending = false;
  bool _showScrollToBottom = false;
  int _lastOtherUnread = -1;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.conversation.messages);
    _partnerPhone = widget.conversation.phone.trim();
    _partnerName = widget.conversation.name.trim();
    _loadHistory();

    // Polling riêng cho đoạn chat đang mở: 3 giây/lần
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _loadHistory(silent: true);
      }
    });

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final offset = _scrollController.offset;
      final max = _scrollController.position.maxScrollExtent;
      final shouldShow = (max - offset) > 300;
      if (shouldShow != _showScrollToBottom) {
        setState(() => _showScrollToBottom = shouldShow);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: false);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuad,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Future<void> _loadHistory({bool silent = false}) async {
    try {
      final currentUserId = await ApiService.getCurrentUserId() ?? 1;
      final fullRes = await ApiService.getChatHistoryFull(receiverId: widget.conversation.partnerId);
      final List<dynamic> history = (fullRes != null && fullRes['data'] is List)
          ? (fullRes['data'] as List)
          : await ApiService.getChatHistory(
              senderId: currentUserId,
              receiverId: widget.conversation.partnerId,
            );

      // Cập nhật số điện thoại của người đang chat từ phản hồi API
      if (fullRes != null && fullRes['partner'] is Map) {
        final p = fullRes['partner'] as Map;
        final phone = (p['soDienThoai'] ?? '').toString().trim();
        final realName = (p['hoTen'] ?? p['tenDoiTac'] ?? p['tenNguoiDung'] ?? '').toString().trim();
        if (realName.isNotEmpty && _partnerName != realName && mounted) {
          setState(() => _partnerName = realName);
        }
        if (phone.isNotEmpty && _partnerPhone != phone && mounted) {
          setState(() => _partnerPhone = phone);
        }
      } else if (_partnerPhone.isEmpty) {
        ApiService.getPartnerInfo(widget.conversation.partnerId).then((info) {
          if (info != null && info['soDienThoai'] != null) {
            final phone = info['soDienThoai'].toString().trim();
            if (phone.isNotEmpty && mounted && _partnerPhone != phone) {
              setState(() => _partnerPhone = phone);
            }
          }
        }).catchError((_) {});
      }

      if (history.isNotEmpty) {
        final parsedMessages = history.map((item) {
          final senderId = item['maNguoiGui'];
          final text = (item['noiDung'] ?? item['message'] ?? '').toString();
          DateTime? msgTime;
          if (item['ngayGui'] != null) {
            msgTime = DateTime.tryParse(item['ngayGui'].toString())?.toLocal();
          }
          final isRead = item['daDoc'] == 1 || item['daDoc'] == true;
          final isRevoked = item['daThuHoi'] == 1 ||
              item['daThuHoi'] == true ||
              '${item['daThuHoi']}'.toLowerCase() == 'true' ||
              text == 'Tin nhắn đã được thu hồi';

          return ChatMessage(
            id: item['maTinNhan'],
            isMe: senderId == currentUserId,
            text: text,
            time: msgTime,
            isRead: isRead,
            isRevoked: isRevoked,
          );
        }).toList();

        if (mounted) {
          // Kiểm tra xem có tin nhắn nào vừa bị thu hồi không
          final hasRevokedChange = _messages.length == parsedMessages.length &&
              _messages.asMap().entries.any(
                  (entry) => entry.value.isRevoked != parsedMessages[entry.key].isRevoked);

          // Chỉ cập nhật nếu số lượng hoặc nội dung tin nhắn mới khác biệt
          final isDifferent = parsedMessages.length != _messages.length ||
              hasRevokedChange ||
              (parsedMessages.isNotEmpty &&
                  _messages.isNotEmpty &&
                  (parsedMessages.last.text != _messages.last.text ||
                      parsedMessages.last.isRevoked != _messages.last.isRevoked));

          if (isDifferent) {
            final oldLen = _messages.length;
            final newLen = parsedMessages.length;

            // Nhận tin nhắn mới từ đối tác hiện tại: không cần hiện popup thông báo che màn hình
            if (newLen > oldLen && oldLen > 0) {
              final newIncoming = parsedMessages.sublist(oldLen).where((m) => !m.isMe && !m.isRevoked).toList();
              if (newIncoming.isNotEmpty) {
                HapticFeedback.lightImpact();
              }
            }

            setState(() {
              _messages = parsedMessages;
            });
            // Nếu người dùng đang ở gần đáy, tự động cuộn xuống
            if (!_showScrollToBottom) {
              Future.delayed(const Duration(milliseconds: 100), () {
                _scrollToBottom(animated: true);
              });
            }
          }
        }
      }

      // Nếu có tin nhắn mới từ đối tác khác gửi tới, hiển thị thanh thông báo nổi ở TRÊN ĐẦU
      try {
        final totalUnread = await ApiService.getTotalUnreadChatCount();
        if (mounted && totalUnread > 0) {
          if (_lastOtherUnread >= 0 && totalUnread > _lastOtherUnread) {
            HapticFeedback.mediumImpact();
            showTopNotification(
              context,
              title: 'Tin nhắn mới',
              message: 'Bạn có $totalUnread tin nhắn chưa đọc từ người khác',
              icon: Icons.mark_chat_unread_rounded,
              iconColor: const Color(0xFF38BDF8),
              actionLabel: 'Xem',
              onAction: () {
                Navigator.pop(context);
              },
            );
          }
          _lastOtherUnread = totalUnread;
        } else {
          _lastOtherUnread = 0;
        }
      } catch (_) {}
    } catch (_) {
      // Bỏ qua lỗi ngầm để tránh gây phiền
    }
  }

  Future<void> _sendMessage([String? quickText]) async {
    final value = (quickText ?? _textController.text).trim();
    if (value.isEmpty) return;

    if (quickText == null) {
      _textController.clear();
    }

    HapticFeedback.lightImpact();

    final currentUserId = await ApiService.getCurrentUserId() ?? 1;
    final newMsg = ChatMessage(
      isMe: true,
      text: value,
      time: DateTime.now(),
      isRead: false,
    );

    // Cập nhật lạc quan (Optimistic update)
    setState(() {
      _messages.add(newMsg);
      _isSending = true;
    });

    widget.onMessageSent?.call(newMsg);
    _scrollToBottom(animated: true);

    try {
      await ApiService.sendChatMessage(
        senderId: currentUserId,
        receiverId: widget.conversation.partnerId,
        message: value,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi gửi tin nhắn: ${errorText(e)}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      XFile? picked;
      try {
        picked = await picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1280,
          maxHeight: 1280,
        );
      } catch (_) {
        // Fallback chọn ảnh nguyên bản nếu thiết bị gặp lỗi nén ảnh trước
        picked = await picker.pickImage(source: source);
      }
      if (picked == null) return;

      setState(() => _isSending = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Đang tải hình ảnh lên...'),
              ],
            ),
            duration: Duration(seconds: 8),
          ),
        );
      }

      final bytes = await picked.readAsBytes();
      String rawName = picked.name.isNotEmpty
          ? picked.name
          : 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Làm sạch tên file và loại bỏ ký tự đặc biệt ':' (từ URI MediaStore Android)
      String filename = rawName.split('/').last.split('\\').last.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
      final lowerName = filename.toLowerCase();
      if (!lowerName.endsWith('.jpg') &&
          !lowerName.endsWith('.jpeg') &&
          !lowerName.endsWith('.png') &&
          !lowerName.endsWith('.webp') &&
          !lowerName.endsWith('.gif')) {
        filename = '$filename.jpg';
      }

      final imageUrl = await ApiService.uploadChatImage(bytes, filename);
      final msgText = '[HÌNH_ẢNH]: $imageUrl';
      await _sendMessage(msgText);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi gửi ảnh: ${errorText(e)}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  // ==========================================
  // HỘP THOẠI & MENU HÀNH ĐỘNG
  // ==========================================

  void _showPartnerInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: widget.conversation.isAdmin
                        ? [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)]
                        : [const Color(0xFFFFB800), const Color(0xFFF59E0B)],
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.conversation.isAdmin
                      ? Icons.support_agent_rounded
                      : Icons.person_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.conversation.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.conversation.isAdmin
                    ? 'Bộ phận Quản Trị Hệ Thống Ong Mật'
                    : 'Chủ vườn liên kết / Đối tác nuôi ong',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              if (_partnerPhone.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Text(
                        _partnerPhone,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _handleCallPartner();
                    },
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: Text(_partnerPhone.isNotEmpty ? 'Gọi: $_partnerPhone' : 'Gọi điện thoại'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.conversation.name),
                      );
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã sao chép thông tin đối tác!'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Sao chép tên'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Chọn nội dung đính kèm',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _AttachmentOption(
                      icon: Icons.location_on_rounded,
                      color: const Color(0xFFEF4444),
                      label: 'Vị trí GPS',
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          final pos = await currentPosition();
                          final locText =
                              '📍 [Vị trí vườn ong hiện tại]: https://maps.google.com/?q=${pos.latitude},${pos.longitude} (Tọa độ: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
                          _sendMessage(locText);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(errorText(e))),
                            );
                          }
                        }
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFF3B82F6),
                      label: 'Thư viện ảnh',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendImage(ImageSource.gallery);
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.camera_alt_rounded,
                      color: const Color(0xFFEC4899),
                      label: 'Chụp ảnh',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendImage(ImageSource.camera);
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.description_rounded,
                      color: const Color(0xFF10B981),
                      label: 'Mẫu thuê vườn',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendMessage(
                          '📋 [Yêu cầu thuê vườn]:\n- Số lượng thùng ong: 50 thùng\n- Thời gian đặt: 30 ngày\n- Nguồn hoa chính: Hoa Nhãn / Vải\n- Đề nghị hỗ trợ nguồn nước và an ninh vườn.',
                        );
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.handshake_rounded,
                      color: const Color(0xFFF59E0B),
                      label: 'Thỏa thuận mật',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendMessage(
                          '🍯 [Thỏa thuận chia sản lượng]:\n- Đơn giá thuê: 1.500.000 VNĐ / vụ hoa\n- Kèm tặng: 2 lít mật ong nguyên chất chuẩn QR truy xuất.',
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCallPartner() async {
    String phone = _partnerPhone.trim();

    // Nếu chưa có số điện thoại, thử tải ngay từ server
    if (phone.isEmpty) {
      setState(() => _isFetchingPartner = true);
      try {
        final info = await ApiService.getPartnerInfo(widget.conversation.partnerId);
        if (info != null && info['soDienThoai'] != null) {
          final fetched = info['soDienThoai'].toString().trim();
          if (fetched.isNotEmpty) {
            phone = fetched;
            if (mounted) setState(() => _partnerPhone = fetched);
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _isFetchingPartner = false);
    }

    if (phone.isEmpty) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.phone_missed_rounded, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('Chưa có số điện thoại', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Người dùng "${widget.conversation.name}" chưa cập nhật số điện thoại liên hệ trong hệ thống.',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Hiển thị bảng xác nhận gọi với số điện thoại thực tế của người đang chat
    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Xác nhận cuộc gọi',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Gọi điện thoại trực tiếp đến người đang trò chuyện:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                      _partnerName,
                      maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF047857),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _launchCall(phone);
                        },
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Gọi ngay', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _revokeMessage(ChatMessage msg) async {
    if (msg.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.undo_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Thu hồi tin nhắn', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn thu hồi tin nhắn này? Tin nhắn sẽ được gỡ bỏ đối với tất cả mọi người trong cuộc trò chuyện.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.revokeChatMessage(msg.id!);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx >= 0) {
            _messages[idx] = ChatMessage(
              id: msg.id,
              isMe: msg.isMe,
              text: msg.text,
              time: msg.time,
              isRead: msg.isRead,
              isRevoked: true,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Đã thu hồi tin nhắn thành công'),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi thu hồi tin nhắn: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showMessageActionMenu(ChatMessage msg) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (!msg.isRevoked) ...[
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.blue),
                  title: const Text('Sao chép tin nhắn'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã sao chép nội dung tin nhắn!'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: Colors.green),
                  title: const Text('Trích dẫn trả lời'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _textController.text = '> ${msg.text}\n';
                    _textController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _textController.text.length),
                    );
                  },
                ),
              ],
              if (msg.isMe && !msg.isRevoked && msg.id != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.undo_rounded, color: Color(0xFFEF4444)),
                  title: const Text(
                    'Thu hồi tin nhắn',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Gỡ tin nhắn đối với tất cả người nhận',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _revokeMessage(msg);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return;
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể gọi đến số: $cleanPhone')),
        );
      }
    }
  }

  // ==========================================
  // XÂY DỰNG GIAO DIỆN CHAT DETAIL
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EE), // Tông màu ấm tự nhiên của Ong Mật
      appBar: _buildChatAppBar(),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildMessageList(),
                if (_showScrollToBottom)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E293B),
                      elevation: 4,
                      onPressed: () => _scrollToBottom(animated: true),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
              ],
            ),
          ),
          _buildQuickSuggestions(),
          _buildMessageInputDock(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildChatAppBar() {
    return AppBar(
      elevation: 1,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1E293B),
      leadingWidth: widget.isEmbedded ? 0 : 48,
      leading: widget.isEmbedded
          ? const SizedBox.shrink()
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: 'Quay lại',
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
      titleSpacing: widget.isEmbedded ? 16 : 0,
      title: InkWell(
        onTap: _showPartnerInfo,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: widget.conversation.isAdmin
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFFFB800),
                    child: Icon(
                      widget.conversation.isAdmin
                          ? Icons.support_agent_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  if (widget.conversation.isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _partnerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          widget.conversation.isAdmin
                              ? (widget.conversation.isOnline ? 'Quản trị viên · Đang trực tuyến' : 'Quản trị viên · Ngoại tuyến')
                              : (widget.conversation.isOnline
                                  ? 'Đang hoạt động'
                                  : 'Ngoại tuyến'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: widget.conversation.isOnline
                                ? const Color(0xFF10B981)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.home_rounded, color: Color(0xFFD97706)),
          tooltip: 'Về màn hình chính',
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            }
          },
        ),
        _isFetchingPartner
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.phone_rounded, color: Color(0xFF10B981)),
                tooltip: 'Gọi điện',
                onPressed: _handleCallPartner,
              ),
        IconButton(
          icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B)),
          tooltip: 'Thông tin đối tác',
          onPressed: _showPartnerInfo,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.chat_bubble_outline,
          message: 'Chưa có tin nhắn nào trong cuộc trò chuyện này.\nHãy gửi lời chào để bắt đầu!',
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.isMe;

        // Kiểm tra xem có cần hiển thị phân cách ngày không
        bool showDate = false;
        if (index == 0) {
          showDate = true;
        } else {
          final prevMsg = _messages[index - 1];
          if (message.time != null && prevMsg.time != null) {
            final curr = message.time!;
            final prev = prevMsg.time!;
            if (curr.day != prev.day ||
                curr.month != prev.month ||
                curr.year != prev.year) {
              showDate = true;
            }
          }
        }

        return Column(
          children: [
            if (showDate && message.time != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDateSeparator(message.time!),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => _showMessageActionMenu(message),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.76,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isMe) ...[
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: widget.conversation.isAdmin
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFFFFB800),
                          child: Icon(
                            widget.conversation.isAdmin
                                ? Icons.support_agent_rounded
                                : Icons.person_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: (isMe && !message.isRevoked)
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFFFFBE1A),
                                      Color(0xFFFFA000),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: message.isRevoked
                                ? (isMe ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC))
                                : (isMe ? null : Colors.white),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: isMe
                                  ? const Radius.circular(18)
                                  : const Radius.circular(4),
                              bottomRight: isMe
                                  ? const Radius.circular(4)
                                  : const Radius.circular(18),
                            ),
                            border: message.isRevoked
                                ? Border.all(color: const Color(0xFFCBD5E1), width: 1)
                                : (isMe ? null : Border.all(color: Colors.grey.shade200)),
                            boxShadow: message.isRevoked
                                ? []
                                : [
                                    BoxShadow(
                                      color: isMe
                                          ? const Color(0xFFFFB800).withValues(alpha: 0.25)
                                          : Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Builder(
                                builder: (context) {
                                  if (message.isRevoked) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.remove_circle_outline_rounded,
                                            size: 15,
                                            color: isMe ? const Color(0xFF64748B) : Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              isMe
                                                  ? 'Bạn đã thu hồi một tin nhắn'
                                                  : 'Tin nhắn đã được thu hồi',
                                              style: TextStyle(
                                                fontStyle: FontStyle.italic,
                                                fontSize: 13.5,
                                                color: isMe ? const Color(0xFF475569) : Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final parsed = _parseMessageContent(message.text);
                                  if (parsed.isImage && parsed.imageUrl != null) {
                                    final resolvedUrl = _resolveImageUrl(parsed.imageUrl!);
                                    return Column(
                                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showFullScreenImage(
                                            context,
                                            resolvedUrl,
                                            parsed.caption,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              constraints: const BoxConstraints(
                                                maxWidth: 240,
                                                maxHeight: 220,
                                              ),
                                              child: Stack(
                                                children: [
                                                  Image.network(
                                                    resolvedUrl,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    loadingBuilder: (ctx, child, progress) {
                                                      if (progress == null) return child;
                                                      return Container(
                                                        height: 140,
                                                        color: Colors.black.withValues(alpha: 0.05),
                                                        alignment: Alignment.center,
                                                        child: CircularProgressIndicator(
                                                          value: progress.expectedTotalBytes != null
                                                              ? progress.cumulativeBytesLoaded /
                                                                  progress.expectedTotalBytes!
                                                              : null,
                                                          strokeWidth: 2,
                                                          color: const Color(0xFFFFB800),
                                                        ),
                                                      );
                                                    },
                                                    errorBuilder: (ctx, error, stackTrace) {
                                                      return Container(
                                                        padding: const EdgeInsets.all(12),
                                                        color: Colors.grey.shade100,
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(
                                                              Icons.broken_image_rounded,
                                                              color: Colors.grey,
                                                              size: 34,
                                                            ),
                                                            const SizedBox(height: 4),
                                                            Text(
                                                              'Không thể tải hình ảnh\n${parsed.imageUrl}',
                                                              textAlign: TextAlign.center,
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 11,
                                                                color: Colors.grey,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  Positioned(
                                                    bottom: 6,
                                                    right: 6,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withValues(alpha: 0.45),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: const Icon(
                                                        Icons.zoom_in_rounded,
                                                        color: Colors.white,
                                                        size: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (parsed.caption != null && parsed.caption!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            parsed.caption!,
                                            style: TextStyle(
                                              color: isMe
                                                  ? const Color(0xFF1E1E1E)
                                                  : const Color(0xFF1E293B),
                                              fontSize: 14,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  } else if (parsed.isLocation && parsed.locationUrl != null) {
                                    return InkWell(
                                      onTap: () async {
                                        final uri = Uri.parse(parsed.locationUrl!);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Colors.white.withValues(alpha: 0.25)
                                              : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.location_on_rounded,
                                              color: Color(0xFFEF4444),
                                              size: 28,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Vị trí vườn ong',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Nhấn để mở Google Maps',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: isMe
                                                          ? Colors.black.withValues(alpha: 0.7)
                                                          : Colors.blue.shade700,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  return Text(
                                    message.text,
                                    style: TextStyle(
                                      color: isMe
                                          ? const Color(0xFF1E1E1E)
                                          : const Color(0xFF1E293B),
                                      fontSize: 14.5,
                                      height: 1.35,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatChatTime(message.time),
                                    style: TextStyle(
                                      color: message.isRevoked
                                          ? Colors.grey.shade400
                                          : (isMe
                                              ? Colors.black.withValues(alpha: 0.55)
                                              : Colors.grey.shade500),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (isMe && !message.isRevoked) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      message.isRead
                                          ? Icons.done_all_rounded
                                          : Icons.done_rounded,
                                      size: 14,
                                      color: message.isRead
                                          ? const Color(0xFF2563EB)
                                          : Colors.black.withValues(alpha: 0.55),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickSuggestions() {
    final chips = [
      '📍 Gửi vị trí vườn',
      '🌸 Tình trạng hoa nở',
      '📜 Hợp đồng thuê vườn',
      '🍯 Sản lượng mật hoa',
      '✅ Đã nhận thông tin',
      '🤝 Đồng ý thỏa thuận',
    ];

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final title = chips[idx];
          return ActionChip(
            label: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.04),
            onPressed: () {
              if (title.contains('vị trí')) {
                _sendMessage(
                  '📍 Bạn có thể chia sẻ chính xác tọa độ vị trí vườn ong qua bản đồ giúp mình được không?',
                );
              } else if (title.contains('hoa nở')) {
                _sendMessage(
                  '🌸 Vườn của bạn đợt này hoa nở đạt khoảng bao nhiêu % rồi? Nguồn phấn có dồi dào không?',
                );
              } else if (title.contains('Hợp đồng')) {
                _sendMessage(
                  '📜 Mình đã xem qua hợp đồng điện tử trên hệ thống và chuẩn bị ký kết.',
                );
              } else if (title.contains('Sản lượng')) {
                _sendMessage(
                  '🍯 Đợt quay mật vừa rồi đạt năng suất rất tốt, cảm ơn chủ vườn đã hỗ trợ an ninh vườn.',
                );
              } else {
                _sendMessage(title);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageInputDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: Color(0xFFD97706),
                size: 26,
              ),
              tooltip: 'Thêm đính kèm',
              onPressed: _showAttachmentSheet,
            ),
            IconButton(
              icon: const Icon(
                Icons.image_outlined,
                color: Color(0xFF3B82F6),
                size: 25,
              ),
              tooltip: 'Gửi ảnh từ thư viện',
              onPressed: () => _pickAndSendImage(ImageSource.gallery),
            ),
            IconButton(
              icon: const Icon(
                Icons.camera_alt_outlined,
                color: Color(0xFF10B981),
                size: 24,
              ),
              tooltip: 'Chụp ảnh gửi ngay',
              onPressed: () => _pickAndSendImage(ImageSource.camera),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Nhập tin nhắn trao đổi...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB800), Color(0xFFFFA000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _isSending ? null : () => _sendMessage(),
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF1E1E1E),
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// THÀNH PHẦN PHỤ: NÚT TÙY CHỌN ĐÍNH KÈM
// ==========================================

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
