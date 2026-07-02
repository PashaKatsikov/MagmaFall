// ignore_for_file: avoid_print
// Generates masked byte lists for sensitive strings.
//
// Keep the mask algorithm in sync with lib/ash/obfuscator.dart. If you change
// the seed there, change it here too and re-run:
//
//   dart run tool/mask_secrets.dart
//
// Then paste the printed lists into lib/vent/*.dart.
//
// Always use `dart run` — never a PowerShell loop (32-bit overflow corrupts
// the bytes and produces broken headers/URLs at runtime).

import 'dart:typed_data';

const List<int> _seed = <int>[
  0x6D, 0x61, 0x67, 0x6D, 0x61, 0x76, 0x65, 0x6E, 0x74, // "magmavent"
];

Uint8List _brewMask() {
  var h = 0x811C9DC5;
  for (final b in _seed) {
    h = (h ^ b) & 0xFFFFFFFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  final mask = Uint8List(32);
  var x = h == 0 ? 0x1A0D0801 : h;
  for (var i = 0; i < mask.length; i++) {
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    x &= 0xFFFFFFFF;
    mask[i] = (x ^ (i * 37 + 11)) & 0xFF;
  }
  return mask;
}

final Uint8List _mask = _brewMask();

List<int> _mask_(String plain) {
  final raw = plain.codeUnits;
  return List<int>.generate(
    raw.length,
    (i) => (raw[i] ^ _mask[i % _mask.length]) & 0xFF,
  );
}

void _emit(String label, String plain) {
  final bytes = _mask_(plain);
  final buf = StringBuffer()..write('$label => const <int>[');
  buf.write(bytes.join(', '));
  buf.write('];');
  print(buf.toString());
}

void main() {
  // ── Known now ──────────────────────────────────────────────
  _emit('gatewayUrl', 'https://magmafall.com/config.php');
  _emit('chromeVer', '132.0.6834.163');
  _emit('webkitVer', '537.36');

  // ── AppsFlyer / Firebase ──────────────────────────────────
  _emit('trackerKey', 'DaQQwnsPxHbMkwbuBDoCCX'); // AppsFlyer Dev Key
  _emit('senderId', '655074876365'); // Firebase project number
  _emit('syncHost', 'https://gcdsdk.appsflyer.com');
  _emit('syncPath', '/install_data/v4.0/');
}
