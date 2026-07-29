import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models/vendor.dart';
import '../../core/state/auth_state.dart';
import '../../core/state/character_state.dart';
import 'character_select_screen.dart';
import 'character_sprite.dart';
import 'market_game/market_map_game_screen.dart';
import 'order_history_screen.dart';
import 'vendor_list_screen.dart';
import 'vendor_menu_screen.dart';

const _columns = 2;
const _cellHeight = 180.0;
const _stallSize = 72.0;
// ระยะขอบสำหรับกันตัวละครเดินชนขอบแผนที่ (ดู _moveAvatarTo) — ไม่เกี่ยวกับ
// สัดส่วนตัวสไปรต์จริง แค่กันไว้ให้มีระยะขอบพอสมควรจากขอบแผนที่
const _avatarClampMargin = 44.0;
const _topPadding = 60.0;
const _bottomPadding = 80.0;
const _nearRadius = 70.0;

// ขนาดที่แสดงบนจอของตัวละคร (sprite sheet จริงคือ 32x32 ต่อเฟรม ขยายเป็น
// สี่เหลี่ยมนี้ให้เห็นชัดขึ้น) ดู CharacterSprite สำหรับการครอปเฟรม
const _avatarDisplaySize = 56.0;

// ทิศที่ตัวละครหันหน้า แมปเข้ากับแถวใน sprite sheet: 0=ลง(หน้า), 1=ซ้าย,
// 2=ขวา, 3=ขึ้น(หลัง) — ดู assets/sprites/CREDITS.txt สำหรับ layout เต็ม
enum _Direction { down, left, right, up }

extension on _Direction {
  int get spriteRow => index;
}

/// หน้าแรกของลูกค้าแบบ "เดินเล่นในตลาด" — แตะที่ไหนก็ได้บนพื้นตลาดให้ตัวละคร
/// เดินไปตรงนั้น หรือแตะที่ร้านค้าตรงๆ ให้เดินไปหาร้านนั้นแล้วเปิดเมนูเลย
/// ตำแหน่งร้านค้าคำนวณจากลำดับในรายการแบบตายตัว (ไม่ได้สุ่ม) เพื่อให้แผนที่
/// หน้าตาเหมือนเดิมทุกครั้งที่เปิด ไม่ใช่สุ่มใหม่แต่ละรอบ
///
/// พื้นตลาดวาดด้วย widget ล้วนๆ (CustomPaint) แทนภาพประกอบจริงหรือ game
/// engine อย่าง Flame — ดู app/README.md สำหรับเหตุผล ส่วนตัวละคร (avatar)
/// ใช้ sprite sheet จริงที่ผู้ใช้เลือกได้ (CharacterSprite/CharacterState,
/// ดู assets/sprites/CREDITS.txt สำหรับที่มา/สิทธิ์การใช้งาน)
class MarketMapScreen extends StatefulWidget {
  const MarketMapScreen({super.key});

  @override
  State<MarketMapScreen> createState() => _MarketMapScreenState();
}

class _MarketMapScreenState extends State<MarketMapScreen> {
  late Future<List<Vendor>> _vendorsFuture;
  Offset _avatarPosition = Offset.zero;
  bool _avatarPlaced = false;
  // เก็บ id ร้านที่เพิ่ง auto-open ไปแล้ว กันไม่ให้เปิดซ้ำทุกครั้งที่อยู่ในระยะ
  // ใกล้ (trigger ตอน "เพิ่งเข้ามาใกล้" ครั้งเดียว ไม่ใช่ตอน "อยู่ใกล้ต่อเนื่อง")
  // รีเซ็ตเป็น null ตอนเดินออกจากระยะใกล้ ร้านเดิมจะ auto-open ได้อีกถ้าเดิน
  // เข้าใกล้ใหม่
  String? _lastNearVendorId;
  // ทิศที่ตัวละครหันหน้าอยู่ล่าสุด (จากการเดินครั้งก่อน) + เฟรมเดินปัจจุบัน
  // (คอลัมน์ 0-3 ของ sprite sheet, 0 = ยืนนิ่ง) ไล่ด้วย _walkTimer ระหว่างที่
  // กำลังเคลื่อนที่ ดู _startWalkAnimation
  _Direction _facing = _Direction.down;
  int _walkFrame = 0;
  Timer? _walkTimer;

