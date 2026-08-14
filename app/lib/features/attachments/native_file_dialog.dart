import 'package:flutter/scheduler.dart';

/// 让 Flutter 模态层先完成一帧，再调原生文件对话框，避免嵌套 BottomSheet 下 picker 迟迟不出现。
Future<void> yieldBeforeNativeFileDialog() async {
  await SchedulerBinding.instance.endOfFrame;
}
