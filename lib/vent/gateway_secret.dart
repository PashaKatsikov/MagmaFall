import '../ash/obfuscator.dart';

// Masked decisioning endpoint. The backend at this address returns the verdict
// {ok, url, expires} that decides whether an install lands on the portal (web)
// or the game (native). Regenerate via tool/mask_secrets.dart.

const List<int> _gateway = <int>[
  82, 255, 149, 86, 21, 148, 93, 221, 178, 195, 78, 93, 32, 78, 233, 166,
  89, 91, 63, 114, 145, 216, 111, 65, 111, 66, 146, 238, 143, 10, 110, 54,
];

/// Full POST endpoint URL, or '' when not yet configured.
String pullGatewayUrl() => reveal(_gateway);
