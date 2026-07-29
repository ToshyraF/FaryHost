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

// ตัวละครพิกเซลอาร์ตสไตล์ "chibi portrait" (หัวโต ผมทรงแหลมสองโทน ตาโตมีประกาย
// เส้นขอบดำหนา) ตามภาพตัวอย่างชุดตัวละครที่ผู้ใช้ส่งมา แทนสไปรต์ RPG
// แบบเดินเต็มตัวรอบก่อนหน้า — วาดทีละ "พิกเซล" (บล็อกสี่เหลี่ยมเล็กๆ) ตาม
// ตาราง _spriteRows ด้านล่าง ไม่ใช้ภาพ/asset จริง เพราะ sandbox นี้ไม่มี
// network ให้ดาวน์โหลดภาพ (เหมือนเหตุผลเดิมทุกจุดในไฟล์นี้) — ออกแบบตัว
// ละครต้นแบบเอง (ไม่ได้ก็อปปี้ตัวละครใดตัวหนึ่งจากภาพตัวอย่างตรงๆ) แล้ว
// ตรวจสอบภาพก่อนโดยจำลองเป็น HTML canvas แล้วถ่ายภาพดูด้วย headless
// Chromium ที่ติดตั้งไว้ในเครื่องนี้ ก่อนย้ายมาเขียนเป็น Dart จริง
const _spritePixel = 3.0;
const _spriteRows = <String>[
  '.....O....O...O.....',
  '....OhO..OhO.OhO....',
  '..OOOOOOOOOOOOOOOO..',
  '.OhhhhhhhhhhhhhhhhO.',
  '.OhhhhLLhhLLhhhhhhO.',
  '.OhhhhhhhhhhhhhhhhO.',
  '..OOOOOOOOOOOOOOOO..',
  '.OhOFFFFFFFFFFFFOhO.',
  '.OhOFFFEeFFeEFFFOhO.',
  '.OFFFFFFFFFFFFFFFFO.',
  '.OFFFFFFFFFFFFFFFFO.',
  '...OFFFFFmmmmFFFFO..',
  '....OFFFFFFFFFFO....',
  '......OOOOOOOO......',
  '......OCCCCCCO......',
  '.....OCcCCcCO.......',
  '....OCCCCCCCCCCO....',
  '....OCCCC..CCCCO....',
  '.....O........O.....',
];
const _spriteColors = <String, Color>{
  'O': Color(0xFF141414), // เส้นขอบดำหนา
  'h': Color(0xFF2E5AA8), // ผมโทนกลาง
  'L': Color(0xFF6FA8F5), // ผมไฮไลต์
  'F': Color(0xFFFFE0C2), // ผิวหน้า
  'E': Color(0xFF1B1B1B), // ตา
  'e': Color(0xFFFFFFFF), // ประกายตา
  'm': Color(0xFF7A3B2E), // ปาก
  'C': Color(0xFFF2A93C), // เสื้อคอปก
  'c': Color(0xFFC97F1E), // เงาเสื้อ
};
// ขนาดจริงของตัวละครบนจอ คำนวณจากขนาดตาราง (แถว/คอลัมน์) คูณ _spritePixel —
// เป็น final ไม่ใช่ const เพราะ .length ไม่ใช่ compile-time constant expression
final _avatarWidth = _spriteRows.first.length * _spritePixel;
final _avatarHeight = _spriteRows.length * _spritePixel;

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

  @override
  void initState() {
    super.initState();
    _vendorsFuture = context.read<ApiClient>().listVendors();
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
    setState(() {
      _avatarPosition = Offset(
        target.dx.clamp(_avatarClampMargin, mapWidth - _avatarClampMargin),
        target.dy.clamp(_avatarClampMargin, mapHeight - _avatarClampMargin),
      );
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
                    child: const _Avatar(),
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

/// ตัวละครของผู้เล่น (ลูกค้า) วาดเป็นพิกเซลอาร์ต "chibi portrait" (หัวโต
/// ผมแหลมสองโทน ตาโตมีประกาย เส้นขอบดำหนา) ตามภาพตัวอย่างที่ผู้ใช้ส่งมา
/// แทนสไปรต์ RPG แบบเดินเต็มตัวรอบก่อนหน้า — วาดด้วย CustomPaint ทีละ
/// บล็อกตามตาราง _spriteRows (ดูด้านบนของไฟล์) ไม่ใช้ภาพ/asset จริง
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avatarWidth,
      height: _avatarHeight,
      child: CustomPaint(painter: _PixelSpritePainter()),
    );
  }
}

/// วาดตาราง _spriteRows ทีละ "พิกเซล" เป็นสี่เหลี่ยมทึบขนาด _spritePixel —
/// เทคนิคเดียวกับ _MarketGroundPainter ด้านบน (Canvas.drawRect ล้วนๆ)
class _PixelSpritePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0; y < _spriteRows.length; y++) {
      final row = _spriteRows[y];
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

  @override
  bool shouldRepaint(covariant _PixelSpritePainter oldDelegate) => false;
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
