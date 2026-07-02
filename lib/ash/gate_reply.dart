/// Parsed verdict from the decisioning gateway.
///
/// Shape: {ok: bool, url: String?, expires: int?, message: String?}
class GateReply {
  const GateReply({
    required this.ok,
    this.url,
    this.expires,
    this.note,
  });

  final bool ok;
  final String? url;
  final int? expires;
  final String? note;

  bool get hasUrl => url != null && url!.isNotEmpty;

  factory GateReply.fromMap(Map<String, dynamic> map) {
    return GateReply(
      ok: map['ok'] == true,
      url: map['url'] as String?,
      expires: map['expires'] is int
          ? map['expires'] as int
          : int.tryParse('${map['expires']}'),
      note: map['message'] as String?,
    );
  }

  factory GateReply.failed(String reason) =>
      GateReply(ok: false, note: reason);
}
