import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decode a QR entirely on-device; QR payloads are never uploaded.
String decodeQrBytes(Uint8List bytes) {
  final picture = img.decodeImage(bytes);
  if (picture == null) throw const FormatException('Unsupported or damaged image');
  final rgba = picture.convert(numChannels: 4);
  final source = RGBLuminanceSource(picture.width, picture.height,
      rgba.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List());
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  return QRCodeReader().decode(bitmap).text;
}

Future<String?> pickAndDecodeQr() async {
  final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp']);
  if (result == null) return null;
  final file = result.files.single;
  final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null) throw const FormatException('Unable to read selected image');
  return decodeQrBytes(bytes);
}

/// Capture the primary Windows display locally. Temporary screenshot is removed.
Future<String> captureAndDecodeQr() async {
  if (!Platform.isWindows) throw UnsupportedError('Screen capture is Windows-only');
  final file = File('${Directory.systemTemp.path}\\easy-auth-qr-${DateTime.now().microsecondsSinceEpoch}.png');
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($args[0], [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $graphics.Dispose()
  $bitmap.Dispose()
}
''';
  try {
    final result = await Process.run('powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script, file.path]);
    if (result.exitCode != 0 || !await file.exists()) {
      throw StateError('Unable to capture screen: ${result.stderr}');
    }
    return decodeQrBytes(await file.readAsBytes());
  } finally {
    if (await file.exists()) await file.delete();
  }
}
