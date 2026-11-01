import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'qr_sync_screen.dart';
import 'services/api_service.dart';
import 'widgets/common.dart';

const _careDone = 'Đã hoàn thành';
const _carePlanned = 'Lên lịch';

class BeekeepingDashboardScreen extends StatefulWidget {
  const BeekeepingDashboardScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<BeekeepingDashboardScreen> createState() => _BeekeepingDashboardScreenState();
}

class _BeekeepingDashboardScreenState extends State<BeekeepingDashboardScreen> {
  late int _tab = widget.initialTab.clamp(0, 3);
  Json? _data;
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
      final data = await ApiService.getBeekeepingDashboard();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e));
      if (_data != null) showSnack(context, _error!, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Json> _list(String key) {
    final value = _data?[key];
    return value is List ? value.whereType<Map>().map((e) => Json.from(e)).toList() : [];
  }

  List<Json> get _hives => _list('hives');
  List<Json> get _rented => _list('rentedLocations');

  Future<void> _act(Future<String> Function() action) async {
    if (await runAction(context, action)) await _load();
  }

  Future<T?> _page<T>(Widget page) => Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));

  // ================= THAO TÁC ĐÀN ONG =================

  Future<void> _addHive() async {
    final payload = await _page<Json>(HiveFormPage(rentedLocations: _rented));
    if (payload != null) await _act(() => ApiService.createHive(payload));
  }

  Future<void> _editHive(Json hive) async {
    final payload = await _page<Json>(HiveFormPage(hive: hive, rentedLocations: _rented));
    if (payload != null) await _act(() => ApiService.updateHive('${hive['maDanOng']}', payload));
  }

  Future<void> _deleteHive(Json hive) async {
    final ok = await confirmDialog(
      context,
      title: 'Xóa ${show(hive['tenDanOng'])}?',
      message: 'Các thùng ong của đàn sẽ bị xóa. Lịch sử sản lượng vẫn được giữ để truy xuất nguồn gốc.',
      confirmLabel: 'Xóa',
      danger: true,
    );
    if (ok) await _act(() => ApiService.deleteHive('${hive['maDanOng']}'));
  }

  Future<void> _gpsFromDevice(Json hive) async {
    await _act(() async {
      final position = await currentPosition();
      return ApiService.updateHiveLocation(
        hiveId: '${hive['maDanOng']}',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    });
  }

  Future<void> _gpsFromMap(Json hive) async {
    final picked = await _page<LatLng>(LocationPickerScreen(initial: latLngOf(hive), title: 'Vị trí ${show(hive['tenDanOng'])}'));
    if (picked == null || !mounted) return;
    final name = await promptText(context, title: 'Tên vị trí', label: 'Mô tả vị trí (không bắt buộc)', initial: show(hive['viTri'], ''));
    if (name == null) return;
    await _act(() => ApiService.updateHiveLocation(
          hiveId: '${hive['maDanOng']}',
          latitude: picked.latitude,
          longitude: picked.longitude,
          locationName: name.isEmpty ? null : name,
        ));
  }

  Future<void> _showGpsHistory(Json hive) async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => FutureBuilder<List<Json>>(
        future: ApiService.getGpsHistory('${hive['maDanOng']}'),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text(errorText(snapshot.error!)));
          final items = snapshot.data ?? [];
          if (items.isEmpty) return const EmptyState(icon: Icons.gps_off, message: 'Chưa có lịch sử GPS.');
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Lịch sử vị trí ${show(hive['tenDanOng'])}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ...items.map((item) => ListTile(
                    leading: const Icon(Icons.location_history, color: Colors.orange),
                    title: Text(show(item['viTri'], 'Vị trí')),
                    subtitle: Text('${double.tryParse('${item['viDo']}')?.toStringAsFixed(5)}, ${double.tryParse('${item['kinhDo']}')?.toStringAsFixed(5)}'),
                    trailing: Text(show(item['thoiGian']), style: const TextStyle(fontSize: 12)),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _hiveActions(Json hive) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget item(String value, IconData icon, String label, {Color? color}) => ListTile(
              leading: Icon(icon, color: color),
              title: Text(label, style: TextStyle(color: color)),
              onTap: () => Navigator.pop(sheetContext, value),
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(show(hive['tenDanOng']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                item('device', Icons.my_location, 'Cập nhật GPS từ thiết bị'),
                item('map', Icons.map_outlined, 'Chọn vị trí trên bản đồ'),
                item('history', Icons.history, 'Lịch sử vị trí'),
                item('care', Icons.event_note, 'Ghi nhận chăm sóc'),
                item('move', Icons.route, 'Lên lịch di chuyển'),
                item('production', Icons.water_drop_outlined, 'Ghi sản lượng thu hoạch'),
                item('edit', Icons.edit_outlined, 'Sửa đàn ong / số thùng'),
                item('delete', Icons.delete_outline, 'Xóa đàn ong', color: Colors.red),
              ],
            ),
          ),
        );
      },
    );
    switch (action) {
      case 'device':
        await _gpsFromDevice(hive);
      case 'map':
        await _gpsFromMap(hive);
      case 'history':
        await _showGpsHistory(hive);
      case 'care':
        await _addCare(hive);
      case 'move':
        await _addMove(hive);
      case 'production':
        await _addProduction(hive);
      case 'edit':
        await _editHive(hive);
      case 'delete':
        await _deleteHive(hive);
    }
  }

  // ================= CHĂM SÓC / DI CHUYỂN / SẢN LƯỢNG =================

  Future<void> _addCare([Json? hive]) async {
    final payload = await _page<Json>(CareFormPage(hives: _hives, initialHiveId: hive?['maDanOng']?.toString()));
    if (payload != null) await _act(() => ApiService.addCareLog(payload));
  }

  Future<void> _addMove([Json? hive]) async {
    if (_hives.isEmpty) return showSnack(context, 'Hãy tạo đàn ong trước khi lên lịch di chuyển.');
    final payload = await _page<Json>(MoveFormPage(hives: _hives, rentedLocations: _rented, initialHiveId: hive?['maDanOng']?.toString()));
    if (payload != null) await _act(() => ApiService.addHiveMove(payload));
  }

  Future<void> _addProduction([Json? hive]) async {
    if (_hives.isEmpty) return showSnack(context, 'Hãy tạo đàn ong trước khi ghi sản lượng.');
    final payload = await _page<Json>(ProductionFormPage(hives: _hives, initialHiveId: hive?['maDanOng']?.toString()));
    if (payload != null) await _act(() => ApiService.addProduction(payload));
  }

  // ================= GIAO DIỆN =================

  static const _titles = ['Đàn ong & thùng ong', 'Lịch chăm sóc', 'Di chuyển đàn ong', 'Sản lượng mật ong'];
  static const _fabLabels = ['Thêm đàn ong', 'Thêm lịch', 'Lên lịch', 'Ghi sản lượng'];

  @override
  Widget build(BuildContext context) {
    final actions = [_addHive, _addCare, _addMove, _addProduction];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _data != null,
        onRetry: _load,
        child: IndexedStack(
          index: _tab,
          children: [_hivesView(), _careView(), _movesView(), _productionView()],
        ),
      ),
      floatingActionButton: _data == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => actions[_tab](),
              icon: const Icon(Icons.add),
              label: Text(_fabLabels[_tab]),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.hive_outlined), selectedIcon: Icon(Icons.hive), label: 'Đàn ong'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Chăm sóc'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Di chuyển'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Sản lượng'),
        ],
      ),
    );
  }

  Widget _scroll(List<Widget> children) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: children),
      );

  Widget _hivesView() {
    final hives = _hives;
    final summary = Json.from(_data?['summary'] as Map? ?? {});
    return _scroll([
      Row(children: [
        Expanded(child: StatTile(label: 'Đàn ong', value: show(summary['totalHives'], '0'), icon: Icons.hive, color: Colors.orange)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(label: 'Thùng ong', value: show(summary['totalBoxes'], '0'), icon: Icons.inventory_2, color: const Color(0xFF1E7B5F))),
      ]),
      const SizedBox(height: 12),
      _HiveMap(hives: hives, onTapHive: _hiveActions),
      if (_rented.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Card(
            color: Color(0xFFEFF6FF),
            child: ListTile(
              leading: Icon(Icons.info_outline, color: Colors.blue),
              title: Text('Bạn chưa có đất thuê. Ký hợp đồng thuê đất để đặt đàn ong tại vườn của chủ đất.'),
            ),
          ),
        ),
      const SizedBox(height: 12),
      if (hives.isEmpty)
        EmptyState(
          icon: Icons.hive_outlined,
          message: 'Chưa có đàn ong nào.',
          action: FilledButton.icon(onPressed: _addHive, icon: const Icon(Icons.add), label: const Text('Thêm đàn ong')),
        ),
      ...hives.map((hive) => Card(
            child: ListTile(
              onTap: () => _hiveActions(hive),
              leading: const CircleAvatar(backgroundColor: kHoneyLight, child: Icon(Icons.hive, color: Colors.orange)),
              title: Text(show(hive['tenDanOng']), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${show(hive['soThung'], '0')} thùng • ${show(hive['tinhTrang'])}\n'
                '${hive['tenDiaDiem'] != null ? 'Đất thuê: ${hive['tenDiaDiem']}' : show(hive['viTri'], 'Chưa có vị trí')}'
                '${latLngOf(hive) == null ? ' • chưa có GPS' : ''}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.more_vert),
            ),
          )),
    ]);
  }

  Widget _careView() {
    final items = _list('careSchedule');
    return _scroll([
      if (items.isEmpty) const EmptyState(icon: Icons.event_available, message: 'Chưa có lịch chăm sóc.'),
      ...items.map((item) {
        final done = item['trangThai'] == _careDone;
        return Dismissible(
          key: ValueKey('care-${item['maLich']}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) => confirmDialog(context, title: 'Xóa lịch chăm sóc?', message: show(item['tenCongViec']), confirmLabel: 'Xóa', danger: true),
          onDismissed: (_) => _act(() => ApiService.deleteCareLog('${item['maLich']}')),
          child: Card(
            child: CheckboxListTile(
              value: done,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => _act(() => ApiService.updateCareStatus('${item['maLich']}', value == true ? _careDone : _carePlanned)),
              title: Text(
                show(item['tenCongViec']),
                style: TextStyle(fontWeight: FontWeight.w700, decoration: done ? TextDecoration.lineThrough : null),
              ),
              subtitle: Text([
                '${show(item['ngay'])} ${show(item['gio'], '')}'.trim(),
                if (item['tenDanOng'] != null) item['tenDanOng'],
                if (item['diaDiem'] != null) item['diaDiem'],
              ].join(' • ')),
              secondary: StatusChip(item['trangThai']),
            ),
          ),
        );
      }),
      if (items.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Chạm ô vuông để đánh dấu hoàn thành • vuốt sang trái để xóa', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45, fontSize: 12)),
        ),
    ]);
  }

  Widget _movesView() {
    final items = _list('movements');
    return _scroll([
      if (items.isEmpty) const EmptyState(icon: Icons.route_outlined, message: 'Chưa có lịch di chuyển.'),
      ...items.map((item) {
        final status = show(item['trangThai']);
        final id = '${item['maDiChuyen']}';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.local_shipping_outlined, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(show(item['tenDanOng'], 'Đàn ong'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  StatusChip(status),
                ]),
                const SizedBox(height: 8),
                Text('${show(item['viTriDi'])}  →  ${show(item['viTriDen'])}'),
                const SizedBox(height: 4),
                Text('Ngày ${show(item['ngay'])}${item['bienSo'] != null ? ' • Xe ${item['bienSo']}' : ''}', style: const TextStyle(color: Colors.black54)),
                if (status == 'Lên lịch' || status == 'Đang di chuyển')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, children: [
                      if (status == 'Lên lịch')
                        OutlinedButton.icon(
                          onPressed: () => _act(() => ApiService.updateMoveStatus(id, 'Đang di chuyển')),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Bắt đầu'),
                        ),
                      FilledButton.icon(
                        onPressed: () => _act(() => ApiService.updateMoveStatus(id, 'Hoàn thành')),
                        icon: const Icon(Icons.flag),
                        label: const Text('Đã tới nơi'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (await confirmDialog(context, title: 'Hủy lịch di chuyển?', message: 'Đàn ong sẽ giữ nguyên vị trí hiện tại.', confirmLabel: 'Hủy lịch', danger: true)) {
                            await _act(() => ApiService.updateMoveStatus(id, 'Đã hủy'));
                          }
                        },
                        child: const Text('Hủy'),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  Widget _productionView() {
    final items = _list('production');
    final summary = Json.from(_data?['summary'] as Map? ?? {});
    return _scroll([
      StatTile(label: 'Tổng sản lượng (kg)', value: formatNumber(summary['totalProductionKg']), icon: Icons.water_drop, color: const Color(0xFF6366F1)),
      const SizedBox(height: 12),
      if (items.isEmpty) const EmptyState(icon: Icons.water_drop_outlined, message: 'Chưa có sản lượng. Mỗi lần thu hoạch sẽ tự tạo mã QR truy xuất.'),
      ...items.map((item) => Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFEDE9FE), child: Icon(Icons.water_drop, color: Color(0xFF6366F1))),
              title: Text('${formatNumber(item['sanLuong'])} ${show(item['donVi'], 'kg')} • ${show(item['loaiMat'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${show(item['ngay'])} • ${show(item['tenDanOng'], 'Đàn ong')}${item['tenDiaDiem'] != null ? '\n${item['tenDiaDiem']}' : ''}'),
              isThreeLine: item['tenDiaDiem'] != null,
              trailing: item['maTruyXuat'] == null
                  ? null
                  : IconButton(
                      tooltip: 'Mã QR truy xuất',
                      icon: const Icon(Icons.qr_code_2),
                      onPressed: () => _page<void>(QrSyncScreen(initialTraceId: int.tryParse('${item['maTruyXuat']}'))),
                    ),
            ),
          )),
    ]);
  }
}

class _HiveMap extends StatelessWidget {
  const _HiveMap({required this.hives, required this.onTapHive});
  final List<Json> hives;
  final ValueChanged<Json> onTapHive;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final hive in hives)
        if (latLngOf(hive) case final point?) (hive: hive, point: point),
    ];
    final fit = points.length > 1
        ? CameraFit.coordinates(coordinates: points.map((p) => p.point).toList(), padding: const EdgeInsets.all(40), maxZoom: 14)
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 220,
        child: Stack(children: [
          FlutterMap(
            key: ValueKey(points.map((p) => '${p.point.latitude},${p.point.longitude}').join('|')),
            options: MapOptions(
              initialCenter: points.isNotEmpty ? points.first.point : kDefaultCenter,
              initialZoom: points.isNotEmpty ? 13 : 5.5,
              initialCameraFit: fit,
            ),
            children: [
              osmTiles(),
              MarkerLayer(
                markers: points
                    .map((p) => Marker(
                          point: p.point,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => onTapHive(p.hive),
                            child: Tooltip(message: show(p.hive['tenDanOng']), child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          if (points.isEmpty)
            const Center(
              child: Card(child: Padding(padding: EdgeInsets.all(10), child: Text('Chưa có tọa độ GPS. Chọn một đàn ong để cập nhật vị trí.'))),
            ),
        ]),
      ),
    );
  }
}

// ================= CÁC TRANG NHẬP LIỆU =================

class _FormPage extends StatelessWidget {
  const _FormPage({required this.title, required this.formKey, required this.onSave, required this.children});
  final String title;
  final GlobalKey<FormState> formKey;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final child in children) Padding(padding: const EdgeInsets.only(bottom: 14), child: child),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Lưu'),
          ),
        ),
      ),
    );
  }
}

