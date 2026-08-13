import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_widget_snapshot.dart';

/// 与安卓原生小组件通信的桥接层。
class AndroidWidgetBridge {
  AndroidWidgetBridge({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.mikeken.kanban/home_widget');

  final MethodChannel _channel;

  /// 将快照写入原生侧并请求刷新小组件。
  Future<void> updateSnapshot(Map<String, dynamic> snapshot) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>(
      'updateSnapshot',
      {'json': jsonEncode(snapshot)},
    );
  }

  /// 便捷方法：直接提交 [AndroidWidgetSnapshot]。
  static Future<void> publish(AndroidWidgetSnapshot snapshot) =>
      AndroidWidgetBridge().updateSnapshot(snapshot.toJson());
}
