import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models/vendor.dart';
import '../../core/state/auth_state.dart';
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

// ตัวละครพิกเซลอาร์ตเต็มตัว 4 ทิศ (ก้ม/หลัง/ซ้าย + ขวา = mirror ของซ้าย) x
// 2 เฟรมขา (ยืนนิ่ง/ก้าวเดิน) สำหรับ movement ตามภาพตัวอย่างที่ผู้ใช้ส่งมา
// (ผมพองสองโทน เสื้อแจ็คเก็ต กางเกงเทา รองเท้าแดงเข้ม) — ออกแบบตัวละครเอง
// ในสไตล์เดียวกัน ไม่ได้ก็อปปี้ตัวใดตัวหนึ่งจากภาพตรงๆ วาดทีละ "พิกเซล"
// (บล็อกสี่เหลี่ยมเล็กๆ) เหมือนเดิม ไม่ใช้ภาพ/asset จริง เพราะ sandbox นี้
// ไม่มี network ให้ดาวน์โหลดภาพ — ออกแบบ/ตรวจสอบภาพก่อนโดยจำลองเป็น HTML
// canvas แล้วถ่ายภาพดูด้วย headless Chromium ที่ติดตั้งไว้ในเครื่องนี้
// ก่อนย้ายมาเขียนเป็น Dart จริง (รอบแรกขาตอนก้าวเดินมีรอยหยักแปลกๆ เพราะช่อง
// ว่างระหว่างขากว้างไม่เท่ากันแต่ละแถว แก้โดยให้ขาซ้าย/ขวาเป็นแท่งตรงยาว
// ไม่เท่ากันแทน ไม่ใช่ปรับความกว้างช่องว่าง)
const _spritePixel = 3.0;

