import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ongmat/main.dart';
import 'package:mobile_ongmat/services/api_service.dart';
import 'package:mobile_ongmat/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Login screen renders title, fields and register link', (tester) async {
    await tester.pumpWidget(const OngMatApp(home: LoginScreen()));

    expect(find.text('Đăng Nhập Hệ Thống'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('Chưa có tài khoản? Đăng ký'), findsOneWidget);
  });

  testWidgets('Login validates empty fields before calling the API', (tester) async {
    await tester.pumpWidget(const OngMatApp(home: LoginScreen()));
    await tester.tap(find.text('ĐĂNG NHẬP'));
    await tester.pump();

    expect(find.text('Nhập email hoặc số điện thoại'), findsOneWidget);
    expect(find.text('Nhập mật khẩu'), findsOneWidget);
  });

  testWidgets('Register screen lets the user choose landowner or beekeeper', (tester) async {
    await tester.pumpWidget(const OngMatApp(home: RegisterScreen()));

    expect(find.text('Nuôi ong'), findsOneWidget);
    expect(find.text('Chủ đất'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  test('Role values are normalized across backend variants', () {
    expect(normalizeAppRole(' ChuDat '), 'chuDat');
    expect(normalizeAppRole('chudat'), 'chuDat');
    expect(normalizeAppRole('nguoinuoiong'), 'nguoiNuoiOng');
    expect(normalizeAppRole('nguoi nuoi ong'), 'nguoiNuoiOng');
    expect(normalizeAppRole('ADMIN'), 'admin');
    expect(normalizeAppRole('khong-ro'), 'nguoiNuoiOng');
  });

  test('QR content is parsed into a honey lot code', () {
    expect(ApiService.parseTraceCode('http://192.168.1.5:3000/truy-xuat-qr?ma=12'), 12);
    expect(ApiService.parseTraceCode('https://ongmat.vn/truy-xuat-qr?x=1&id=7'), 7);
    expect(ApiService.parseTraceCode(' #34 '), 34);
    expect(ApiService.parseTraceCode('https://example.com/khac'), isNull);
  });

  test('Formatting helpers produce Vietnamese display values', () {
    expect(formatMoney(3500000), '3.500.000 đ');
    expect(formatMoney(null), 'Thỏa thuận');
    expect(formatNumber(12.0), '12');
    expect(formatNumber('12.5'), '12.5');
    expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
    expect(latLngOf({'viDo': '16.1', 'kinhDo': 108.2})?.latitude, 16.1);
    expect(latLngOf({'viDo': 0, 'kinhDo': 0}), isNull);
  });
}
