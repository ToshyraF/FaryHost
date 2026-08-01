import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/models/vendor.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/state/character_state.dart';
import '../character_select_screen.dart';
import '../order_history_screen.dart';
import '../vendor_list_screen.dart';
import '../vendor_menu_sheet.dart';
import 'market_flame_game.dart';

/// หน้าแรกของลูกค้าแบบ "เดินเล่นในตลาด" — เดินไปตามที่แตะหรือกด D-pad ทีละ
/// ก้าว (ดู market_flame_game.dart), แตะร้านค้าให้เดินไปหาแล้วเปิดเมนูเป็น
/// popup (`VendorMenuSheet`) ลอยทับแผนที่แทนการ push ไปหน้าใหม่ทั้งหน้า —
/// ปิด popup แล้วเดินต่อได้เลย ไม่ต้องกด back (ดู app/README.md's "Market map")
/// render ด้วย [Flame](https://flame-engine.org) เดิมมีเวอร์ชัน widget ล้วนๆ
/// (`MarketMapScreen`) เป็นหน้าหลักคู่กันไป และหน้านี้เป็นแค่ทางเลือกทดลองที่
/// เข้าถึงจากปุ่มในแอปบาร์ของเวอร์ชันนั้น (กันความเสี่ยงตอน `flame` ยังไม่เคย
/// ผ่านการ build จริงเลยในสภาพแวดล้อมที่เขียนโค้ดนี้ — sandbox บล็อกไม่ให้ดึง
/// จาก pub.dev) แต่หลัง CI ยืนยันว่าใช้งานได้จริงและตรวจสอบด้วยรูป golden
/// จริงหลายรอบ ผู้ใช้ขอให้เหลือแค่เวอร์ชันนี้เวอร์ชันเดียว จึงลบเวอร์ชัน
/// widget ทิ้งทั้งไฟล์และย้ายปุ่มในแอปบาร์ (เลือกตัวละคร/ดูแบบรายการ/
/// ประวัติการสั่ง/ออกจากระบบ) มาไว้ที่นี่แทน — ดู app/README.md's "Market map"
class MarketMapGameScreen extends StatefulWidget {
  const MarketMapGameScreen({super.key});

  @override
  State<MarketMapGameScreen> createState() => _MarketMapGameScreenState();
}

class _MarketMapGameScreenState extends State<MarketMapGameScreen> {
  late Future<List<Vendor>> _vendorsFuture;
  // สร้างครั้งเดียวแล้วเก็บไว้ (ไม่ใช่สร้างใหม่ทุกครั้งที่ builder ของ
  // FutureBuilder รัน) เพราะปุ่ม D-pad ต้องเรียกเมธอดบน instance เดียวกับที่
  // กำลังรันอยู่จริงใน GameWidget — ถ้าสร้างใหม่ทุก rebuild เกมจะรีสตาร์ททุกครั้ง
  MarketFlameGame? _game;

  @override
  void initState() {
    super.initState();
    _vendorsFuture = context.read<ApiClient>().listVendors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เดินเล่นในตลาด'),
        actions: [
          IconButton(
            icon: const Icon(Icons.face_retouching_natural),
            tooltip: 'เลือกตัวละคร',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CharacterSelectScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.view_list),
            tooltip: 'ดูแบบรายการ',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VendorListScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'ประวัติการสั่ง',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: FutureBuilder<List<Vendor>>(
        future: _vendorsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('โหลดข้อมูลไม่สำเร็จ'));
          }
          final vendors = snapshot.data!;
          if (vendors.isEmpty) {
            return const Center(child: Text('ยังไม่มีร้านค้าเปิดขาย'));
          }
          final game = _game ??= MarketFlameGame(
            vendors: vendors,
            characterAssetPath: context.read<CharacterState>().selected.assetPath,
            onOpenVendor: (vendor) => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => VendorMenuSheet(vendorId: vendor.id),
            ),
          );
          return Stack(
            children: [
              GameWidget(game: game),
              _Dpad(
                onDirectionDown: game.beginDpadMovement,
                onDirectionUp: game.endDpadMovement,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ปุ่มบังคับทิศทางมุมจอซ้ายล่าง แบบ D-pad เกมพกพาเก่า — กดค้างเพื่อเดิน
/// ต่อเนื่องทีละก้าว ปล่อยนิ้วเพื่อหยุด วาดด้วย widget ล้วนๆ (วงกลม 4 อัน +
/// ไอคอนลูกศร) ไม่ใช่ภาพประกอบ เป็น widget ธรรมดาที่วางทับ GameWidget ผ่าน
/// Stack ไม่ใช่ Flame component เอง เพราะ overlay UI/ปุ่มกดเป็นงานที่ widget
/// ปกติของ Flutter ทำได้ตรงไปตรงมากว่า
class _Dpad extends StatelessWidget {
  final void Function(MapDirection direction) onDirectionDown;
  final VoidCallback onDirectionUp;

  const _Dpad({required this.onDirectionDown, required this.onDirectionUp});

  Widget _button(MapDirection dir, IconData icon) {
    return GestureDetector(
      onTapDown: (_) => onDirectionDown(dir),
      onTapUp: (_) => onDirectionUp(),
      onTapCancel: onDirectionUp,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.brown.shade700,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 16,
      child: Opacity(
        opacity: 0.85,
        child: SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(top: 0, child: _button(MapDirection.up, Icons.keyboard_arrow_up)),
              Positioned(bottom: 0, child: _button(MapDirection.down, Icons.keyboard_arrow_down)),
              Positioned(left: 0, child: _button(MapDirection.left, Icons.keyboard_arrow_left)),
              Positioned(right: 0, child: _button(MapDirection.right, Icons.keyboard_arrow_right)),
            ],
          ),
        ),
      ),
    );
  }
}
