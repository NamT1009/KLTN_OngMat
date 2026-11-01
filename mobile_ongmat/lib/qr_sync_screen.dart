import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/api_service.dart';
import 'widgets/common.dart';

/// Mỗi lần ghi sản lượng tạo một lô mật có mã truy xuất riêng; màn hình này
/// hiển thị mã QR của từng lô để in lên nhãn sản phẩm.
class QrSyncScreen extends StatefulWidget {
  const QrSyncScreen({super.key, this.initialTraceId});
  final int? initialTraceId;

  @override
  State<QrSyncScreen> createState() => _QrSyncScreenState();
}

class _QrSyncScreenState extends State<QrSyncScreen> {
  List<Json>? _traces;
  int? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialTraceId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final traces = await ApiService.getTraces();
      if (!mounted) return;
      setState(() {
        _traces = traces;
        final ids = traces.map((t) => int.tryParse('${t['id']}')).toSet();
        if (_selectedId == null || !ids.contains(_selectedId)) {
          _selectedId = traces.isEmpty ? null : int.tryParse('${traces.first['id']}');
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final traces = _traces ?? [];
    final selected = traces.where((t) => int.tryParse('${t['id']}') == _selectedId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Mã QR truy xuất')),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _traces != null,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (selected == null)
                const EmptyState(
                  icon: Icons.qr_code_2,
                  message: 'Chưa có lô mật nào. Hãy ghi sản lượng thu hoạch trong mục Sản lượng để tạo mã QR.',
                )
              else
                _QrCard(trace: selected),
              if (traces.length > 1) ...[
                const SizedBox(height: 16),
                const Text('Các lô mật khác', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...traces.map((t) {
                  final id = int.tryParse('${t['id']}');
                  return Card(
                    color: id == _selectedId ? kHoneyLight : null,
                    child: ListTile(
                      leading: const Icon(Icons.qr_code),
                      title: Text('#${t['id']} • ${show(t['sanPham'])}'),
                      subtitle: Text('${formatNumber(t['sanLuongDuKien'])} kg • ${show(t['tenDanOng'], show(t['tenDiaDiem']))} • ${show(t['thoiGian'])}'),
                      onTap: () => setState(() => _selectedId = id),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.trace});
  final Json trace;

  @override
  Widget build(BuildContext context) {
    final url = show(trace['qrUrl'], '${ApiConfig.baseUrl}/truy-xuat-qr?ma=${trace['id']}');
    final qrImage = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&margin=8&data=${Uri.encodeComponent(url)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Lô mật #${trace['id']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              width: 230,
              height: 230,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Colors.black12, width: 2), borderRadius: BorderRadius.circular(20)),
              child: Image.network(
                qrImage,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Text('Không tải được ảnh QR (cần Internet).\nVẫn có thể mở hoặc sao chép đường dẫn bên dưới.', textAlign: TextAlign.center),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _row('Sản phẩm', show(trace['sanPham'])),
            _row('Sản lượng', '${formatNumber(trace['sanLuongDuKien'])} kg'),
            _row('Đàn ong', show(trace['tenDanOng'])),
            _row('Nơi khai thác', show(trace['tenDiaDiem'])),
            _row('Giống ong', show(trace['loaiOng'])),
            _row('Thời gian', show(trace['thoiGian'])),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) showSnack(context, 'Đã sao chép đường dẫn truy xuất.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Sao chép'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && context.mounted) {
                      showSnack(context, 'Không mở được trình duyệt.', error: true);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Xem như khách'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
