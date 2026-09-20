import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  // 高德 SDK 需在 runApp 前初始化（各平台 Key 在 amap_strategy 中配置）
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShowLocationApp());
}
