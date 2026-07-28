import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/models/vendor.dart';
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
          return GameWidget(
            game: MarketFlameGame(
              vendors: vendors,
              onOpenVendor: (vendor) => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => VendorMenuScreen(vendorId: vendor.id)),
              ),
            ),
          );
        },
      ),
    );
  }
}
