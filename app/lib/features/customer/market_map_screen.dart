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
// ระยะขอบสำหรับกันตัวละครเดินชนขอบแผนที่ (ดู _stepInDirection) — ไม่เกี่ยวกับ
// สัดส่วนตัวสไปรต์จริง แค่กันไว้ให้มีระยะขอบพอสมควรจากขอบแผนที่
const _avatarClampMargin = 44.0;
const _topPadding = 60.0;
const _bottomPadding = 80.0;
const _nearRadius = 70.0;

// ขนาดที่แสดงบนจอของตัวละคร (sprite sheet จริงคือ 32x32 ต่อเฟรม ขยายเป็น
// สี่เหลี่ยมนี้ให้เห็นชัดขึ้น) ดู CharacterSprite สำหรับการครอปเฟรม
const _avatarDisplaySize = 56.0;

// เดินทีละ "ก้าว" ระยะคงที่แบบเกมเก่า (Game Boy) แทนการลอยไปตำแหน่งใดก็ได้
// ต่อเนื่อง — ทุกก้อง (ไม่ว่าจะสั่งจาก D-pad หรือแตะพื้น/ร้านค้า) ขยับ
// ระยะเท่ากันนี้เสมอ ดู _stepInDirection
const _stepSize = 32.0;
// เวลาต่อ 1 ก้าว ทั้งระยะเลื่อนของ AnimatedPositioned และจังหวะที่ D-pad
// ค้างกด/คิวเดินไปร้านค้าจะสั่งก้าวถัดไป
const _stepDuration = Duration(milliseconds: 160);

// ทิศที่ตัวละครหันหน้า แมปเข้ากับแถวใน sprite sheet: 0=ลง(หน้า), 1=ซ้าย,
// 2=ขวา, 3=ขึ้น(หลัง) — ดู assets/sprites/CREDITS.txt สำหรับ layout เต็ม
enum _Direction { down, left, right, up }

extension on _Direction {
  int get spriteRow => index;
}

/// หน้าแรกของลูกค้าแบบ "เดินเล่นในตลาด" — แตะที่ไหนก็ได้บนพื้นตลาด หรือกด
/// D-pad มุมจอ ให้ตัวละครเดินไปตรงนั้นทีละก้าว (แบบเกม Game Boy เก่า) หรือแตะ
/// ที่ร้านค้าตรงๆ ให้เดินไปหาร้านนั้นแล้วเปิดเมนูเลย ตำแหน่งร้านค้าคำนวณจาก
/// ลำดับในรายการแบบตายตัว (ไม่ได้สุ่ม) เพื่อให้แผนที่หน้าตาเหมือนเดิมทุกครั้ง
/// ที่เปิด ไม่ใช่สุ่มใหม่แต่ละรอบ
///
/// พื้นตลาดวาดด้วย widget ล้วนๆ (CustomPaint) แทนภาพประกอบจริงหรือ game
/// engine อย่าง Flame — ดู app/README.md สำหรับเหตุผล ส่วนตัวละคร (avatar)
/// ใช้ sprite sheet จริงที่ผู้ใช้เลือกได้ (CharacterSprite/CharacterState,
/// ดู assets/sprites/CREDITS.txt สำหรับที่มา/สิทธิ์การใช้งาน) กล้อง (scroll
/// offset) เลื่อนตามตัวละครอัตโนมัติเสมอ (ดู _followAvatarWithCamera) กัน
/// ไม่ให้ตัวละครเดินออกนอกจอตอนแผนที่สูงกว่า viewport
class MarketMapScreen extends StatefulWidget {
  const MarketMapScreen({super.key});

  @override
  State<MarketMapScreen> createState() => _MarketMapScreenState();
}

