import '../ash/obfuscator.dart';

// AppsFlyer + Firebase credentials, masked. These arrive from the manager
// later; until then trackerKey / senderId stay empty and the attribution
// layer degrades gracefully (see AttributionDesk).

const List<int> _trackerKey = <int>[
  126, 234, 176, 119, 17, 192, 1, 162, 167, 234, 75, 125, 42, 95, 234, 191,
  119, 49, 51, 94, 191, 175,
];
const List<int> _senderId = <int>[
  12, 190, 212, 22, 81, 154, 74, 197, 233, 145, 31, 5,
];

const List<int> _syncHost = <int>[
  82, 255, 149, 86, 21, 148, 93, 221, 184, 193, 77, 67, 37, 67, 166, 171,
  69, 5, 47, 123, 144, 142, 105, 92, 47, 71, 148, 228,
];
const List<int> _syncPath = <int>[
  21, 226, 143, 85, 18, 207, 30, 158, 128, 198, 72, 68, 32, 7, 254, 254,
  27, 69, 115,
];

/// AppsFlyer Dev Key ('' until provided).
String pullTrackerKey() => reveal(_trackerKey);

/// Firebase project number / sender id ('' until provided).
String pullSenderId() => reveal(_senderId);

/// Builds the GCD (get-conversion-data) retry endpoint used when AppsFlyer
/// first reports a false "Organic" status.
String buildSyncEndpoint(String appId, String deviceId) {
  final host = reveal(_syncHost);
  if (host.isEmpty) return '';
  return '$host${reveal(_syncPath)}$appId?device_id=$deviceId';
}
