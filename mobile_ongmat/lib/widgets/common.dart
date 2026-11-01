import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

const kHoney = Color(0xFFF59E0B);
const kHoneyDark = Color(0xFFD97706);
const kHoneyLight = Color(0xFFFEF3C7);
const kBackground = Color(0xFFF8FAFC);
const kDefaultCenter = LatLng(16.0471, 108.2068);

/// Danh sách 63 tỉnh thành Việt Nam đầy đủ chuẩn xác
const List<String> kAllProvincesOfVietnam = [
  'Tất cả tỉnh thành',
  'An Giang',
  'Bà Rịa - Vũng Tàu',
  'Bắc Giang',
  'Bắc Kạn',
  'Bạc Liêu',
  'Bắc Ninh',
  'Bến Tre',
  'Bình Định',
  'Bình Dương',
  'Bình Phước',
  'Bình Thuận',
  'Cà Mau',
  'Cần Thơ',
  'Cao Bằng',
  'Đà Nẵng',
  'Đắk Lắk',
  'Đắk Nông',
  'Điện Biên',
  'Đồng Nai',
  'Đồng Tháp',
  'Gia Lai',
  'Hà Giang',
  'Hà Nam',
  'Hà Nội',
  'Hà Tĩnh',
  'Hải Dương',
  'Hải Phòng',
  'Hậu Giang',
  'Hòa Bình',
  'Hưng Yên',
  'Khánh Hòa',
  'Kiên Giang',
  'Kon Tum',
  'Lai Châu',
  'Lâm Đồng',
  'Lạng Sơn',
  'Lào Cai',
  'Long An',
  'Nam Định',
  'Nghệ An',
  'Ninh Bình',
  'Ninh Thuận',
  'Phú Thọ',
  'Phú Yên',
  'Quảng Bình',
  'Quảng Nam',
  'Quảng Ngãi',
  'Quảng Ninh',
  'Quảng Trị',
  'Sóc Trăng',
  'Sơn La',
  'Tây Ninh',
  'Thái Bình',
  'Thái Nguyên',
  'Thanh Hóa',
  'Thừa Thiên Huế',
  'Tiền Giang',
  'TP Hồ Chí Minh',
  'Trà Vinh',
  'Tuyên Quang',
  'Vĩnh Long',
  'Vĩnh Phúc',
  'Yên Bái',
];

String errorText(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Hiển thị thanh thông báo nổi ở TRÊN ĐẦU màn hình (Top In-App Notification Banner)
void showTopNotification(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.mark_chat_unread_rounded,
  Color iconColor = const Color(0xFF38BDF8),
  String? actionLabel,
  VoidCallback? onAction,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 4),
}) {
  TopNotificationOverlay.show(
    context,
    title: title,
    message: message,
    icon: icon,
    iconColor: iconColor,
    actionLabel: actionLabel,
    onAction: onAction,
    onTap: onTap,
    duration: duration,
  );
}

class TopNotificationOverlay {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void hide() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    try {
      _currentEntry?.remove();
    } catch (_) {}
    _currentEntry = null;
  }

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.mark_chat_unread_rounded,
    Color iconColor = const Color(0xFF38BDF8),
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    hide();

    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopNotificationWidget(
        title: title,
        message: message,
        icon: icon,
        iconColor: iconColor,
        actionLabel: actionLabel,
        onAction: () {
          hide();
          onAction?.call();
        },
        onTap: () {
          hide();
          onTap?.call();
        },
        onDismiss: hide,
      ),
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        hide();
      }
    });
  }
}