class _MarketMapScreenState extends State<MarketMapScreen> {
  late Future<List<Vendor>> _vendorsFuture;
  final _scrollController = ScrollController();
  Offset _avatarPosition = Offset.zero;
  bool _avatarPlaced = false;
  // เก็บ id ร้านที่เพิ่ง auto-open ไปแล้ว กันไม่ให้เปิดซ้ำทุกครั้งที่อยู่ในระยะ
  // ใกล้ (trigger ตอน "เพิ่งเข้ามาใกล้" ครั้งเดียว ไม่ใช่ตอน "อยู่ใกล้ต่อเนื่อง")
  // รีเซ็ตเป็น null ตอนเดินออกจากระยะใกล้ ร้านเดิมจะ auto-open ได้อีกถ้าเดิน
  // เข้าใกล้ใหม่
  String? _lastNearVendorId;
  // ทิศที่ตัวละครหันหน้าอยู่ล่าสุด (จากก้าวก่อนหน้า) + เฟรมเดินปัจจุบัน
  // (คอลัมน์ 0-3 ของ sprite sheet, 0 = ยืนนิ่ง) ไล่ทีละ 1 ทุกครั้งที่ก้าวจริง
  // (ดู _stepInDirection) แล้วรีเซ็ตกลับ 0 เมื่อหยุดเดิน (ดู _stopMovement)
  _Direction _facing = _Direction.down;
  int _walkFrame = 0;

  // ค่าจากรอบ build ล่าสุด (mapWidth/mapHeight ต้องรอ MediaQuery ซึ่งมีให้ใช้
  // ตอน build เท่านั้น) เก็บไว้ใช้ในเมธอดเดินที่ถูกเรียกนอก build (จาก D-pad
  // หรือ timer callback)
  double _currentMapWidth = 0;
  double _currentMapHeight = 0;
  double _currentCellWidth = 0;
  List<Vendor> _currentVendors = const [];

  // ตัวเดียวที่ขับเคลื่อนการเดินทั้งหมด ไม่ว่าจะมาจาก D-pad ค้างกดหรือคิว
  // เดินไปยังจุดที่แตะ — เริ่มเดินแบบใดแบบหนึ่งจะ cancel อีกแบบทิ้งเสมอ กัน
  // ไม่ให้ทั้งสองแย่งกันขับเคลื่อนพร้อมกัน
  Timer? _moveTimer;
  _Direction? _activeDpadDirection;
  final List<_Direction> _pendingPath = [];

