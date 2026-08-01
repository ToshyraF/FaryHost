import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/state/auth_state.dart';

/// หน้าจอสมัครสมาชิก — เลือกได้ว่าจะสมัครเป็น "ลูกค้า" หรือ "ร้านค้า"
/// (role นี้กำหนดตายตัวตอนสมัคร เปลี่ยนทีหลังไม่ได้ ตรงกับ backend ที่ไม่มี
/// endpoint แก้ role)
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _role = 'customer';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// สมัครสมาชิกแล้ว login ให้อัตโนมัติในคราวเดียว (AuthState.register จะเก็บ
  /// token ที่ backend ออกให้ตอนสมัครเสร็จ ไม่ต้อง login ซ้ำ) หน้านี้อาจถูก
  /// push ทับมาจาก WelcomeScreen หรือ LoginScreen ก็ได้ (ปุ่ม "ยังไม่มีบัญชี?
  /// สมัครสมาชิก") ทำให้ Navigator stack ลึกได้มากกว่า 1 ชั้น — ต้อง
  /// popUntil((route) => route.isFirst) กลับไปที่ route แรก (AuthGate) เอง
  /// หลังสมัครสำเร็จ ไม่งั้นจะค้างอยู่หน้านี้ต่อ เพราะ AuthGate rebuild ใหม่
  /// ที่ route แรกสุดไม่ได้ทำให้ route ที่ push ทับอยู่หายไปเอง
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _fullNameController.text.trim(),
            role: _role,
            phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'สมัครสมาชิกไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สมัครสมาชิก')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ปุ่มเลือกบทบาท: ลูกค้า หรือ ร้านค้า
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'customer', label: Text('ลูกค้า')),
                      ButtonSegment(value: 'vendor', label: Text('ร้านค้า')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล'),
                    validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกชื่อ' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'อีเมล'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกอีเมล' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'เบอร์โทร (ไม่บังคับ)'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
                    obscureText: true,
                    // ต้องตรงกับกฎของ backend (registerRequest ใน auth.go: len(password) >= 8)
                    validator: (v) => (v == null || v.length < 8) ? 'รหัสผ่านอย่างน้อย 8 ตัวอักษร' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('สมัครสมาชิก'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
