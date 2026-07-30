import 'dart:async' as async_lib;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Colors, Curves, TextStyle;
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/models/vendor.dart';

const _columns = 2;
const _cellHeight = 180.0;
const _stallSize = 72.0;
const _topPadding = 60.0;
const _bottomPadding = 80.0;
const _nearRadius = 70.0;
// ระยะขอบกันตัวละครเดินชนขอบแผนที่/หลุดจอ — เดียวกับเวอร์ชัน widget (ดู
// market_map_screen.dart) เวอร์ชัน Flame เดิมไม่เคย clamp ตำแหน่งผู้เล่นเลย
// (แค่กล้องที่ clamp เองใน update() ด้านล่าง) เลยเดินทะลุขอบแผนที่ไปได้จริง
const _avatarClampMargin = 44.0;

const _playerDisplaySize = 56.0;

// เดินทีละ "ก้าว" ระยะคงที่แบบเกมเก่า (Game Boy) แทนการไถลไปตำแหน่งใดก็ได้
// ต่อเนื่อง — เดียวกับเวอร์ชัน widget (ดู market_map_screen.dart) ทุกก้าว
// (ไม่ว่าสั่งจาก D-pad หรือแตะพื้น/ร้านค้า) ขยับระยะเท่ากันนี้เสมอ
const _stepSize = 32.0;
const _stepDuration = Duration(milliseconds: 160);
const _stepSeconds = 0.16; // เท่ากับ _stepDuration แต่เป็นหน่วยวินาทีให้ EffectController

// sprite sheet ตาราง 4x4 เฟรม 32x32: แถว 0=ลง(หน้า), 1=ซ้าย, 2=ขวา, 3=ขึ้น
// (หลัง), คอลัมน์ 0-3 คือ walk cycle — เดียวกับเวอร์ชัน widget (ดู
// market_map_screen.dart/character_sprite.dart) ที่มา/สิทธิ์การใช้งานอยู่ใน
// assets/sprites/CREDITS.txt
const _frameSize = 32.0;

// public เพราะต้องใช้ข้ามไฟล์ (D-pad ใน market_map_game_screen.dart เรียก
// MarketFlameGame.beginDpadMovement/endDpadMovement ซึ่งรับ/ใช้ type นี้)
enum MapDirection { down, left, right, up }

extension on MapDirection {
  int get spriteRow => index;
}

/// เวอร์ชันทดลองของแผนที่ตลาด สร้างด้วย Flame (Flutter game engine) แทนการ
/// วาดด้วย widget ล้วนๆ เหมือน MarketMapScreen ปกติ — โครงเดียวกัน (ตัวละคร
/// เดินไปตามที่แตะทีละก้าว หรือกด D-pad, แตะร้านค้าให้เดินไปหาแล้วเปิดเมนู)
/// แต่ render ผ่าน game loop ของ Flame แทน widget tree ธรรมดา
///
/// นี่คือของทดลองจริงๆ: ไม่เคย build/รันเลยเพราะ sandbox นี้ไม่มี network
/// ให้ดึง flame จาก pub.dev มาใช้ได้ (เหมือนที่ MarketMapScreen ตัวปกติเลี่ยง
/// การพึ่ง external package มาโดยตลอด) ต้องรอ CI (ที่เข้าถึง pub.dev ได้จริง)
/// ยืนยันว่า compile ผ่านและ API ที่ใช้ตรงกับเวอร์ชัน flame ที่ resolve ได้จริง
class MarketFlameGame extends FlameGame with TapCallbacks {
  final List<Vendor> vendors;
  final void Function(Vendor vendor) onOpenVendor;
  final String characterAssetPath;

  MarketFlameGame({
    required this.vendors,
    required this.onOpenVendor,
    required this.characterAssetPath,
  });

  late final PlayerComponent player;
  late final double _worldHeight;
  final List<StallComponent> _stalls = [];

  // ตัวเดียวที่ขับเคลื่อนการเดินทั้งหมด (เหมือนเวอร์ชัน widget) — เริ่มเดิน
  // แบบใดแบบหนึ่ง (D-pad ค้าง / คิวเดินไปจุดที่แตะ) จะ cancel อีกแบบทิ้งเสมอ
  async_lib.Timer? _moveTimer;
  MapDirection? _activeDpadDirection;
  final List<MapDirection> _pendingPath = [];

