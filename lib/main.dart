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
  Acct(this.row, this.pan, this.pwd, this.status, this.date);
}

String _s(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value;
  return v.toString();
}

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
  bool loggedIn = false, injected = false;
  late final WebViewController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (current >= 0 && !injected && !loggedIn) {
            injected = true;
            final a = accts[current];
            ctrl.runJavaScript(fillJs(a.pan, a.pwd));
          }
        },
        onUrlChange: (c) {
          if (current >= 0 && (c.url ?? '').contains('dashboard') && !loggedIn) {
            setState(() => loggedIn = true);
          }
        },
      ));
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
      list.add(Acct(i, g(0).toUpperCase(), g(1), g(2), g(3)));
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
      msg('All done. Tap share icon to get the Excel.');
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
    await save(accts[current], tc.text);
    await advance();
  }

  Future<void> save(Acct a, String status) async {
    final d = DateTime.now();
    a.status = status;
    a.date =
        '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    final sheet = excel!.tables[excel!.tables.keys.first]!;
    sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: a.row),
        TextCellValue(a.status));
    sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: a.row),
        TextCellValue(a.date));
    final bytes = excel!.save();
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
        child: Wrap(spacing: 8, children: [
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
        ]),
      ),
      if (accts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'Excel columns (row 1 headers): PAN | Password | Status | Date.\n'
              'Captcha/OTP you complete in the app. Use only for your own or authorised accounts.'),
        ),
      Expanded(
        child: ListView(
          children: accts
              .map((a) => ListTile(
                    title: Text(a.pan),
                    subtitle: Text(a.status.isEmpty ? 'Pending' : a.status),
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
              ? 'Logged in. Open the refund / filed returns page, then tap Capture.'
              : 'Logging in automatically. Complete captcha / OTP if asked.'),
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
