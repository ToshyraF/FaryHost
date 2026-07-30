import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/models/vendor.dart';
import '../../../core/state/character_state.dart';
import '../vendor_menu_screen.dart';
import 'market_flame_game.dart';

/// เวอร์ชันทดลอง: หน้าเดียวกับ MarketMapScreen แต่ render ด้วย Flame แทน
/// widget ธรรมดา ดู market_flame_game.dart สำหรับรายละเอียดว่าทดลองอะไรอยู่
/// และทำไมยังไม่เคยรันจริง — เข้าถึงได้จาก MarketMapScreen's app bar
/// (ปุ่ม "ทดลองเวอร์ชันเกม") ไม่ได้แทนที่หน้าเดิม เผื่อ Flame integration
/// มีปัญหาที่ต้องแก้หลายรอบ ผู้ใช้ยังมีหน้าที่ใช้งานได้จริงอยู่เสมอ
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
      appBar: AppBar(title: const Text('เดินเล่นในตลาด (ทดลอง: Flame)')),
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
            onOpenVendor: (vendor) => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VendorMenuScreen(vendorId: vendor.id)),
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

/// ปุ่มบังคับทิศทางมุมจอซ้ายล่าง แบบ D-pad เกมพกพาเก่า — เดียวกับเวอร์ชัน
/// widget (ดู market_map_screen.dart) แค่ยิงเข้า MarketFlameGame แทน setState
/// ตรงๆ กดค้างเพื่อเดินต่อเนื่องทีละก้าว ปล่อยนิ้วเพื่อหยุด วาดด้วย widget
/// ล้วนๆ (วงกลม 4 อัน + ไอคอนลูกศร) ไม่ใช่ภาพประกอบ เป็น widget ธรรมดาที่วาง
/// ทับ GameWidget ผ่าน Stack ไม่ใช่ Flame component เอง เพราะ overlay
/// UI/ปุ่มกดเป็นงานที่ widget ปกติของ Flutter ทำได้ตรงไปตรงมากว่า
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