  @override
  Color backgroundColor() => const Color(0xFFF3E5C8);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // ไม่ await การ decode sprite sheet ของตัวละครตรงนี้ -- เคยลองทำแบบนั้น
    // (await ก่อนสร้างอย่างอื่นทั้งหมด) แล้วพบว่า GameWidget ทั้งก้อนค้างอยู่ที่
    // หน้า loading เปล่าๆ จนกว่า onLoad() ทั้งฟังก์ชันจะ resolve เสร็จ -- ไม่ใช่
    // แค่ PlayerComponent ที่หายไป แต่พื้น/ป้ายร้านก็ไม่ขึ้นด้วย (ยืนยันจากภาพ
    // จริงที่ผู้ใช้ส่งมา ว่างเปล่าทั้งจอ) เพราะ decode ผ่าน engine's image codec
    // เป็นการ round-trip แบบ async จริง ไม่ใช่แค่ resolve microtask เฉยๆ ในบาง
    // สภาพแวดล้อม (เช่น golden test ที่ pump จำนวนเฟรมคงที่ ไม่ใช้
    // pumpAndSettle()) อาจไม่เสร็จทันเวลาที่ pump ไว้ -- ให้พื้น/ป้ายร้าน/ตัว
    // ละคร (แสดง placeholder ว่างจนกว่าจะโหลดเสร็จ) ถูกสร้างทันทีแทน ไม่ผูกกับ
    // การโหลดภาพเลย ดู PlayerComponent.onLoad() สำหรับที่ที่ decode เกิดขึ้นจริง
    final mapHeight = _mapHeight(vendors.length);
    _worldHeight = mapHeight;
    final cellWidth = size.x / _columns;

    // ทางเดินสีเข้มขึ้นสลับกับพื้นตลาด (สีพื้นมาจาก backgroundColor() ด้านบน)
    for (double y = _topPadding + _cellHeight / 2 - 14; y < mapHeight; y += _cellHeight) {
      add(
        RectangleComponent(
          position: Vector2(0, y),
          size: Vector2(size.x, 28),
          paint: Paint()..color = const Color(0xFFE3D2A6),
        ),
      );
    }

    for (var i = 0; i < vendors.length; i++) {
      final vendor = vendors[i];
      final position = _stallPosition(i, cellWidth);
      // ประกาศแบบ late แล้วค่อย assign เพื่อให้ callback onTap อ้างอิงตัวเองได้
      // (ต้อง set wasNear=true ตอนแตะตรงๆ ไม่งั้นพอเดินไปถึง proximity check
      // ใน update() จะเห็นว่า "เพิ่งเข้าใกล้" แล้วเปิดเมนูซ้ำอีกรอบ)
      late final StallComponent stall;
      stall = StallComponent(
        vendor: vendor,
        stallPosition: position,
        onTap: () {
          _walkPathTo(position);
          stall.wasNear = true;
          onOpenVendor(vendor);
        },
      );
      _stalls.add(stall);
      add(stall);
    }

    player = PlayerComponent(assetPath: characterAssetPath)..position = Vector2(size.x / 2, _topPadding);
    add(player);

