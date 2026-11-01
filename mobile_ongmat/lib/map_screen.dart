import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'chat_hub_screen.dart';
import 'rental_request_screen.dart';
import 'services/api_service.dart';
import 'widgets/common.dart';

/// Bản đồ vị trí: người nuôi ong tìm đất đặt ong với bộ lọc đa tiêu chí,
/// chủ đất xem và quản lý vị trí vườn rẫy.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _search = TextEditingController();
  final _map = MapController();
  List<Json>? _all;
  bool _loading = true;
  String? _error;
  LatLng? _me;
  int? _selected;
  String _vaiTro = '';
  int _myId = 0;

  // --- CÁC TIÊU CHÍ BỘ LỌC ĐA NĂNG ---
  String? _provinceFilter; // Địa điểm / Tỉnh thành
  double? _radiusKm; // Khoảng cách GPS
  String? _capacityFilter; // Sức chứa đàn ong ('small': <30, 'medium': 30-80, 'large': >80)
  String? _priceFilter; // Giá thuê ('under800', '800to1500', 'over1500')
  String? _flowerFilter; // Loài hoa đặc trưng
  String? _climateFilter; // Khí hậu tại địa điểm
  String? _beeFilter; // Thích hợp loại ong gì
  List<String> _flowerCatalog = [];
  List<String> _beeCatalog = [];

  bool get _isLandowner => _vaiTro == 'chuDat';

  // Danh sách các loài hoa đặc trưng tổng hợp từ CSDL & vị trí thực tế
  List<String> get _effectiveFlowers {
    final set = <String>{};
    set.addAll(_flowerCatalog);
    for (final l in (_all ?? [])) {
      final f = (l['loaiHoa'] ?? '').toString().trim();
      if (f.isNotEmpty && !f.toLowerCase().contains('tất cả')) {
        for (final part in f.split(',')) {
          final p = part.trim();
          if (p.isNotEmpty) set.add(p);
        }
      }
    }
    if (set.isEmpty) {
      set.addAll([
        'Hoa Cà Phê',
        'Hoa Vải Thiều',
        'Hoa Nhãn Lồng',
        'Hoa Tràm Rừng',
        'Hoa Mận, Hoa Mơ',
        'Hoa Bạc Hà Đá',
        'Hoa Tự Nhiên',
      ]);
    }
    return set.toList();
  }

  // Danh sách các giống ong tổng hợp từ CSDL & vị trí thực tế
  List<String> get _effectiveBees {
    final set = <String>{};
    set.addAll(_beeCatalog);
    for (final l in (_all ?? [])) {
      final b = (l['loaiOngPhuHop'] ?? '').toString().trim();
      if (b.isNotEmpty && !b.toLowerCase().contains('mọi loài') && !b.toLowerCase().contains('tất cả')) {
        set.add(b);
      }
    }
    if (set.isEmpty) {
      set.addAll([
        'Ong nội (Apis cerana)',
        'Ong ngoại / Ong Ý (Apis mellifera)',
        'Ong dú (Stingless bee)',
      ]);
    }
    return set.toList();
  }

  int get _activeFilterCount {
    int count = 0;
    if (_provinceFilter != null) count++;
    if (_radiusKm != null) count++;
    if (_capacityFilter != null) count++;
    if (_priceFilter != null) count++;
    if (_flowerFilter != null) count++;
    if (_climateFilter != null) count++;
    if (_beeFilter != null) count++;
    return count;
  }

  void _clearAllFilters() {
    setState(() {
      _provinceFilter = null;
      _radiusKm = null;
      _capacityFilter = null;
      _priceFilter = null;
      _flowerFilter = null;
      _climateFilter = null;
      _beeFilter = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = normalizeAppRole(prefs.getString('vaiTro'));
      final myId = prefs.getInt('maNguoiDung') ?? 0;
      if (mounted) {
        setState(() {
          _vaiTro = role;
          _myId = myId;
        });
      }

      List<Json> locations = [];
      if (role == 'chuDat') {
        // Tải danh sách đất của chủ đất từ getLandownerDashboard
        try {
          final dash = await ApiService.getLandownerDashboard();
          final myLocs = List<Json>.from(dash['locations'] as List? ?? []);
          for (final loc in myLocs) {
            loc['isMyLand'] = true;
            loc['tenChuDat'] = 'Tôi';
          }
          locations.addAll(myLocs);
        } catch (_) {}

        // Tải thêm các vị trí đất mở nếu có
        try {
          final avail = await ApiService.getAvailableLocations();
          for (final a in avail) {
            if (!locations.any((l) => '${l['maDiaDiem']}' == '${a['maDiaDiem']}')) {
              locations.add(a);
            }
          }
        } catch (_) {}
      } else {
        locations = await ApiService.getAvailableLocations();
      }

      // Tải danh mục loài hoa và giống ong động từ Admin CSDL
      try {
        final catalog = await ApiService.getSpeciesCatalog();
        final flowers = (catalog['flowers'] as List?)
                ?.map((e) => (e['tenLoaiHoa'] ?? '').toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            [];
        final bees = (catalog['bees'] as List?)
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

      if (mounted) setState(() => _all = locations);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _distance(Json farm) {
    final point = latLngOf(farm);
    if (_me == null || point == null) return null;
    return const Distance().as(LengthUnit.Kilometer, _me!, point);
  }

  List<Json> get _farms {
    final keyword = _search.text.trim().toLowerCase();
    final list = (_all ?? []).where((farm) {
      final flowerStr = (farm['loaiHoa'] ?? '').toString();
      final climateStr = (farm['khiHau'] ?? '').toString();
      final beeStr = (farm['loaiOngPhuHop'] ?? '').toString();
      final text =
          '${farm['tenDiaDiem']} ${farm['diaChiChiTiet']} ${farm['tenChuDat']} $flowerStr $climateStr $beeStr'
              .toLowerCase();
      final distance = _distance(farm);
      final cap = int.tryParse('${farm['sucChuaToiDa']}') ?? 0;
      final price = num.tryParse('${farm['giaThueThang']}') ?? 0;

      // 1. Tìm kiếm từ khóa
      if (keyword.isNotEmpty && !text.contains(keyword)) return false;

      // 1.5. Lọc theo Địa điểm / Tỉnh thành (Hỗ trợ 63 tỉnh thành & viết tắt)
      if (_provinceFilter != null &&
          _provinceFilter!.isNotEmpty &&
          _provinceFilter != 'Tất cả tỉnh thành') {
        if (!_matchesProvince(farm, _provinceFilter!)) return false;
      }

      // 2. Khoảng cách GPS
      if (_radiusKm != null && (distance == null || distance > _radiusKm!)) {
        return false;
      }

      // 3. Sức chứa / Số lượng đàn ong
      if (_capacityFilter != null) {
        if (_capacityFilter == 'small' && cap >= 30) return false;
        if (_capacityFilter == 'medium' && (cap < 30 || cap > 80)) return false;
        if (_capacityFilter == 'large' && cap <= 80) return false;
      }

      // 4. Giá thuê
      if (_priceFilter != null) {
        if (_priceFilter == 'under800' && (price <= 0 || price > 800000)) return false;
        if (_priceFilter == '800to1500' && (price < 800000 || price > 1500000)) return false;
        if (_priceFilter == 'over1500' && price < 1500000) return false;
      }

      // 5. Loài hoa đặc trưng
      if (_flowerFilter != null) {
        final target = _flowerFilter!.toLowerCase();
        final clean = target.replaceAll('hoa', '').trim();
        final flLow = flowerStr.toLowerCase();
        final matches = flLow.contains(target) ||
            flLow.contains(clean) ||
            target.contains(flLow) ||
            clean.split(',').any((p) => flLow.contains(p.trim())) ||
            text.contains(clean);
        if (!matches) return false;
      }

      // 6. Khí hậu
      if (_climateFilter != null) {
        final target = _climateFilter!.toLowerCase();
        final clLow = climateStr.toLowerCase();
        if (!clLow.contains(target) && !text.contains(target)) {
          return false;
        }
      }

      // 7. Thích hợp loại ong gì
      if (_beeFilter != null) {
        final target = _beeFilter!.toLowerCase();
        final beeLow = beeStr.toLowerCase();
        final isUniversal = beeLow.contains('mọi loài') || beeLow.contains('đa loài');
        if (!isUniversal) {
          final tokens = target
              .replaceAll('(', ' ')
              .replaceAll(')', ' ')
              .replaceAll('/', ' ')
              .split(RegExp(r'\s+'))
              .where((t) => t.length > 2 && t != 'ong')
              .toList();

          bool matched = beeLow.contains(target) || target.contains(beeLow);
          if (!matched) {
            for (final t in tokens) {
              if (beeLow.contains(t) || text.contains(t)) {
                matched = true;
                break;
              }
            }
          }
          if (!matched) return false;
        }
      }

      return true;
    }).toList();

    if (_me != null) {
      list.sort((a, b) =>
          (_distance(a) ?? double.infinity).compareTo(_distance(b) ?? double.infinity));
    }
    return list;
  }

  Future<void> _nearMeWithRadius(double km) async {
    try {
      final position = await currentPosition();
      if (!mounted) return;
      setState(() {
        _me = position;
        _radiusKm = km;
      });
      _map.move(position, km <= 20 ? 11 : 9);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  void _focus(Json farm) {
    setState(() => _selected = int.tryParse('${farm['maDiaDiem']}'));
    final point = latLngOf(farm);
    if (point != null) _map.move(point, 13);
  }

  bool _matchesProvince(Map<String, dynamic> farm, String targetProv) {
    if (targetProv.isEmpty || targetProv == 'Tất cả tỉnh thành') return true;
    final addr = '${farm['diaChiChiTiet']} ${farm['tenDiaDiem']}'.toLowerCase();
    final target = targetProv.toLowerCase();
    if (addr.contains(target)) return true;

    final clean = target
        .replaceAll('tỉnh ', '')
        .replaceAll('thành phố ', '')
        .replaceAll('tp ', '')
        .replaceAll('tp.', '')
        .replaceAll('-', ' ')
        .trim();
    if (clean.isNotEmpty && addr.contains(clean)) return true;

    if (target.contains('hồ chí minh')) {
      if (addr.contains('tp.hcm') ||
          addr.contains('tphcm') ||
          addr.contains('tp hcm') ||
          addr.contains('hcm') ||
          addr.contains('sài gòn')) {
        return true;
      }
    }
    if (target.contains('hà nội') && (addr.contains('hn') || addr.contains('ha noi'))) {
      return true;
    }
    if (target.contains('đà nẵng') && (addr.contains('đn') || addr.contains('da nang'))) {
      return true;
    }
    if (target.contains('bà rịa') && addr.contains('vũng tàu')) {
      return true;
    }
    if (target.contains('thừa thiên huế') && addr.contains('huế')) {
      return true;
    }
    return false;
  }

  void _autoFocusSelectedFarms() {
    final list = _farms;
    final points = [
      for (final farm in list)
        if (latLngOf(farm) case final point?) (farm: farm, point: point),
    ];
    if (points.isNotEmpty) {
      final first = points.first;
      setState(() => _selected = int.tryParse('${first.farm['maDiaDiem']}'));
      _map.move(first.point, 12);
    } else if (_provinceFilter != null &&
        _provinceFilter!.isNotEmpty &&
        _provinceFilter != 'Tất cả tỉnh thành') {
      _panToProvince(_provinceFilter!);
    }
  }

  Future<void> _panToProvince(String prov) async {
    try {
      final results = await ApiService.searchPlaces('$prov, Việt Nam');
      if (results.isNotEmpty && mounted) {
        final lat = double.tryParse('${results.first['lat']}');
        final lon = double.tryParse('${results.first['lon']}');
        if (lat != null && lon != null) {
          _map.move(LatLng(lat, lon), 10);
          showSnack(
            context,
            '📍 Đã di chuyển bản đồ đến $prov (Chưa có vườn rẫy nào đăng ký tại tỉnh này)',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _chatWithLandowner(Json farm) async {
    int? partnerId = int.tryParse('${farm['maChuDat']}');
    String partnerName = (farm['tenChuDat'] != null && farm['tenChuDat'].toString().trim().isNotEmpty)
        ? farm['tenChuDat'].toString().trim()
        : 'Chủ đất';
    String partnerPhone = farm['sdtChuDat']?.toString() ?? farm['soDienThoai']?.toString() ?? '';

    // Nếu partnerId trống hoặc 0, tự động tra cứu từ backend chat theo số điện thoại hoặc tên
    if (partnerId == null || partnerId == 0) {
      if (partnerPhone.isNotEmpty) {
        try {
          final found = await ApiService.searchChatUsers(partnerPhone);
          if (found.isNotEmpty) {
            final u = found.first;
            partnerId = int.tryParse('${u['maNguoiDung']}');
            if (u['hoTen'] != null && u['hoTen'].toString().trim().isNotEmpty) {
              partnerName = u['hoTen'].toString().trim();
            }
          }
        } catch (_) {}
      }
      if ((partnerId == null || partnerId == 0) && partnerName != 'Chủ đất' && partnerName != 'Tôi') {
        try {
          final found = await ApiService.searchChatUsers(partnerName);
          if (found.isNotEmpty) {
            final u = found.first;
            partnerId = int.tryParse('${u['maNguoiDung']}');
            if (u['hoTen'] != null && u['hoTen'].toString().trim().isNotEmpty) {
              partnerName = u['hoTen'].toString().trim();
            }
            if (u['soDienThoai'] != null) {
              partnerPhone = u['soDienThoai'].toString().trim();
            }
          }
        } catch (_) {}
      }
      if ((partnerId == null || partnerId == 0) && partnerName.toLowerCase().contains('demo')) {
        partnerId = 2; // ID mặc định của Chủ đất Demo
      }
    }

    if (partnerId == null || partnerId == 0) {
      if (mounted) showSnack(context, 'Không tìm thấy thông tin tài khoản của chủ đất để nhắn tin.');
      return;
    }

    if (partnerId == _myId && _myId > 0) {
      if (mounted) showSnack(context, 'Đây là đất của bạn, không thể tự nhắn tin cho chính mình.');
      return;
    }

    if (!mounted) return;
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
  }

  Future<void> _request(Json farm) async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RentalRequestScreen(location: farm)),
    );
    if (sent == true) await _load();
  }

  // --- MODAL BOTTOM SHEET BỘ LỌC CHI TIẾT ---
  void _openFilterDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return SizedBox(
              height: MediaQuery.of(modalContext).size.height * 0.82,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune_rounded, color: Color(0xFFD97706)),
                            const SizedBox(width: 8),
                            const Text(
                              'Bộ lọc tìm kiếm đất',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (_activeFilterCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEA580C),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_activeFilterCount',
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
                        TextButton(
                          onPressed: () {
                            _clearAllFilters();
                            setModalState(() {});
                            setState(() {});
                          },
                          child: const Text('Đặt lại', style: TextStyle(color: Color(0xFFEF4444))),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                          // 1. Địa điểm / Tỉnh thành (Dạng menu sổ xuống đầy đủ 63 tỉnh thành)
                          _buildSectionTitle(Icons.place_rounded, 'Địa điểm / Tỉnh thành (Toàn quốc)'),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _provinceFilter != null ? const Color(0xFFD97706) : const Color(0xFFCBD5E1),
                                width: _provinceFilter != null ? 1.6 : 1,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _provinceFilter ?? 'Tất cả tỉnh thành',
                                icon: const Icon(Icons.arrow_drop_down_circle_rounded, color: Color(0xFFD97706)),
                                menuMaxHeight: 360,
                                items: kAllProvincesOfVietnam.map((prov) {
                                  final isAll = prov == 'Tất cả tỉnh thành';
                                  return DropdownMenuItem<String>(
                                    value: prov,
                                    child: Row(
                                      children: [
                                        Icon(
                                          isAll ? Icons.public_rounded : Icons.location_on_rounded,
                                          size: 16,
                                          color: isAll ? const Color(0xFFD97706) : const Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            prov,
                                            style: TextStyle(
                                              fontWeight: isAll ? FontWeight.bold : FontWeight.w500,
                                              color: const Color(0xFF1E293B),
                                              fontSize: 13.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  final selected = (val == null || val == 'Tất cả tỉnh thành') ? null : val;
                                  setModalState(() => _provinceFilter = selected);
                                  setState(() => _provinceFilter = selected);
                                  _autoFocusSelectedFarms();
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 2. Khoảng cách
                          _buildSectionTitle(Icons.near_me_rounded, 'Khoảng cách vị trí'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Tất cả khoảng cách',
                                selected: _radiusKm == null,
                                onSelected: () {
                                  setModalState(() => _radiusKm = null);
                                  setState(() => _radiusKm = null);
                                },
                              ),
                              _buildChoiceChip(
                                label: '< 15 km (Gần tôi)',
                                selected: _radiusKm == 15,
                                onSelected: () {
                                  setModalState(() => _radiusKm = 15);
                                  setState(() => _radiusKm = 15);
                                  if (_me == null) {
                                    _nearMeWithRadius(15).then((_) {
                                      if (mounted) {
                                        setModalState(() {});
                                        setState(() {});
                                      }
                                    });
                                  }
                                },
                              ),
                              _buildChoiceChip(
                                label: '< 30 km',
                                selected: _radiusKm == 30,
                                onSelected: () {
                                  setModalState(() => _radiusKm = 30);
                                  setState(() => _radiusKm = 30);
                                  if (_me == null) {
                                    _nearMeWithRadius(30).then((_) {
                                      if (mounted) {
                                        setModalState(() {});
                                        setState(() {});
                                      }
                                    });
                                  }
                                },
                              ),
                              _buildChoiceChip(
                                label: '< 50 km',
                                selected: _radiusKm == 50,
                                onSelected: () {
                                  setModalState(() => _radiusKm = 50);
                                  setState(() => _radiusKm = 50);
                                  if (_me == null) {
                                    _nearMeWithRadius(50).then((_) {
                                      if (mounted) {
                                        setModalState(() {});
                                        setState(() {});
                                      }
                                    });
                                  }
                                },
                              ),
                              _buildChoiceChip(
                                label: '< 100 km',
                                selected: _radiusKm == 100,
                                onSelected: () {
                                  setModalState(() => _radiusKm = 100);
                                  setState(() => _radiusKm = 100);
                                  if (_me == null) {
                                    _nearMeWithRadius(100).then((_) {
                                      if (mounted) {
                                        setModalState(() {});
                                        setState(() {});
                                      }
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 2. Số lượng đàn ong / Sức chứa
                          _buildSectionTitle(Icons.hive_rounded, 'Số lượng đàn ong / Sức chứa'),
                          Wrap(
                            spacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Mọi quy mô',
                                selected: _capacityFilter == null,
                                onSelected: () {
                                  setModalState(() => _capacityFilter = null);
                                  setState(() => _capacityFilter = null);
                                },
                              ),
                              _buildChoiceChip(
                                label: 'Nhỏ (< 30 thùng)',
                                selected: _capacityFilter == 'small',
                                onSelected: () {
                                  setModalState(() => _capacityFilter = 'small');
                                  setState(() => _capacityFilter = 'small');
                                },
                              ),
                              _buildChoiceChip(
                                label: 'Vừa (30 - 80 thùng)',
                                selected: _capacityFilter == 'medium',
                                onSelected: () {
                                  setModalState(() => _capacityFilter = 'medium');
                                  setState(() => _capacityFilter = 'medium');
                                },
                              ),
                              _buildChoiceChip(
                                label: 'Lớn (> 80 thùng)',
                                selected: _capacityFilter == 'large',
                                onSelected: () {
                                  setModalState(() => _capacityFilter = 'large');
                                  setState(() => _capacityFilter = 'large');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 3. Mức giá thuê
                          _buildSectionTitle(Icons.payments_rounded, 'Mức giá thuê đất'),
                          Wrap(
                            spacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Mọi mức giá',
                                selected: _priceFilter == null,
                                onSelected: () {
                                  setModalState(() => _priceFilter = null);
                                  setState(() => _priceFilter = null);
                                },
                              ),
                              _buildChoiceChip(
                                label: '< 800.000 đ/tháng',
                                selected: _priceFilter == 'under800',
                                onSelected: () {
                                  setModalState(() => _priceFilter = 'under800');
                                  setState(() => _priceFilter = 'under800');
                                },
                              ),
                              _buildChoiceChip(
                                label: '800k - 1.5 triệu/tháng',
                                selected: _priceFilter == '800to1500',
                                onSelected: () {
                                  setModalState(() => _priceFilter = '800to1500');
                                  setState(() => _priceFilter = '800to1500');
                                },
                              ),
                              _buildChoiceChip(
                                label: '> 1.5 triệu/tháng',
                                selected: _priceFilter == 'over1500',
                                onSelected: () {
                                  setModalState(() => _priceFilter = 'over1500');
                                  setState(() => _priceFilter = 'over1500');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 4. Loài hoa đặc trưng
                          _buildSectionTitle(
                              Icons.local_florist_rounded, 'Loài hoa đặc trưng / Nguồn mật'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Tất cả loài hoa',
                                selected: _flowerFilter == null,
                                onSelected: () {
                                  setModalState(() => _flowerFilter = null);
                                  setState(() => _flowerFilter = null);
                                },
                              ),
                              for (final f in _effectiveFlowers)
                                _buildChoiceChip(
                                  label: f,
                                  selected: _flowerFilter == f,
                                  onSelected: () {
                                    final val = (_flowerFilter == f ? null : f);
                                    setModalState(() => _flowerFilter = val);
                                    setState(() => _flowerFilter = val);
                                    _autoFocusSelectedFarms();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 5. Khí hậu
                          _buildSectionTitle(Icons.wb_sunny_rounded, 'Khí hậu tại địa điểm'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Mọi khí hậu',
                                selected: _climateFilter == null,
                                onSelected: () {
                                  setModalState(() => _climateFilter = null);
                                  setState(() => _climateFilter = null);
                                  _autoFocusSelectedFarms();
                                },
                              ),
                              for (final c in [
                                'Ôn đới',
                                'Cao nguyên',
                                'Nhiệt đới',
                              ])
                                _buildChoiceChip(
                                  label: c == 'Ôn đới'
                                      ? 'Ôn đới mát mẻ'
                                      : (c == 'Cao nguyên'
                                          ? 'Cao nguyên ôn hòa'
                                          : 'Nhiệt đới nắng ấm'),
                                  selected: _climateFilter == c,
                                  onSelected: () {
                                    final val = (_climateFilter == c ? null : c);
                                    setModalState(() => _climateFilter = val);
                                    setState(() => _climateFilter = val);
                                    _autoFocusSelectedFarms();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 6. Thích hợp loại ong gì
                          _buildSectionTitle(
                              Icons.pest_control_rounded, 'Thích hợp cho loài ong gì'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Mọi loài ong',
                                selected: _beeFilter == null,
                                onSelected: () {
                                  setModalState(() => _beeFilter = null);
                                  setState(() => _beeFilter = null);
                                  _autoFocusSelectedFarms();
                                },
                              ),
                              for (final b in _effectiveBees)
                                _buildChoiceChip(
                                  label: b,
                                  selected: _beeFilter == b,
                                  onSelected: () {
                                    final val = (_beeFilter == b ? null : b);
                                    setModalState(() => _beeFilter = val);
                                    setState(() => _beeFilter = val);
                                    _autoFocusSelectedFarms();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: const Color(0xFFD97706),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(modalContext).pop(),
                        child: Text(
                          'Xem kết quả (${_farms.length} địa điểm)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFB45309)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilterChip<T>({
    required IconData icon,
    required String label,
    required bool isSelected,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    return PopupMenuButton<T>(
      tooltip: label,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(maxHeight: 380, minWidth: 220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD97706) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFB45309) : const Color(0xFFCBD5E1),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFFD97706),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFD97706) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFFB45309) : const Color(0xFFCBD5E1),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farms = _farms;
    final points = [
      for (final farm in farms)
        if (latLngOf(farm) case final point?) (farm: farm, point: point),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLandowner ? 'Bản đồ vị trí vườn rẫy' : 'Tìm đất đặt ong'),
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        hasData: _all != null,
        onRetry: _load,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Tìm theo tên vườn, địa chỉ, hoa, loài ong...',
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),

          // --- THANH CUỘN BỘ LỌC NGANG DƯỚI THANH TÌM KIẾM ---
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // 1. Nút mở toàn bộ bộ lọc
                ActionChip(
                  avatar: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _activeFilterCount > 0 ? Colors.white : const Color(0xFFD97706),
                  ),
                  backgroundColor: _activeFilterCount > 0
                      ? const Color(0xFFD97706)
                      : const Color(0xFFFEF3C7),
                  label: Text(
                    _activeFilterCount > 0 ? 'Bộ lọc ($_activeFilterCount)' : 'Bộ lọc',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _activeFilterCount > 0 ? Colors.white : const Color(0xFF92400E),
                    ),
                  ),
                  onPressed: _openFilterDialog,
                ),
                const SizedBox(width: 8),

                // 1.5. Dropdown Địa điểm / Tỉnh thành (ĐẦY ĐỦ 63 TỈNH THÀNH)
                _buildDropdownFilterChip<String>(
                  icon: Icons.place_rounded,
                  label: _provinceFilter != null ? _provinceFilter! : 'Địa điểm (63 tỉnh)',
                  isSelected: _provinceFilter != null,
                  items: [
                    for (final prov in kAllProvincesOfVietnam)
                      PopupMenuItem<String>(
                        value: prov,
                        child: Row(
                          children: [
                            Icon(
                              prov == 'Tất cả tỉnh thành'
                                  ? Icons.public_rounded
                                  : Icons.location_on_rounded,
                              size: 16,
                              color: (_provinceFilter ?? 'Tất cả tỉnh thành') == prov
                                  ? const Color(0xFFD97706)
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                prov,
                                style: TextStyle(
                                  fontWeight: (_provinceFilter ?? 'Tất cả tỉnh thành') == prov
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: (_provinceFilter ?? 'Tất cả tỉnh thành') == prov
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF1E293B),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if ((_provinceFilter ?? 'Tất cả tỉnh thành') == prov)
                              const Icon(Icons.check, size: 16, color: Color(0xFFD97706)),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (val) {
                    setState(() {
                      _provinceFilter = (val == 'Tất cả tỉnh thành') ? null : val;
                    });
                    _autoFocusSelectedFarms();
                  },
                ),
                const SizedBox(width: 8),

                // 2. Dropdown Khoảng cách
                _buildDropdownFilterChip<double?>(
                  icon: Icons.near_me_rounded,
                  label: _radiusKm != null ? '< ${_radiusKm!.toInt()} km' : 'Khoảng cách',
                  isSelected: _radiusKm != null,
                  items: const [
                    PopupMenuItem(value: null, child: Text('Tất cả khoảng cách')),
                    PopupMenuItem(value: 15.0, child: Text('< 15 km (Gần tôi)')),
                    PopupMenuItem(value: 30.0, child: Text('< 30 km')),
                    PopupMenuItem(value: 50.0, child: Text('< 50 km')),
                    PopupMenuItem(value: 100.0, child: Text('< 100 km')),
                  ],
                  onSelected: (val) {
                    setState(() => _radiusKm = val);
                    if (val != null && _me == null) {
                      _nearMeWithRadius(val);
                    } else {
                      _autoFocusSelectedFarms();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 3. Dropdown Sức chứa đàn ong
                _buildDropdownFilterChip<String?>(
                  icon: Icons.hive_rounded,
                  label: _capacityFilter == 'small'
                      ? '< 30 thùng'
                      : (_capacityFilter == 'medium'
                          ? '30 - 80 thùng'
                          : (_capacityFilter == 'large' ? '> 80 thùng' : 'Sức chứa đàn')),
                  isSelected: _capacityFilter != null,
                  items: const [
                    PopupMenuItem(value: null, child: Text('Mọi quy mô')),
                    PopupMenuItem(value: 'small', child: Text('Nhỏ (< 30 thùng)')),
                    PopupMenuItem(value: 'medium', child: Text('Vừa (30 - 80 thùng)')),
                    PopupMenuItem(value: 'large', child: Text('Lớn (> 80 thùng)')),
                  ],
                  onSelected: (val) {
                    setState(() => _capacityFilter = val);
                    _autoFocusSelectedFarms();
                  },
                ),
                const SizedBox(width: 8),

                // 4. Dropdown Giá thuê
                _buildDropdownFilterChip<String?>(
                  icon: Icons.payments_rounded,
                  label: _priceFilter == 'under800'
                      ? '< 800k'
                      : (_priceFilter == '800to1500'
                          ? '800k - 1.5tr'
                          : (_priceFilter == 'over1500' ? '> 1.5tr' : 'Giá thuê')),
                  isSelected: _priceFilter != null,
                  items: const [
                    PopupMenuItem(value: null, child: Text('Mọi mức giá')),
                    PopupMenuItem(value: 'under800', child: Text('< 800.000 đ/tháng')),
                    PopupMenuItem(value: '800to1500', child: Text('800k - 1.5 triệu/tháng')),
                    PopupMenuItem(value: 'over1500', child: Text('> 1.5 triệu/tháng')),
                  ],
                  onSelected: (val) {
                    setState(() => _priceFilter = val);
                    _autoFocusSelectedFarms();
                  },
                ),
                const SizedBox(width: 8),

                // 5. Dropdown Loài hoa
                _buildDropdownFilterChip<String?>(
                  icon: Icons.local_florist_rounded,
                  label: _flowerFilter != null ? _flowerFilter! : 'Loài hoa',
                  isSelected: _flowerFilter != null,
                  items: [
                    const PopupMenuItem(value: null, child: Text('Tất cả loài hoa')),
                    for (final f in _effectiveFlowers)
                      PopupMenuItem(
                        value: f,
                        child: Row(
                          children: [
                            const Icon(Icons.eco_rounded, size: 16, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                            if (_flowerFilter == f)
                              const Icon(Icons.check, size: 16, color: Color(0xFFD97706)),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (val) {
                    setState(() => _flowerFilter = val);
                    _autoFocusSelectedFarms();
                  },
                ),
                const SizedBox(width: 8),

                // 6. Dropdown Khí hậu
                _buildDropdownFilterChip<String?>(
                  icon: Icons.wb_sunny_rounded,
                  label: _climateFilter != null ? 'Khí hậu $_climateFilter' : 'Khí hậu',
                  isSelected: _climateFilter != null,
                  items: const [
                    PopupMenuItem(value: null, child: Text('Mọi khí hậu')),
                    PopupMenuItem(value: 'Ôn đới', child: Text('Ôn đới mát mẻ')),
                    PopupMenuItem(value: 'Cao nguyên', child: Text('Cao nguyên ôn hòa')),
                    PopupMenuItem(value: 'Nhiệt đới', child: Text('Nhiệt đới nắng ấm')),
                  ],
                  onSelected: (val) {
                    setState(() => _climateFilter = val);
                    _autoFocusSelectedFarms();
                  },
                ),
                const SizedBox(width: 8),

                // 7. Dropdown Loài ong
                _buildDropdownFilterChip<String?>(
                  icon: Icons.pest_control_rounded,
                  label: _beeFilter != null ? _beeFilter! : 'Loại ong',
                  isSelected: _beeFilter != null,
                  items: [
                    const PopupMenuItem(value: null, child: Text('Tất cả loại ong')),
                    for (final b in _effectiveBees)
                      PopupMenuItem(
                        value: b,
                        child: Row(
                          children: [
                            const Icon(Icons.pest_control_rounded, size: 16, color: Color(0xFFD97706)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(b, style: const TextStyle(fontSize: 13))),
                            if (_beeFilter == b)
                              const Icon(Icons.check, size: 16, color: Color(0xFFD97706)),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (val) {
                    setState(() => _beeFilter = val);
                    _autoFocusSelectedFarms();
                  },
                ),

                if (_activeFilterCount > 0) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16, color: Colors.red),
                    label: const Text('Xóa lọc',
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _clearAllFilters,
                  ),
                ],
              ],
            ),
          ),

          // --- KHUNG BẢN ĐỒ FLUTTER MAP ---
          SizedBox(
            height: 220,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: points.isNotEmpty ? points.first.point : kDefaultCenter,
                initialZoom: points.isNotEmpty ? 8 : 5.5,
              ),
              children: [
                osmTiles(),
                MarkerLayer(markers: [
                  if (_me != null)
                    Marker(
                      point: _me!,
                      width: 26,
                      height: 26,
                      child: const Icon(Icons.my_location, color: Colors.blue),
                    ),
                  ...points.map((p) {
                    final active = int.tryParse('${p.farm['maDiaDiem']}') == _selected;
                    final isMyFarm = p.farm['isMyLand'] == true ||
                        (int.tryParse('${p.farm['maChuDat']}') ?? 0) == _myId && _myId > 0;
                    return Marker(
                      point: p.point,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _focus(p.farm),
                        child: Icon(
                          Icons.location_on,
                          color: active
                              ? Colors.red
                              : (isMyFarm ? const Color(0xFFEA580C) : const Color(0xFF1E7B5F)),
                          size: active ? 44 : 38,
                        ),
                      ),
                    );
                  }),
                ]),
              ],
            ),
          ),

          // --- DANH SÁCH CÁC KHU ĐẤT ĐÃ LỌC ---
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: farms.isEmpty
                  ? ListView(
                      children: const [
                        EmptyState(
                          icon: Icons.search_off_rounded,
                          message: 'Không tìm thấy địa điểm phù hợp với bộ lọc.',
                        )
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: farms.length,
                      itemBuilder: (_, index) => _farmCard(farms[index]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTag(IconData icon, String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _farmCard(Json farm) {
    final distance = _distance(farm);
    final myStatus = farm['trangThaiYeuCauCuaToi'];
    final active = int.tryParse('${farm['maDiaDiem']}') == _selected;
    final isMine = farm['isMyLand'] == true ||
        (int.tryParse('${farm['maChuDat']}') ?? 0) == _myId && _myId > 0;
    final flower = farm['loaiHoa']?.toString();
    final bee = farm['loaiOngPhuHop']?.toString();
    final climate = farm['khiHau']?.toString();
    final price = farm['giaThueThang'];

    final maxCap = int.tryParse('${farm['sucChuaToiDa']}') ?? 0;
    final rented = int.tryParse('${farm['soDanDaThue']}') ?? 0;
    final remaining = farm['sucChuaConLai'] != null
        ? int.tryParse('${farm['sucChuaConLai']}') ?? (maxCap - rented).clamp(0, 999999)
        : (maxCap - rented).clamp(0, 999999);
    final isFull = (remaining <= 0 && maxCap > 0);

    return Card(
      elevation: active ? 3 : 0,
      color: active ? const Color(0xFFFFFBEB) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: active ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
          width: active ? 1.8 : 1,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _focus(farm),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  show(farm['tenDiaDiem']),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (distance != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.near_me_rounded, size: 12, color: Color(0xFF2563EB)),
                      const SizedBox(width: 3),
                      Text(
                        '${distance.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    show(farm['diaChiChiTiet']),
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                InkWell(
                  onTap: isMine ? null : () => _chatWithLandowner(farm),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isMine ? const Color(0xFFFFF7ED) : const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isMine ? const Color(0xFFFDBA74) : const Color(0xFFBAE6FD),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMine ? Icons.person_rounded : Icons.chat_bubble_outline_rounded,
                          size: 13,
                          color: isMine ? const Color(0xFFEA580C) : const Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isMine ? 'Chủ sở hữu: Tôi' : 'Chủ đất: ${show(farm['tenChuDat'])}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isMine ? const Color(0xFFEA580C) : const Color(0xFF0369A1),
                          ),
                        ),
                        if (!isMine) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 9, color: Color(0xFF0284C7)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!isMine && farm['uyTinChuDat'] != null)
                  UserReputationBadge(
                    isNew: farm['laNguoiMoiChuDat'],
                    rating: farm['uyTinChuDat'],
                    reviewCount: farm['tongDanhGiaChuDat'],
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // THẺ THÔNG TIN ĐẶC TRƯNG: HOA, KHÍ HẬU, LOÀI ONG, GIÁ THUÊ & SỨC CHỨA
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (flower != null && flower.isNotEmpty)
                  _buildTag(Icons.local_florist_rounded, flower, const Color(0xFFEC4899),
                      const Color(0xFFFDF2F8)),
                if (climate != null && climate.isNotEmpty)
                  _buildTag(Icons.wb_sunny_rounded, climate, const Color(0xFFD97706),
                      const Color(0xFFFFFBEB)),
                if (bee != null && bee.isNotEmpty)
                  _buildTag(Icons.pest_control_rounded, bee, const Color(0xFF0D9488),
                      const Color(0xFFF0FDFA)),
                if (price != null && num.tryParse('$price') != null && num.parse('$price') > 0)
                  _buildTag(
                    Icons.payments_rounded,
                    '${formatNumber(price)} đ/tháng',
                    const Color(0xFF16A34A),
                    const Color(0xFFF0FDF4),
                  )
                else
                  _buildTag(Icons.handshake_outlined, 'Giá thỏa thuận', const Color(0xFF64748B),
                      const Color(0xFFF8FAFC)),
                _buildTag(
                  Icons.inventory_2_outlined,
                  'Sức chứa $maxCap đàn${farm['dienTich'] != null ? ' (${formatNumber(farm['dienTich'])} ha)' : ''}',
                  const Color(0xFF3B82F6),
                  const Color(0xFFEFF6FF),
                ),
                // HIỂN THỊ CHỖ TRỐNG CÒN LẠI HOẶC ĐÃ HẾT CHỖ
                if (isFull)
                  _buildTag(
                    Icons.block_rounded,
                    'Đã hết chỗ ($rented/$maxCap đàn)',
                    Colors.red.shade700,
                    const Color(0xFFFEF2F2),
                  )
                else if (rented > 0)
                  _buildTag(
                    Icons.check_circle_outline_rounded,
                    'Còn trống $remaining/$maxCap đàn (Thuê tiếp)',
                    const Color(0xFF16A34A),
                    const Color(0xFFF0FDF4),
                  )
                else
                  _buildTag(
                    Icons.meeting_room_outlined,
                    'Trống 100% (còn $maxCap đàn)',
                    const Color(0xFFD97706),
                    const Color(0xFFFEF3C7),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            _isLandowner
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isMine ? const Color(0xFFFFEDD5) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: isMine ? Border.all(color: const Color(0xFFF97316)) : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMine ? Icons.verified_user_rounded : Icons.place_rounded,
                            size: 14,
                            color: isMine ? const Color(0xFFEA580C) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMine
                                ? (farm['trangThaiKiemDuyet'] == 'ChoDiemDuyet'
                                    ? 'Đất của tôi (Chờ duyệt)'
                                    : 'Đất của tôi (Đã duyệt)')
                                : 'Vườn nhà khác',
                            style: TextStyle(
                              color: isMine ? const Color(0xFFEA580C) : const Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    children: [
                      // Nút Nhắn tin hỏi chủ đất
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                          backgroundColor: const Color(0xFFF0F9FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _chatWithLandowner(farm),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                        label: const Text(
                          'Nhắn tin',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Nút Gửi yêu cầu thuê / Trạng thái
                      Expanded(
                        child: myStatus != null
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: StatusChip(myStatus),
                              )
                            : (isFull
                                ? FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.grey.shade400,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: null,
                                    icon: const Icon(Icons.block_rounded, size: 16),
                                    label: const Text(
                                      'Đã hết chỗ',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFD97706),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _request(farm),
                                    icon: const Icon(Icons.send_rounded, size: 16),
                                    label: Text(
                                      'Gửi yêu cầu thuê (còn ${remaining} chỗ)',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  )),
                      ),
                    ],
                  ),
          ]),
        ),
      ),
    );
  }
}
