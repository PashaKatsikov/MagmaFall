/// Which experience an install is locked into.
///
/// - [web]        → portal WebView (paid/attributed users)
/// - [native]     → the volcano game (organic users; also the offline path)
/// - [unresolved] → not decided yet (very first launch)
enum FlowStage {
  web,
  native,
  unresolved;

  static FlowStage parse(String? raw) => switch (raw) {
        'web' => FlowStage.web,
        'native' => FlowStage.native,
        _ => FlowStage.unresolved,
      };

  String get token => switch (this) {
        FlowStage.web => 'web',
        FlowStage.native => 'native',
        FlowStage.unresolved => 'unresolved',
      };
}
