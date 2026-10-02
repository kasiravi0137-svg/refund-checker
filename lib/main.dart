import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

const loginUrl = 'https://eportal.incometax.gov.in/iec/foservices/#/login';

void main() => runApp(const MaterialApp(
    debugShowCheckedModeBanner: false, home: Home()));

class Acct {
  final int row;
  final String pan, pwd;
  String status, date;
  String name = '', mobile = '', email = '';
  Acct(this.row, this.pan, this.pwd, [this.status = '', this.date = '']);
}

String _s(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value;
  return v.toString();
}

// ---- Login auto-fill (unchanged logic) ----
String fillJs(String pan, String pwd) => '''
(function(){
 var P=${jsonEncode(pan)}, W=${jsonEncode(pwd)};
 function setV(el,v){var s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;s.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));el.dispatchEvent(new Event('blur',{bubbles:true}));}
 function btn(){return [].slice.call(document.querySelectorAll('button')).find(function(x){return x.innerText.toLowerCase().indexOf('continue')>-1&&!x.disabled});}
 var n=0,pwdAt=0,pwdClicks=0,lastClick=0,panLast=0;
 var timer=setInterval(function(){
  var now=Date.now();
  if(++n>1600||location.href.indexOf('dashboard')>-1){clearInterval(timer);return}
  var w=document.querySelector("input[type=password]");
  if(w){
   if(!pwdAt){setV(w,W);var c=document.querySelector("input[type=checkbox]");if(c&&!c.checked)c.click();pwdAt=now;return}
   if(pwdClicks==0&&now-pwdAt>1200){var b=btn();if(b){b.click();pwdClicks=1;lastClick=now}return}
   if(pwdClicks>0&&pwdClicks<3&&now-lastClick>2500&&document.body.innerText.toLowerCase().indexOf('not authenticated')>-1){var b2=btn();if(b2){b2.click();pwdClicks++;lastClick=now}}
   return;
  }
  var i=document.querySelector("input[name=panAdhaarUserId], input[type=text]");
  if(i){
   if(i.value!==P){setV(i,P);lastClick=now;return}
   if(now-lastClick>250&&now-panLast>1000){var b3=btn();if(b3){b3.click();panLast=now}}
  }
 },150);
})();
''';

