import 'package:shared_preferences/shared_preferences.dart';

/// Persists the player's best endless-run score.
class ProgressService {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  static const _bestScoreKey = 'best_score';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  int get bestScore => _prefs?.getInt(_bestScoreKey) ?? 0;

  /// Stores [score] if it beats the current record. Returns true if it was a
  /// new best.
  Future<bool> submitScore(int score) async {
    await init();
    if (score > bestScore) {
      await _prefs!.setInt(_bestScoreKey, score);
      return true;
    }
    return false;
  }
}