const _spriteTopDown = <String>[
  '......OObbOO........',
  '.....ObbbbbbO.......',
  '....ObbBBbbBBbO.....',
  '...ObbbbbbbbbbbO....',
  '..ObbBBbbbbBBbbbO...',
  '.ObbbbbbbbbbbbbbbO..',
  '.ObbbbbbbbbbbbbbbO..',
  'ObbbbbbbbbbbbbbbbbO.',
  'ObbbOOOOOOOOOOObbbO.',
  'ObbOFFFFFFFFFFFObbO.',
  '.ObOFFFEeFFeEFFObO..',
  '.ObOFFFFFFFFFFObO...',
  '..OFFFFFFFFFFFO.....',
  '...OFFFmmmmFFO......',
  '....OFFFFFFFO.......',
  '......OOOOOO........',
  '.....OJJJJJJO.......',
  '....OJJjJJjJJO......',
  '....OJJJJJJJJO......',
];
const _spriteTopUp = <String>[
  '......OObbOO........',
  '.....ObbbbbbO.......',
  '....ObbBBbbBBbO.....',
  '...ObbbbbbbbbbbO....',
  '..ObbBBbbbbBBbbbO...',
  '.ObbbbbbbbbbbbbbbO..',
  '.ObbbbbbbbbbbbbbbO..',
  'ObbbbbbbbbbbbbbbbbO.',
  'ObbbbbbBBbbBBbbbbbO.',
  'ObbbbbbbbbbbbbbbbbO.',
  '.ObbbbbbbbbbbbbbbO..',
  '.ObbbbbbbbbbbbbbbO..',
  '..ObbbbbbbbbbbbbO...',
  '...ObbbbbbbbbbbO....',
  '....ObbbbbbbbbO.....',
  '......OOOOOO........',
  '.....OJJJJJJO.......',
  '....OJJjJJjJJO......',
  '....OJJJJJJJJO......',
];
const _spriteTopLeft = <String>[
  '.....OObbOO.........',
  '....ObbbbbbO........',
  '...ObbBBbbBBbO......',
  '..ObbbbbbbbbbbO.....',
  '.ObbBBbbbbbbbbO.....',
  '.ObbbbbbbbbbbbO.....',
  'ObbbbbbbbbbbbbO.....',
  'ObbbbbbbbbbbbbO.....',
  'ObbbOOOOOOObbbO.....',
  'ObbOFFFFFFFObbO.....',
  '.ObOFFEeFFFObO......',
  '.ObOFFFFFFFObO......',
  '..OFFFFFFFFO........',
  '...OFFmmFFO.........',
  '....OFFFFO..........',
  '......OOOO..........',
  '.....OJJJJO.........',
  '....OJJjJJJO........',
  '....OJJJJJJO........',
];
// ขา 2 เฟรม ใช้ร่วมกันทุกทิศ (แค่ต่อท้ายหลัง top ของแต่ละทิศด้านบน) — เฟรม
// ยืนนิ่งขาชิด กับเฟรมก้าวเดินขาข้างหนึ่งยาว/ต่ำกว่าอีกข้าง (ไม่ใช่ปรับความ
// กว้างช่องว่างระหว่างขา ดูเหตุผลด้านบน)
const _legsIdle = <String>[
  '....OGGGGGGGGO......',
  '....OGGGGGGGGO......',
  '.....OGG..GGO.......',
  '.....OGG..GGO.......',
  '.....ORR..RRO.......',
  '......OO..OO........',
];
const _legsStride = <String>[
  '....OGGGGGGGGO......',
  '.....OGG..GGO.......',
  '.....OGG..GGO.......',
  '.....OGG..RRO.......',
  '.....ORR....O.......',
  '......OO............',
];
const _spriteColors = <String, Color>{
  'O': Color(0xFF141414), // เส้นขอบดำหนา
  'b': Color(0xFF8A6A5C), // ผมโทนกลาง
  'B': Color(0xFFB08E7C), // ผมไฮไลต์
  'F': Color(0xFFFFDDBB), // ผิวหน้า
  'E': Color(0xFF241812), // ตา
  'e': Color(0xFFFFFFFF), // ประกายตา
  'm': Color(0xFF8A4A3A), // ปาก
  'J': Color(0xFF5C7A9C), // เสื้อแจ็คเก็ต
  'j': Color(0xFF425E7C), // เงาเสื้อ
  'G': Color(0xFF9A9A9A), // กางเกง
  'R': Color(0xFF5C2020), // รองเท้า
};
// ขนาดจริงของตัวละครบนจอ คำนวณจากขนาดตาราง (แถว/คอลัมน์) คูณ _spritePixel —
// เป็น final ไม่ใช่ const เพราะ .length ไม่ใช่ compile-time constant expression
// (ทุกทิศทางสูง/กว้างเท่ากันหมด: top 19 แถว + ขา 6 แถว = 25 แถว, 20 คอลัมน์)
final _avatarWidth = _spriteTopDown.first.length * _spritePixel;
final _avatarHeight = (_spriteTopDown.length + _legsIdle.length) * _spritePixel;

enum _Direction { down, up, left, right }

List<String> _spriteTopFor(_Direction direction) {
  switch (direction) {
    case _Direction.down:
      return _spriteTopDown;
    case _Direction.up:
      return _spriteTopUp;
    case _Direction.left:
    case _Direction.right:
      return _spriteTopLeft;
  }
}