  @override
  void initState() {
    super.initState();
    _vendorsFuture = context.read<ApiClient>().listVendors();
  }

  @override
  void dispose() {
    _walkTimer?.cancel();
    super.dispose();
  }

  Offset _stallPosition(int index, double cellWidth) {
    final row = index ~/ _columns;
    final col = index % _columns;
    return Offset(
      col * cellWidth + cellWidth / 2,
      row * _cellHeight + _cellHeight / 2 + _topPadding,
    );
  }

  double _mapHeight(int vendorCount) {
    final rows = (vendorCount / _columns).ceil();
    return rows * _cellHeight + _topPadding + _bottomPadding;
  }

  void _moveAvatarTo(Offset target, double mapWidth, double mapHeight) {
    final clamped = Offset(
      target.dx.clamp(_avatarClampMargin, mapWidth - _avatarClampMargin),
      target.dy.clamp(_avatarClampMargin, mapHeight - _avatarClampMargin),
    );
    final delta = clamped - _avatarPosition;
    setState(() {
      // แกนไหนเดินมากกว่า (แนวนอน/แนวตั้ง) ถือว่าตัวละครหันไปทางนั้น — ไม่
      // เปลี่ยนทิศถ้าแทบไม่ได้ขยับ (เช่นแตะซ้ำตำแหน่งเดิม)
      if (delta.distance > 1) {
        _facing = delta.dx.abs() > delta.dy.abs()
            ? (delta.dx > 0 ? _Direction.right : _Direction.left)
            : (delta.dy > 0 ? _Direction.down : _Direction.up);
      }
      _avatarPosition = clamped;
    });
    if (delta.distance > 1) {
      _startWalkAnimation();
    }
  }

