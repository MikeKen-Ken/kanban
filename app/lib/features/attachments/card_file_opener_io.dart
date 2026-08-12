import 'package:url_launcher/url_launcher.dart';

Future<bool> openCardFileAttachment({required String filePath}) async {
  final uri = Uri.file(filePath);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
