import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_hub_screen.dart';
import 'main.dart';
import 'services/api_service.dart';
import 'trace_lookup_screen.dart';
import 'widgets/common.dart';

/// Quản trị viên trên mobile: theo dõi nhanh vị trí trại ong, thống kê và hoạt động hệ thống.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _tab = 0;
  Json? _data;
  bool _loading = true;
  String? _error;
  String _name = 'Quản trị viên';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _name = p.getString('hoTen') ?? _name);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getAdminOverview();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Json> _list(String key) {
    final v = _data?[key];
    return v is List
        ? v.whereType<Map>().map((e) => Json.from(e)).toList()
        : [];
  }

  Future<void> _logout() async {
    if (!await confirmDialog(
      context,
      title: 'Đăng xuất?',
      message: 'Bạn sẽ cần đăng nhập lại để tiếp tục.',
      confirmLabel: 'Đăng xuất',
    ))
      return;
    await ApiService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản trị hệ thống',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Tra cứu lô mật',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TraceLookupScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Tin nhắn',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatHubScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
        ],
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _data != null,
        onRetry: _load,
        child: IndexedStack(index: _tab, children: [_overview(), _map()]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Thống kê',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Bản đồ',
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final k = Json.from(_data?['kpi'] as Map? ?? {});
    final months = _list('sanLuongTheoThang');
    final maxKg = months.fold<double>(
      1,
      (m, x) => (double.tryParse('${x['kg']}') ?? 0) > m
          ? double.parse('${x['kg']}')
          : m,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Xin chào, $_name',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.3,
            children: [
              StatTile(
                label: 'Người dùng',
                value: show(k['tongNguoiDung'], '0'),
                icon: Icons.people,
                color: Colors.blue,
              ),
              StatTile(
                label: 'Địa điểm chờ duyệt',
                value: show(k['diaDiemChoDuyet'], '0'),
                icon: Icons.pending_actions,
                color: Colors.red,
              ),
              StatTile(
                label: 'Đàn ong',
                value: show(k['tongDanOng'], '0'),
                icon: Icons.hive,
                color: Colors.orange,
              ),
              StatTile(
                label: 'Thùng ong',
                value: show(k['tongThungOng'], '0'),
                icon: Icons.inventory_2,
                color: const Color(0xFF1E7B5F),
              ),
              StatTile(
                label: 'Hợp đồng hiệu lực',
                value: show(k['hopDongHieuLuc'], '0'),
                icon: Icons.handshake,
                color: Colors.indigo,
              ),
              StatTile(
                label: 'Sản lượng (kg)',
                value: formatNumber(k['tongSanLuongKg']),
                icon: Icons.water_drop,
                color: const Color(0xFF6366F1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sản lượng 12 tháng (kg)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: months.map((m) {
                        final kg = double.tryParse('${m['kg']}') ?? 0;
                        return Expanded(
                          child: Tooltip(
                            message: '${m['thang']}: ${formatNumber(kg)} kg',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  height: 120 * kg / maxKg + 2,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kHoney,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  show(m['thang']).substring(0, 2),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _listCard(
            'Sản lượng theo loại mật',
            _list('sanLuongTheoLoaiMat')
                .map((x) => (show(x['loaiMat']), '${formatNumber(x['kg'])} kg'))
                .toList(),
          ),
          _listCard(
            'Tình trạng đàn ong',
            _list('danOngTheoTinhTrang')
                .map(
                  (x) => (
                    show(x['tinhTrang']),
                    '${show(x['soDan'])} đàn · ${show(x['soThung'])} thùng',
                  ),
                )
                .toList(),
          ),
          _listCard(
            'Địa điểm sản lượng cao',
            _list('diaDiemSanLuongCao')
                .map(
                  (x) => (
                    '${show(x['tenDiaDiem'])}\n${show(x['chuDat'])}',
                    '${formatNumber(x['kg'])} kg',
                  ),
                )
                .toList(),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lô mật truy xuất gần đây',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._list('loTruyXuatGanDay').map(
                    (x) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('#${x['maLo']} · ${show(x['sanPham'])}'),
                      subtitle: Text(
                        '${formatNumber(x['kg'])} kg · ${show(x['tenDiaDiem'])} · ${show(x['nguoiNuoiOng'])}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TraceDetailScreen(
                            traceId: int.parse('${x['maLo']}'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listCard(String title, List<(String, String)> rows) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Text(
              'Chưa có dữ liệu.',
              style: TextStyle(color: Colors.black54),
            ),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(r.$1)),
                  Text(
                    r.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _map() {
    final locations = _list('locations');
    final hives = _list('hives');
    final markers = <Marker>[
      for (final l in locations)
        if (latLngOf(l) case final p?)
          Marker(
            point: p,
            width: 36,
            height: 36,
            child: GestureDetector(
              onTap: () => _info(
                show(l['tenDiaDiem']),
                'Chủ đất: ${show(l['tenChuDat'])}\n${show(l['soThung'], '0')}/${show(l['sucChuaToiDa'], '0')} thùng\nNgười thuê: ${show(l['nguoiThue'], 'chưa có')}',
              ),
              child: const Icon(
                Icons.landscape,
                color: Color(0xFF1E7B5F),
                size: 30,
              ),
            ),
          ),
      for (final h in hives)
        if (latLngOf(h) case final p?)
          Marker(
            point: p,
            width: 40,
            height: 40,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => _info(
                show(h['tenDanOng']),
                '${show(h['soThung'], '0')} thùng · ${show(h['tinhTrang'])}\n${show(h['viTri'])}\nNgười nuôi: ${show(h['tenNguoiNuoiOng'])}\nCập nhật: ${show(h['ngayCapNhat'])}',
              ),
              child: const Icon(Icons.location_on, color: Colors.red, size: 38),
            ),
          ),
    ];
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: markers.isNotEmpty
                ? markers.first.point
                : kDefaultCenter,
            initialZoom: 5.5,
            initialCameraFit: markers.length > 1
                ? CameraFit.coordinates(
                    coordinates: markers.map((m) => m.point).toList(),
                    padding: const EdgeInsets.all(40),
                  )
                : null,
          ),
          children: [
            osmTiles(),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '${locations.length} địa điểm (xanh) · ${hives.length} đàn ong có GPS (đỏ)',
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _info(String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