/// หน้าแรกของลูกค้าแบบ "เดินเล่นในตลาด" — แตะที่ไหนก็ได้บนพื้นตลาดให้ตัวละคร
/// เดินไปตรงนั้น หรือแตะที่ร้านค้าตรงๆ ให้เดินไปหาร้านนั้นแล้วเปิดเมนูเลย
/// ตำแหน่งร้านค้าคำนวณจากลำดับในรายการแบบตายตัว (ไม่ได้สุ่ม) เพื่อให้แผนที่
/// หน้าตาเหมือนเดิมทุกครั้งที่เปิด ไม่ใช่สุ่มใหม่แต่ละรอบ
///
/// วาดพื้นตลาด/ตัวละครด้วย widget ล้วนๆ (ไอคอน, Container, CustomPaint) แทน
/// การใช้ภาพประกอบจริงหรือ game engine อย่าง Flame เพราะ sandbox ที่เขียนโค้ด
/// นี้ไม่มี network ให้ดาวน์โหลดภาพ และการเพิ่ม dependency ใหม่ที่ไม่เคยรันเทส
/// ได้เลยมีความเสี่ยงเกินจำเป็น — ดู app/README.md
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
  // ทิศที่ตัวละครหันหน้าอยู่ล่าสุด (จากการเดินครั้งก่อน) + เฟรมขา (0=ยืนนิ่ง,
  // 1=ก้าวเดิน) สลับกันด้วย _walkTimer ระหว่างที่กำลังเคลื่อนที่ ดู
  // _startWalkAnimation
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

  // สลับเฟรมขา (ยืนนิ่ง/ก้าวเดิน) ทุก 120ms ระหว่างที่ตัวละครกำลังเคลื่อนที่
  // (350ms เท่ากับ duration ของ AnimatedPositioned ที่ใช้เลื่อนตำแหน่งจริง)
  // แล้วกลับไปยืนนิ่งเมื่อถึงปลายทาง
  void _startWalkAnimation() {
    _walkTimer?.cancel();
    var frame = 1;
    setState(() => _walkFrame = frame);
    _walkTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      frame = 1 - frame;
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
                    left: _avatarPosition.dx - _avatarWidth / 2,
                    top: _avatarPosition.dy - _avatarHeight / 2,
                    child: _Avatar(facing: _facing, walkFrame: _walkFrame),
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

/// ตัวละครของผู้เล่น (ลูกค้า) วาดเป็นพิกเซลอาร์ตเต็มตัว 4 ทิศตามที่กำลังเดิน
/// (facing) พร้อมสลับเฟรมขา (walkFrame: 0 ยืนนิ่ง, 1 ก้าวเดิน) ตามภาพ
/// ตัวอย่างที่ผู้ใช้ส่งมา — ทิศ "right" ใช้สไปรต์เดียวกับ "left" แล้ว mirror
/// แนวนอนด้วย Transform แทนการวาดสไปรต์แยกอีกชุด (ประหยัดงานออกแบบและตัดความ
/// เสี่ยงเรื่อง sprite ไม่ตรงกัน) วาดด้วย CustomPaint ทีละบล็อกตามตาราง
/// สไปรต์ (ดูด้านบนของไฟล์) ไม่ใช้ภาพ/asset จริง
class _Avatar extends StatelessWidget {
  final _Direction facing;
  final int walkFrame;

  const _Avatar({required this.facing, required this.walkFrame});

  @override
  Widget build(BuildContext context) {
    final legs = walkFrame == 0 ? _legsIdle : _legsStride;
    final rows = [..._spriteTopFor(facing), ...legs];
    final sprite = SizedBox(
      width: _avatarWidth,
      height: _avatarHeight,
      child: CustomPaint(painter: _PixelSpritePainter(rows)),
    );
    if (facing != _Direction.right) return sprite;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
      child: sprite,
    );
  }
}

/// วาดตาราง rows ทีละ "พิกเซล" เป็นสี่เหลี่ยมทึบขนาด _spritePixel — เทคนิค
/// เดียวกับ _MarketGroundPainter ด้านบน (Canvas.drawRect ล้วนๆ)
class _PixelSpritePainter extends CustomPainter {
  final List<String> rows;

  _PixelSpritePainter(this.rows);

  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      for (var x = 0; x < row.length; x++) {
        final color = _spriteColors[row[x]];
        if (color == null) continue; // '.' หรืออักขระที่ไม่รู้จัก = โปร่งใส
        canvas.drawRect(
          Rect.fromLTWH(x * _spritePixel, y * _spritePixel, _spritePixel, _spritePixel),
          Paint()..color = color,
        );
      }
    }
  }

  // rows เปลี่ยนทุกครั้งที่ facing/walkFrame เปลี่ยน (list instance ใหม่เสมอ)
  // repaint ใหม่ทุกครั้งไปเลยง่ายกว่าเทียบ content ทีละ element — งานวาดของ
  // สไปรต์เล็กๆ นี้ถูกมากไม่กระทบ performance
  @override
  bool shouldRepaint(covariant _PixelSpritePainter oldDelegate) => true;
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