    // แผนที่สูงกว่าจอได้เมื่อร้านค้าเยอะ (mapHeight ขึ้นกับจำนวนร้าน) ให้กล้อง
    // เลื่อนตามตัวละครในแนวตั้ง (verticalOnly: true เพราะแนวนอนแคบพอดีจอเสมอ
    // อยู่แล้ว จาก _columns คงที่) ส่วนการกันไม่ให้เลื่อนเกินขอบแผนที่ทำเองใน
    // update() ด้านล่าง แทนการใช้ camera.setBounds — API นั้นต้องพึ่ง shape
    // class ของ Flame ที่ชื่อ/ที่ import ไม่ตรงกับเวอร์ชันที่ resolve จริงบน CI
    camera.follow(player, verticalOnly: true);
  }

  @override
  void onRemove() {
    _moveTimer?.cancel();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final halfHeight = size.y / 2;
    final minY = halfHeight;
    final maxY = _worldHeight - halfHeight;
    if (maxY > minY) {
      camera.viewfinder.position.y = camera.viewfinder.position.y.clamp(minY, maxY);
    } else {
      // แผนที่เตี้ยกว่าจอ (ร้านค้าน้อย) ไม่ต้อง scroll เลย ตรึงกล้องไว้กลางแผนที่
      camera.viewfinder.position.y = _worldHeight / 2;
    }

    // เดินเข้าใกล้ร้านไหน (ในระยะ _nearRadius) เปิดเมนูร้านนั้นให้เลย — trigger
    // ตอน "เพิ่งเข้ามาใกล้" ครั้งเดียว (wasNear เดิมเป็น false) ไม่ใช่ทุก frame
    // ที่ยังอยู่ในระยะ ไม่งั้นจะเปิดหน้าเมนูซ้อนกันรัวๆ ระหว่างที่ยืนอยู่ตรงนั้น
    // ทำงานถูกต้องไม่ว่าตำแหน่งผู้เล่นจะขยับแบบทีละก้าวหรือต่อเนื่อง เพราะเช็ค
    // ทุก frame อยู่แล้ว ไม่ขึ้นกับกลไกการเดิน
    for (final stall in _stalls) {
      final isNear = stall.position.distanceTo(player.position) < _nearRadius;
      if (isNear && !stall.wasNear) {
        stall.wasNear = true;
        onOpenVendor(stall.vendor);
      } else if (!isNear) {
        stall.wasNear = false;
      }
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    // onTapUp นี้อยู่บน game root (นอก world/camera transform) event.localPosition
    // จึงเป็นพิกัดจอ ไม่ใช่พิกัดแผนที่ — ต้องแปลงผ่านกล้องก่อน ไม่งั้นตอนกล้อง
    // เลื่อน (หลังเพิ่ม camera.follow) ตัวละครจะเดินไปผิดตำแหน่ง
    _walkPathTo(camera.globalToLocal(event.canvasPosition));
  }

  /// เริ่มเดินค้างทิศ [dir] ต่อเนื่องขณะกด D-pad ค้างไว้ (เรียกจาก
  /// market_map_game_screen.dart) — ก้าวแรกทันทีให้รู้สึกตอบสนองทันที แล้วก้าว
  /// ต่อไปทุก _stepDuration จนกว่าจะปล่อยนิ้ว (ดู endDpadMovement) การกด D-pad
  /// จะยกเลิกคิวเดินไปยังจุดที่แตะไว้ก่อนหน้าเสมอ
  void beginDpadMovement(MapDirection dir) {
    _pendingPath.clear();
    _activeDpadDirection = dir;
    _stepInDirection(dir);
    _moveTimer?.cancel();
    _moveTimer = async_lib.Timer.periodic(_stepDuration, (timer) {
      final active = _activeDpadDirection;
      if (active == null) {
        timer.cancel();
        _moveTimer = null;
        player.resetWalkFrame();
        return;
      }
      _stepInDirection(active);
    });
  }

  void endDpadMovement() {
    _activeDpadDirection = null;
  }

  // เรียกทั้งตอนแตะพื้นที่ว่างและตอนแตะร้านค้าตรงๆ — สร้างคิวก้าวเดินไปยัง
  // [rawTarget] แล้วเดินให้ทีละก้าวห่างกัน _stepDuration แทนการไถลไปจุดนั้นใน
  // ทีเดียวแบบเดิม (เดิมไม่ clamp ขอบเขตเลย ทำให้เดินทะลุขอบแผนที่ได้)
  void _walkPathTo(Vector2 rawTarget) {
    final target = Vector2(
      rawTarget.x.clamp(_avatarClampMargin, size.x - _avatarClampMargin),
      rawTarget.y.clamp(_avatarClampMargin, _worldHeight - _avatarClampMargin),
    );
    _activeDpadDirection = null;
    _moveTimer?.cancel();
    _moveTimer = null;
    _pendingPath
      ..clear()
      ..addAll(_buildPath(player.position, target));
    if (_pendingPath.isEmpty) return;
    _consumeNextPathStep();
    if (_pendingPath.isEmpty) return; // ถึงตั้งแต่ก้าวแรก ไม่ต้องตั้ง timer ต่อ
    _moveTimer = async_lib.Timer.periodic(_stepDuration, (timer) {
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
    if (_pendingPath.isEmpty) player.resetWalkFrame();
  }

  // แปลงระยะทางจากตำแหน่งผู้เล่นปัจจุบันถึง [to] เป็นคิวก้าวเดิน 4 ทิศ (ไม่มี
  // แนวทแยง เหมือนเกมเก่า) — แกนไหนเหลือระยะมากกว่าก้าวไปทางนั้นก่อนในแต่ละก้าว
  // ทำให้เส้นทางดูเป็นขั้นบันไดแทนที่จะเดินแกนเดียวจนสุดแล้วค่อยเปลี่ยนแกน
  List<MapDirection> _buildPath(Vector2 from, Vector2 to) {
    var dx = ((to.x - from.x) / _stepSize).round();
    var dy = ((to.y - from.y) / _stepSize).round();
    final path = <MapDirection>[];
    while (dx != 0 || dy != 0) {
      if (dx.abs() >= dy.abs() && dx != 0) {
        path.add(dx > 0 ? MapDirection.right : MapDirection.left);
        dx += dx > 0 ? -1 : 1;
      } else {
        path.add(dy > 0 ? MapDirection.down : MapDirection.up);
        dy += dy > 0 ? -1 : 1;
      }
    }
    return path;
  }

  // ก้าวเดียวระยะ _stepSize ไปทาง [dir] clamp ไม่ให้เกินขอบแผนที่เสมอ (ดูหมาย
  // เหตุ _avatarClampMargin ด้านบน — เวอร์ชันเดิมไม่เคย clamp ตรงนี้เลย)
  void _stepInDirection(MapDirection dir) {
    final vector = switch (dir) {
      MapDirection.up => Vector2(0, -1),
      MapDirection.down => Vector2(0, 1),
      MapDirection.left => Vector2(-1, 0),
      MapDirection.right => Vector2(1, 0),
    };
    final target = player.position + vector * _stepSize;
    final clamped = Vector2(
      target.x.clamp(_avatarClampMargin, size.x - _avatarClampMargin),
      target.y.clamp(_avatarClampMargin, _worldHeight - _avatarClampMargin),
    );
    player.stepTo(clamped, dir);
  }

  Vector2 _stallPosition(int index, double cellWidth) {
    final row = index ~/ _columns;
    final col = index % _columns;
    return Vector2(
      col * cellWidth + cellWidth / 2,
      row * _cellHeight + _cellHeight / 2 + _topPadding,
    );
  }

  double _mapHeight(int vendorCount) {
    final rows = (vendorCount / _columns).ceil();
    return rows * _cellHeight + _topPadding + _bottomPadding;
  }
}

/// ตัวละครของผู้เล่น วาดจาก sprite sheet จริงเดียวกับเวอร์ชัน widget (ดู
/// CharacterSprite/market_map_screen.dart) หันทิศทางตามที่เดิน (แถวในตาราง)
/// พร้อมไล่เฟรมเดิน (คอลัมน์) ทีละเฟรมต่อก้าว — โหลด+decode ภาพเองใน
/// onLoad() ของ component นี้ (ไม่ผูกกับ onLoad() ของ MarketFlameGame ทั้งก้อน
/// -- เคยลอง await ไว้ที่นั่นแล้วพบว่า GameWidget ทั้งหน้าค้างที่ loading
/// เปล่าๆ จนกว่า decode จะเสร็จ ดูคอมเมนต์ใน MarketFlameGame.onLoad()) ระหว่าง
/// รอ sheet โหลดเสร็จ render() จะข้ามการวาดไปก่อน (โปร่งใส ไม่ error) แล้วขึ้น
/// เองทันทีที่โหลดเสร็จเพราะ game loop วาดใหม่ทุกเฟรมอยู่แล้ว วาดด้วย
/// canvas.drawImageRect ตรงๆ แทนการซ้อน CircleComponent/RectangleComponent
/// หลายชิ้น ลดความเสี่ยงจาก API ที่ไม่เคยยืนยันในเวอร์ชัน Flame ที่ resolve
/// จริง (render(Canvas) เป็น core API ของ Component ที่เสถียรมาก ทุก shape
/// component ที่ใช้อยู่แล้วในไฟล์นี้ก็ implement มันแบบเดียวกันนี้อยู่แล้วภายใน)
///
/// การเดินทั้งหมด (คิว/D-pad/จังหวะก้าว) ถูกขับเคลื่อนจาก MarketFlameGame ไม่ใช่
/// component นี้ — component นี้แค่รับคำสั่ง "ก้าวเดียวไปจุดนี้" ผ่าน [stepTo]
/// แล้วอัปเดตทิศ/เฟรม/เอฟเฟกต์เลื่อนของตัวเอง เหมือน widget เวอร์ชัน (state
/// class คุมการเดิน, CharacterSprite แค่ render 1 เฟรม)
class PlayerComponent extends PositionComponent {
  final String assetPath;

  PlayerComponent({required this.assetPath})
      : super(size: Vector2.all(_playerDisplaySize), anchor: Anchor.center);

  Image? _sheet;
  MapDirection _facing = MapDirection.down;
  int _walkFrame = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final data = await rootBundle.load(assetPath);
    final codec = await instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _sheet = frame.image;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final sheet = _sheet;
    if (sheet == null) return; // ยังโหลดภาพไม่เสร็จ ข้ามเฟรมนี้ไปก่อน
    final src = Rect.fromLTWH(
      _walkFrame * _frameSize,
      _facing.spriteRow * _frameSize,
      _frameSize,
      _frameSize,
    );
    final dst = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawImageRect(sheet, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  /// ก้าวเดียวไปยัง [target] (คำนวณ/clamp มาแล้วจาก MarketFlameGame) หันหน้า
  /// ไปทาง [dir] และไล่เฟรมเดินไปอีก 1 เฟรม แล้วค่อยๆ เลื่อนไปด้วย MoveToEffect
  /// ระยะเวลาเท่ากับ _stepDuration ให้ดูเป็นการก้าวจริง ไม่ใช่การสอนกระโดด
  void stepTo(Vector2 target, MapDirection dir) {
    _facing = dir;
    _walkFrame = (_walkFrame + 1) % 4;
    add(MoveToEffect(target, EffectController(duration: _stepSeconds, curve: Curves.easeOut)));
  }

  void resetWalkFrame() {
    _walkFrame = 0;
  }
}

/// ป้ายร้านค้า 1 ร้านบนแผนที่ Flame — แตะที่วงกลมนี้เพื่อเดินไปหาแล้วเปิดเมนู
class StallComponent extends PositionComponent with TapCallbacks {
  final Vendor vendor;
  final void Function() onTap;

  // ใช้ตรวจว่า "เพิ่งเข้ามาใกล้" ร้านนี้หรือยัง (ดู MarketFlameGame.update())
  bool wasNear = false;

  StallComponent({
    required this.vendor,
    required Vector2 stallPosition,
    required this.onTap,
  }) : super(position: stallPosition, size: Vector2.all(_stallSize), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    add(
      CircleComponent(
        radius: _stallSize / 2,
        paint: Paint()..color = vendor.isOpen ? Colors.white : Colors.grey.shade300,
      ),
    );
    add(
      CircleComponent(
        radius: _stallSize / 2,
        paint: Paint()
          ..color = Colors.brown.shade300
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      ),
    );
    add(
      TextComponent(
        text: vendor.name,
        anchor: Anchor.topCenter,
        position: Vector2(_stallSize / 2, _stallSize + 4),
        // fontFamily ต้องระบุ 'Loma' ตรงๆ เพราะ Flame's TextComponent ไม่ได้
        // สืบทอด ThemeData ของแอป (ต่างจาก widget ปกติที่ได้ฟอนต์ default จาก
        // buildAppTheme() อัตโนมัติ) ไม่งั้นชื่อร้านภาษาไทยจะขึ้นเป็นกล่องเปล่า
        textRenderer: TextPaint(style: const TextStyle(fontSize: 12, color: Colors.black, fontFamily: 'Loma')),
      ),
    );
  }

  @override
  void onTapUp(TapUpEvent event) {
    onTap();
  }
}
