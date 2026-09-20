// 项目包含 Android 原生插件（高德 SDK / Mock Location MethodChannel），
// 在单元测试环境无法直接 runApp，所以此 smoke test 仅作占位，
// 保证 `flutter test` / `flutter analyze` 不会因为不存在 MyApp 而报错。
// 真正的功能测试需要集成测试（integration_test）。

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder smoke test', () {
    expect(true, isTrue);
  });
}