  // ไล่เฟรมเดิน (คอลัมน์ 0-3 ของ sprite sheet) ทุก 90ms ระหว่างที่ตัวละครกำลัง
  // เคลื่อนที่ (350ms เท่ากับ duration ของ AnimatedPositioned ที่ใช้เลื่อน
  // ตำแหน่งจริง) แล้วกลับไปเฟรม 0 (ยืนนิ่ง) เมื่อถึงปลายทาง
  void _startWalkAnimation() {
    _walkTimer?.cancel();
    var frame = 0;
    _walkTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      frame = (frame + 1) % 4;
      setState(() => _walkFrame = frame);
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      _walkTimer?.cancel();
      if (mounted) setState(() => _walkFrame = 0);
    });
  }

  void _openVendor(Vendor vendor, Offset stallPos, double mapWidth, double mapHeight) {
    _moveAvatarTo(stallPos, mapWidth, mapHeight);
    // กัน _maybeAutoOpenNearbyVendor เปิดร้านเดิมซ้ำถ้าแตะพื้นที่ว่างใกล้ๆ
    // ร้านนี้อีกทีทันทีหลังกลับมาจากหน้าเมนู
    _lastNearVendorId = vendor.id;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorMenuScreen(vendorId: vendor.id)),
    );
  }

  // เรียกหลัง _moveAvatarTo ทุกครั้งที่แตะพื้นที่ว่าง (ไม่ใช่ตอนแตะร้านค้าตรงๆ
  // ซึ่งเปิดเมนูอยู่แล้วผ่าน _openVendor — ไม่งั้นจะเปิดซ้อนกัน 2 หน้า) ถ้า
  // เดินเข้าใกล้ร้านไหน (ในระยะ _nearRadius) ให้เปิดเมนูร้านนั้นขึ้นมาเลย
  void _maybeAutoOpenNearbyVendor(List<Vendor> vendors, double cellWidth) {
    Vendor? nearVendor;
    for (var i = 0; i < vendors.length; i++) {
      if ((_stallPosition(i, cellWidth) - _avatarPosition).distance < _nearRadius) {
        nearVendor = vendors[i];
        break;
      }
    }
    if (nearVendor != null && nearVendor.id != _lastNearVendorId) {
      _lastNearVendorId = nearVendor.id;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VendorMenuScreen(vendorId: nearVendor!.id)),
      );
    } else if (nearVendor == null) {
      _lastNearVendorId = null;
    }
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
            icon: const Icon(Icons.videogame_asset),
            tooltip: 'ทดลองเวอร์ชันเกม (Flame)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MarketMapGameScreen()),
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

          final mapWidth = MediaQuery.of(context).size.width;
          final cellWidth = mapWidth / _columns;
          final mapHeight = _mapHeight(vendors.length);

          // วางตัวละครไว้กลางแผนที่ตอนเปิดหน้านี้ครั้งแรก (ทำครั้งเดียว เพราะ
          // mapWidth ต้องรอ MediaQuery ซึ่งมีให้ใช้ตอน build เท่านั้น)
          if (!_avatarPlaced) {
            _avatarPosition = Offset(mapWidth / 2, _topPadding);
            _avatarPlaced = true;
          }

          return SingleChildScrollView(
            child: SizedBox(
              width: mapWidth,
              height: mapHeight,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _MarketGroundPainter())),
                  // แตะพื้นที่ว่างให้ตัวละครเดินไปตรงนั้น (ร้านค้าซึ่งวางทับ
                  // อยู่ข้างบนจะกันไม่ให้ tap ทะลุมาถึงชั้นนี้ ไม่ชนกัน)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) {
                      _moveAvatarTo(details.localPosition, mapWidth, mapHeight);
                      _maybeAutoOpenNearbyVendor(vendors, cellWidth);
                    },
                    child: SizedBox(width: mapWidth, height: mapHeight),
                  ),
                  for (var i = 0; i < vendors.length; i++)
                    _StallMarker(
                      vendor: vendors[i],
                      position: _stallPosition(i, cellWidth),
                      isNear: (_stallPosition(i, cellWidth) - _avatarPosition).distance < _nearRadius,
                      onTap: () => _openVendor(vendors[i], _stallPosition(i, cellWidth), mapWidth, mapHeight),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    left: _avatarPosition.dx - _avatarDisplaySize / 2,
                    top: _avatarPosition.dy - _avatarDisplaySize / 2,
                    child: CharacterSprite(
                      assetPath: context.watch<CharacterState>().selected.assetPath,
                      row: _facing.spriteRow,
                      col: _walkFrame,
                      displaySize: _avatarDisplaySize,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// พื้นตลาด: สีพื้นอุ่นๆ + ทางเดินเป็นแถบสีเข้มขึ้นสลับกัน วาดด้วย CustomPaint
/// ล้วนๆ ไม่ต้องพึ่งไฟล์ภาพ
class _MarketGroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ground = Paint()..color = const Color(0xFFF3E5C8);
    canvas.drawRect(Offset.zero & size, ground);

    final path = Paint()..color = const Color(0xFFE3D2A6);
    const pathHeight = 28.0;
    for (double y = _topPadding + _cellHeight / 2 - pathHeight / 2; y < size.height; y += _cellHeight) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, pathHeight), path);
    }
  }

  @override
  bool shouldRepaint(covariant _MarketGroundPainter oldDelegate) => false;
}

/// ป้ายร้านค้า 1 ร้านบนแผนที่ — ขยายเล็กน้อย (AnimatedScale) และขอบเปลี่ยนสี
/// ตอนตัวละครเดินเข้าใกล้ ให้ความรู้สึกเหมือนเกมโดยไม่บังคับต้องเดินไปถึง
/// ก่อนถึงจะกดเปิดร้านได้ (แตะได้ตลอด เพื่อไม่ให้กระทบการใช้งานจริง)
class _StallMarker extends StatelessWidget {
  final Vendor vendor;
  final Offset position;
  final bool isNear;
  final VoidCallback onTap;

  const _StallMarker({
    required this.vendor,
    required this.position,
    required this.isNear,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - _stallSize / 2 - 20,
      top: position.dy - _stallSize / 2,
      width: _stallSize + 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 250),
              scale: isNear ? 1.15 : 1.0,
              child: Container(
                width: _stallSize,
                height: _stallSize,
                decoration: BoxDecoration(
                  color: vendor.isOpen ? Colors.white : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isNear ? Theme.of(context).colorScheme.primary : Colors.brown.shade300,
                    width: isNear ? 3 : 2,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Icon(
                  Icons.storefront,
                  color: vendor.isOpen ? Colors.brown.shade400 : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              vendor.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