class _TopNotificationWidget extends StatefulWidget {
  const _TopNotificationWidget({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    this.actionLabel,
    this.onAction,
    this.onTap,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissWithAnimation() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                _dismissWithAnimation();
              }
            },
            onTap: widget.onTap ?? (widget.actionLabel != null ? widget.onAction : _dismissWithAnimation),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.iconColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, color: widget.iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.actionLabel != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          backgroundColor: widget.iconColor.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onAction,
                        child: Text(
                          widget.actionLabel!,
                          style: TextStyle(
                            color: widget.iconColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Chạy một thao tác ghi dữ liệu: khóa màn hình bằng vòng xoay, báo kết quả và
/// trả về true nếu thành công để màn hình gọi tải lại dữ liệu.
Future<bool> runAction(
  BuildContext context,
  Future<String> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final message = await action();
    navigator.pop();
    if (context.mounted) showSnack(context, message);
    return true;
  } catch (error) {
    navigator.pop();
    if (context.mounted) showSnack(context, errorText(error), error: true);
    return false;
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Đồng ý',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Colors.red)
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Hộp thoại nhập một dòng văn bản (lý do từ chối, mã OTP...). Trả về null nếu hủy.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  TextInputType keyboardType = TextInputType.text,
  bool required = false,
  String confirmLabel = 'Xác nhận',
  String? helper,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      label: label,
      initial: initial,
      keyboardType: keyboardType,
      required: required,
      confirmLabel: confirmLabel,
      helper: helper,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.keyboardType,
    required this.required,
    required this.confirmLabel,
    this.helper,
  });

  final String title;
  final String label;
  final String initial;
  final TextInputType keyboardType;
  final bool required;
  final String confirmLabel;
  final String? helper;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = 'Vui lòng nhập ${widget.label.toLowerCase()}');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          helperMaxLines: 3,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

// ================= HIỂN THỊ =================

String formatMoney(Object? value) {
  final number = num.tryParse('${value ?? ''}');
  if (number == null) return 'Thỏa thuận';
  final digits = number.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '$buffer đ';
}

String formatNumber(Object? value) {
  final number = num.tryParse('${value ?? ''}');
  if (number == null) return '0';
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(1);
}

String show(Object? value, [String fallback = '—']) =>
    value == null || value.toString().trim().isEmpty
    ? fallback
    : value.toString();

const _statusStyles = <String, (String, Color)>{
  'ChoDuyet': ('Chờ duyệt', Color(0xFFF59E0B)),
  'ChoKhachKy': ('Chờ ký', Color(0xFF3B82F6)),
  'DaKy': ('Đã ký', Color(0xFF16A34A)),
  'HoanThanh': ('Đã hoàn thành', Color(0xFF0D9488)),
  'TuChoi': ('Từ chối', Color(0xFFDC2626)),
  'DaHuy': ('Đã hủy', Color(0xFF6B7280)),
  'ChoDiemDuyet': ('Chờ kiểm duyệt', Color(0xFFF59E0B)),
  'DaDuyet': ('Đã duyệt', Color(0xFF16A34A)),
  'Lên lịch': ('Lên lịch', Color(0xFF3B82F6)),
  'Đã hoàn thành': ('Đã hoàn thành', Color(0xFF16A34A)),
  'Đang di chuyển': ('Đang di chuyển', Color(0xFFF97316)),
  'Hoàn thành': ('Hoàn thành', Color(0xFF16A34A)),
  'Đã hủy': ('Đã hủy', Color(0xFF6B7280)),
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final Object? status;

  @override
  Widget build(BuildContext context) {
    final key = show(status, '');
    final (label, color) =
        _statusStyles[key] ?? (show(status), const Color(0xFF6B7280));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Huy hiệu uy tín: hiển thị danh xưng "Người mới" (🌱) hoặc số sao đánh giá uy tín (⭐)
class UserReputationBadge extends StatelessWidget {
  const UserReputationBadge({
    super.key,
    this.isNew,
    this.rating,
    this.reviewCount,
    this.fontSize = 11,
  });

  final dynamic isNew;
  final dynamic rating;
  final dynamic reviewCount;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final count = int.tryParse('$reviewCount') ?? 0;
    final num? parsedRating = num.tryParse('$rating');
    final bool userIsNew = isNew == true ||
        isNew == 1 ||
        isNew == '1' ||
        count == 0 ||
        parsedRating == null;

    if (userIsNew) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌱', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
            Text(
              'Người mới',
              style: TextStyle(
                color: const Color(0xFF047857),
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
          const SizedBox(width: 2),
          Text(
            parsedRating.toStringAsFixed(1),
            style: TextStyle(
              color: const Color(0xFFB45309),
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 2),
            Text(
              ' ($count ĐG)',
              style: TextStyle(
                color: const Color(0xFF78350F),
                fontSize: fontSize - 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 56, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Khung tải dữ liệu chuẩn: lần đầu hiện vòng xoay, lỗi có nút thử lại,
/// các lần làm mới sau giữ nguyên nội dung cũ để không bị nháy màn hình.
class AsyncBody extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.loading,
    required this.error,
    required this.hasData,
    required this.onRetry,
    required this.child,
  });

  final bool loading;
  final String? error;
  final bool hasData;
  final Future<void> Function() onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hasData && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!hasData && error != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          message: error!,
          action: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ),
      );
    }
    return Stack(
      children: [
        child,
        if (loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.18),
                        color.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
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
}

// ================= Ô NHẬP NGÀY / GIỜ =================

String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.controller,
    required this.label,
    this.firstDate,
    this.lastDate,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_rounded),
        border: const OutlineInputBorder(),
      ),
      validator: (value) => value == null || value.isEmpty
          ? 'Vui lòng chọn ${label.toLowerCase()}'
          : null,
      onTap: () async {
        DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
        final first = dateOnly(firstDate ?? DateTime(2020));
        final last = dateOnly(lastDate ?? DateTime(2035));
        var current = dateOnly(
          DateTime.tryParse(controller.text) ?? DateTime.now(),
        );
        if (current.isBefore(first)) current = first;
        if (current.isAfter(last)) current = last;
        final picked = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: first,
          lastDate: last,
        );
        if (picked != null) {
          controller.text = isoDate(picked);
          onChanged?.call(controller.text);
        }
      },
    );
  }
}

