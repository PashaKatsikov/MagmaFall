import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(MagmaColors.deepRock)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _reload() {
    setState(() {
      _error = false;
      _loading = true;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MagmaColors.deepRock,
      appBar: AppBar(
        backgroundColor: MagmaColors.rock,
        foregroundColor: MagmaColors.cream,
        title: Text(widget.title, style: arcadeText(size: 18)),
      ),
      body: Stack(
        children: [
          if (!_error) WebViewWidget(controller: _controller),
          if (_loading && !_error)
            const Center(
              child: CircularProgressIndicator(color: MagmaColors.ember),
            ),
          if (_error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: MagmaColors.cream, size: 56),
                  const SizedBox(height: 16),
                  Text('Could not load the page.',
                      style: arcadeText(size: 16)),
                  const SizedBox(height: 8),
                  Text('Please check your connection.',
                      style: arcadeText(size: 13, color: MagmaColors.cream)),
                  const SizedBox(height: 20),
                  MagmaButton(label: 'RETRY', onPressed: _reload),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
