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
const _avatarWidth = 40.0;
const _avatarHeight = 56.0;
// ระยะขอบสำหรับกันตัวละครเดินชนขอบแผนที่ (ดู _moveAvatarTo) — ตัวเลขเดิม
// ก่อนเปลี่ยนจากอวตารสี่เหลี่ยมจัตุรัสมาเป็นร่างคนยืน ไม่เกี่ยวกับสัดส่วน
// ร่างกายจริง แค่กันไว้ให้มีระยะขอบเท่าเดิม
const _avatarClampMargin = 44.0;
const _topPadding = 60.0;
const _bottomPadding = 80.0;
const _nearRadius = 70.0;

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

/// ตัวละครของผู้เล่น (ลูกค้า) ออกแบบเป็นคนยืน/เดินสไตล์ชิบิ/kawaii เหมาะกับ
/// กลุ่มวัยรุ่น — หัว + ลำตัว + แขน + ขาสองข้างที่ก้าวไม่เท่ากันให้ดูเหมือน
/// กำลังเดิน แทนวงกลมหน้าเดียวหรือไอคอนคนเดินแบบเดิม ประกอบจาก widget ล้วนๆ
/// ไม่ใช้ภาพ/asset — ทุกชิ้นส่วนวางด้วย Positioned ที่ระบุ
/// left/top/width/height ครบทุกค่า (คำนวณเป็นพิกเซลตรงๆ จากสัดส่วนของ
/// _avatarWidth/_avatarHeight) ไม่ใช้ Align เพราะรอบก่อนหน้าที่ใช้ Align ทำให้
/// golden screenshot ออกมาผิดรูป (sandbox นี้ไม่มี Flutter SDK ให้รันเทียบเอง
/// ได้ ตรวจพบผ่านการดู CI artifact เท่านั้น)
class _Avatar extends StatelessWidget {
  const _Avatar();

  static const _faceColor = Color(0xFF6B4A6B);
  static const _blushColor = Color(0xFFFF8FB1);
  static const _skinGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB6E6), Color(0xFFB6A8FF)],
  );
  static const _armColor = Color(0xFFFFB6E6);
  static const _headSize = 28.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avatarWidth,
      height: _avatarHeight,
      child: Stack(
        children: [
          // ขาซ้าย (ก้าวหน้า สัมผัสพื้น)
          Positioned(
            left: 11,
            top: 42,
            width: 8,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _faceColor, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          // ขาขวา (ก้าวถอยหลัง/ยกขึ้นเล็กน้อย สั้นกว่า)
          Positioned(
            left: 21,
            top: 40,
            width: 8,
            height: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _faceColor, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          // แขนซ้าย
          Positioned(
            left: 2,
            top: 29,
            width: 8,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _armColor, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          // แขนขวา
          Positioned(
            left: 30,
            top: 29,
            width: 8,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _armColor, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          // ลำตัว
          Positioned(
            left: 9,
            top: 26,
            width: 22,
            height: 18,
            child: const DecoratedBox(
              decoration: BoxDecoration(gradient: _skinGradient, borderRadius: BorderRadius.all(Radius.circular(7))),
            ),
          ),
          // หัว (มีหน้าคิ้วตาแก้มปากอยู่ข้างใน)
          Positioned(
            left: (_avatarWidth - _headSize) / 2,
            top: 0,
            width: _headSize,
            height: _headSize,
            child: const _Head(),
          ),
        ],
      ),
    );
  }
}

/// หัวของตัวละคร: วงกลมไล่สีชมพู-ม่วงพาสเทล + ตากลมโตมีประกาย + แก้มแดง +
/// ปากยิ้มเล็กๆ — สัดส่วนเดิมจาก _Avatar ตอนยังเป็นแค่หัวลอย เปลี่ยนฐานคำนวณ
/// จาก _avatarSize (ทั้งตัว) มาเป็น _headSize (แค่หัว) แทน
class _Head extends StatelessWidget {
  const _Head();

  static const _eyeSize = _Avatar._headSize * 0.18;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: _Avatar._skinGradient,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Stack(
        children: [
          // แก้มซ้าย
          Positioned(
            left: _Avatar._headSize * 0.172,
            top: _Avatar._headSize * 0.614,
            width: _Avatar._headSize * 0.14,
            height: _Avatar._headSize * 0.09,
            child: const _Blush(),
          ),
          // แก้มขวา
          Positioned(
            left: _Avatar._headSize * 0.688,
            top: _Avatar._headSize * 0.614,
            width: _Avatar._headSize * 0.14,
            height: _Avatar._headSize * 0.09,
            child: const _Blush(),
          ),
          // แถวตาทั้งสองข้าง (กว้างรวม = 2 ตา + ช่องว่างตรงกลาง)
          Positioned(
            left: _Avatar._headSize * 0.125,
            top: _Avatar._headSize * 0.3485,
            width: _Avatar._headSize * 0.5,
            height: _eyeSize,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_Eye(), _Eye()],
            ),
          ),
          // ปาก
          Positioned(
            left: _Avatar._headSize * 0.195,
            top: _Avatar._headSize * 0.705,
            width: _Avatar._headSize * 0.22,
            height: _Avatar._headSize * 0.09,
            child: Container(
              decoration: BoxDecoration(
                color: _Avatar._faceColor,
                borderRadius: BorderRadius.circular(_Avatar._headSize * 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ตาข้างหนึ่งของตัวละคร: วงกลมขาว + รูม่านตาสีเข้ม + จุดประกายเล็กๆ
class _Eye extends StatelessWidget {
  const _Eye();

  static const _headSize = _Avatar._headSize;
  static const _pupilSize = _headSize * 0.1;
  static const _highlightSize = _headSize * 0.04;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _headSize * 0.18,
      height: _headSize * 0.18,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
      child: Stack(
        children: [
          Positioned(
            left: _headSize * 0.04,
            top: _headSize * 0.04,
            width: _pupilSize,
            height: _pupilSize,
            child: const _Pupil(),
          ),
          Positioned(
            left: _headSize * 0.049,
            top: _headSize * 0.042,
            width: _highlightSize,
            height: _highlightSize,
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pupil extends StatelessWidget {
  const _Pupil();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: _Avatar._faceColor),
    );
  }
}

/// แก้มแดงข้างหนึ่ง
class _Blush extends StatelessWidget {
  const _Blush();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Avatar._blushColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(_Avatar._headSize * 0.05),
      ),
    );
  }
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
