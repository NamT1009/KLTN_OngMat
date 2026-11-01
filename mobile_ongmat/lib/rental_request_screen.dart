import 'chat_hub_screen.dart';
import 'package:flutter/material.dart';

import 'contract_screen.dart';
import 'map_screen.dart';
import 'services/api_service.dart';
import 'widgets/common.dart';

/// Form gửi yêu cầu thuê một địa điểm cụ thể; trả về true khi gửi thành công.
class RentalRequestScreen extends StatefulWidget {
  const RentalRequestScreen({super.key, required this.location});
  final Json location;

  @override
  State<RentalRequestScreen> createState() => _RentalRequestScreenState();
}

class _RentalRequestScreenState extends State<RentalRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _start = TextEditingController(text: isoDate(DateTime.now().add(const Duration(days: 7))));
  final _end = TextEditingController(text: isoDate(DateTime.now().add(const Duration(days: 187))));
  late final TextEditingController _hiveCount;
  final _price = TextEditingController();
  final _note = TextEditingController();
  bool _submitting = false;

  int get _capacity => int.tryParse('${widget.location['sucChuaToiDa']}') ?? 0;
  int get _rentedHives => int.tryParse('${widget.location['soDanDaThue']}') ?? 0;
  int get _remainingCapacity {
    if (widget.location['sucChuaConLai'] != null) {
      return int.tryParse('${widget.location['sucChuaConLai']}') ?? (_capacity - _rentedHives).clamp(0, 999999);
    }
    return (_capacity - _rentedHives).clamp(0, 999999);
  }
  bool get _isFull => _capacity > 0 && _remainingCapacity <= 0;

  @override
  void initState() {
    super.initState();
    final defaultCount = _isFull
        ? 0
        : (_remainingCapacity >= 10 ? 10 : (_remainingCapacity > 0 ? _remainingCapacity : 1));
    _hiveCount = TextEditingController(text: '$defaultCount');
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _hiveCount, _price, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isFull) {
      showSnack(context, 'Địa điểm này đã hết chỗ đặt đàn ong!', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final message = await ApiService.createRentalRequest({
        'maDiaDiem': widget.location['maDiaDiem'],
        'thoiGianBatDau': _start.text,
        'thoiGianKetThuc': _end.text,
        'soDanOng': int.parse(_hiveCount.text.trim()),
        'giaThueDuKien': _price.text.trim().isEmpty ? null : num.parse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')),
        'ghiChu': _note.text.trim(),
      });
      if (!mounted) return;
      showSnack(context, message);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gửi yêu cầu thuê'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0284C7),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Hỏi chủ đất', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              final partnerId = int.tryParse('${location['maChuDat']}');
              final partnerName = location['tenChuDat']?.toString() ?? 'Chủ đất';
              final partnerPhone = location['sdtChuDat']?.toString() ?? location['soDienThoai']?.toString() ?? '';
              if (partnerId != null && partnerId > 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatHubScreen(
                      initialPartnerId: partnerId,
                      initialPartnerName: partnerName,
                      initialPartnerRole: 'chuDat',
                      initialPartnerPhone: partnerPhone,
                    ),
                  ),
                );
              } else {
                showSnack(context, 'Chưa có thông tin liên hệ của chủ đất.');
              }
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            color: kHoneyLight,
            child: ListTile(
              leading: const Icon(Icons.landscape, color: Color(0xFF1E7B5F)),
              title: Text(show(location['tenDiaDiem']), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(show(location['diaChiChiTiet'])),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text('Chủ đất: ${show(location['tenChuDat'])}'),
                      UserReputationBadge(
                        isNew: location['laNguoiMoiChuDat'],
                        rating: location['uyTinChuDat'],
                        reviewCount: location['tongDanhGiaChuDat'],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Sức chứa: $_capacity đàn • Đã thuê: $_rentedHives đàn'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isFull
                          ? Colors.red.shade100
                          : (_rentedHives > 0 ? Colors.blue.shade100 : Colors.green.shade100),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isFull
                              ? Icons.block
                              : (_rentedHives > 0 ? Icons.inventory_2_outlined : Icons.check_circle_outline),
                          size: 15,
                          color: _isFull
                              ? Colors.red.shade800
                              : (_rentedHives > 0 ? Colors.blue.shade800 : Colors.green.shade800),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isFull
                              ? 'ĐÃ HẾT CHỖ'
                              : (_rentedHives > 0
                                  ? 'CÒN TRỐNG $_remainingCapacity/$_capacity ĐÀN (CÓ THỂ THUÊ TIẾP)'
                                  : 'CÒN TRỐNG TOÀN BỘ ($_capacity ĐÀN)'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isFull
                                ? Colors.red.shade900
                                : (_rentedHives > 0 ? Colors.blue.shade900 : Colors.green.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: DateField(controller: _start, label: 'Ngày bắt đầu', firstDate: DateTime.now(), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: DateField(controller: _end, label: 'Ngày kết thúc', firstDate: DateTime.now(), onChanged: (_) => setState(() {}))),
          ]),
          const SizedBox(height: 14),
          TextFormField(
            controller: _hiveCount,
            enabled: !_isFull,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Số đàn ong dự kiến',
              helperText: _isFull
                  ? 'Địa điểm này hiện đã kín chỗ'
                  : 'Còn trống $_remainingCapacity/$_capacity đàn (tối đa thuê $_remainingCapacity đàn)',
              prefixIcon: const Icon(Icons.hive_outlined),
            ),
            validator: (v) {
              if (_isFull) return 'Địa điểm đã hết chỗ, không thể gửi yêu cầu';
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1) return 'Nhập số lớn hơn 0';
              if (_remainingCapacity > 0 && n > _remainingCapacity) {
                return 'Vượt quá chỗ trống còn lại ($_remainingCapacity đàn)';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Giá đề xuất (đồng, không bắt buộc)', prefixIcon: Icon(Icons.payments_outlined)),
          ),
          const SizedBox(height: 14),
          TextFormField(controller: _note, maxLines: 4, decoration: const InputDecoration(labelText: 'Ghi chú cho chủ đất')),
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final start = DateTime.tryParse(_start.text);
            final end = DateTime.tryParse(_end.text);
            final invalid = start != null && end != null && !end.isAfter(start);
            return invalid ? const Text('Ngày kết thúc phải sau ngày bắt đầu.', style: TextStyle(color: Colors.red)) : const SizedBox.shrink();
          }),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: _isFull ? Colors.grey : null,
            ),
            onPressed: (_submitting || _isFull) ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_isFull ? Icons.block : Icons.send),
            label: Text(_isFull ? 'Đã hết chỗ' : (_submitting ? 'Đang gửi...' : 'Gửi yêu cầu')),
          ),
        ),
      ),
    );
  }
}

