import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../bridge/insight.dart';
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

  bool _offerReached = false;
  bool _pageHadError = false;

  static final RegExp _depositRx = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

  StreamSubscription<List<ConnectivityResult>>? _linkSub;
  Timer? _offlineDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Insight.screen('web');
    Insight.event('web_open');

    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _goImmersive();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(emberClient.agent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..addJavaScriptChannel(
        'AegisInsight',
        onMessageReceived: (m) => _onWebSignal(m.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _pageHadError = false;
          if (mounted) setState(() => _spinning = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _spinning = false);
          _redirectHits = 0;
          _stripSafeArea();
          _liftInputsAboveKeyboard();
          _installInsightProbe();
          _trackWebPage(url);
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
    if (state == AppLifecycleState.resumed) {
      _goImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      Insight.event('web_background');
    }
  }

  NavigationDecision _onNavigate(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;

    const web = {'http', 'https', 'about', 'data', 'blob'};
    if (web.contains(uri.scheme)) {
      if (req.isMainFrame) _lastMainUrl = req.url;
      return NavigationDecision.navigate;
    }
    Insight.event('web_external');
    Insight.tag('web_external_scheme', uri.scheme);
    _openExternally(uri);
    return NavigationDecision.prevent;
  }

  void _onError(WebResourceError err) {
    if (err.isForMainFrame != true) return;

    _pageHadError = true;

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

    final String reason = _classifyWebError(err);
    final String failed = _lastMainUrl ?? widget.url;
    final String host = Uri.tryParse(failed)?.host ?? '';
    Insight.event('web_error');
    Insight.tag('web_error_reason', reason);
    Insight.tag('web_last_error', '${err.errorCode}:${err.description}');
    if (host.isNotEmpty) Insight.tag('web_error_host', host);
    if (!_offerReached) {
      Insight.event('web_offer_unreachable');
      Insight.tag('offer_reached', 'false');
      Insight.tag('offer_unreachable_reason', reason);
    } else {
      Insight.event('web_error_after_load');
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

  void _trackWebPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    Insight.screenName('web:${uri == null ? url : '${uri.host}${uri.path}'}');
    Insight.event('web_page');
    Insight.tag('web_last_url', url);
    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null) Insight.tag('offer_host', uri!.host);
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  static String _classifyWebError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') || d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') || d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) {
      return 'dns_unresolved';
    }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) {
      return 'no_network';
    }
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') || d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) return 'ssl_error';
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  void _installInsightProbe() {
    _web.runJavaScript(r'''
(function(){
  if (window.__aegisInsight) return; window.__aegisInsight = true;
  function send(t){ try { AegisInsight.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
      case 'form_submit':
        Insight.event('web_form_submit');
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
  var CSS=
    // Zero out safe-area CSS variables so sites using env(safe-area-inset-*)
    // don't leave empty notch bars. We do NOT touch padding/margin on html,
    // body, #app, #root — the site's own layout must be preserved.
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
    '}' +
    // Only strip padding-top from known shell-wrapper elements, not from
    // html/body/#app where the site may rely on its own padding for layout.
    '.gameview-mobile-header,.app-header{padding-top:0!important;margin-top:0!important;}';
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
