import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/api_service.dart';
import 'widgets/common.dart';

/// Khách hàng tra cứu nguồn gốc mật ong: nhập mã lô, tìm theo tên hoặc quét QR.
/// Dùng được khi chưa đăng nhập.
class TraceLookupScreen extends StatefulWidget {
  const TraceLookupScreen({super.key});

  @override
  State<TraceLookupScreen> createState() => _TraceLookupScreenState();
}

class _TraceLookupScreenState extends State<TraceLookupScreen> {
  final _search = TextEditingController();
  List<Json>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String keyword) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiService.searchProducts(keyword);
      if (!mounted) return;
      final code = ApiService.parseTraceCode(keyword);
      if (code != null && items.length == 1) return _openTrace(code);
      setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTrace(int id) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TraceDetailScreen(traceId: id)));
  }

  Future<void> _scan() async {
    final code = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (code != null && mounted) _openTrace(code);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Tra cứu nguồn gốc mật ong')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Quét mã QR'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => _load(v.trim()),
            decoration: InputDecoration(
              hintText: 'Mã lô in trên nhãn, tên mật, vườn hoặc người nuôi ong',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _load(_search.text.trim())),
            ),
          ),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            hasData: _items != null,
            onRetry: () => _load(_search.text.trim()),
            child: RefreshIndicator(
              onRefresh: () => _load(_search.text.trim()),
              child: items.isEmpty
                  ? ListView(children: const [EmptyState(icon: Icons.search_off, message: 'Không tìm thấy sản phẩm phù hợp.')])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: kHoneyLight, child: Icon(Icons.water_drop, color: Color(0xFFB07D00))),
                            title: Text('#${item['maLo']} · ${show(item['sanPham'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${formatNumber(item['kg'])} kg · ${show(item['tenDiaDiem'])}\n${show(item['nguoiNuoiOng'])} · ${show(item['ngay'])}'),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openTrace(int.parse('${item['maLo']}')),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Quét mã QR trên nhãn sản phẩm, trả về mã lô.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final code = ApiService.parseTraceCode(barcode.rawValue ?? '');
      if (code != null) {
        _handled = true;
        Navigator.pop(context, code);
        return;
      }
    }
    showSnack(context, 'Mã QR không thuộc hệ thống truy xuất ong mật.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã QR'),
        actions: [IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch())],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Không mở được camera: ${error.errorDetails?.message ?? error.errorCode.name}.\nHãy cấp quyền camera hoặc nhập mã lô thủ công.',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: kHoney, width: 3), borderRadius: BorderRadius.circular(20)),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Text('Đưa mã QR trên nhãn mật ong vào khung', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6)])),
        ),
      ]),
    );
  }
}

/// Thông tin nguồn gốc, nhà sản xuất và hành trình của một lô mật.
class TraceDetailScreen extends StatefulWidget {
  const TraceDetailScreen({super.key, required this.traceId});
  final int traceId;

  @override
  State<TraceDetailScreen> createState() => _TraceDetailScreenState();
}

class _TraceDetailScreenState extends State<TraceDetailScreen> {
  Json? _trace;
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
      final trace = await ApiService.getPublicTrace(widget.traceId);
      if (mounted) setState(() => _trace = trace);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _trace ?? {};
    final point = _trace == null ? null : latLngOf(t);
    final journey = (t['hanhTrinh'] as List?)?.whereType<Map>().toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: Text('Lô mật #${widget.traceId}')),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _trace != null,
        onRetry: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFD76A), kHoney]), borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(show(t['sanPham']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${formatNumber(t['sanLuongDuKien'])} kg · ${show(t['trangThai'])} · ${show(t['thoiGian'])}'),
            ]),
          ),
          const SizedBox(height: 12),
          _section('Nguồn gốc sản phẩm', [
            _row('Loại ong', t['loaiOng']),
            _row('Đàn ong', t['tenDanOng'] == null ? null : '${t['tenDanOng']} (${show(t['soThung'], '0')} thùng)'),
            _row('Nguồn hoa', t['cayTruoc']),
            _row('Nơi khai thác', t['tenVuon'] ?? t['tenDiaDiem']),
            _row('Địa chỉ', t['diaChiChiTiet']),
          ]),
          _section('Nhà sản xuất', [
            _row('Người nuôi ong', t['nguoiNuoiOng']),
            _row('Điện thoại', t['sdtNguoiNuoiOng']),
            _row('Chủ đất', t['chuDat']),
          ]),
          if (point != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  options: MapOptions(initialCenter: point, initialZoom: 12),
                  children: [
                    osmTiles(),
                    MarkerLayer(markers: [Marker(point: point, width: 44, height: 44, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: Colors.red, size: 42))]),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Hành trình đàn ong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (journey.isEmpty) const Text('Chưa có dữ liệu hành trình.', style: TextStyle(color: Colors.black54)),
                ...journey.map((step) => IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Column(children: [
                          Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 4), decoration: const BoxDecoration(color: kHoney, shape: BoxShape.circle)),
                          Expanded(child: Container(width: 2, color: kHoneyLight)),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(show(step['thoiGian']), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              Text(show(step['loai']), style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(show(step['noiDung'])),
                            ]),
                          ),
                        ),
                      ]),
                    )),
              ]),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(ApiService.publicTraceUrl(widget.traceId)), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Mở trang truy xuất trên trình duyệt'),
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget?> rows) {
    final visible = rows.whereType<Widget>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...visible,
        ]),
      ),
    );
  }

  Widget? _row(String label, Object? value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54))),
        Expanded(child: Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
