import 'package:flutter/material.dart';
import 'package:uni_pool/constants.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url});
  final String url;

  @override
  State<WebViewScreen> createState() => _WebVieScreenState();
}

class _WebVieScreenState extends State<WebViewScreen> {
  late final WebViewController webViewController;
  String? code;

  @override
  void initState() {
    super.initState();
    webViewController = WebViewController()
      ..loadRequest(Uri.parse(widget.url))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            if (change.url == null) return;
            if (change.url!.startsWith('$authHost/cb')) {
              debugPrint(change.url);
              code = change.url!
                  .split('?')[1]
                  .split('&')
                  .firstWhere(
                    (element) => element.startsWith('code'),
                    orElse: () => '',
                  )
                  .split('=')[1];
              Navigator.pop(context, code);
            }
          },
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browser')),
      body: WebViewWidget(controller: webViewController),
    );
  }
}
