import 'dart:math';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url});
  final String url;

  @override
  State<WebViewScreen> createState() => _WebVieScreenState();
}

class _WebVieScreenState extends State<WebViewScreen> {
  late final WebViewController webViewController;

  @override
  void initState() {
    super.initState();
    webViewController = WebViewController()..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(
          context,
          http.Response(
            jsonEncode({
              'id': '0311900${(Random().nextInt(7) + 3)}',
              'name': 'Kalliopi Nasiou',
              'token': '123456789',
            }),
            200,
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Browser')),
        body: WebViewWidget(controller: webViewController),
      ),
    );
  }
}