  @override
  void initState() {
    super.initState();
    _vendorsFuture = context.read<ApiClient>().listVendors();
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _scrollController.dispose();
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

  // ก้าวเดียวระยะ _stepSize ไปทาง [dir] — หัวใจของการเดินทั้งหมดในหน้านี้ ไม่
  // ว่าจะสั่งจาก D-pad หรือคิวเดินไปยังจุดที่แตะก็เรียกเมธอดนี้ทีละก้าวเสมอ
  // (ดู _startDpadMovement/_consumeNextPathStep) ทำให้ระยะก้าวเท่ากันทุกครั้ง
  // แบบเกม Game Boy เก่า แทนการลอยไปตำแหน่งใดก็ได้ต่อเนื่องแบบเดิม
  void _stepInDirection(_Direction dir) {
    if (_currentMapWidth <= 0 || _currentMapHeight <= 0) return;
    final vector = switch (dir) {
      _Direction.up => const Offset(0, -1),
      _Direction.down => const Offset(0, 1),
      _Direction.left => const Offset(-1, 0),
      _Direction.right => const Offset(1, 0),
    };
    final target = _avatarPosition + vector * _stepSize;
    final clamped = Offset(
      target.dx.clamp(_avatarClampMargin, _currentMapWidth - _avatarClampMargin),
      target.dy.clamp(_avatarClampMargin, _currentMapHeight - _avatarClampMargin),
    );
    setState(() {
      _facing = dir;
      _avatarPosition = clamped;
      _walkFrame = (_walkFrame + 1) % 4;
    });
    _followAvatarWithCamera();
    _maybeAutoOpenNearbyVendor(_currentVendors, _currentCellWidth);
  }

  // เลื่อน scroll offset ให้ตัวละครอยู่กลาง viewport เสมอเท่าที่ทำได้ (clamp
  // ไม่ให้เลื่อนเกินขอบแผนที่จริง) กันไม่ให้ตัวละครเดินหลุดออกนอกจอตอนแผนที่
  // สูงกว่า viewport (มีร้านค้าเยอะ) — เทียบเท่า camera.follow ของเวอร์ชัน
  // Flame (ดู market_flame_game.dart)
  void _followAvatarWithCamera() {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final maxScroll = (_currentMapHeight - viewport).clamp(0.0, double.infinity);
    final target = (_avatarPosition.dy - viewport / 2).clamp(0.0, maxScroll);
    _scrollController.animateTo(target, duration: _stepDuration, curve: Curves.easeOut);
  }

  void _stopMovement() {
    _moveTimer?.cancel();
    _moveTimer = null;
    _activeDpadDirection = null;
    _pendingPath.clear();
    if (_walkFrame != 0) setState(() => _walkFrame = 0);
  }

  // เริ่มเดินค้างทิศ [dir] ต่อเนื่องขณะกด D-pad ค้างไว้ — ก้าวแรกทันทีให้รู้สึก
  // ตอบสนองทันที แล้วก้าวต่อไปทุก _stepDuration จนกว่าจะปล่อยนิ้ว (ดู
  // _stopDpadMovement) การกด D-pad จะยกเลิกคิวเดินไปยังจุดที่แตะไว้ก่อนหน้าเสมอ
  void _startDpadMovement(_Direction dir) {
    _pendingPath.clear();
    _activeDpadDirection = dir;
    _stepInDirection(dir);
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(_stepDuration, (timer) {
      final active = _activeDpadDirection;
      if (active == null) {
        timer.cancel();
        _moveTimer = null;
        if (_walkFrame != 0) setState(() => _walkFrame = 0);
        return;
      }
      _stepInDirection(active);
    });
  }

  void _stopDpadMovement() {
    _activeDpadDirection = null;
  }

  // แปลงระยะทางจาก [from] ถึง [to] เป็นคิวก้าวเดิน 4 ทิศ (ไม่มีแนวทแยง เหมือน
  // เกมเก่า) — แกนไหนเหลือระยะมากกว่าก้าวไปทางนั้นก่อนในแต่ละก้าว ทำให้เส้นทาง
  // ดูเป็นขั้นบันไดแทนที่จะเดินแกนเดียวจนสุดแล้วค่อยเปลี่ยนแกน
  List<_Direction> _buildPath(Offset from, Offset to) {
    var dx = ((to.dx - from.dx) / _stepSize).round();
    var dy = ((to.dy - from.dy) / _stepSize).round();
    final path = <_Direction>[];
    while (dx != 0 || dy != 0) {
      if (dx.abs() >= dy.abs() && dx != 0) {
        path.add(dx > 0 ? _Direction.right : _Direction.left);
        dx += dx > 0 ? -1 : 1;
      } else {
        path.add(dy > 0 ? _Direction.down : _Direction.up);
        dy += dy > 0 ? -1 : 1;
      }
    }
    return path;
  }

  // เรียกทั้งตอนแตะพื้นที่ว่างและตอนแตะร้านค้าตรงๆ (ดู _openVendor) — สร้างคิว
  // ก้าวเดินไปยัง [rawTarget] แล้วเดินให้ทีละก้าวห่างกัน _stepDuration แทนการ
  // ลอยไปจุดนั้นในทีเดียวแบบเดิม
  void _walkPathTo(Offset rawTarget) {
    final target = Offset(
      rawTarget.dx.clamp(_avatarClampMargin, _currentMapWidth - _avatarClampMargin),
      rawTarget.dy.clamp(_avatarClampMargin, _currentMapHeight - _avatarClampMargin),
    );
    _activeDpadDirection = null;
    _moveTimer?.cancel();
    _moveTimer = null;
    _pendingPath
      ..clear()
      ..addAll(_buildPath(_avatarPosition, target));
    if (_pendingPath.isEmpty) return;
    _consumeNextPathStep();
    if (_pendingPath.isEmpty) return; // ถึงตั้งแต่ก้าวแรก ไม่ต้องตั้ง timer ต่อ
    _moveTimer = Timer.periodic(_stepDuration, (timer) {
      _consumeNextPathStep();
      if (_pendingPath.isEmpty) {
        timer.cancel();
        _moveTimer = null;
      }
    });
  }

  void _consumeNextPathStep() {
    if (_pendingPath.isEmpty) return;
    final dir = _pendingPath.removeAt(0);
    _stepInDirection(dir);
    if (_pendingPath.isEmpty && _walkFrame != 0) {
      setState(() => _walkFrame = 0);
    }
  }

  void _openVendor(Vendor vendor, Offset stallPos) {
    _walkPathTo(stallPos);
    // กัน _maybeAutoOpenNearbyVendor เปิดร้านเดิมซ้ำถ้าแตะพื้นที่ว่างใกล้ๆ
    // ร้านนี้อีกทีทันทีหลังกลับมาจากหน้าเมนู
    _lastNearVendorId = vendor.id;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorMenuScreen(vendorId: vendor.id)),
    );
  }

  // เรียกหลังทุกก้าวเดิน (ดู _stepInDirection) ไม่ใช่แค่ตอนแตะพื้นที่ว่างแบบ
  // เดิม เพราะตอนนี้การเดินเป็นแบบทีละก้าวจริง เลยเช็คระยะห่างจากร้านค้าได้
  // แม่นยำกว่าเดิม (ก่อนหน้านี้เช็คแค่ตอนแตะ โดยอิงตำแหน่งปลายทางที่ยังไม่ได้
  // เดินไปถึงจริง) ไม่ทำงานตอนแตะร้านค้าตรงๆ ซึ่งเปิดเมนูอยู่แล้วผ่าน
  // _openVendor — ไม่งั้นจะเปิดซ้อนกัน 2 หน้า
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
          _currentMapWidth = mapWidth;
          _currentMapHeight = mapHeight;
          _currentCellWidth = cellWidth;
          _currentVendors = vendors;

          // วางตัวละครไว้กลางแผนที่ตอนเปิดหน้านี้ครั้งแรก (ทำครั้งเดียว เพราะ
          // mapWidth ต้องรอ MediaQuery ซึ่งมีให้ใช้ตอน build เท่านั้น)
          if (!_avatarPlaced) {
            _avatarPosition = Offset(mapWidth / 2, _topPadding);
            _avatarPlaced = true;
          }

          return Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                child: SizedBox(
                  width: mapWidth,
                  height: mapHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(child: CustomPaint(painter: _MarketGroundPainter())),
                      // แตะพื้นที่ว่างให้ตัวละครเดินไปตรงนั้นทีละก้าว (ร้านค้า
                      // ซึ่งวางทับอยู่ข้างบนจะกันไม่ให้ tap ทะลุมาถึงชั้นนี้
                      // ไม่ชนกัน)
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) => _walkPathTo(details.localPosition),
                        child: SizedBox(width: mapWidth, height: mapHeight),
                      ),
                      for (var i = 0; i < vendors.length; i++)
                        _StallMarker(
                          vendor: vendors[i],
                          position: _stallPosition(i, cellWidth),
                          isNear: (_stallPosition(i, cellWidth) - _avatarPosition).distance < _nearRadius,
                          onTap: () => _openVendor(vendors[i], _stallPosition(i, cellWidth)),
                        ),
                      AnimatedPositioned(
                        duration: _stepDuration,
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
              ),
              _Dpad(
                onDirectionDown: _startDpadMovement,
                onDirectionUp: _stopDpadMovement,
              ),
            ],
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

