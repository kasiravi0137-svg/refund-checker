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
 function setV(el,v){var s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;s.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}
 function clickBtn(t){var b=[].slice.call(document.querySelectorAll('button')).find(function(x){return x.innerText.trim().toLowerCase()===t&&!x.disabled});if(b){b.click();return true}return false}
 var step=0,n=0;
 var timer=setInterval(function(){
  if(++n>120){clearInterval(timer);return}
  if(step==0){var i=document.querySelector("input[name=panAdhaarUserId], input[type=text]");if(i){setV(i,P);step=1;setTimeout(function(){clickBtn('continue')},600)}}
  else if(step==1){var w=document.querySelector("input[type=password]");if(w){setV(w,W);var c=document.querySelector("input[type=checkbox]");if(c&&!c.checked)c.click();step=2}}
  else{clearInterval(timer)}
 },500);
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
  List