class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.schedule_rounded),
        border: const OutlineInputBorder(),
      ),
      onTap: () async {
        final parts = controller.text.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: parts.length == 2
              ? TimeOfDay(
                  hour: int.tryParse(parts[0]) ?? 7,
                  minute: int.tryParse(parts[1]) ?? 0,
                )
              : const TimeOfDay(hour: 7, minute: 0),
        );
        if (picked != null) {
          controller.text =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        }
      },
    );
  }
}

// ================= ĐỊNH VỊ & CHỌN VỊ TRÍ =================

Future<LatLng> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Hãy bật dịch vụ định vị (GPS) trên thiết bị.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception('Ứng dụng chưa được cấp quyền truy cập vị trí.');
  }
  try {
    // 1. Thử lấy vị trí với độ chính xác cao nhất (ưu tiên chip GPS thực tế)
    final LocationSettings locationSettings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        forceLocationManager: true, // Tránh cache tháp sóng cũ của Google Play Services
        intervalDuration: const Duration(seconds: 1),
        timeLimit: const Duration(seconds: 12),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 12),
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    // 2. Dự phòng: Thử lại chế độ thông thường
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LatLng(lastKnown.latitude, lastKnown.longitude);
      }
      rethrow;
    }
  }
}

LatLng? latLngOf(Map<String, dynamic> item) {
  final lat = double.tryParse('${item['viDo']}');
  final lng = double.tryParse('${item['kinhDo']}');
  if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;
  return LatLng(lat, lng);
}

// 1. CHUYỂN SANG GOOGLE MAPS TILE LAYER (Khắc phục triệt để lỗi màn hình xám)
TileLayer osmTiles() => TileLayer(
  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
  subdomains: const ['0', '1', '2', '3'],
  userAgentPackageName: 'com.example.mobile_ongmat',
  maxZoom: 20,
  maxNativeZoom: 20,
);

