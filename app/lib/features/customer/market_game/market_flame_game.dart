import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Colors, Curves, TextStyle;

import '../../../core/models/vendor.dart';

const _columns = 2;
const _cellHeight = 180.0;
const _stallSize = 72.0;
const _topPadding = 60.0;
const _bottomPadding = 80.0;
const _nearRadius = 70.0;

// ตัวละครพิกเซลอาร์ต "chibi portrait" เดียวกับเวอร์ชัน widget (ดู
// _Avatar/_PixelSpritePainter ใน market_map_screen.dart) — คัดลอกตาราง/พาเลต
// สีมาตรงๆ แทนการ import ข้ามไฟล์ เพื่อให้เวอร์ชันทดลองนี้ยังแยกอิสระจาก
// เวอร์ชัน widget เหมือนเดิม (จะได้ลบทิ้งได้ง่ายถ้าการทดลอง Flame ไม่ไปต่อ)
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
  'O': Color(0xFF141414),
  'h': Color(0xFF2E5AA8),
  'L': Color(0xFF6FA8F5),
  'F': Color(0xFFFFE0C2),
  'E': Color(0xFF1B1B1B),
  'e': Color(0xFFFFFFFF),
  'm': Color(0xFF7A3B2E),
  'C': Color(0xFFF2A93C),
  'c': Color(0xFFC97F1E),
};
// เป็น final ไม่ใช่ const เพราะ .length ไม่ใช่ compile-time constant expression
final _playerWidth = _spriteRows.first.length * _spritePixel;
final _playerHeight = _spriteRows.length * _spritePixel;

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

  MarketFlameGame({required this.vendors, required this.onOpenVendor});

  late final PlayerComponent player;
  late final double _worldHeight;
  final List<StallComponent> _stalls = [];

  @override
  Color backgroundColor() => const Color(0xFFF3E5C8);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

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

    player = PlayerComponent()..position = Vector2(size.x / 2, _topPadding);
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

/// ตัวละครของผู้เล่น วาดเป็นพิกเซลอาร์ต "chibi portrait" เดียวกับเวอร์ชัน
/// widget (ดู _Avatar/_PixelSpritePainter ใน market_map_screen.dart) แทน
/// สไปรต์ RPG แบบเดินเต็มตัวรอบก่อนหน้า — override
/// render() วาด Canvas.drawRect ทีละบล็อกตามตาราง _spriteRows โดยตรง แทนการ
/// ซ้อน CircleComponent/RectangleComponent หลายชิ้น ลดความเสี่ยงจาก API ที่
/// ไม่เคยยืนยันในเวอร์ชัน Flame ที่ resolve จริง (render(Canvas) เป็น core
/// API ของ Component ที่เสถียรมาก ทุก shape component ที่ใช้อยู่แล้วในไฟล์นี้
/// ก็ implement มันแบบเดียวกันนี้อยู่แล้วภายใน)
class PlayerComponent extends PositionComponent {
  PlayerComponent() : super(size: Vector2(_playerWidth, _playerHeight), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
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

  void walkTo(Vector2 target) {
    add(MoveToEffect(target, EffectController(duration: 0.35, curve: Curves.easeOut)));
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
        textRenderer: TextPaint(style: const TextStyle(fontSize: 12, color: Colors.black)),
      ),
    );
  }

  @override
  void onTapUp(TapUpEvent event) {
    onTap();
  }
}