/// Danh sách yêu cầu thuê của người nuôi ong và trạng thái xử lý.
class MyRentalRequestsScreen extends StatefulWidget {
  const MyRentalRequestsScreen({super.key});

  @override
  State<MyRentalRequestsScreen> createState() => _MyRentalRequestsScreenState();
}

class _MyRentalRequestsScreenState extends State<MyRentalRequestsScreen> {
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
      final items = await ApiService.getMyRentalRequests();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Json item) async {
    if (!await confirmDialog(context, title: 'Hủy yêu cầu thuê?', message: show(item['tenDiaDiem']), confirmLabel: 'Hủy yêu cầu', danger: true)) return;
    if (!mounted) return;
    if (await runAction(context, () => ApiService.cancelRentalRequest('${item['maYeuCau']}'))) await _load();
  }

  Future<void> _findLand() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Yêu cầu thuê của tôi')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _findLand, icon: const Icon(Icons.travel_explore), label: const Text('Tìm đất')),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _items != null,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: items.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.request_quote_outlined, message: 'Bạn chưa gửi yêu cầu thuê nào.')])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final status = show(item['trangThai']);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(show(item['tenDiaDiem']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            StatusChip(status),
                          ]),
                          const SizedBox(height: 6),
                          Text('${show(item['thoiGianBatDau'])} → ${show(item['thoiGianKetThuc'])} • ${show(item['soDanOng'], '0')} đàn'),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text('Chủ đất: ${show(item['tenChuDat'])}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                              UserReputationBadge(
                                isNew: item['laNguoiMoiChuDat'],
                                rating: item['uyTinChuDat'],
                                reviewCount: item['tongDanhGiaChuDat'],
                              ),
                            ],
                          ),
                          Text('Giá đề xuất: ${formatMoney(item['giaThueDuKien'])}', style: const TextStyle(color: Colors.black54)),
                          if (item['lyDoTuChoi'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Lý do từ chối: ${item['lyDoTuChoi']}', style: const TextStyle(color: Colors.red)),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0284C7),
                                  side: const BorderSide(color: Color(0xFF38BDF8), width: 1.1),
                                  backgroundColor: const Color(0xFFF0F9FF),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  final partnerId = int.tryParse('${item['maChuDat']}');
                                  final partnerName = item['tenChuDat']?.toString() ?? 'Chủ đất';
                                  final partnerPhone = item['sdtChuDat']?.toString() ?? item['soDienThoai']?.toString() ?? '';
                                  if (partnerId != null && partnerId > 0) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatHubScreen(
                                          initialPartnerId: partnerId,
                                          initialPartnerName: partnerName,
                                          initialPartnerRole: 'chuDat',
                                          initialPartnerPhone: partnerPhone,
                                        ),
                                      ),
                                    );
                                  } else {
                                    showSnack(context, 'Chưa có thông tin liên hệ của chủ đất.');
                                  }
                                },
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                                label: const Text('Nhắn tin', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              ),
                              if (status == 'ChoDuyet' || status == 'ChoKhachKy') ...[
                                const SizedBox(width: 8),
                                status == 'ChoDuyet'
                                    ? TextButton.icon(onPressed: () => _cancel(item), icon: const Icon(Icons.close), label: const Text('Hủy yêu cầu'))
                                    : FilledButton.icon(
                                        onPressed: () async {
                                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractScreen()));
                                          if (mounted) _load();
                                        },
                                        icon: const Icon(Icons.draw),
                                        label: const Text('Ký hợp đồng'),
                                      ),
                              ],
                            ],
                          )
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
