import 'package:shared_preferences/shared_preferences.dart';

import '../features/project/project_settings.dart';
import '../features/project/projects_manifest.dart';
import '../models/kanban_models.dart';
import 'board_storage.dart';

BoardStorage createBoardStorage({
  Object? baseDirectory,
  SharedPreferences? prefs,
}) {
  throw UnsupportedError('当前平台不支持本地看板存储');
}
