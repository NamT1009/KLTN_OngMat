import 'chat_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'services/api_service.dart';
import 'widgets/common.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// Nghiệp vụ chủ đất: đăng địa điểm đặt ong, duyệt yêu cầu thuê,
/// giám sát đàn ong và sản lượng khai thác trên đất của mình.
class LandownerScreen extends StatefulWidget {
  const LandownerScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<LandownerScreen> createState() => _LandownerScreenState();
}

class _LandownerScreenState extends State<LandownerScreen> {
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
      final data = await ApiService.getLandownerDashboard();
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
    return value is List
        ? value.whereType<Map>().map((e) => Json.from(e)).toList()
        : [];
  }

  Json get _summary => Json.from(_data?['summary'] as Map? ?? {});

  Future<void> _act(Future<String> Function() action) async {
    if (await runAction(context, action)) await _load();
  }

  // ================= ĐỊA ĐIỂM =================

  Future<void> _addLocation() async {
    final payload = await Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => const LocationFormPage()),
    );
    if (payload != null) await _act(() => ApiService.createLocation(payload));
  }

  Future<void> _editLocation(Json location) async {
    final rented = int.tryParse('${location['soDanDaThue']}') ?? 0;
    if (location['nguoiThue'] != null || rented > 0) {
      return showSnack(
        context,
        'Địa điểm đang có hợp đồng thuê hiệu lực nên không thể chỉnh sửa.',
      );
    }
    final payload = await Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => LocationFormPage(location: location)),
    );
    if (payload != null) {
      await _act(
        () => ApiService.updateLocation(
          int.parse('${location['maDiaDiem']}'),
          payload,
        ),
      );
    }
  }

  Future<void> _deleteLocation(Json location) async {
    final ok = await confirmDialog(
      context,
      title: 'Xóa ${show(location['tenDiaDiem'])}?',
      message:
          'Chỉ xóa được địa điểm chưa phát sinh yêu cầu thuê, hợp đồng hoặc đàn ong.',
      confirmLabel: 'Xóa',
      danger: true,
    );
    if (ok) {
      await _act(
        () => ApiService.deleteLocation(int.parse('${location['maDiaDiem']}')),
      );
    }
  }

  // ================= YÊU CẦU THUÊ =================

  Future<void> _approve(Json request) async {
    final isNew =
        request['laNguoiMoiNuoiOng'] == true ||
        request['laNguoiMoiNuoiOng'] == 1 ||
        request['laNguoiMoiNuoiOng'] == '1' ||
        (int.tryParse('${request['tongDanhGiaNguoiNuoiOng']}') ?? 0) == 0;
    final rating = num.tryParse('${request['uyTinNguoiNuoiOng']}');
    final count = int.tryParse('${request['tongDanhGiaNguoiNuoiOng']}') ?? 0;
    final beekeeperName = show(request['tenNguoiNuoiOng']);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF1E7B5F)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Xem xét duyệt cho thuê')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yêu cầu thuê vườn ${show(request['tenDiaDiem'])} cho ${show(request['soDanOng'], '0')} đàn ong.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isNew
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isNew
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Người thuê: $beekeeperName',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        UserReputationBadge(
                          isNew: isNew,
                          rating: rating,
                          reviewCount: count,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isNew) ...[
                      const Text(
                        '⚠️ Người nuôi ong này là Người mới (chưa có đánh giá từ việc thuê vườn trước). '
                        'Bạn nên trao đổi kỹ về phương án di chuyển, bảo vệ cây cối và tiền đặt cọc trước khi duyệt cho thuê!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF065F46),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else ...[
                      Text(
                        '✨ Người nuôi ong có uy tín ${rating?.toStringAsFixed(1) ?? '5.0'}/5 ⭐ từ $count lượt đánh giá của các chủ đất khác. Đối tác đáng tin cậy!',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bạn có đồng ý duyệt và tiến hành chốt giá hợp đồng không?',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cân nhắc lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tiếp tục duyệt'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final price = await promptText(
      context,
      title: 'Duyệt cho thuê ${show(request['tenDiaDiem'])}',
      label: 'Giá thuê chốt (đồng)',
      initial: request['giaThueDuKien'] == null
          ? ''
          : formatNumber(request['giaThueDuKien']),
      keyboardType: TextInputType.number,
      confirmLabel: 'Duyệt & tạo hợp đồng',
      helper:
          'Hợp đồng sẽ được gửi cho ${show(request['tenNguoiNuoiOng'])} ký xác nhận.',
    );
    if (price == null) return;
    final digits = price.replaceAll(RegExp(r'[^0-9]'), '');
    await _act(
      () => ApiService.approveRentalRequest(
        '${request['maYeuCau']}',
        giaThue: digits.isEmpty ? null : num.parse(digits),
      ),
    );
  }

  Future<void> _reject(Json request) async {
    final reason = await promptText(
      context,
      title: 'Từ chối yêu cầu',
      label: 'Lý do',
      required: true,
      confirmLabel: 'Từ chối',
    );
    if (reason != null) {
      await _act(
        () => ApiService.rejectRentalRequest('${request['maYeuCau']}', reason),
      );
    }
  }

  // ================= GIAO DIỆN =================

  static const _titles = [
    'Địa điểm của tôi',
    'Yêu cầu thuê',
    'Đàn ong trên đất',
    'Sản lượng trên đất',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _data != null,
        onRetry: _load,
        child: IndexedStack(
          index: _tab,
          children: [
            _locationsView(),
            _requestsView(),
            _hivesView(),
            _productionView(),
          ],
        ),
      ),
      floatingActionButton: _tab == 0 && _data != null
          ? FloatingActionButton.extended(
              onPressed: _addLocation,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Đăng địa điểm'),
            )
          : null,
    );
  }

  Widget _scroll(List<Widget> children) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: children,
    ),
  );

  Widget _pointsMap(
    List<Json> items,
    String Function(Json) label,
    Color color,
  ) {
    final points = [
      for (final item in items)
        if (latLngOf(item) case final point?) (item: item, point: point),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 200,
        child: FlutterMap(
          key: ValueKey(
            points
                .map((p) => '${p.point.latitude},${p.point.longitude}')
                .join('|'),
          ),
          options: MapOptions(
            initialCenter: points.isNotEmpty
                ? points.first.point
                : kDefaultCenter,
            initialZoom: points.isNotEmpty ? 12 : 5.5,
            initialCameraFit: points.length > 1
                ? CameraFit.coordinates(
                    coordinates: points.map((p) => p.point).toList(),
                    padding: const EdgeInsets.all(40),
                    maxZoom: 14,
                  )
                : null,
          ),
          children: [
            osmTiles(),
            MarkerLayer(
              markers: points
                  .map(
                    (p) => Marker(
                      point: p.point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Tooltip(
                        message: label(p.item),
                        child: Icon(Icons.location_on, color: color, size: 38),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationsView() {
    final items = _list('locations');
    return _scroll([
      Row(
        children: [
          Expanded(
            child: StatTile(
              label: 'Đã duyệt',
              value: show(_summary['approvedLocations'], '0'),
              icon: Icons.verified,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              label: 'Chờ kiểm duyệt',
              value: show(_summary['waitingReview'], '0'),
              icon: Icons.hourglass_top,
              color: Colors.orange,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (items.isNotEmpty) ...[
        _pointsMap(
          items,
          (i) => show(i['tenDiaDiem']),
          const Color(0xFF1E7B5F),
        ),
        const SizedBox(height: 12),
      ],
      if (items.isEmpty)
        EmptyState(
          icon: Icons.add_location_alt_outlined,
          message:
              'Bạn chưa đăng địa điểm nào. Địa điểm sau khi được quản trị viên duyệt sẽ hiển thị cho người nuôi ong.',
          action: FilledButton.icon(
            onPressed: _addLocation,
            icon: const Icon(Icons.add),
            label: const Text('Đăng địa điểm'),
          ),
        ),
      ...items.map((l) {
        final capacity = int.tryParse('${l['sucChuaToiDa']}') ?? 0;
        final rentedHives =
            int.tryParse('${l['soDanDaThue']}') ??
            (int.tryParse('${l['soDanOng']}') ?? 0);
        final remaining = l['sucChuaConLai'] != null
            ? (int.tryParse('${l['sucChuaConLai']}') ??
                  (capacity - rentedHives).clamp(0, 999999))
            : (capacity - rentedHives).clamp(0, 999999);
        final isFull = capacity > 0 && remaining <= 0;
        final tenantList = show(l['danhSachNguoiThue'] ?? l['nguoiThue']);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        show(l['tenDiaDiem']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    StatusChip(l['trangThaiKiemDuyet']),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      onSelected: (v) =>
                          v == 'edit' ? _editLocation(l) : _deleteLocation(l),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Sửa thông tin'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Xóa',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  show(l['diaChiChiTiet']),
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isFull
                            ? Colors.red.shade50
                            : (rentedHives > 0
                                  ? Colors.blue.shade50
                                  : Colors.green.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFull
                              ? Colors.red.shade300
                              : (rentedHives > 0
                                    ? Colors.blue.shade300
                                    : Colors.green.shade300),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFull
                                ? Icons.block
                                : (rentedHives > 0
                                      ? Icons.inventory_2_outlined
                                      : Icons.check_circle_outline),
                            size: 13,
                            color: isFull
                                ? Colors.red.shade700
                                : (rentedHives > 0
                                      ? Colors.blue.shade700
                                      : Colors.green.shade700),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isFull
                                ? 'Đã hết chỗ'
                                : (rentedHives > 0
                                      ? 'Còn trống $remaining/$capacity đàn'
                                      : 'Đang trống 100%'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isFull
                                  ? Colors.red.shade700
                                  : (rentedHives > 0
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatNumber(l['dienTich'])} ha • Sức chứa: $capacity đàn • Đã cho thuê: $rentedHives đàn (Còn trống: $remaining đàn)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (capacity > 0) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (rentedHives / capacity).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isFull
                          ? Colors.red
                          : (rentedHives > 0
                                ? Colors.amber.shade700
                                : Colors.green),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    if (tenantList.isNotEmpty)
                      Text(
                        'Người thuê: $tenantList',
                        style: const TextStyle(
                          color: Color(0xFF1E7B5F),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if ((int.tryParse('${l['yeuCauChoDuyet']}') ?? 0) > 0)
                      InkWell(
                        onTap: () => setState(() => _tab = 1),
                        child: Text(
                          '${l['yeuCauChoDuyet']} yêu cầu chờ duyệt ›',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if ((num.tryParse('${l['sanLuongKg']}') ?? 0) > 0)
                      Text('Đã thu ${formatNumber(l['sanLuongKg'])} kg mật'),
                  ],
                ),
                if (l['trangThaiKiemDuyet'] == 'TuChoi' &&
                    l['lyDoTuChoi'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Lý do từ chối: ${l['lyDoTuChoi']} – sửa thông tin để gửi duyệt lại.',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  Widget _requestsView() {
    final items = _list('requests');
    return _scroll([
      if (items.isEmpty)
        const EmptyState(
          icon: Icons.inbox_outlined,
          message: 'Chưa có yêu cầu thuê nào.',
        ),
      ...items.map((r) {
        final status = show(r['trangThai']);
        return Card(
          color: status == 'ChoDuyet' ? const Color(0xFFFFFBEB) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        show(r['tenDiaDiem']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    StatusChip(status),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      'Người nuôi ong: ${show(r['tenNguoiNuoiOng'])} • ${show(r['sdtNguoiNuoiOng'])}',
                    ),
                    UserReputationBadge(
                      isNew: r['laNguoiMoiNuoiOng'],
                      rating: r['uyTinNguoiNuoiOng'],
                      reviewCount: r['tongDanhGiaNguoiNuoiOng'],
                    ),
                  ],
                ),
                Text(
                  '${show(r['thoiGianBatDau'])} → ${show(r['thoiGianKetThuc'])} • ${show(r['soDanOng'], '0')} đàn',
                ),
                Text(
                  'Giá đề xuất: ${formatMoney(r['giaThueDuKien'])} • Gửi lúc ${show(r['ngayTao'])}',
                  style: const TextStyle(color: Colors.black54),
                ),
                if ((r['ghiChu'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '“${r['ghiChu']}”',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                if (r['lyDoTuChoi'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Lý do từ chối: ${r['lyDoTuChoi']}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(
                            color: Color(0xFF38BDF8),
                            width: 1.1,
                          ),
                          backgroundColor: const Color(0xFFF0F9FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          final partnerId = int.tryParse(
                            '${r['maNguoiNuoiOng']}',
                          );
                          final partnerName =
                              r['tenNguoiNuoiOng']?.toString() ??
                              'Người nuôi ong';
                          final partnerPhone =
                              r['sdtNguoiNuoiOng']?.toString() ?? '';
                          if (partnerId != null && partnerId > 0) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatHubScreen(
                                  initialPartnerId: partnerId,
                                  initialPartnerName: partnerName,
                                  initialPartnerRole: 'nguoiNuoiOng',
                                  initialPartnerPhone: partnerPhone,
                                ),
                              ),
                            );
                          } else {
                            showSnack(
                              context,
                              'Chưa có thông tin liên hệ của người nuôi ong.',
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                        ),
                        label: const Text(
                          'Nhắn tin',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (status == 'ChoDuyet') ...[
                        OutlinedButton.icon(
                          onPressed: () => _reject(r),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Từ chối'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _approve(r),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Duyệt'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  Widget _hivesView() {
    final items = _list('hives');
    return _scroll([
      Row(
        children: [
          Expanded(
            child: StatTile(
              label: 'Đàn ong trên đất',
              value: show(_summary['hivesOnLand'], '0'),
              icon: Icons.hive,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              label: 'Thùng ong',
              value: show(_summary['boxesOnLand'], '0'),
              icon: Icons.inventory_2,
              color: const Color(0xFF1E7B5F),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (items.isNotEmpty) ...[
        _pointsMap(
          items,
          (i) => '${show(i['tenDanOng'])} – ${show(i['tenNguoiNuoiOng'])}',
          Colors.red,
        ),
        const SizedBox(height: 12),
      ],
      if (items.isEmpty)
        const EmptyState(
          icon: Icons.hive_outlined,
          message: 'Chưa có đàn ong nào được đặt trên đất của bạn.',
        ),
      ...items.map(
        (h) => Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: kHoneyLight,
              child: Icon(Icons.hive, color: Colors.orange),
            ),
            title: Text(
              '${show(h['tenDanOng'])} • ${show(h['soThung'], '0')} thùng',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${show(h['tenDiaDiem'])} • ${show(h['tinhTrang'])}\n'
              'Người nuôi: ${show(h['tenNguoiNuoiOng'])} (${show(h['sdtNguoiNuoiOng'])}) • Cập nhật ${show(h['ngayCapNhat'])}',
            ),
            isThreeLine: true,
          ),
        ),
      ),
    ]);
  }

  Widget _productionView() {
    final items = _list('production');
    return _scroll([
      StatTile(
        label: 'Tổng sản lượng thu trên đất (kg)',
        value: formatNumber(_summary['productionKg']),
        icon: Icons.water_drop,
        color: const Color(0xFF6366F1),
      ),
      const SizedBox(height: 12),
      if (items.isEmpty)
        const EmptyState(
          icon: Icons.water_drop_outlined,
          message: 'Chưa có sản lượng khai thác trên đất của bạn.',
        ),
      ...items.map(
        (p) => Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE9FE),
              child: Icon(Icons.water_drop, color: Color(0xFF6366F1)),
            ),
            title: Text(
              '${formatNumber(p['sanLuong'])} ${show(p['donVi'], 'kg')} • ${show(p['loaiMat'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${show(p['ngay'])} • ${show(p['tenDiaDiem'])}\n${show(p['tenNguoiNuoiOng'])} • ${show(p['tenDanOng'])}',
            ),
            isThreeLine: true,
          ),
        ),
      ),
    ]);
  }
}

class LocationFormPage extends StatefulWidget {
  const LocationFormPage({super.key, this.location});
  final Json? location;

  @override
  State<LocationFormPage> createState() => _LocationFormPageState();
}

class _LocationFormPageState extends State<LocationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.location?['tenDiaDiem']?.toString() ?? '',
  );
  late final _address = TextEditingController(
    text: widget.location?['diaChiChiTiet']?.toString() ?? '',
  );
  late final _area = TextEditingController(
    text: widget.location == null
        ? ''
        : formatNumber(widget.location!['dienTich']),
  );
  late final _capacity = TextEditingController(
    text: widget.location?['sucChuaToiDa']?.toString() ?? '',
  );
  late final _flower = TextEditingController(
    text: widget.location?['loaiHoa']?.toString() ?? '',
  );
  late final _beeType = TextEditingController(
    text: widget.location?['loaiOngPhuHop']?.toString() ?? '',
  );
  late final _price = TextEditingController(
    text: widget.location?['giaThueThang'] != null
        ? '${widget.location!['giaThueThang']}'
        : '',
  );
  late String _detectedClimate = widget.location?['khiHau']?.toString() ?? '';
  late final _legal = TextEditingController(
    text: widget.location?['thongTinPhapLy']?.toString() ?? '',
  );
  late LatLng? _point = widget.location == null
      ? null
      : latLngOf(widget.location!);
  bool _pointMissing = false;
  bool _detectingWeather = false;
  List<String> _flowerCatalog = [];
  List<String> _beeCatalog = [];

  // Biến quản lý ảnh
  Uint8List? _imageBytes;
  String? _imageBase64;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    _existingImageUrl = widget.location?['hinhAnh']?.toString();
    _loadCatalog();
    if (_point != null && _detectedClimate.isEmpty) {
      _autoDetectFromLocation(_point!, _address.text);
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await ApiService.getSpeciesCatalog();
      final flowers =
          (catalog['flowers'] as List?)
              ?.map((e) => (e['tenLoaiHoa'] ?? '').toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];
      final bees =
          (catalog['bees'] as List?)
              ?.map((e) => (e['tenLoaiOng'] ?? '').toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _flowerCatalog = flowers;
          _beeCatalog = bees;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _area,
      _capacity,
      _flower,
      _beeType,
      _price,
      _legal,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // HÀM CHỌN ẢNH TỪ THƯ VIỆN ĐIỆN THOẠI
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          _existingImageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi chọn ảnh: $e', error: true);
    }
  }

  // TỰ ĐỘNG NHẬN DIỆN KHÍ HẬU, LOÀI HOA VÀ LOÀI ONG PHÙ HỢP THEO ĐỊA ĐIỂM
  Future<void> _autoDetectFromLocation(
    LatLng point, [
    String? addressText,
    bool force = false,
  ]) async {
    final addr = (addressText ?? _address.text).toLowerCase();
    String detectedClimate = '';
    String detectedFlower = '';
    String detectedBee = '';

    if (addr.contains('mộc châu') ||
        addr.contains('sơn la') ||
        addr.contains('điện biên') ||
        addr.contains('lai châu') ||
        addr.contains('hòa bình') ||
        addr.contains('sa pa') ||
        addr.contains('sapa') ||
        addr.contains('lào cai') ||
        addr.contains('yên bái')) {
      detectedClimate = 'Ôn đới núi cao mát mẻ (16°C - 24°C)';
      detectedFlower = 'Hoa mận, Hoa mơ, Tam giác mạch, Hoa rừng Tây Bắc';
      detectedBee = 'Ong nội (Apis cerana)';
    } else if (addr.contains('hà giang') ||
        addr.contains('mèo vạc') ||
        addr.contains('đồng văn') ||
        addr.contains('cao bằng') ||
        addr.contains('lạng sơn') ||
        addr.contains('bắc kạn') ||
        addr.contains('tuyên quang')) {
      detectedClimate = 'Cao nguyên đá khô lạnh, trong lành (15°C - 22°C)';
      detectedFlower = 'Hoa bạc hà đá núi cao, Hoa tam giác mạch';
      detectedBee = 'Ong nội (Apis cerana)';
    } else if (addr.contains('đà lạt') ||
        addr.contains('lâm đồng') ||
        addr.contains('bảo lộc')) {
      detectedClimate = 'Cao nguyên ôn đới mát mẻ (17°C - 23°C)';
      detectedFlower = 'Hoa cà phê, Hoa dã quỳ, Hoa thông, Hoa bơ';
      detectedBee = 'Ong Ý (Apis mellifera) & Ong nội';
    } else if (addr.contains('đắk lắk') ||
        addr.contains('dak lak') ||
        addr.contains('gia lai') ||
        addr.contains('buôn ma thuột') ||
        addr.contains('pleiku') ||
        addr.contains('đắk nông') ||
        addr.contains('dak nong') ||
        addr.contains('kon tum')) {
      detectedClimate = 'Cao nguyên ôn hòa, đất đỏ bazan (20°C - 28°C)';
      detectedFlower = 'Hoa cà phê, Hoa cao su, Hoa điều';
      detectedBee = 'Ong Ý (Apis mellifera)';
    } else if (addr.contains('bắc giang') ||
        addr.contains('lục ngạn') ||
        addr.contains('chí linh')) {
      detectedClimate = 'Nhiệt đới 4 mùa, mùa hoa ấm áp';
      detectedFlower = 'Hoa vải thiều đặc sản, Hoa cam Lục Ngạn';
      detectedBee = 'Ong Ý & Ong nội';
    } else if (addr.contains('hưng yên') ||
        addr.contains('hải dương') ||
        addr.contains('hà nam') ||
        addr.contains('hà nội') ||
        addr.contains('thái bình') ||
        addr.contains('nam định') ||
        addr.contains('ninh bình') ||
        addr.contains('bắc ninh') ||
        addr.contains('vĩnh phúc') ||
        addr.contains('phú thọ') ||
        addr.contains('hải phòng') ||
        addr.contains('quảng ninh')) {
      detectedClimate = 'Nhiệt đới ẩm gió mùa (22°C - 30°C)';
      detectedFlower = 'Hoa nhãn lồng, Hoa bưởi, Hoa táo';
      detectedBee = 'Ong Ý & Ong nội';
    } else if (addr.contains('thanh hóa') ||
        addr.contains('nghệ an') ||
        addr.contains('hà tĩnh') ||
        addr.contains('quảng bình') ||
        addr.contains('quảng trị') ||
        addr.contains('thừa thiên huế') ||
        addr.contains('huế')) {
      detectedClimate = 'Nhiệt đới gió mùa miền Trung nắng ấm';
      detectedFlower = 'Hoa keo tràm, Hoa rừng tự nhiên, Hoa cam';
      detectedBee = 'Ong nội & Ong ngoại / Ong Ý';
    } else if (addr.contains('đà nẵng') ||
        addr.contains('quảng nam') ||
        addr.contains('quảng ngãi') ||
        addr.contains('bình định') ||
        addr.contains('phú yên') ||
        addr.contains('khánh hòa') ||
        addr.contains('nha trang') ||
        addr.contains('ninh thuận') ||
        addr.contains('bình thuận')) {
      detectedClimate = 'Duyên hải Nam Trung Bộ nắng ấm (26°C - 32°C)';
      detectedFlower = 'Hoa keo lai, Hoa ăn trái, Hoa táo, Hoa nho';
      detectedBee = 'Ong ngoại / Ong Ý (Apis mellifera) & Ong nội';
    } else if (addr.contains('củ chi') ||
        addr.contains('cu chi') ||
        addr.contains('phú hòa đông')) {
      detectedClimate = 'Nhiệt đới nắng ấm Đông Nam Bộ (26°C - 34°C)';
      detectedFlower = 'Hoa cây ăn trái Củ Chi, Hoa tràm bông vàng, Hoa cao su';
      detectedBee = 'Ong Ý (Apis mellifera) & Ong dú';
    } else if (addr.contains('bình phước') ||
        addr.contains('tây ninh') ||
        addr.contains('đồng nai') ||
        addr.contains('bình dương') ||
        addr.contains('hồ chí minh') ||
        addr.contains('sài gòn') ||
        addr.contains('vũng tàu')) {
      detectedClimate = 'Nhiệt đới nắng ấm (26°C - 32°C)';
      detectedFlower = 'Hoa điều, Hoa cao su, Hoa tràm bông vàng';
      detectedBee = 'Ong Ý (Apis mellifera)';
    } else if (addr.contains('cà mau') ||
        addr.contains('u minh') ||
        addr.contains('kiên giang') ||
        addr.contains('bến tre') ||
        addr.contains('đồng tháp') ||
        addr.contains('cần thơ') ||
        addr.contains('tiền giang') ||
        addr.contains('vĩnh long') ||
        addr.contains('an giang') ||
        addr.contains('sóc trăng') ||
        addr.contains('hậu giang') ||
        addr.contains('trà vinh') ||
        addr.contains('bạc liêu') ||
        addr.contains('long an')) {
      detectedClimate = 'Nhiệt đới ẩm Nam Bộ (28°C - 33°C)';
      detectedFlower = 'Hoa tràm rừng U Minh, Hoa dừa, Cây ăn trái';
      detectedBee = 'Ong Ý & Ong dú (Stingless bee)';
    } else {
      if (point.latitude >= 21.0) {
        detectedClimate = 'Cận nhiệt đới / Ôn hòa 4 mùa';
        detectedFlower = 'Hoa nhãn, Hoa vải, Hoa mận, Hoa rừng tự nhiên';
        detectedBee = 'Ong nội & Ong Ý';
      } else if (point.latitude >= 16.0 && point.latitude < 21.0) {
        detectedClimate = 'Nhiệt đới gió mùa miền Trung';
        detectedFlower = 'Hoa keo tràm, Hoa rừng tự nhiên';
        detectedBee = 'Ong nội & Ong ngoại / Ong Ý';
      } else if (point.latitude >= 11.5 && point.latitude < 16.0) {
        if (point.longitude < 108.5) {
          detectedClimate = 'Cao nguyên ôn hòa đất đỏ bazan';
          detectedFlower = 'Hoa cà phê, Hoa cao su, Hoa điều';
          detectedBee = 'Ong Ý (Apis mellifera)';
        } else {
          detectedClimate = 'Duyên hải miền Trung nắng ấm';
          detectedFlower = 'Hoa keo, Cây ăn trái, Hoa táo';
          detectedBee = 'Ong Ý & Ong nội';
        }
      } else {
        if (point.latitude < 10.2) {
          detectedClimate = 'Nhiệt đới ẩm Nam Bộ nắng ấm';
          detectedFlower = 'Hoa tràm, Hoa dừa, Cây ăn trái';
          detectedBee = 'Ong Ý & Ong dú';
        } else {
          detectedClimate = 'Nhiệt đới nắng ấm Đông Nam Bộ';
          detectedFlower = 'Hoa điều, Hoa cao su, Hoa tràm';
          detectedBee = 'Ong Ý (Apis mellifera)';
        }
      }
    }

    setState(() => _detectingWeather = true);
    try {
      final current = await ApiService.getWeather(
        point.latitude,
        point.longitude,
      );
      if (current != null && current['temperature_2m'] != null) {
        final temp = current['temperature_2m'];
        final hum = current['relative_humidity_2m'];
        detectedClimate = 'Hiện tại: $temp°C, ẩm $hum% • $detectedClimate';
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _detectingWeather = false;
        _detectedClimate = detectedClimate;
        if (detectedFlower.isNotEmpty &&
            (force || _flower.text.trim().isEmpty)) {
          _flower.text = detectedFlower;
        }
        if (detectedBee.isNotEmpty && (force || _beeType.text.trim().isEmpty)) {
          _beeType.text = detectedBee;
        }
      });
      showSnack(
        context,
        '⚡ Đã tự động nhận diện loài hoa & giống ong theo tọa độ! Bạn vẫn có thể chỉnh sửa tùy ý.',
      );
    }
  }

  // ĐỊNH VỊ NHANH TỌA ĐỘ VÀ SINH THÁI TỪ ĐỊA CHỈ ĐÃ NHẬP
  Future<void> _locateFromAddress() async {
    final text = _address.text.trim();
    if (text.isEmpty) {
      showSnack(context, 'Vui lòng nhập địa chỉ trước khi tìm kiếm.');
      return;
    }
    showSnack(context, '🔍 Đang định vị tọa độ theo địa chỉ...');
    try {
      final results = await ApiService.searchPlaces(text);
      if (results.isNotEmpty && mounted) {
        final first = results.first;
        final lat = double.tryParse('${first['lat']}');
        final lon = double.tryParse('${first['lon']}');
        if (lat != null && lon != null) {
          final target = LatLng(lat, lon);
          setState(() {
            _point = target;
            _pointMissing = false;
          });
          _autoDetectFromLocation(target, text, true);
          showSnack(
            context,
            '⚡ Đã định vị thành công: ${first['display_name']} và tự động điền hoa & ong!',
          );
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      showSnack(
        context,
        'Chưa tìm thấy tọa độ tự động. Bạn hãy bấm "Chọn vị trí trên bản đồ" để ghim trực tiếp.',
      );
    }
  }

  Future<void> _pick() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initial: _point,
          initialQuery: _address.text.trim(),
          title: 'Vị trí địa điểm',
          onSelected: (point, address) {
            if (address != null && address.isNotEmpty) {
              final current = _address.text.trim();
              final houseMatch = RegExp(
                r'^[0-9]+[A-Za-z]?(/[0-9]+[A-Za-z]?)?',
              ).firstMatch(current);
              if (houseMatch != null &&
                  !address.startsWith(houseMatch.group(0)!)) {
                _address.text = '${houseMatch.group(0)!} $address';
              } else {
                _address.text = address;
              }
            }
          },
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _point = picked;
        _pointMissing = false;
      });
      _autoDetectFromLocation(picked, _address.text, true);
    }
  }

  void _save() {
    final valid = _formKey.currentState!.validate();
    setState(() => _pointMissing = _point == null);
    if (!valid || _point == null) return;

    final parsedPrice = double.tryParse(
      _price.text.trim().replaceAll(',', '').replaceAll('.', ''),
    );

    Map<String, dynamic> dataToSend = {
      'tenDiaDiem': _name.text.trim(),
      'diaChiChiTiet': _address.text.trim(),
      'dienTich': double.parse(_area.text.trim().replaceAll(',', '.')),
      'sucChuaToiDa': int.parse(_capacity.text.trim()),
      'loaiHoa': _flower.text.trim().isNotEmpty ? _flower.text.trim() : null,
      'loaiOngPhuHop': _beeType.text.trim().isNotEmpty
          ? _beeType.text.trim()
          : null,
      'giaThueThang': parsedPrice,
      'khiHau': _detectedClimate.trim().isNotEmpty
          ? _detectedClimate.trim()
          : null,
      'thongTinPhapLy': _legal.text.trim(),
      'viDo': _point!.latitude,
      'kinhDo': _point!.longitude,
    };

    if (_imageBase64 != null) {
      dataToSend['hinhAnh'] = _imageBase64;
    }

    Navigator.pop<Json>(context, dataToSend);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.location == null ? 'Đăng địa điểm đặt ong' : 'Sửa địa điểm',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.location != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Sau khi sửa, địa điểm sẽ được quản trị viên kiểm duyệt lại.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),

            // --- KHUNG TẢI ẢNH LÊN ---
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 180,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400, width: 1.5),
                  image: _imageBytes != null
                      ? DecorationImage(
                          image: MemoryImage(_imageBytes!),
                          fit: BoxFit.cover,
                        )
                      : (_existingImageUrl != null &&
                            _existingImageUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(_existingImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child:
                    _imageBytes == null &&
                        (_existingImageUrl == null ||
                            _existingImageUrl!.isEmpty)
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 42,
                            color: Colors.black45,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Chạm để tải ảnh vườn lên',
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
              ),
            ),

            // --------------------------
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Tên địa điểm',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nhập tên địa điểm' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              decoration: InputDecoration(
                labelText:
                    'Địa chỉ chi tiết (VD: 283/2 Đường Nguyễn Thị Nê...)',
                prefixIcon: const Icon(Icons.home_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.travel_explore_rounded,
                    color: Color(0xFFD97706),
                  ),
                  tooltip: 'Tìm vị trí & hoa theo địa chỉ này',
                  onPressed: _locateFromAddress,
                ),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nhập địa chỉ' : null,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _area,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Diện tích (ha)',
                    ),
                    validator: (v) =>
                        (double.tryParse(
                                  (v ?? '').trim().replaceAll(',', '.'),
                                ) ??
                                0) <=
                            0
                        ? 'Lớn hơn 0'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sức chứa (thùng)',
                    ),
                    validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0
                        ? 'Số nguyên > 0'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(
                  color: _pointMissing ? Colors.red : Colors.black26,
                ),
              ),
              onPressed: _pick,
              icon: Icon(
                _point == null
                    ? Icons.add_location_alt_outlined
                    : Icons.location_on,
                color: _point == null ? null : Colors.red,
              ),
              label: Text(
                _point == null
                    ? 'Chọn vị trí trên bản đồ'
                    : 'Vị trí: ${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)} (chạm để đổi)',
              ),
            ),
            if (_pointMissing)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Vui lòng chọn vị trí',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 18),

            // --- THÔNG TIN SINH THÁI, KHÍ HẬU & LOÀI HOA ĐẶC TRƯNG ---
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.eco_rounded,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Môi trường & Sinh thái đặt ong',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                      if (_detectingWeather)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_point != null)
                        InkWell(
                          onTap: () =>
                              _autoDetectFromLocation(_point!, _address.text),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: Color(0xFFD97706),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Gợi ý nhanh',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _flower,
                    decoration: const InputDecoration(
                      labelText: 'Loài hoa đặc trưng (Nguồn hoa chính)',
                      hintText: 'Chọn từ danh mục hoặc nhập loài hoa...',
                      prefixIcon: Icon(Icons.local_florist_rounded),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_flowerCatalog.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _flowerCatalog
                          .map(
                            (f) => ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                Icons.local_florist,
                                size: 14,
                                color: Color(0xFFD97706),
                              ),
                              label: Text(
                                f,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () => setState(() => _flower.text = f),
                            ),
                          )
                          .toList(),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Đang tải danh mục hoa từ hệ thống...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),

                  // KHÍ HẬU: LẤY TRỰC TIẾP TỪ TỌA ĐỘ ĐỊA ĐIỂM (KHÔNG CẦN NHẬP TAY)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withAlpha(15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.wb_sunny_rounded,
                            color: Color(0xFFD97706),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Khí hậu tại địa điểm (Lấy tự động theo tọa độ)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(height: 3),
                              if (_detectingWeather)
                                const Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Đang kiểm tra thời tiết thực tế từ tọa độ...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  _detectedClimate.isNotEmpty
                                      ? _detectedClimate
                                      : (_point != null
                                            ? 'Đang nhận diện theo tọa độ...'
                                            : 'Sẽ tự động cập nhật ngay khi bạn chọn vị trí trên bản đồ.'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _detectedClimate.isNotEmpty
                                        ? const Color(0xFF1E293B)
                                        : Colors.black45,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _beeType,
                    decoration: const InputDecoration(
                      labelText: 'Loài ong phù hợp nhất',
                      hintText: 'Chọn từ danh mục giống ong hoặc nhập...',
                      prefixIcon: Icon(Icons.pest_control_rounded),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_beeCatalog.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _beeCatalog
                          .map(
                            (b) => ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                Icons.pest_control,
                                size: 14,
                                color: Color(0xFFD97706),
                              ),
                              label: Text(
                                b,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () =>
                                  setState(() => _beeType.text = b),
                            ),
                          )
                          .toList(),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Đang tải danh mục giống ong từ hệ thống...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giá thuê tham khảo (VNĐ/tháng)',
                      hintText: 'Để trống nếu miễn phí hoặc thỏa thuận',
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _legal,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Thông tin pháp lý (số sổ đỏ, giấy tờ...)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _save,
            icon: const Icon(Icons.send),
            label: Text(
              widget.location == null
                  ? 'Gửi kiểm duyệt'
                  : 'Lưu và gửi duyệt lại',
            ),
          ),
        ),
      ),
    );
  }
}
