import 'package:flutter/material.dart';

import '../game/game_screen.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'webview_page.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  static const _privacyUrl = 'https://magmafall.com/privacy-policy.html';
  static const _supportUrl = 'https://magmafall.com/support.html';

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _play() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
    if (mounted) setState(() {}); // refresh best score on return
  }

  void _openPage(String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebViewPage(title: title, url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final best = ProgressService.instance.bestScore;
    return Scaffold(
      backgroundColor: MagmaColors.deepRock,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.jpg', fit: BoxFit.cover),
          Container(color: MagmaColors.deepRock.withValues(alpha: 0.4)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Image.asset('assets/logo.webp'),
                      ),
                    ),
                  ),
                  _buildBestScore(best),
                  const SizedBox(height: 18),
                  MagmaButton(
                    label: 'PLAY',
                    icon: Icons.play_arrow_rounded,
                    width: 260,
                    onPressed: _play,
                  ),
                  const SizedBox(height: 20),
                  _buildFooterLinks(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBestScore(int best) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: MagmaColors.shadow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MagmaColors.rock, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded,
              color: MagmaColors.gold, size: 22),
          const SizedBox(width: 10),
          Text('BEST  $best', style: arcadeText(size: 18)),
        ],
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _linkButton(
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy Policy',
          onTap: () => _openPage('Privacy Policy', MenuScreen._privacyUrl),
        ),
        _linkButton(
          icon: Icons.help_outline_rounded,
          label: 'Support',
          onTap: () => _openPage('Support', MenuScreen._supportUrl),
        ),
      ],
    );
  }

  Widget _linkButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: MagmaColors.shadow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: MagmaColors.cream),
              const SizedBox(width: 6),
              Text(label, style: arcadeText(size: 13, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
