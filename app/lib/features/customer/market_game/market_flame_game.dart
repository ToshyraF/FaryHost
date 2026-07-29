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

const _playerDisplaySize = 56.0;

// sprite sheet ตาราง 4x4 เฟรม 32x32: แถว 0=ลง(หน้า), 1=ซ้าย, 2=ขวา, 3=ขึ้น
// (หลัง), คอลัมน์ 0-3 คือ walk cycle — เดียวกับเวอร์ชัน widget (ดู
// market_map_screen.dart/character_sprite.dart) ที่มา/สิทธิ์การใช้งานอยู่ใน
// assets/sprites/CREDITS.txt
const _frameSize = 32.0;

enum _Direction { down, left, right, up }

extension on _Direction {
  int get spriteRow => index;
}

/// เวอร์ชันทดลองของแผนที่ตลาด สร้างด้วย Flame (Flutter game engine) แทนการ
/// วาดด้วย widget ล้วนๆ เหมือน MarketMapScreen ปกติ — โครงเดียวกัน (ตัวละคร
/// เดินไปตามที่แตะ, แตะร้านค้าให้เดินไปหาแล้วเปิดเมนู) แต่ render ผ่าน
/// game loop ของ Flame แทน widget tree ธรรมดา
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

  @override
  Color backgroundColor() => const Color(0xFFF3E5C8);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // โหลด+decode sprite sheet ของตัวละครที่นี่ (แล้วรอให้เสร็จก่อน) แทนที่จะ
    // ทำใน PlayerComponent.onLoad() -- ตอนแรกทำในนั้นแล้วพบว่า golden test
    // ถ่ายภาพตอน component ยังโหลดภาพไม่เสร็จ (ยืนยันจากภาพจริงที่ผู้ใช้ส่งมา
    // ตัวละครไม่ขึ้นเลย) เพราะ FlameGame ทั้งก้อนจะพร้อม render ก็ต่อเมื่อ
    // onLoad() ของ MarketFlameGame เองเสร็จสมบูรณ์ก่อน ทำที่นี่แล้ว await จึง
    // การันตีว่าภาพพร้อมก่อน PlayerComponent จะถูกสร้าง/render เฟรมแรกเลย
    final characterData = await rootBundle.load(characterAssetPath);
    final characterCodec = await instantiateImageCodec(characterData.buffer.asUint8List());
    final characterFrame = await characterCodec.getNextFrame();
    final characterSheet = characterFrame.image;

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
          player.walkTo(position);
          stall.wasNear = true;
          onOpenVendor(vendor);
        },
      );
      _stalls.add(stall);
      add(stall);
    }

    player = PlayerComponent(sheet: characterSheet)..position = Vector2(size.x / 2, _topPadding);
    add(player);

    // แผนที่สูงกว่าจอได้เมื่อร้านค้าเยอะ (mapHeight ขึ้นกับจำนวนร้าน) ให้กล้อง
    // เลื่อนตามตัวละครในแนวตั้ง (verticalOnly: true เพราะแนวนอนแคบพอดีจอเสมอ
    // อยู่แล้ว จาก _columns คงที่) ส่วนการกันไม่ให้เลื่อนเกินขอบแผนที่ทำเองใน
    // update() ด้านล่าง แทนการใช้ camera.setBounds — API นั้นต้องพึ่ง shape
    // class ของ Flame ที่ชื่อ/ที่ import ไม่ตรงกับเวอร์ชันที่ resolve จริงบน CI
    camera.follow(player, verticalOnly: true);
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
    player.walkTo(camera.globalToLocal(event.canvasPosition));
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
/// พร้อมไล่เฟรมเดิน (คอลัมน์) ระหว่างเคลื่อนที่ — รับภาพที่ decode เสร็จแล้ว
/// เข้ามาตรงๆ จาก MarketFlameGame.onLoad() (ไม่ decode เองใน onLoad() ของ
/// component นี้ เพราะรอบแรกที่ทำแบบนั้นพบว่า golden test ถ่ายภาพก่อนโหลด
/// เสร็จ ตัวละครเลยไม่ขึ้นเลย -- ดูคอมเมนต์ใน MarketFlameGame.onLoad()) แล้ว
/// render ด้วย canvas.drawImageRect ตรงๆ แทนการซ้อน
/// CircleComponent/RectangleComponent หลายชิ้น ลดความเสี่ยงจาก API ที่ไม่เคย
/// ยืนยันในเวอร์ชัน Flame ที่ resolve จริง (render(Canvas) เป็น core API ของ
/// Component ที่เสถียรมาก ทุก shape component ที่ใช้อยู่แล้วในไฟล์นี้ก็
/// implement มันแบบเดียวกันนี้อยู่แล้วภายใน)
class PlayerComponent extends PositionComponent {
  final Image sheet;

  PlayerComponent({required this.sheet})
      : super(size: Vector2.all(_playerDisplaySize), anchor: Anchor.center);

  _Direction _facing = _Direction.down;
  int _walkFrame = 0;
  // Timer จาก dart:async ต้อง alias เพราะ package:flame/components.dart
  // export คลาสชื่อ Timer ของตัวเองด้วย (flame/src/timer.dart) ซึ่งไม่มี
  // .periodic()/.cancel() แบบเดียวกัน — ถ้าไม่ alias ชื่อ Timer เปล่าๆ จะ
  // resolve ไปเป็นของ Flame แทน
  async_lib.Timer? _walkTimer;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final src = Rect.fromLTWH(
      _walkFrame * _frameSize,
      _facing.spriteRow * _frameSize,
      _frameSize,
      _frameSize,
    );
    final dst = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawImageRect(sheet, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  void walkTo(Vector2 target) {
    final delta = target - position;
    if (delta.length > 1) {
      _facing = delta.x.abs() > delta.y.abs()
          ? (delta.x > 0 ? _Direction.right : _Direction.left)
          : (delta.y > 0 ? _Direction.down : _Direction.up);
      _startWalkAnimation();
    }
    add(MoveToEffect(target, EffectController(duration: 0.35, curve: Curves.easeOut)));
  }

  void _startWalkAnimation() {
    _walkTimer?.cancel();
    _walkFrame = 0;
    _walkTimer = async_lib.Timer.periodic(const Duration(milliseconds: 90), (_) {
      _walkFrame = (_walkFrame + 1) % 4;
    });
    async_lib.Future.delayed(const Duration(milliseconds: 350), () {
      _walkTimer?.cancel();
      _walkFrame = 0;
    });
  }

  @override
  void onRemove() {
    _walkTimer?.cancel();
    super.onRemove();
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
