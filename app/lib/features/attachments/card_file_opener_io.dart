import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

Future<bool> openCardFileAttachment({required String filePath}) async {
  final uri = Uri.file(filePath);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> openCardFileAttachmentDirectory({
  required String filePath,
}) async {
  final directory = Directory(p.dirname(filePath));
  if (!await directory.exists()) return false;
  return launchUrl(
    Uri.directory(directory.path),
    mode: LaunchMode.externalApplication,
  );
}
