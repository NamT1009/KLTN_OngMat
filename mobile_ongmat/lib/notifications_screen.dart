import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Json>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiService.getNotifications();
      if (!mounted) return;
      setState(() => _items = items);
      // Mở màn hình nghĩa là đã xem: đánh dấu đã đọc ở nền, không chặn giao diện.
      if (items.any((item) => item['daDoc'] != true)) {
        ApiService.markNotificationsRead().catchError((_) {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _items != null,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: items.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.notifications_none, message: 'Chưa có thông báo.')])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final level = show(item['mucDo'], 'Thấp');
                    final color = level == 'Cao' ? Colors.red : level == 'Trung bình' ? Colors.orange : Colors.blueGrey;
                    final unread = item['daDoc'] != true;
                    return Card(
                      color: unread ? const Color(0xFFFFFBEB) : Colors.white,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(level == 'Cao' ? Icons.priority_high_rounded : Icons.notifications_rounded, color: color),
                        ),
                        title: Text(show(item['tieuDe']), style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                        subtitle: Text('${show(item['noiDung'])}\n${show(item['thoiGian'])}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