DropdownButtonFormField<String> _hivePicker(List<Json> hives, String? value, ValueChanged<String?> onChanged, {bool required = true}) {
  return DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Đàn ong', prefixIcon: Icon(Icons.hive_outlined)),
    items: [
      if (!required) const DropdownMenuItem(value: null, child: Text('Không gắn đàn ong cụ thể')),
      ...hives.map((h) => DropdownMenuItem(value: '${h['maDanOng']}', child: Text('${show(h['tenDanOng'])} (${show(h['soThung'], '0')} thùng)'))),
    ],
    onChanged: onChanged,
    validator: required ? (v) => v == null ? 'Chọn đàn ong' : null : null,
  );
}

Widget _suggestions(List<String> values, TextEditingController controller) => Wrap(
      spacing: 6,
      runSpacing: -6,
      children: values.map((v) => ActionChip(label: Text(v), onPressed: () => controller.text = v)).toList(),
    );

class HiveFormPage extends StatefulWidget {
  const HiveFormPage({super.key, this.hive, required this.rentedLocations});
  final Json? hive;
  final List<Json> rentedLocations;

  @override
  State<HiveFormPage> createState() => _HiveFormPageState();
}

class _HiveFormPageState extends State<HiveFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.hive?['tenDanOng']?.toString() ?? '');
  late final _boxes = TextEditingController(text: widget.hive?['soThung']?.toString() ?? '10');
  late final _place = TextEditingController(text: widget.hive?['viTri']?.toString() ?? '');
  late final _status = TextEditingController(text: widget.hive?['tinhTrang']?.toString() ?? 'Khỏe mạnh');
  late final _flower = TextEditingController(text: widget.hive?['cayTruoc']?.toString() ?? '');
  late int? _location = int.tryParse('${widget.hive?['maDiaDiem']}');

  @override
  void dispose() {
    for (final c in [_name, _boxes, _place, _status, _flower]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop<Json>(context, {
      'tenDanOng': _name.text.trim(),
      'soThung': int.parse(_boxes.text.trim()),
      'viTri': _place.text.trim(),
      'tinhTrang': _status.text.trim(),
      'cayTruoc': _flower.text.trim(),
      'maDiaDiem': _location,
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.rentedLocations.any((l) => int.tryParse('${l['maDiaDiem']}') == _location);
    return _FormPage(
      title: widget.hive == null ? 'Thêm đàn ong' : 'Sửa đàn ong',
      formKey: _formKey,
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Tên đàn ong', prefixIcon: Icon(Icons.badge_outlined)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Nhập tên đàn ong' : null,
        ),
        TextFormField(
          controller: _boxes,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Số thùng ong', prefixIcon: Icon(Icons.inventory_2_outlined), helperText: 'Hệ thống tự tạo mã cho từng thùng'),
          validator: (v) {
            final n = int.tryParse((v ?? '').trim());
            return n == null || n < 1 || n > 500 ? 'Số thùng từ 1 đến 500' : null;
          },
        ),
        DropdownButtonFormField<int>(
          initialValue: hasLocation ? _location : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Đặt tại đất đã thuê', prefixIcon: Icon(Icons.landscape_outlined)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Không – vị trí riêng của tôi')),
            ...widget.rentedLocations.map((l) => DropdownMenuItem(
                  value: int.tryParse('${l['maDiaDiem']}'),
                  child: Text('${show(l['tenDiaDiem'])} (còn ${(int.tryParse('${l['sucChuaToiDa']}') ?? 0) - (int.tryParse('${l['soThungDangDat']}') ?? 0)} chỗ)'),
                )),
          ],
          onChanged: (value) => setState(() => _location = value),
        ),
        TextFormField(controller: _place, decoration: const InputDecoration(labelText: 'Mô tả vị trí', prefixIcon: Icon(Icons.place_outlined))),
        TextFormField(controller: _status, decoration: const InputDecoration(labelText: 'Tình trạng đàn', prefixIcon: Icon(Icons.health_and_safety_outlined))),
        _suggestions(['Khỏe mạnh', 'Cần bổ sung thức ăn', 'Đang chia đàn', 'Có dấu hiệu bệnh', 'Yếu'], _status),
        TextFormField(controller: _flower, decoration: const InputDecoration(labelText: 'Nguồn hoa', prefixIcon: Icon(Icons.local_florist_outlined))),
        _suggestions(['Hoa nhãn', 'Hoa vải', 'Hoa cà phê', 'Hoa bạc hà', 'Hoa keo'], _flower),
      ],
    );
  }
}