/// ปุ่มบังคับทิศทางมุมจอซ้ายล่าง แบบ D-pad เกมพกพาเก่า — กดค้างเพื่อเดิน
/// ต่อเนื่องทีละก้าว (ดู _startDpadMovement), ปล่อยนิ้วเพื่อหยุด วาดด้วย
/// widget ล้วนๆ (วงกลม 4 อัน + ไอคอนลูกศร) ไม่ใช่ภาพประกอบ ตามธรรมเนียมเดิม
/// ของหน้านี้ที่ไม่พึ่งไฟล์ภาพที่ต้องดึงมาจากภายนอก
class _Dpad extends StatelessWidget {
  final void Function(_Direction direction) onDirectionDown;
  final VoidCallback onDirectionUp;

  const _Dpad({required this.onDirectionDown, required this.onDirectionUp});

  Widget _button(_Direction dir, IconData icon) {
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
              Positioned(top: 0, child: _button(_Direction.up, Icons.keyboard_arrow_up)),
              Positioned(bottom: 0, child: _button(_Direction.down, Icons.keyboard_arrow_down)),
              Positioned(left: 0, child: _button(_Direction.left, Icons.keyboard_arrow_left)),
              Positioned(right: 0, child: _button(_Direction.right, Icons.keyboard_arrow_right)),
            ],
          ),
        ),
      ),
    );
  }
}
