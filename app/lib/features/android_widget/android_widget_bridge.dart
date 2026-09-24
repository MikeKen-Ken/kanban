import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 与安卓原生小组件通信的桥接层。
class AndroidWidgetBridge {
  AndroidWidgetBridge({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.mikeken.kanban/home_widget');

  final MethodChannel _channel;

  /// Publish project snapshots and refresh home widgets.
  Future<void> updateProjects(Map<String, dynamic> projects) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>(
      'updateProjects',
      {'json': jsonEncode(projects)},
    );
  }

  Future<bool> consumePendingSync() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('consumePendingSync') ?? false;
  }

  void setSyncRequestHandler(Future<void> Function() handler) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'syncRequested') await handler();
    });
  }
}
