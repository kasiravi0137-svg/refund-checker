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
// Runs entirely inside the SPA. Reports back through the 'Refund' JS channel:
//   {t:'dash', name, mobile, email}
//   {t:'status', status, date}
//   {t:'err', msg}
//   {t:'log', msg}
// NOTE: the menu/dropdown selectors are best-effort. If a step stalls it posts
// an 'err' and the manual Capture button stays available as a fallback.
String autoJs() => '''
(function(){
 function post(o){try{Refund.postMessage(JSON.stringify(o))}catch(e){}}
 function all(sel){return [].slice.call(document.querySelectorAll(sel));}
 function vis(el){if(!el)return false;var r=el.getBoundingClientRect();return r.width>0&&r.height>0;}
 function findByText(sel,txt){txt=txt.toLowerCase();return all(sel).find(function(e){return (e.innerText||e.textContent||'').toLowerCase().indexOf(txt)>-1;});}
 function clickEl(e){if(!e)return false;try{e.scrollIntoView({block:'center'});}catch(x){} try{e.click();}catch(y){return false;} return true;}
 function text(){return document.body.innerText||'';}

 var step='dash', tick=0, acted=-50, done=false, dashSent=false;
 function ready(w){return tick-acted>w;}
 function act(){acted=tick;}

 function getName(){var m=text().match(/welcome\\s*back[,\\s]+([A-Za-z][A-Za-z .'-]{0,40})/i);return m?m[1].trim():'';}
 function getEmail(){var m=text().match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/);return m?m[0]:'';}
 function getMobile(){
   var lines=text().split('\\n');
   for(var i=0;i<lines.length;i++){
     var ln=lines[i];
     var d=ln.replace(/\\D/g,'');
     if((ln.indexOf('+')>-1||/[6-9]\\d{9}/.test(d))&&d.length>=10&&d.length<=13){
       var ten=d.slice(-10);
       if(/^[6-9]\\d{9}\$/.test(ten))return ten;
     }
   }
   var m=text().match(/[6-9]\\d{9}/);return m?m[0]:'';
 }

 function findAYselect(){
   return all('select').find(function(s){return [].slice.call(s.options).some(function(o){return (o.text||'').indexOf('2026-27')>-1;});});
 }
 function setNativeAY(s){
   var opt=[].slice.call(s.options).find(function(o){return (o.text||'').indexOf('2026-27')>-1;});
   if(!opt)return false;
   var setter=Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype,'value').set;
   setter.call(s,opt.value); s.dispatchEvent(new Event('input',{bubbles:true})); s.dispatchEvent(new Event('change',{bubbles:true}));
   return true;
 }
 function clickAYoption(){
   var o=all('li,span,div,p,[role=option]').find(function(e){var t=(e.innerText||e.textContent||'').trim();return (t==='2026-27'||/^2026-27\\b/.test(t))&&vis(e);});
   return clickEl(o);
 }
 function openAY(){
   var lab=findByText('label,span,div,p','Assessment Year');
   var trig=null;
   if(lab){var c=lab.parentElement;for(var k=0;k<4&&c;k++){trig=c.querySelector('select,.p-dropdown,.mat-select,mat-select,[role=combobox],.ng-select,input,button');if(trig)break;c=c.parentElement;}}
   if(!trig){trig=document.querySelector('.p-dropdown,mat-select,[role=combobox],.ng-select');}
   return clickEl(trig);
 }

 var tmr=setInterval(function(){
   tick++;
   if(done)return;
   if(tick>500){post({t:'err',msg:'timeout at '+step});clearInterval(tmr);done=true;return;}
   var T=text(), low=T.toLowerCase();
   try{
   if(step==='dash'){
     if(T.length<40)return;
     if(!dashSent && (low.indexOf('welcome')>-1 || /[A-Z]{5}\\d{4}[A-Z]/.test(T))){
       post({t:'dash',name:getName(),mobile:getMobile(),email:getEmail()});
       dashSent=true; step='nav'; act(); post({t:'log',msg:'dashboard captured'});
     }
     return;
   }
   if(step==='nav'){
     var rl=findByText('a,span,div,button,li','Know Your Refund Status');
     if(rl&&vis(rl)){clickEl(rl);step='ay';act();post({t:'log',msg:'opening refund status'});return;}
     if(ready(8)){
       var tog=document.querySelector('[aria-label*="menu" i],button.navbar-toggler,.navbar-toggler,.hamburger,.menu-icon');
       if(!tog){
         tog=all('button,a').find(function(e){var r=e.getBoundingClientRect();return r.top<120&&r.right>window.innerWidth-90&&r.width<70;});
       }
       clickEl(tog); step='services'; act();
     }
     return;
   }
   if(step==='services'){
     var rl2=findByText('a,span,div,button,li','Know Your Refund Status');
     if(rl2&&vis(rl2)){clickEl(rl2);step='ay';act();return;}
     if(ready(6)){var sv=findByText('a,span,div,button,li','Services');clickEl(sv);step='refund';act();}
     return;
   }
   if(step==='refund'){
     if(ready(4)){
       var rl3=findByText('a,span,div,button,li','Know Your Refund Status');
       if(rl3){clickEl(rl3);step='ay';act();}
       else{post({t:'err',msg:'refund menu not found'});clearInterval(tmr);done=true;}
     }
     return;
   }
   if(step==='ay'){
     if(low.indexOf('assessment year')<0 && low.indexOf('know refund status')<0)return;
     var ns=findAYselect();
     if(ns){if(setNativeAY(ns)){step='submit';act();post({t:'log',msg:'AY selected'});}return;}
     if(ready(3)){
       if(clickAYoption()){step='submit';act();post({t:'log',msg:'AY selected'});}
       else{openAY();}
     }
     return;
   }
   if(step==='submit'){
     if(ready(3)){
       var sb=all('button,input[type=submit],a').find(function(e){var t=(e.innerText||e.value||'').trim().toLowerCase();return t==='submit'||(t.indexOf('submit')>-1&&t.indexOf('dashboard')<0);});
       if(sb){clickEl(sb);step='result';act();post({t:'log',msg:'submitted'});}
       else if(ready(20)){post({t:'err',msg:'submit button not found'});clearInterval(tmr);done=true;}
     }
     return;
   }
   if(step==='result'){
     if(low.indexOf('status of income tax refund')>-1 || low.indexOf('date of status')>-1){
       var st='', dt='';
       var tbls=all('table');
       for(var i=0;i<tbls.length;i++){
         var h=(tbls[i].innerText||'').toLowerCase();
         if(h.indexOf('status')>-1 && h.indexOf('date of status')>-1){
           var rows=tbls[i].querySelectorAll('tr');
           if(rows.length>=2){
             var cells=rows[1].querySelectorAll('td,th');
             if(cells.length>=1)st=(cells[0].innerText||'').trim();
             if(cells.length>=2)dt=(cells[1].innerText||'').trim();
           }
           break;
         }
       }
       if(!st){var idx=low.indexOf('your refund');if(idx>-1)st=T.substring(idx,idx+400);}
       st=st.replace(/\\s+/g,' ').trim(); dt=dt.replace(/\\s+/g,' ').trim();
       if(st){post({t:'status',status:st,date:dt});clearInterval(tmr);done=true;}
       else if(ready(25)){post({t:'err',msg:'result text empty'});clearInterval(tmr);done=true;}
     } else if(low.indexOf('no record')>-1){
       post({t:'status',status:T.replace(/\\s+/g,' ').slice(0,300),date:''});clearInterval(tmr);done=true;
     }
     return;
   }
   }catch(e){post({t:'err',msg:'js:'+(e&&e.message?e.message:e)});clearInterval(tmr);done=true;}
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
    Future.delayed(const Duration(milliseconds: 900), () {
      if (loggedIn && current >= 0 && autoMode) {
        setState(() => auto = 'Reading dashboard...');
        ctrl.runJavaScript(autoJs());
      }
    });
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
        if (mounted) setState(() => auto = (o['msg'] ?? '').toString());
        break;
      case 'dash':
        a.name = (o['name'] ?? '').toString();
        a.mobile = (o['mobile'] ?? '').toString();
        a.email = (o['email'] ?? '').toString();
        if (mounted) setState(() => auto = 'Dashboard: ${a.name}');
        await writeResults();
        break;
      case 'status':
        a.status = (o['status'] ?? '').toString();
        a.date = (o['date'] ?? '').toString();
        await writeResults();
        if (mounted) setState(() => auto = 'Saved. Next PAN...');
        await advance();
        break;
      case 'err':
        if (a.status.isEmpty) a.status = 'ISSUE: ${o['msg']}';
        await writeResults();
        if (mounted) {
          setState(() => auto =
              'Auto step failed (${o['msg']}). Finish manually then tap Capture, or Skip.');
          msg('Auto failed: ${o['msg']}');
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

  // Manual fallback capture (status only; name/mobile/email come from auto run).
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
    if (a.date.isEmpty) a.date = '';
    await writeResults();
    await advance();
  }

  // Build the result workbook fresh each time from in-memory data, so saving
  // after every PAN never loses earlier rows. One row per PAN, fixed columns.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refund Status Checker'),
        actions: [
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
              'Output columns written automatically: '
              'PAN | Name | Mobile | Email | Status | Date of Status.\n\n'
              'With Auto ON: after each login the app reads the dashboard, '
              'opens Services > Know Your Refund Status, picks AY 2026-27, '
              'submits, saves the result, logs out and moves to the next PAN.\n'
              'You still complete captcha / OTP during each login.\n\n'
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
                    ].where((e) => e.isNotEmpty).join(' — ')),
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
