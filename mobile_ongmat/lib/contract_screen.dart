import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';
import 'services/api_service.dart';
import 'widgets/common.dart';

/// Hợp đồng thuê đất: chủ đất xem hợp đồng trên đất của mình,
/// người nuôi ong xem và ký xác nhận bằng OTP qua Email.
class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key});

  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  List<Json>? _contracts;
  bool _loading = true;
  String? _error;
  bool _isLandowner = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => _isLandowner =
              normalizeAppRole(prefs.getString('vaiTro')) == 'chuDat',
        );
      }
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getContracts();
      if (mounted) setState(() => _contracts = data);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf(String contractId) async {
    final ok = await launchUrl(
      Uri.parse(ApiService.getContractPdfUrl(contractId)),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      showSnack(context, 'Không mở được PDF hợp đồng.', error: true);
    }
  }

  Future<void> _sign(Json contract) async {
    final id = '${contract['maHopDong']}';
    final isNew = contract['laNguoiMoiChuDat'] == true ||
        contract['laNguoiMoiChuDat'] == 1 ||
        contract['laNguoiMoiChuDat'] == '1' ||
        (int.tryParse('${contract['tongDanhGiaChuDat']}') ?? 0) == 0;
    final rating = num.tryParse('${contract['uyTinChuDat']}');
    final count = int.tryParse('${contract['tongDanhGiaChuDat']}') ?? 0;
    final ownerName = show(contract['tenChuDat']);
    final ownerPhone = show(contract['sdtChuDat']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.draw, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Expanded(child: Text('Ký hợp đồng $id')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bạn đang thực hiện ký hợp đồng thuê đất tại ${show(contract['tenDiaDiem'])} '
                'với giá ${formatMoney(contract['giaThue'])}, thời hạn ${show(contract['thoiHan'])}.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              // Đánh giá uy tín của Chủ đất để người thuê xem xét trước khi ký
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isNew ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isNew ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Chủ đất: $ownerName',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        UserReputationBadge(
                          isNew: isNew,
                          rating: rating,
                          reviewCount: count,
                        ),
                      ],
                    ),
                    if (ownerPhone.isNotEmpty && ownerPhone != '—') ...[
                      const SizedBox(height: 2),
                      Text(
                        'Điện thoại: $ownerPhone',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (isNew) ...[
                      const Text(
                        '⚠️ Lưu ý: Chủ đất này là Người mới và chưa có lượt đánh giá nào từ các đợt thuê trước. '
                        'Khuyến nghị bạn nên liên hệ trực tiếp hoặc khảo sát vườn thực tế trước khi ký hợp đồng!',
                        style: TextStyle(fontSize: 12, color: Color(0xFF065F46), fontWeight: FontWeight.w500),
                      ),
                    ] else ...[
                      Text(
                        '✨ Chủ đất đạt uy tín ${rating?.toStringAsFixed(1) ?? '5.0'}/5 ⭐ dựa trên $count lượt đánh giá từ các người nuôi ong trước. Đáng tin cậy để ký kết.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hệ thống sẽ gửi mã xác thực OTP 6 số qua email của bạn để hoàn tất việc ký.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Xem xét lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nhận mã OTP để ký'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    String? emailNhan;
    final sent = await runAction(context, () async {
      final result = await ApiService.requestContractOtp(id);
      emailNhan =
          (result['data'] as Map?)?['emailNhan']?.toString() ??
          result['emailNhan']?.toString();
      return result['message']?.toString() ?? 'Đã gửi mã OTP qua Gmail.';
    });
    if (!sent || !mounted) return;

    final helperText = emailNhan != null && emailNhan!.isNotEmpty
        ? 'Mã OTP 6 số đã được gửi đến email:\n$emailNhan (hiệu lực 5 phút)'
        : 'Mã xác thực OTP đã được gửi về Gmail của bạn (hiệu lực 5 phút).';

    final otp = await promptText(
      context,
      title: 'Nhập mã OTP',
      label: 'Mã OTP 6 số',
      keyboardType: TextInputType.number,
      required: true,
      confirmLabel: 'Ký xác nhận',
      helper: helperText,
    );
    if (otp == null || !mounted) return;

    if (await runAction(
      context,
      () => ApiService.signContract(contractId: id, otp: otp),
    )) {
      await _load();
    }
  }

  Future<void> _complete(Json contract) async {
    final id = '${contract['maHopDong']}';
    final confirmed = await confirmDialog(
      context,
      title: 'Hoàn tất thuê?',
      message:
          'Xác nhận kết thúc và hoàn tất đợt thuê vườn ${show(contract['tenDiaDiem'])} '
          'theo hợp đồng số $id. Sau khi hoàn tất, bạn và đối tác có thể gửi đánh giá cho nhau.',
      confirmLabel: 'Hoàn tất thuê',
    );
    if (!confirmed || !mounted) return;

    if (await runAction(
      context,
      () => ApiService.completeContract(id),
    )) {
      await _load();
      if (mounted) {
        _openReview(contract);
      }
    }
  }

  void _openReview(Json contract) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        contract: contract,
        isLandowner: _isLandowner,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contracts = _contracts ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Hợp đồng thuê đất')),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _contracts != null,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: contracts.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: Icons.handshake_outlined,
                      message: _isLandowner
                          ? 'Chưa có hợp đồng. Hợp đồng được tạo khi bạn duyệt yêu cầu thuê.'
                          : 'Chưa có hợp đồng. Hợp đồng được tạo khi chủ đất duyệt yêu cầu thuê của bạn.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: contracts.length,
                  itemBuilder: (_, index) => _card(contracts[index]),
                ),
        ),
      ),
    );
  }

  Widget _card(Json c) {
    final status = show(c['trangThai']);
    final canSign = !_isLandowner && status == 'ChoKhachKy';
    final canComplete = status == 'DaKy';
    final canReview = status == 'DaKy' || status == 'HoanThanh';

    final myRating = _isLandowner ? c['saoChuDatDanhGia'] : c['saoNguoiNuoiOngDanhGia'];
    final partnerRating = _isLandowner ? c['saoNguoiNuoiOngDanhGia'] : c['saoChuDatDanhGia'];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    show(c['tenHopDong']),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                StatusChip(status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              show(c['maHopDong']),
              style: const TextStyle(color: Colors.black45, fontSize: 12),
            ),
            const Divider(height: 20),
            _row(Icons.landscape_outlined, 'Địa điểm', show(c['tenDiaDiem'])),
            _row(
              Icons.person_outline,
              _isLandowner ? 'Người nuôi ong' : 'Chủ đất',
              _isLandowner
                  ? '${show(c['tenNguoiNuoiOng'])} • ${show(c['sdtNguoiNuoiOng'])}'
                  : '${show(c['tenChuDat'])} • ${show(c['sdtChuDat'])}',
              badge: UserReputationBadge(
                isNew: _isLandowner ? c['laNguoiMoiNuoiOng'] : c['laNguoiMoiChuDat'],
                rating: _isLandowner ? c['uyTinNguoiNuoiOng'] : c['uyTinChuDat'],
                reviewCount: _isLandowner ? c['tongDanhGiaNguoiNuoiOng'] : c['tongDanhGiaChuDat'],
              ),
            ),
            _row(
              Icons.payments_outlined,
              'Giá thuê',
              formatMoney(c['giaThue']),
            ),
            _row(Icons.date_range_outlined, 'Thời hạn', show(c['thoiHan'])),
            _row(
              Icons.gavel_outlined,
              'Bồi thường',
              show(c['quyDinhBoiThuong']),
            ),
            if (c['ngayKy'] != null)
              _row(Icons.verified_outlined, 'Ngày ký', show(c['ngayKy'])),
            if (c['ngayHoanThanh'] != null)
              _row(Icons.task_alt_outlined, 'Hoàn thành', show(c['ngayHoanThanh'])),

            if (status == 'ChoKhachKy' && _isLandowner)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Đang chờ người nuôi ong ký xác nhận.',
                  style: TextStyle(color: Colors.blue),
                ),
              ),

            // Phần tóm tắt đánh giá của hai bên
            if (canReview) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            myRating != null
                                ? 'Đánh giá của bạn: $myRating/5 ⭐'
                                : 'Bạn chưa đánh giá đối tác',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: myRating != null ? Colors.black87 : Colors.orange[800],
                            ),
                          ),
                          Text(
                            partnerRating != null
                                ? 'Đối tác đánh giá: $partnerRating/5 ⭐'
                                : 'Chờ đối tác đánh giá',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openPdf('${c['maHopDong']}'),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Xem PDF'),
                ),
                if (canSign)
                  FilledButton.icon(
                    onPressed: () => _sign(c),
                    icon: const Icon(Icons.draw, size: 18),
                    label: const Text('Ký xác nhận'),
                  ),
                if (canComplete)
                  FilledButton.tonalIcon(
                    onPressed: () => _complete(c),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Hoàn tất thuê'),
                  ),
                if (canReview)
                  ElevatedButton.icon(
                    onPressed: () => _openReview(c),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.star_rounded, size: 18),
                    label: Text(myRating != null ? 'Xem / Sửa ĐG' : 'Đánh giá ⭐'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Widget? badge}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black45),
        const SizedBox(width: 8),
        SizedBox(
          width: 105,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (badge != null) badge,
            ],
          ),
        ),
      ],
    ),
  );
}

