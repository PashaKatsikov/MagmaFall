import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../forge/attribution_desk.dart';
import '../forge/gate_caller.dart';
import '../forge/link_sensor.dart';
import '../forge/local_store.dart';
import '../forge/signal_center.dart';
import '../forge/ua_client.dart';
import 'offline_view.dart';

/// Full-screen immersive portal. Hosts the offer URL and handles keyboard,
/// safe-area, redirect loops and connectivity drops.
class PortalView extends StatefulWidget {
  const PortalView({
    super.key,
    required this.url,
    required this.store,
    required this.signals,
    required this.link,
    required this.attribution,
    required this.gate,
  });

  final String url;
  final LocalStore store;
  final SignalCenter signals;
  final LinkSensor link;
  final AttributionDesk attribution;
  final GateCaller gate;

  @override
  State<PortalView> createState() => _PortalViewState();
}

class _PortalViewState extends State<PortalView> with WidgetsBindingObserver {
  late final WebViewController _web;
  bool _spinning = true;
  bool _routedOffline = false;

  String? _lastMainUrl;
  int _redirectHits = 0;

  StreamSubscription<List<ConnectivityResult>>? _linkSub;
  Timer? _offlineDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _goImmersive();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(emberClient.agent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _spinning = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _spinning = false);
          _redirectHits = 0;
          _stripSafeArea();
          _liftInputsAboveKeyboard();
        },
        onWebResourceError: _onError,
        onHttpError: (_) {},
        onNavigationRequest: _onNavigate,
      ));

    _configureAndroid();
    _web.loadRequest(Uri.parse(widget.url));

    widget.signals.onWarmUrl = (url) {
      if (mounted) _web.loadRequest(Uri.parse(url));
    };

    // Ensure FCM token is reported even if permission was granted after
    // BootGate was already disposed (e.g. via PulsePrompt).
    widget.signals.onTokenRotated = _reportToken;
    final existing = widget.signals.token;
    if (existing != null && existing.isNotEmpty) {
      _reportToken(existing);
    }

    _linkSub = widget.link.changes.listen((results) {
      if (!LinkSensor.allDown(results)) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce =
          Timer(const Duration(milliseconds: 700), _bailOffline);
    });
  }

  void _goImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _goImmersive();
  }

  NavigationDecision _onNavigate(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;

    const web = {'http', 'https', 'about', 'data', 'blob'};
    if (web.contains(uri.scheme)) {
      if (req.isMainFrame) _lastMainUrl = req.url;
      return NavigationDecision.navigate;
    }
    _openExternally(uri);
    return NavigationDecision.prevent;
  }

  void _onError(WebResourceError err) {
    if (err.isForMainFrame != true) return;

    final blurb = err.description.toLowerCase();
    final loop = blurb.contains('too_many_redirects') ||
        blurb.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;
    if (loop && _lastMainUrl != null && _redirectHits < 3) {
      _redirectHits++;
      _web.loadRequest(Uri.parse(_lastMainUrl!));
      return;
    }

    // Cover the native error page immediately.
    if (mounted) setState(() => _spinning = true);

    final dnsLike = blurb.contains('name_not_resolved') ||
        blurb.contains('internet_disconnected') ||
        blurb.contains('network_changed') ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -21;

    if (dnsLike) {
      _bailOffline();
    } else {
      _maybeBailOffline();
    }
  }

  Future<void> _maybeBailOffline() async {
    if (_routedOffline) return;
    if (await widget.link.online) return;
    _bailOffline();
  }

  void _bailOffline() {
    if (_routedOffline || !mounted) return;
    _routedOffline = true;
    _web.currentUrl().then((current) {
      final url = current ?? widget.url;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OfflineView(
            onRetry: (_) => PortalView(
              url: url,
              store: widget.store,
              signals: widget.signals,
              link: widget.link,
              attribution: widget.attribution,
              gate: widget.gate,
            ),
          ),
        ),
      );
    });
  }

  void _configureAndroid() {
    if (!Platform.isAndroid) return;
    if (_web.platform is! AndroidWebViewController) return;
    final ctrl = _web.platform as AndroidWebViewController;
    ctrl.setMediaPlaybackRequiresUserGesture(false);
    ctrl.setOnShowFileSelector(_pickFiles);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(ctrl, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (picked != null && picked.files.isNotEmpty) {
        return picked.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _openExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _liftInputsAboveKeyboard() {
    _web.runJavaScript(r'''
(function(){
  if (window.__mfKb) return; window.__mfKb = true;
  function editable(n){ if(!n) return false; var t=n.tagName;
    return t==='INPUT'||t==='TEXTAREA'||n.isContentEditable===true; }
  function lift(){
    var n=document.activeElement; if(!editable(n)) return;
    var vv=window.visualViewport;
    if(vv){ var b=n.getBoundingClientRect(); var edge=vv.offsetTop+vv.height;
      if(b.bottom>edge-20||b.top<vv.offsetTop){ n.scrollIntoView({behavior:'auto',block:'nearest'}); } }
    else { n.scrollIntoView({behavior:'auto',block:'nearest'}); }
  }
  document.addEventListener('focusin',function(e){ if(editable(e.target)) setTimeout(lift,350); });
  if(window.visualViewport){ var last=window.visualViewport.height;
    window.visualViewport.addEventListener('resize',function(){ var h=window.visualViewport.height;
      if(h<last) setTimeout(lift,120); last=h; }); }
})();
''');
  }

  void _stripSafeArea() {
    _web.runJavaScript(r'''
(function(){
  if (window.__mfSa) return; window.__mfSa = true;
  var ID='__mfSaStyle';
  var CSS=':root{--safe-area-inset-top:0px!important;--safe-area-inset-right:0px!important;'+
    '--safe-area-inset-bottom:0px!important;--safe-area-inset-left:0px!important;'+
    '--sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;}'+
    'html,body,#app,#root,#__nuxt,#__layout{padding-top:0!important;'+
    'padding-left:0!important;padding-right:0!important;margin-top:0!important;}';
  function kbOpen(){ if(!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight*0.75; }
  function apply(){
    if(kbOpen()) return;
    var head=document.head||document.documentElement; if(!head) return;
    var m=document.querySelector('meta[name="viewport"]');
    if(m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content')||'')){
      var c=(m.getAttribute('content')||'').replace(/,?\s*viewport-fit\s*=\s*\w+/ig,'').trim();
      m.setAttribute('content', c+(c?', ':'')+'viewport-fit=contain');
    }
    var s=document.getElementById(ID);
    if(!s){ s=document.createElement('style'); s.id=ID; head.appendChild(s); }
    if(s.textContent!==CSS) s.textContent=CSS;
  }
  apply();
  ['pushState','replaceState'].forEach(function(fn){
    var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments);
      setTimeout(apply,80); setTimeout(apply,400); return r; };
  });
  window.addEventListener('popstate',function(){ setTimeout(apply,80); });
  setInterval(apply,2500);
})();
''');
  }

  Future<bool> _handleBack() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    }
    return false;
  }

  void _reportToken(String token) {
    widget.attribution
        .composeBody(
          locale: Platform.localeName.replaceAll('-', '_'),
          pushToken: token,
        )
        .then(widget.gate.ask)
        .ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _offlineDebounce?.cancel();
    widget.signals.onWarmUrl = null;
    widget.signals.onTokenRotated = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final inset = MediaQuery.of(context).viewPadding;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              // Portrait: keep clear of the status bar. Landscape: keep clear
              // of a side camera notch, but go under the top bar (immersive).
              padding: landscape
                  ? EdgeInsets.only(left: inset.left, right: inset.right)
                  : EdgeInsets.only(top: inset.top),
              child: WebViewWidget(controller: _web),
            ),
            if (_spinning)
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6A00)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
