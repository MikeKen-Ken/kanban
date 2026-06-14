import 'card_image_add_source.dart';
import 'picked_image_bytes.dart';

Future<List<PickedImageBytes>> pickImagesForSource(
  CardImageAddSource source,
) async =>
    const [];

Future<List<PickedImageBytes>> pickCardImagesFromGallery() async => const [];

Future<List<PickedImageBytes>> pickCardImageFromCamera() async => const [];

Future<List<PickedImageBytes>> pasteCardImagesFromClipboard() async =>
    const [];

Future<List<PickedImageBytes>> pickCardImages() async => const [];
