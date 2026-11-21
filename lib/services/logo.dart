import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Logo / kop toko: diperkecil otomatis saat upload, disimpan di database (ikut backup),
/// dan diubah menjadi gambar hitam-putih untuk printer thermal.
class LogoService {
  /// Ukuran maksimal sisi terpanjang setelah resize
  static const int maxSide = 600;

  /// Foto apa pun (jpg/png/webp/bmp/gif) -> PNG kecil dalam base64.
  /// Melempar [FormatException] bila file bukan gambar.
  static String fromPicked(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) throw const FormatException('File bukan gambar (pakai JPG atau PNG)');
    var im = img.bakeOrientation(src);
    if (im.width > maxSide || im.height > maxSide) {
      im = im.width >= im.height
          ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
    }
    return base64Encode(img.encodePng(im, level: 6));
  }

  static Uint8List? decode(String b64) {
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static final Map<String, List<int>> _rasterCache = {};

  /// Perintah ESC/POS (GS v 0) untuk mencetak logo di tengah kertas.
  /// [paperDots] 384 (58mm) / 576 (80mm), [widthPct] lebar logo dalam persen kertas.
  static List<int> escPos(Uint8List png, {required int paperDots, int widthPct = 60, int maxHeight = 200}) {
    final key = '${png.length}_${png.hashCode}_${paperDots}_${widthPct}_$maxHeight';
    final cached = _rasterCache[key];
    if (cached != null) return cached;
    final src = img.decodeImage(png);
    if (src == null) return const [];

    var w = (paperDots * widthPct.clamp(20, 100) / 100).round();
    var h = (src.height * w / src.width).round();
    if (h > maxHeight) {
      h = maxHeight;
      w = (src.width * h / src.height).round();
    }
    if (w < 8 || h < 8) return const [];
    final im = img.copyResize(src, width: w, height: h, interpolation: img.Interpolation.average);

    // grayscale (latar transparan dianggap putih)
    final gray = List<double>.filled(paperDots * h, 255);
    final left = ((paperDots - w) / 2).floor();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final m = p.maxChannelValue.toDouble();
        final a = m == 0 ? 1.0 : p.a / m;
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / (m == 0 ? 1 : m) * 255;
        gray[y * paperDots + left + x] = lum * a + 255 * (1 - a);
      }
    }

    // dithering Floyd-Steinberg -> hitam/putih
    final bits = List<bool>.filled(paperDots * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < paperDots; x++) {
        final i = y * paperDots + x;
        final old = gray[i];
        final black = old < 128;
        bits[i] = black;
        final err = old - (black ? 0 : 255);
        if (x + 1 < paperDots) gray[i + 1] += err * 7 / 16;
        if (y + 1 < h) {
          if (x > 0) gray[i + paperDots - 1] += err * 3 / 16;
          gray[i + paperDots] += err * 5 / 16;
          if (x + 1 < paperDots) gray[i + paperDots + 1] += err * 1 / 16;
        }
      }
    }

    // kirim per potongan 24 baris agar printer murah tidak kehabisan buffer
    final bytesPerRow = (paperDots + 7) ~/ 8;
    final out = <int>[0x1B, 0x61, 0x00];
    for (var y0 = 0; y0 < h; y0 += 24) {
      final rows = (h - y0) < 24 ? (h - y0) : 24;
      out.addAll([0x1D, 0x76, 0x30, 0x00, bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF, rows & 0xFF, (rows >> 8) & 0xFF]);
      for (var y = y0; y < y0 + rows; y++) {
        for (var bx = 0; bx < bytesPerRow; bx++) {
          var b = 0;
          for (var k = 0; k < 8; k++) {
            final x = bx * 8 + k;
            if (x < paperDots && bits[y * paperDots + x]) b |= 0x80 >> k;
          }
          out.add(b);
        }
      }
    }
    out.add(0x0A);
    _rasterCache[key] = out;
    return out;
  }
}