class CareFormPage extends StatefulWidget {
  const CareFormPage({super.key, required this.hives, this.initialHiveId});
  final List<Json> hives;
  final String? initialHiveId;

  @override
  State<CareFormPage> createState() => _CareFormPageState();
}

class _CareFormPageState extends State<CareFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _task = TextEditingController(text: 'Kiểm tra sức khỏe đàn ong');
  final _date = TextEditingController(text: isoDate(DateTime.now()));
  final _time = TextEditingController(text: '07:00');
  final _note = TextEditingController();
  late String? _hive = widget.initialHiveId;
  bool _done = false;

  @override
  void dispose() {
    for (final c in [_task, _date, _time, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormPage(
      title: 'Lịch chăm sóc',
      formKey: _formKey,
      onSave: () {
        if (!_formKey.currentState!.validate()) return;
        Navigator.pop<Json>(context, {
          'maDanOng': _hive,
          'tenCongViec': _task.text.trim(),
          'ngay': _date.text,
          'gio': _time.text,
          'ghiChu': _note.text.trim(),
          'trangThai': _done ? _careDone : _carePlanned,
        });
      },
      children: [
        _hivePicker(widget.hives, _hive, (v) => setState(() => _hive = v), required: false),
        TextFormField(
          controller: _task,
          decoration: const InputDecoration(labelText: 'Công việc', prefixIcon: Icon(Icons.task_alt)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Nhập công việc' : null,
        ),
        _suggestions(['Kiểm tra sức khỏe đàn ong', 'Bổ sung thức ăn', 'Cho uống nước', 'Phòng trị bệnh', 'Thay ong chúa', 'Vệ sinh thùng'], _task),
        Row(children: [
          Expanded(child: DateField(controller: _date, label: 'Ngày')),
          const SizedBox(width: 12),
          Expanded(child: TimeField(controller: _time, label: 'Giờ')),
        ]),
        TextFormField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Ghi chú')),
        SwitchListTile(
          value: _done,
          onChanged: (v) => setState(() => _done = v),
          title: const Text('Đã thực hiện xong'),
          subtitle: const Text('Bật nếu đây là ghi nhận công việc đã làm'),
        ),
      ],
    );
  }
}

class MoveFormPage extends StatefulWidget {
  const MoveFormPage({super.key, required this.hives, required this.rentedLocations, this.initialHiveId});
  final List<Json> hives;
  final List<Json> rentedLocations;
  final String? initialHiveId;

  @override
  State<MoveFormPage> createState() => _MoveFormPageState();
}

class _MoveFormPageState extends State<MoveFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _destination = TextEditingController();
  final _date = TextEditingController(text: isoDate(DateTime.now()));
  final _plate = TextEditingController();
  final _note = TextEditingController();
  late String? _hive = widget.initialHiveId;
  late bool _toRented = widget.rentedLocations.isNotEmpty;
  int? _location;

  @override
  void dispose() {
    for (final c in [_destination, _date, _plate, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hive = widget.hives.where((h) => '${h['maDanOng']}' == _hive).firstOrNull;
    return _FormPage(
      title: 'Lên lịch di chuyển',
      formKey: _formKey,
      onSave: () {
        if (!_formKey.currentState!.validate()) return;
        Navigator.pop<Json>(context, {
          'maDanOng': _hive,
          if (_toRented) 'maDiaDiemDen': _location else 'viTriDen': _destination.text.trim(),
          'ngay': _date.text,
          'bienSo': _plate.text.trim(),
          'ghiChu': _note.text.trim(),
        });
      },
      children: [
        _hivePicker(widget.hives, _hive, (v) => setState(() => _hive = v)),
        if (hive != null) Text('Vị trí hiện tại: ${show(hive['tenDiaDiem'] ?? hive['viTri'], 'chưa xác định')}', style: const TextStyle(color: Colors.black54)),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Đất đã thuê'), icon: Icon(Icons.landscape_outlined)),
            ButtonSegment(value: false, label: Text('Vị trí khác'), icon: Icon(Icons.edit_location_alt_outlined)),
          ],
          selected: {_toRented},
          onSelectionChanged: (v) => setState(() => _toRented = v.first),
        ),
        if (_toRented)
          widget.rentedLocations.isEmpty
              ? const Text('Bạn chưa có đất thuê đã ký hợp đồng.', style: TextStyle(color: Colors.red))
              : DropdownButtonFormField<int>(
                  initialValue: _location,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Điểm đến', prefixIcon: Icon(Icons.flag_outlined)),
                  items: widget.rentedLocations
                      .map((l) => DropdownMenuItem(value: int.tryParse('${l['maDiaDiem']}'), child: Text(show(l['tenDiaDiem']))))
                      .toList(),
                  onChanged: (v) => setState(() => _location = v),
                  validator: (v) => v == null ? 'Chọn điểm đến' : null,
                )
        else
          TextFormField(
            controller: _destination,
            decoration: const InputDecoration(labelText: 'Điểm đến', prefixIcon: Icon(Icons.flag_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Nhập điểm đến' : null,
          ),
        DateField(controller: _date, label: 'Ngày di chuyển'),
        TextFormField(controller: _plate, decoration: const InputDecoration(labelText: 'Biển số xe (không bắt buộc)', prefixIcon: Icon(Icons.local_shipping_outlined))),
        TextFormField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú')),
      ],
    );
  }
}

class ProductionFormPage extends StatefulWidget {
  const ProductionFormPage({super.key, required this.hives, this.initialHiveId});
  final List<Json> hives;
  final String? initialHiveId;

  @override
  State<ProductionFormPage> createState() => _ProductionFormPageState();
}

class _ProductionFormPageState extends State<ProductionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _type = TextEditingController(text: 'Mật hoa nhãn');
  final _bee = TextEditingController(text: 'Ong ngoại (Apis mellifera)');
  final _date = TextEditingController(text: isoDate(DateTime.now()));
  final _note = TextEditingController();
  late String? _hive = widget.initialHiveId ?? (widget.hives.length == 1 ? '${widget.hives.first['maDanOng']}' : null);
  String _unit = 'kg';

  @override
  void dispose() {
    for (final c in [_quantity, _type, _bee, _date, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormPage(
      title: 'Ghi sản lượng thu hoạch',
      formKey: _formKey,
      onSave: () {
        if (!_formKey.currentState!.validate()) return;
        Navigator.pop<Json>(context, {
          'maDanOng': _hive,
          'sanLuong': double.parse(_quantity.text.trim().replaceAll(',', '.')),
          'donVi': _unit,
          'loaiMat': _type.text.trim(),
          'loaiOng': _bee.text.trim(),
          'ngay': _date.text,
          'ghiChu': _note.text.trim(),
        });
      },
      children: [
        _hivePicker(widget.hives, _hive, (v) => setState(() => _hive = v)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextFormField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Sản lượng', prefixIcon: Icon(Icons.scale_outlined)),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                return n == null || n <= 0 ? 'Lớn hơn 0' : null;
              },
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'kg', label: Text('kg')), ButtonSegment(value: 'lít', label: Text('lít'))],
            selected: {_unit},
            onSelectionChanged: (v) => setState(() => _unit = v.first),
          ),
        ]),
        TextFormField(
          controller: _type,
          decoration: const InputDecoration(labelText: 'Loại mật', prefixIcon: Icon(Icons.water_drop_outlined)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Nhập loại mật' : null,
        ),
        _suggestions(['Mật hoa nhãn', 'Mật hoa vải', 'Mật hoa cà phê', 'Mật bạc hà', 'Mật hoa keo'], _type),
        TextFormField(controller: _bee, decoration: const InputDecoration(labelText: 'Giống ong', prefixIcon: Icon(Icons.bug_report_outlined))),
        DateField(controller: _date, label: 'Ngày thu hoạch'),
        TextFormField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú')),
        const Text('Sau khi lưu, hệ thống tự tạo mã QR truy xuất nguồn gốc cho lô mật này.', style: TextStyle(color: Colors.black54)),
      ],
    );
  }
}
