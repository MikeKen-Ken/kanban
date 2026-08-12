import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

Future<bool> openAgentDispatchSkillDirectory(String skillPath) async {
  final directory = Directory(p.dirname(skillPath));
  if (!await directory.exists()) return false;
  return launchUrl(
    Uri.directory(directory.path),
    mode: LaunchMode.externalApplication,
  );
}
