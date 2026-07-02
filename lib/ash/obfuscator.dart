import 'dart:typed_data';

// Sensitive strings (gateway host, tracker key, sender id, UA fragments) are
// never embedded as plain literals. They live as masked byte lists and are
// recovered at runtime by [reveal].
//
// The mask is derived from a project-local seed phrase through FNV-1a hashing
// followed by an xorshift32 stream, then folded with a positional constant.
// Changing the seed changes the whole mask, giving this binary its own
// signature. After editing the seed, regenerate every masked list with
// tool/mask_secrets.dart.

const List<int> _seed = <int>[
  0x6D, 0x61, 0x67, 0x6D, 0x61, 0x76, 0x65, 0x6E, 0x74, // "magmavent"
];

Uint8List _brewMask() {
  var h = 0x811C9DC5; // FNV-1a offset basis
  for (final b in _seed) {
    h = (h ^ b) & 0xFFFFFFFF;
    h = (h * 0x01000193) & 0xFFFFFFFF; // FNV prime
  }

  final mask = Uint8List(32);
  var x = h == 0 ? 0x1A0D0801 : h;
  for (var i = 0; i < mask.length; i++) {
    // xorshift32
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    x &= 0xFFFFFFFF;
    mask[i] = (x ^ (i * 37 + 11)) & 0xFF;
  }
  return mask;
}

final Uint8List _mask = _brewMask();

/// Recovers a UTF-8 string from a masked byte list.
String reveal(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ^ _mask[i % _mask.length]) & 0xFF;
  }
  return String.fromCharCodes(out);
}