/// Bottom Sheet đánh giá chất lượng thuê đất giữa Người nuôi ong & Chủ đất
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.contract,
    required this.isLandowner,
    required this.onSaved,
  });

  final Json contract;
  final bool isLandowner;
  final VoidCallback onSaved;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  bool _loading = true;
  bool _submitting = false;
  List<Json> _reviews = [];
  int _soSao = 5;
  int _tieuChi1 = 5;
  int _tieuChi2 = 5;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    setState(() => _loading = true);
    try {
      final contractId = '${widget.contract['maHopDong']}';
      final reviews = await ApiService.getContractReviews(contractId);
      if (mounted) {
        setState(() {
          _reviews = reviews;
          final myRole = widget.isLandowner ? 'chuDat' : 'nguoiNuoiOng';
          final myReview = reviews.firstWhere(
            (r) => r['vaiTroDanhGia'] == myRole,
            orElse: () => <String, dynamic>{},
          );
          if (myReview.isNotEmpty) {
            _soSao = int.tryParse('${myReview['soSao']}') ?? 5;
            _tieuChi1 = int.tryParse('${myReview['tieuChi1']}') ?? 5;
            _tieuChi2 = int.tryParse('${myReview['tieuChi2']}') ?? 5;
            _commentController.text = myReview['nhanXet']?.toString() ?? '';
          }
        });
      }
    } catch (_) {
      // Bỏ qua lỗi mạng
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final contractId = '${widget.contract['maHopDong']}';
    setState(() => _submitting = true);
    try {
      await ApiService.submitContractReview(
        contractId: contractId,
        soSao: _soSao,
        tieuChi1: _tieuChi1,
        tieuChi2: _tieuChi2,
        nhanXet: _commentController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Gửi đánh giá thành công! Cảm ơn đóng góp của bạn.');
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _starBar(int current, ValueChanged<int> onChanged, {double size = 32}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final star = index + 1;
        return InkWell(
          onTap: () => onChanged(star),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              star <= current ? Icons.star_rounded : Icons.star_outline_rounded,
              color: Colors.amber,
              size: size,
            ),
          ),
        );
      }),
    );
  }

  String _ratingLabel(int stars) {
    switch (stars) {
      case 1:
        return '1/5 - Rất không hài lòng';
      case 2:
        return '2/5 - Chưa đạt yêu cầu';
      case 3:
        return '3/5 - Tạm ổn';
      case 4:
        return '4/5 - Rất tốt & hài lòng';
      case 5:
      default:
        return '5/5 - Tuyệt vời & Rất khuyến khích!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerRole = widget.isLandowner ? 'nguoiNuoiOng' : 'chuDat';
    final partnerReview = _reviews.firstWhere(
      (r) => r['vaiTroDanhGia'] == partnerRole,
      orElse: () => <String, dynamic>{},
    );

    final partnerName = widget.isLandowner
        ? show(widget.contract['tenNguoiNuoiOng'])
        : show(widget.contract['tenChuDat']);

    final crit1Label = widget.isLandowner
        ? 'Ý thức giữ gìn vườn tược & cây cối'
        : 'Nguồn hoa, môi trường & độ an toàn vườn';

    final crit2Label = widget.isLandowner
        ? 'Thực hiện đúng cam kết & thanh toán'
        : 'Thái độ hợp tác & hỗ trợ của chủ đất';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.amber.withValues(alpha: 0.2),
                  child: const Icon(Icons.star_rounded, color: Colors.amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isLandowner ? 'Đánh giá Người nuôi ong' : 'Đánh giá Chủ đất & Vườn',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Đối tác: $partnerName • HĐ: ${widget.contract['maHopDong']}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Hiển thị đánh giá từ đối tác nếu có
            if (partnerReview.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.rate_review_outlined, size: 18, color: Colors.blue),
                        const SizedBox(width: 6),
                        Text(
                          'Đánh giá từ $partnerName',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < (int.tryParse('${partnerReview['soSao']}') ?? 5)
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 16,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((partnerReview['nhanXet'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '“${partnerReview['nhanXet']}”',
                        style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Gửi lúc ${show(partnerReview['ngayTao'])}',
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else ...[
              // Đánh giá tổng thể
              const Text(
                'Mức độ hài lòng tổng thể:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _starBar(_soSao, (v) => setState(() => _soSao = v), size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _ratingLabel(_soSao),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tiêu chí 1
              Text(
                crit1Label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              Row(
                children: [
                  _starBar(_tieuChi1, (v) => setState(() => _tieuChi1 = v), size: 24),
                  const SizedBox(width: 8),
                  Text('$_tieuChi1/5 ⭐', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
              const SizedBox(height: 10),

              // Tiêu chí 2
              Text(
                crit2Label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              Row(
                children: [
                  _starBar(_tieuChi2, (v) => setState(() => _tieuChi2 = v), size: 24),
                  const SizedBox(width: 8),
                  Text('$_tieuChi2/5 ⭐', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
              const SizedBox(height: 16),

              // Nhận xét chi tiết
              const Text(
                'Nhận xét & Góp ý chi tiết:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Nhận xét về vườn, độ an toàn, sự hỗ trợ hoặc lưu ý cho các đợt thuê sau...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.05),
                ),
              ),
              const SizedBox(height: 20),

              // Nút hành động
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Đóng'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: _submitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(_submitting ? 'Đang gửi...' : 'Gửi đánh giá'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
