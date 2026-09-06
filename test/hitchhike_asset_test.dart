import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decodeAsset(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Hitchhike keeps both production keys and exact canvas sizes', () async {
    final full = await _decodeAsset('assets/images/powerups/hitchhike.png');
    final thumb = await _decodeAsset(
      'assets/images/powerups/hitchhike_thumb.png',
    );

    expect((full.width, full.height), (128, 128));
    expect((thumb.width, thumb.height), (106, 88));
  });

  test('Hitchhike canvases retain transparent corners', () async {
    for (final path in const [
      'assets/images/powerups/hitchhike.png',
      'assets/images/powerups/hitchhike_thumb.png',
    ]) {
      final image = await _decodeAsset(path);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);
      final rgba = bytes!.buffer.asUint8List();
      int alphaAt(int x, int y) => rgba[((y * image.width + x) * 4) + 3];

      expect(alphaAt(0, 0), 0, reason: '$path top-left');
      expect(alphaAt(image.width - 1, 0), 0, reason: '$path top-right');
      expect(alphaAt(0, image.height - 1), 0, reason: '$path bottom-left');
      expect(
        alphaAt(image.width - 1, image.height - 1),
        0,
        reason: '$path bottom-right',
      );
      var hasOpaquePixel = false;
      for (var index = 3; index < rgba.length; index += 4) {
        if (rgba[index] == 255) {
          hasOpaquePixel = true;
          break;
        }
      }
      expect(hasOpaquePixel, isTrue, reason: '$path contains visible art');
    }
  });
}