// ---- Post-login automation driver ----
// Channel 'Refund' messages:
//   {t:'dash',name,mobile,email}  {t:'status',status,date}
//   {t:'err',msg}  {t:'log',msg}  {t:'diag',data}
String autoJs() => '''
(function(){
 function post(o){try{Refund.postMessage(JSON.stringify(o))}catch(e){}}
 function log(m){post({t:'log',msg:m});}
 function all(sel){try{return [].slice.call(document.querySelectorAll(sel));}catch(e){return [];}}
 function textOf(e){return ((e&&(e.innerText||e.textContent))||'').trim();}
 function text(){return document.body.innerText||'';}
 function visible(e){
   if(!e)return false;
   try{var cs=getComputedStyle(e);if(cs.visibility==='hidden'||cs.display==='none')return false;
       if(e.offsetParent===null&&cs.position!=='fixed')return false;}catch(x){}
   var r=e.getBoundingClientRect();return r.width>1&&r.height>1;
 }
 function clickable(e){
   var n=e;
   for(var i=0;i<7&&n;i++){
     var tag=n.tagName?n.tagName.toLowerCase():'';
     if(tag==='a'||tag==='button')return n;
     if(n.getAttribute){
       var role=n.getAttribute('role');
       if(role==='button'||role==='menuitem'||role==='link')return n;
       if(n.hasAttribute('routerlink')||n.hasAttribute('ng-reflect-router-link')||n.hasAttribute('onclick'))return n;
     }
     try{if(getComputedStyle(n).cursor==='pointer')return n;}catch(y){}
     n=n.parentElement;
   }
   return e;
 }
 function realClick(e){
   if(!e)return false; e=clickable(e);
   try{e.scrollIntoView({block:'center'});}catch(x){}
   var ev=['pointerover','pointerenter','pointerdown','mousedown','pointerup','mouseup'];
   for(var i=0;i<ev.length;i++){
     try{
       var E=(window.PointerEvent&&ev[i].indexOf('pointer')===0)?new PointerEvent(ev[i],{bubbles:true,cancelable:true,view:window}):new MouseEvent(ev[i].replace('pointer','mouse'),{bubbles:true,cancelable:true,view:window});
       e.dispatchEvent(E);
     }catch(z){}
   }
   try{if(e.focus)e.focus();}catch(f){}
   try{e.click();}catch(w){}
   return true;
 }
 function item(txt){
   txt=txt.toLowerCase();
   var c=all('a,button,li,span,div,p,[role=menuitem],[role=button]').filter(function(e){return visible(e)&&textOf(e).toLowerCase().indexOf(txt)>-1;});
   c.sort(function(a,b){return textOf(a).length-textOf(b).length;});
   return c[0];
 }
 function menuOpen(){
   var hits=0;['Services','Grievances','Pending Actions','Authorised Partners','AIS'].forEach(function(L){if(item(L))hits++;});
   return hits>=2;
 }
 function toggleCands(){
   var out=[];
   all('mat-icon,i,span,button,a').forEach(function(e){if(textOf(e).toLowerCase()==='menu')out.push(e);});
   all('[aria-label]').forEach(function(e){var a=(e.getAttribute('aria-label')||'').toLowerCase();if(a.indexOf('menu')>-1||a.indexOf('navigation')>-1||a.indexOf('hamburger')>-1)out.push(e);});
   all('.navbar-toggler,.hamburger,.menu-icon,.menu-toggle,[class*="burger"],[class*="hamburger"],[class*="menu-toggle"]').forEach(function(e){out.push(e);});
   var top=all('button,a,[role=button],mat-icon,i').filter(function(e){if(!visible(e))return false;var r=e.getBoundingClientRect();return r.top<150&&r.left>window.innerWidth*0.45;});
   top.sort(function(a,b){return b.getBoundingClientRect().right-a.getBoundingClientRect().right;});
   out=out.concat(top);
   var seen=[],res=[];
   out.forEach(function(e){if(e&&visible(e)&&seen.indexOf(e)<0){seen.push(e);res.push(e);}});
   return res;
 }
 function attr(e,n){try{return e.getAttribute?e.getAttribute(n):'';}catch(x){return '';}}
 function desc(e){
   if(!e)return 'null';
   var t=e.tagName?e.tagName.toLowerCase():'?';
   var id=e.id?('#'+e.id):'';
   var cls=''; try{if(e.className&&e.className.toString)cls='.'+e.className.toString().trim().replace(/\\s+/g,'.').slice(0,50);}catch(x){}
   var r=attr(e,'role')?('[role='+attr(e,'role')+']'):'';
   var h=attr(e,'href')||attr(e,'routerlink')||attr(e,'ng-reflect-router-link'); h=h?(' @'+h):'';
   var vis=visible(e)?'':' (hidden)';
   return t+id+cls+r+h+' "'+textOf(e).slice(0,34)+'"'+vis;
 }
 function ancestry(e){var o=[],n=e;for(var i=0;i<6&&n;i++){o.push(desc(n));n=n.parentElement;}return o.join('\\n   > ');}
 function dumpMenu(reason){
   try{
     var L=['=== DIAG: '+reason+' @ '+location.href+' ==='];
     var sv=item('Services');
     L.push('Services item: '+desc(sv));
     if(sv){L.push('Services ancestry:\\n   '+ancestry(sv));
            L.push('Services clickable target: '+desc(clickable(sv)));
            L.push('Services outerHTML: '+((sv.outerHTML||'').slice(0,320)));}
     ['Dashboard','e-File','Authorised Partners','Services','AIS','Pending Actions','Grievances','Help','Know Your Refund Status','Refund Reissue','Tax Credit Mismatch'].forEach(function(x){L.push('["'+x+'"] -> '+desc(item(x)));});
     var anchors=all('a[href]').filter(function(a){var t=textOf(a).toLowerCase();return t.indexOf('refund')>-1||t.indexOf('services')>-1;});
     L.push('refund/services anchors: '+anchors.length);
     anchors.slice(0,8).forEach(function(a){L.push('  a '+desc(a));});
     var ov=all('.cdk-overlay-container,[class*="overlay"],[class*="dialog"],[class*="sidenav"],[class*="drawer"],[role=dialog],mat-dialog-container');
     L.push('overlay containers: '+ov.length);
     ov.slice(0,4).forEach(function(o){L.push('  ov '+desc(o)+' kids='+o.children.length);});
     post({t:'diag',data:L.join('\\n')});
   }catch(e){post({t:'diag',data:'diag err '+e.message});}
 }
 function refundHref(){
   var as=all('a[href]');
   var best=as.find(function(x){return textOf(x).toLowerCase().indexOf('know your refund')>-1;});
   if(!best)best=as.find(function(x){var h=(attr(x,'href')||'').toLowerCase();return h.indexOf('refund')>-1&&h.indexOf('reissue')<0;});
   return best?attr(best,'href'):null;
 }
 function navTo(h){try{location.href=(new URL(h,location.href)).href;return true;}catch(e){try{location.hash=h;return true;}catch(x){return false;}}}

 function getName(){var m=text().match(/welcome\\s*back[,\\s]+([A-Za-z][A-Za-z .'-]{0,40})/i);return m?m[1].trim():'';}
 function getEmail(){var m=text().match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/);return m?m[0]:'';}
 function getMobile(){
   var lines=text().split('\\n');
   for(var i=0;i<lines.length;i++){
     var ln=lines[i], d=ln.replace(/\\D/g,'');
     if((ln.indexOf('+')>-1||/[6-9]\\d{9}/.test(d))&&d.length>=10&&d.length<=13){var ten=d.slice(-10);if(/^[6-9]\\d{9}\$/.test(ten))return ten;}
   }
   var m=text().match(/[6-9]\\d{9}/);return m?m[0]:'';
 }
 function findAYselect(){return all('select').find(function(s){return [].slice.call(s.options).some(function(o){return (o.text||'').indexOf('2026-27')>-1;});});}
 function setNativeAY(s){
   var opt=[].slice.call(s.options).find(function(o){return (o.text||'').indexOf('2026-27')>-1;});
   if(!opt)return false;
   var setter=Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype,'value').set;
   setter.call(s,opt.value); s.dispatchEvent(new Event('input',{bubbles:true})); s.dispatchEvent(new Event('change',{bubbles:true})); return true;
 }
 function clickAYoption(){
   var o=all('li,span,div,p,[role=option]').filter(function(e){var t=textOf(e);return visible(e)&&(t==='2026-27'||/^2026-27\\b/.test(t));});
   o.sort(function(a,b){return textOf(a).length-textOf(b).length;});
   if(o[0]){realClick(o[0]);return true;} return false;
 }
 function openAY(){
   var lab=item('Assessment Year'), trig=null;
   if(lab){var c=lab.parentElement;for(var k=0;k<4&&c;k++){trig=c.querySelector('select,.p-dropdown,.mat-select,mat-select,[role=combobox],.ng-select,input,button');if(trig)break;c=c.parentElement;}}
   if(!trig)trig=document.querySelector('.p-dropdown,mat-select,[role=combobox],.ng-select');
   if(trig){realClick(trig);return true;} return false;
 }
 function findSubmit(){
   var c=all('button,input[type=submit],a[role=button],a').filter(function(e){if(!visible(e))return false;var t=(e.innerText||e.value||'').trim().toLowerCase();return t==='submit'||(t.indexOf('submit')>-1&&t.indexOf('dashboard')<0);});
   c.sort(function(a,b){return (b.tagName.toLowerCase()==='button'?1:0)-(a.tagName.toLowerCase()==='button'?1:0);});
   return c[0];
 }

 var step='dash',tick=0,acted=-50,done=false,dashSent=false,cands=null,ci=0,svClicked=false,ayTried=0;
 function ready(w){return tick-acted>w;}
 function act(){acted=tick;}
 function fail(msg){dumpMenu(msg);post({t:'err',msg:msg});clearInterval(tmr);done=true;}

 var tmr=setInterval(function(){
   tick++; if(done)return;
   if(tick>650){fail('timeout at '+step);return;}
   var T=text(), low=T.toLowerCase();
   try{
   if(step==='dash'){
     if(T.length<40)return;
     if(!dashSent&&(low.indexOf('welcome')>-1||/[A-Z]{5}\\d{4}[A-Z]/.test(T))){
       post({t:'dash',name:getName(),mobile:getMobile(),email:getEmail()});
       dashSent=true;step='nav';cands=null;ci=0;act();log('dashboard captured, opening menu');
     }
     return;
   }
   if(step==='nav'){
     var rl=item('Know Your Refund Status');
     if(rl){log('refund link visible: '+desc(rl));realClick(rl);step='ay';act();return;}
     var rh=refundHref();
     if(rh){log('direct refund href: '+rh);navTo(rh);step='ay';act();return;}
     if(menuOpen()){log('menu open');step='services';svClicked=false;act();return;}
     if(cands===null){cands=toggleCands();ci=0;log('menu candidates: '+cands.length);}
     if(ready(10)){
       if(ci<cands.length){log('tap menu button '+(ci+1)+': '+desc(cands[ci]));realClick(cands[ci]);ci++;act();}
       else{cands=toggleCands();ci=0;if(cands.length===0)fail('menu toggle not found');}
     }
     return;
   }
   if(step==='services'){
     var rl2=item('Know Your Refund Status');
     if(rl2){log('refund link: '+desc(rl2));realClick(rl2);step='ay';act();return;}
     var rh2=refundHref();
     if(rh2&&svClicked){log('refund href after services: '+rh2);navTo(rh2);step='ay';act();return;}
     if(!svClicked){
       var sv=item('Services');
       if(sv){log('services el: '+desc(sv)+' | click target: '+desc(clickable(sv)));realClick(sv);svClicked=true;act();}
       else if(ready(12)){dumpMenu('Services element not found');step='nav';cands=null;ci=0;act();}
       return;
     }
     if(ready(30))fail('refund link not found after Services');
     return;
   }
   if(step==='ay'){
     if(low.indexOf('assessment year')<0&&low.indexOf('know refund status')<0)return;
     var ns=findAYselect();
     if(ns){if(setNativeAY(ns)){step='submit';act();log('AY selected (native)');}return;}
     if(ready(3)){
       if(clickAYoption()){step='submit';act();log('AY selected');}
       else{openAY();ayTried++;if(ayTried>25)fail('AY dropdown failed');}
     }
     return;
   }
   if(step==='submit'){
     if(ready(3)){
       var sb=findSubmit();
       if(sb){log('submit: '+desc(sb));realClick(sb);step='result';act();}
       else if(ready(20))fail('submit button not found');
     }
     return;
   }
   if(step==='result'){
     if(low.indexOf('status of income tax refund')>-1||low.indexOf('date of status')>-1){
       var st='',dt='',tbls=all('table');
       for(var i=0;i<tbls.length;i++){
         var h=(tbls[i].innerText||'').toLowerCase();
         if(h.indexOf('status')>-1&&h.indexOf('date of status')>-1){
           var rows=tbls[i].querySelectorAll('tr');
           if(rows.length>=2){var cells=rows[1].querySelectorAll('td,th');if(cells.length>=1)st=(cells[0].innerText||'').trim();if(cells.length>=2)dt=(cells[1].innerText||'').trim();}
           break;
         }
       }
       if(!st){var idx=low.indexOf('your refund');if(idx>-1)st=T.substring(idx,idx+400);}
       st=st.replace(/\\s+/g,' ').trim(); dt=dt.replace(/\\s+/g,' ').trim();
       if(st){post({t:'status',status:st,date:dt});clearInterval(tmr);done=true;}
       else if(ready(25))fail('result text empty');
     } else if(low.indexOf('no record')>-1){
       post({t:'status',status:T.replace(/\\s+/g,' ').slice(0,300),date:''});clearInterval(tmr);done=true;
     }
     return;
   }
   }catch(e){fail('js:'+(e&&e.message?e.message:e));}
 },200);
})();
''';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Excel? excel;
  String? outPath;
  String? logPath;
  List<Acct> accts = [];
  int current = -1;
  bool loggedIn = false, injected = false, autoStarted = false;
  bool autoMode = true;
  String auto = '';
  late final WebViewController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Refund',
          onMessageReceived: (m) => onDriver(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          if (current >= 0 && !injected && !loggedIn) {
            injected = true;
            final a = accts[current];
            ctrl.runJavaScript(fillJs(a.pan, a.pwd));
          }
          if (current >= 0 && loggedIn && autoMode && !autoStarted) {
            autoStarted = true;
            _injectDriver();
          }
        },
        onUrlChange: (c) {
          if (current >= 0 && (c.url ?? '').contains('dashboard') && !loggedIn) {
            setState(() => loggedIn = true);
            if (autoMode && !autoStarted) {
              autoStarted = true;
              _injectDriver();
            }
          }
        },
      ));
  }

  void _injectDriver() {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (loggedIn && current >= 0 && autoMode) {
        setState(() => auto = 'Reading dashboard...');
        ctrl.runJavaScript(autoJs());
      }
    });
  }

  Future<void> logLine(String s) async {
    logPath ??=
        '${(await getApplicationDocumentsDirectory()).path}/refund_log.txt';
    final t = DateTime.now().toIso8601String();
    try {
      await File(logPath!)
          .writeAsString('[$t] $s\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> onDriver(String raw) async {
    if (current < 0 || current >= accts.length) return;
    Map<String, dynamic> o;
    try {
      o = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final a = accts[current];
    switch (o['t']) {
      case 'log':
        final m = (o['msg'] ?? '').toString();
        await logLine('LOG [${a.pan}] $m');
        if (mounted) setState(() => auto = m);
        break;
      case 'diag':
        await logLine('DIAG [${a.pan}]\n${(o['data'] ?? '').toString()}');
        if (mounted) msg('Diagnostics saved. Tap the log icon to share.');
        break;
      case 'dash':
        a.name = (o['name'] ?? '').toString();
        a.mobile = (o['mobile'] ?? '').toString();
        a.email = (o['email'] ?? '').toString();
        await logLine(
            'DASH [${a.pan}] name=${a.name} mobile=${a.mobile} email=${a.email}');
        if (mounted) setState(() => auto = 'Dashboard: ${a.name}');
        await writeResults();
        break;
      case 'status':
        a.status = (o['status'] ?? '').toString();
        a.date = (o['date'] ?? '').toString();
        await logLine('STATUS [${a.pan}] ${a.status} | ${a.date}');
        await writeResults();
        if (mounted) setState(() => auto = 'Saved. Next PAN...');
        await advance();
        break;
      case 'err':
        final m = (o['msg'] ?? '').toString();
        await logLine('ERR [${a.pan}] $m');
        if (a.status.isEmpty) a.status = 'ISSUE: $m';
        await writeResults();
        if (mounted) {
          setState(() => auto =
              'Auto step failed ($m). Finish manually then Capture, or Skip.');
          msg('Auto failed: $m');
        }
        break;
    }
  }

  void msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (r == null || r.files.single.bytes == null) return;
    final ex = Excel.decodeBytes(r.files.single.bytes!);
    final sheet = ex.tables[ex.tables.keys.first]!;
    final list = <Acct>[];
    for (var i = 1; i < sheet.maxRows; i++) {
      final row = sheet.row(i);
      String g(int c) => c < row.length ? _s(row[c]).trim() : '';
      if (g(0).isEmpty || g(1).isEmpty) continue;
      list.add(Acct(i, g(0).toUpperCase(), g(1)));
    }
    final dir = await getApplicationDocumentsDirectory();
    setState(() {
      excel = ex;
      accts = list;
      outPath = '${dir.path}/refund_results.xlsx';
      logPath = '${dir.path}/refund_log.txt';
    });
    msg('${list.length} accounts loaded');
  }

  Future<void> start(int i) async {
    setState(() {
      current = i;
      loggedIn = false;
      injected = false;
      autoStarted = false;
      auto = '';
    });
    await logLine('---- START ${accts[i].pan} ----');
    await WebViewCookieManager().clearCookies();
    await ctrl.clearLocalStorage();
    await ctrl.loadRequest(Uri.parse(loginUrl));
  }

  int nextPending(int from) {
    for (var i = from; i < accts.length; i++) {
      if (accts[i].status.isEmpty) return i;
    }
    return -1;
  }

  Future<void> advance() async {
    final n = nextPending(current + 1);
    if (n < 0) {
      setState(() => current = -1);
      msg('All done. Tap the share icon to get the Excel.');
    } else {
      await start(n);
    }
  }

  Future<String> pageText() async {
    final r = await ctrl.runJavaScriptReturningResult('document.body.innerText');
    var s = r.toString();
    if (s.startsWith('"')) s = jsonDecode(s) as String;
    return s;
  }

  // Manual fallback capture (status only).
  Future<void> capture() async {
    final text = await pageText();
    final hits = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) =>
            l.isNotEmpty &&
            ['refund', 'status', 'processed', 'ack']
                .any((k) => l.toLowerCase().contains(k)))
        .take(6)
        .join(' | ');
    final tc = TextEditingController(text: hits.isEmpty ? 'Not found' : hits);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save this status?'),
        content: TextField(controller: tc, maxLines: 6),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final a = accts[current];
    a.status = tc.text;
    await writeResults();
    await advance();
  }

  // Rebuild the result workbook from memory each save: never loses earlier rows.
  Future<void> writeResults() async {
    if (outPath == null) {
      final dir = await getApplicationDocumentsDirectory();
      outPath = '${dir.path}/refund_results.xlsx';
    }
    final ex = Excel.createExcel();
    final sheetName = ex.getDefaultSheet()!;
    final s = ex[sheetName];
    List<CellValue?> rowOf(List<String> v) =>
        v.map((e) => TextCellValue(e) as CellValue?).toList();
    s.appendRow(rowOf([
      'PAN Card Number',
      'Name',
      'Mobile Number',
      'Email',
      'Status',
      'Date of Status'
    ]));
    for (final a in accts) {
      s.appendRow(rowOf([a.pan, a.name, a.mobile, a.email, a.status, a.date]));
    }
    final bytes = ex.save();
    if (bytes != null) await File(outPath!).writeAsBytes(bytes, flush: true);
  }

  Future<void> share() async {
    if (outPath == null || !File(outPath!).existsSync()) {
      msg('Nothing saved yet');
      return;
    }
    await Share.shareXFiles([XFile(outPath!)]);
  }

  Future<void> shareLog() async {
    if (logPath == null || !File(logPath!).existsSync()) {
      msg('No log yet');
      return;
    }
    await Share.shareXFiles([XFile(logPath!)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refund Status Checker'),
        actions: [
          IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Share log',
              onPressed: shareLog),
          if (accts.isNotEmpty)
            IconButton(icon: const Icon(Icons.share), onPressed: share)
        ],
      ),
      body: current >= 0 ? runView() : listView(),
    );
  }

  Widget listView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(
              onPressed: pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select Excel')),
          if (accts.isNotEmpty)
            ElevatedButton.icon(
                onPressed: () {
                  final n = nextPending(0);
                  n < 0 ? msg('Nothing pending') : start(n);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start')),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Auto'),
            Switch(
                value: autoMode,
                onChanged: (v) => setState(() => autoMode = v)),
          ]),
        ]),
      ),
      if (accts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'Input Excel (row 1 = headers): PAN | Password.\n'
              'Output columns: PAN | Name | Mobile | Email | Status | Date of Status.\n\n'
              'Auto ON: after each login it reads the dashboard, opens '
              'Services > Know Your Refund Status, picks AY 2026-27, submits, '
              'saves, logs out and moves to the next PAN. Complete captcha / OTP '
              'during each login.\n\n'
              'If a step fails, tap the bug icon (top bar) to share the log.\n'
              'Use only for your own or authorised accounts.'),
        ),
      Expanded(
        child: ListView(
          children: accts
              .map((a) => ListTile(
                    title: Text(a.pan),
                    subtitle: Text([
                      a.name,
                      a.status.isEmpty ? 'Pending' : a.status
                    ].where((e) => e.isNotEmpty).join(' - ')),
                    trailing: Text(a.date, style: const TextStyle(fontSize: 11)),
                  ))
              .toList(),
        ),
      ),
    ]);
  }

  Widget runView() {
    final a = accts[current];
    return Column(children: [
      Expanded(child: WebViewWidget(controller: ctrl)),
      Container(
        width: double.infinity,
        color: Colors.grey.shade200,
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${a.pan}  (${current + 1}/${accts.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(loggedIn
              ? (autoMode
                  ? (auto.isEmpty ? 'Logged in. Running automatically...' : auto)
                  : 'Logged in. Open the refund page, then tap Capture.')
              : 'Logging in automatically. Complete captcha / OTP if asked.'),
          const SizedBox(height: 6),
          Row(children: [
            ElevatedButton(onPressed: capture, child: const Text('Capture')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: advance, child: const Text('Skip')),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: () => setState(() => current = -1),
                child: const Text('Stop')),
          ]),
        ]),
      ),
    ]);
  }
}