/// Màn hình chọn vị trí: hỗ trợ Tìm kiếm địa điểm, Chạm bản đồ và GPS hiện tại
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initial,
    this.initialQuery,
    this.title = 'Chọn vị trí',
    this.onSelected,
  });
  final LatLng? initial;
  final String? initialQuery;
  final String title;
  final void Function(LatLng point, String? address)? onSelected;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  final _searchController = TextEditingController();
  LatLng? _picked;
  bool _locating = false;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];
  String? _selectedAddress;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchPlace(widget.initialQuery!.trim());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // TÌM KIẾM ĐỊA CHỈ & TỌA ĐỘ THÔNG MINH
  Future<void> _searchPlace(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      showSnack(context, 'Vui lòng nhập địa chỉ hoặc tọa độ cần tìm.');
      return;
    }

    FocusScope.of(context).unfocus();

    // 1. HỖ TRỢ NHẬP TRỰC TIẾP TỌA ĐỘ (vd: 10.8231, 106.6297)
    final coordMatch = RegExp(
      r'^([-+]?[0-9]*\.?[0-9]+)[,\s]+([-+]?[0-9]*\.?[0-9]+)$',
    ).firstMatch(text);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lon = double.tryParse(coordMatch.group(2)!);
      if (lat != null &&
          lon != null &&
          lat >= -90 &&
          lat <= 90 &&
          lon >= -180 &&
          lon <= 180) {
        final target = LatLng(lat, lon);
        setState(() {
          _picked = target;
          _selectedAddress = 'Tọa độ: $lat, $lon';
          _searchResults = [];
        });
        _map.move(target, 16);
        return;
      }
    }

    setState(() {
      _searching = true;
      _searchResults = [];
    });

    List<Map<String, dynamic>> results = [];

    // 1. TÌM KIẾM QUA BACKEND PROXY (HOẠT ĐỘNG 100% CẢ TRÊN CHROME/WEB VÀ NATIVE, KHÔNG BỊ CORS)
    try {
      results = await ApiService.searchPlaces(text);
    } catch (_) {}

    // 2. DỰ PHÒNG: Open-Meteo Geocoding
    if (results.isEmpty) {
      try {
        final fallbackUrl = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
          'name': text,
          'count': '6',
          'language': 'vi',
          'format': 'json',
        });
        final res = await http.get(fallbackUrl).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(res.bodyBytes));
          final List items = data['results'] ?? [];
          results = items.map((item) {
            final parts = [
              item['name'],
              item['admin3'],
              item['admin2'],
              item['admin1'],
              item['country'],
            ].where((s) => s != null && s.toString().trim().isNotEmpty).toSet().toList();

            return {
              'display_name': parts.join(', '),
              'lat': (item['latitude'] as num).toDouble(),
              'lon': (item['longitude'] as num).toDouble(),
            };
          }).where((item) => (item['display_name'] as String).isNotEmpty).toList();
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _searchResults = results;
        _searching = false;
      });

      if (results.isEmpty) {
        showSnack(
          context,
          'Không tìm thấy địa điểm. Thử nhập Tỉnh/Thành phố hoặc dán tọa độ.',
        );
      }
    }
  }

  // CHỌN KẾT QUẢ TÌM KIẾM VÀ BAY TỚI VỊ TRÍ ĐÓ
  void _selectSearchResult(Map<String, dynamic> item) {
    final lat = double.tryParse('${item['lat']}');
    final lon = double.tryParse('${item['lon']}');
    if (lat != null && lon != null) {
      final target = LatLng(lat, lon);
      setState(() {
        _picked = target;
        _selectedAddress = item['display_name']?.toString();
        _searchResults = [];
        _searchController.text = item['display_name']?.toString() ?? '';
      });
      _map.move(target, 16);
    }
  }

  // TỰ ĐỘNG LẤY TÊN ĐỊA CHỈ TỪ TỌA ĐỘ (REVERSE GEOCODING)
  Future<void> _reverseGeocode(LatLng point) async {
    // 1. Thử qua Backend Proxy (Bảo đảm không bị lỗi CORS trên Chrome)
    try {
      final addr = await ApiService.reverseGeocode(point.latitude, point.longitude);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() {
          _selectedAddress = addr;
          _searchController.text = addr;
        });
        return;
      }
    } catch (_) {}

    // 2. Dự phòng Photon
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/reverse?lat=${point.latitude}&lon=${point.longitude}',
      );
      final headers = <String, String>{
        if (!kIsWeb)
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) MobileOngMat/1.0',
        'Accept': 'application/json',
      };
      final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final features = data['features'] as List? ?? [];
        if (features.isNotEmpty) {
          final props = features[0]['properties'] ?? {};
          final parts = [
            if (props['name'] != null && props['name'] != props['street']) props['name'],
            if (props['street'] != null) props['street'],
            props['district'] ?? props['county'],
            props['city'] ?? props['state'],
            props['country'] ?? 'Việt Nam',
          ].where((s) => s != null && s.toString().trim().isNotEmpty).toSet().toList();
          final addr = parts.join(', ');
          if (mounted && addr.isNotEmpty) {
            setState(() {
              _selectedAddress = addr;
              _searchController.text = addr;
            });
            return;
          }
        }
      }
    } catch (_) {}
  }

  // LẤY TỌA ĐỘ GPS HIỆN TẠI VỚI ĐỘ CHÍNH XÁC CAO NHẤT
  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      final position = await currentPosition();
      if (!mounted) return;
      setState(() {
        _picked = position;
      });
      _map.move(position, 17);
      await _reverseGeocode(position);
      if (mounted) {
        if (kIsWeb) {
          showSnack(context, '📍 Đã định vị theo mạng Internet trình duyệt. Bạn có thể chạm bản đồ hoặc tìm kiếm để tinh chỉnh đúng thửa vườn!');
        } else {
          showSnack(context, '📍 Đã định vị chính xác vị trí của bạn!');
        }
      }
    } catch (error) {
      if (mounted) showSnack(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          // 1. BẢN ĐỒ GOOGLE MAPS TILE
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: widget.initial ?? kDefaultCenter,
              initialZoom: widget.initial != null ? 16 : 6,
              onTap: (_, point) {
                FocusScope.of(context).unfocus();
                setState(() {
                  _picked = point;
                  _searchResults = [];
                });
                _reverseGeocode(point);
              },
            ),
            children: [
              osmTiles(),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 48,
                      height: 48,
                      alignment: Alignment.bottomCenter, // Mũi kim ghim chạm đúng vị trí pixel
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 46,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 2. THANH TÌM KIẾM ĐỊA ĐIỂM
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.search, color: Colors.amber),
                          tooltip: 'Tìm kiếm',
                          onPressed: () => _searchPlace(_searchController.text),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Tìm địa chỉ, vườn, xã/huyện, tỉnh...',
                              hintStyle: TextStyle(fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: _searchPlace,
                          ),
                        ),
                        if (_searching)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchResults = []);
                            },
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_forward,
                            color: Colors.orange,
                          ),
                          onPressed: () => _searchPlace(_searchController.text),
                        ),
                      ],
                    ),
                  ),
                ),

                // MENU SỔ XUỐNG 63 TỈNH THÀNH VIỆT NAM ĐỂ CHỦ ĐẤT CHỌN NHANH ĐỊA BÀN
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    tooltip: 'Chọn nhanh Tỉnh / Thành phố',
                    position: PopupMenuPosition.under,
                    constraints: const BoxConstraints(maxHeight: 380, minWidth: 260),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (prov) {
                      if (prov == 'Tất cả tỉnh thành') return;
                      _searchController.text = prov;
                      _searchPlace(prov);
                    },
                    itemBuilder: (context) => [
                      for (final prov in kAllProvincesOfVietnam)
                        if (prov != 'Tất cả tỉnh thành')
                          PopupMenuItem<String>(
                            value: prov,
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFD97706)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    prov,
                                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD97706), width: 1.3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_drop_down_circle_outlined, size: 16, color: Color(0xFFD97706)),
                          SizedBox(width: 6),
                          Text(
                            'Chọn nhanh Tỉnh/Thành phố (63 tỉnh)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down_rounded, size: 18, color: Color(0xFFD97706)),
                        ],
                      ),
                    ),
                  ),
                ),

                // DANH SÁCH GỢI Ý KẾT QUẢ TÌM KIẾM
                if (_searchResults.isNotEmpty)
                  Card(
                    elevation: 5,
                    margin: const EdgeInsets.only(top: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = _searchResults[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place, color: Colors.red),
                            title: Text(
                              item['display_name']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: () => _selectSearchResult(item),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 3. THẺ HIỂN THỊ TỌA ĐỘ ĐÃ CHỌN
          Positioned(
            left: 12,
            right: 80,
            bottom: 12,
            child: Card(
              color: Colors.white.withValues(alpha: 0.92),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  _picked == null
                      ? 'Chạm bản đồ hoặc tìm kiếm để chọn vị trí.'
                      : (_selectedAddress != null
                            ? 'Đã chọn: $_selectedAddress'
                            : 'Đã chọn: ${_picked!.latitude.toStringAsFixed(6)}, ${_picked!.longitude.toStringAsFixed(6)}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'gps',
        backgroundColor: Colors.amber,
        onPressed: _locating ? null : _useGps,
        child: _locating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black87,
                ),
              )
            : const Icon(Icons.my_location, color: Colors.black87),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFFB07D00),
            ),
            onPressed: _picked == null
                ? null
                : () {
                    widget.onSelected?.call(_picked!, _selectedAddress);
                    Navigator.pop(context, _picked);
                  },
            icon: const Icon(Icons.check),
            label: const Text(
              'Dùng vị trí này',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
