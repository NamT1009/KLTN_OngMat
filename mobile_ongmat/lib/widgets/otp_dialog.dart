import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Hiển thị hộp thoại xác thực mã OTP gửi về Gmail / SĐT
Future<bool> showOtpDialog({
  required BuildContext context,
  String? email,
  String? soDienThoai,
  required String loaiHanhDong,
}) async {
  final otpController = TextEditingController();
  bool isVerifying = false;
  bool isResending = false;
  String? errorMessage;
  int countdown = 60;
  Timer? timer;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          // Bắt đầu đếm ngược 60s cho phép gửi lại mã
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (countdown > 0) {
              setModalState(() => countdown--);
            } else {
              t.cancel();
            }
          });

          final targetInfo = email != null && email.isNotEmpty
              ? email
              : (soDienThoai ?? '');

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            title: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFDBA74)),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: Color(0xFFD97706),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Xác thực tài khoản',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF4B5563),
                        height: 1.45,
                      ),
                      children: [
                        const TextSpan(text: 'Mã xác thực OTP gồm 6 chữ số đã được gửi tới:\n'),
                        TextSpan(
                          text: targetInfo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                        if (email != null && email.isNotEmpty)
                          const TextSpan(
                            text: '\n(Vui lòng kiểm tra Hộp thư đến hoặc Thư rác/Spam)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB45309),
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      hintStyle: const TextStyle(
                        color: Color(0xFFD1D5DB),
                        letterSpacing: 8,
                      ),
                      errorText: errorMessage,
                      errorMaxLines: 2,
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFD97706),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Nút gửi lại mã hoặc đếm ngược
                  if (countdown > 0)
                    Text(
                      'Gửi lại mã sau ${countdown}s',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFD97706),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      onPressed: isResending
                          ? null
                          : () async {
                              setModalState(() {
                                isResending = true;
                                errorMessage = null;
                              });
                              try {
                                final res = await ApiService.sendOtp(
                                  email: email ?? '',
                                  soDienThoai: soDienThoai,
                                  loaiHanhDong: loaiHanhDong,
                                );
                                setModalState(() {
                                  isResending = false;
                                  if (res['success'] == true) {
                                    countdown = 60;
                                    timer?.cancel();
                                    timer = null;
                                  } else {
                                    errorMessage = res['message'] ?? 'Tài khoản Gmail không tồn tại hoặc không gửi được mã';
                                  }
                                });
                              } catch (e) {
                                setModalState(() {
                                  isResending = false;
                                  final errStr = e.toString().toLowerCase();
                                  if (errStr.contains('550') ||
                                      errStr.contains('5.1.1') ||
                                      errStr.contains('không tồn tại')) {
                                    errorMessage = 'Tài khoản Gmail không tồn tại!';
                                  } else {
                                    errorMessage = 'Lỗi gửi lại mã OTP';
                                  }
                                });
                              }
                            },
                      icon: isResending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Gửi lại mã OTP',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            actions: [
              TextButton(
                onPressed: isVerifying
                    ? null
                    : () {
                        timer?.cancel();
                        Navigator.pop(ctx, false);
                      },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('Hủy'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: isVerifying
                    ? null
                    : () async {
                        final otp = otpController.text.trim();
                        if (otp.length < 6) {
                          setModalState(
                            () => errorMessage = 'Vui lòng nhập đủ 6 chữ số',
                          );
                          return;
                        }

                        setModalState(() {
                          isVerifying = true;
                          errorMessage = null;
                        });

                        try {
                          final res = await ApiService.verifyOtp(
                            email: email,
                            soDienThoai: soDienThoai,
                            maOtp: otp,
                            loaiHanhDong: loaiHanhDong,
                          );

                          if (res['success'] == true) {
                            timer?.cancel();
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } else {
                            setModalState(() {
                              isVerifying = false;
                              errorMessage = res['message'] ??
                                  'Mã OTP không chính xác hoặc đã hết hạn';
                            });
                          }
                        } catch (e) {
                          setModalState(() {
                            isVerifying = false;
                            errorMessage = 'Lỗi kết nối kiểm tra mã OTP';
                          });
                        }
                      },
                child: isVerifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : const Text(
                        'XÁC NHẬN',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  timer?.cancel();
  return result ?? false;
}
