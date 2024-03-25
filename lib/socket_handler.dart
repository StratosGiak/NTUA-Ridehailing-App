import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uni_pool/constants.dart';

class SocketConnection {
  static final receiveController = StreamController<String>();
  static final receiveSubscription =
      receiveController.stream.listen((event) {});
  static final connectionController = StreamController<String>();
  static final connectionSubscription =
      connectionController.stream.listen((event) {});
  static late WebSocket channel;
  static bool connected = false;
  static int tries = 0;

  SocketConnection._internal();

  static Future<bool> create() async {
    SocketConnection._internal();
    final result = await connect();
    if (result != null) {
      connected = true;
      channel = result;
      channel.listen(
        (data) => receiveController.add(data),
        onDone: () => _onDone(),
        onError: (error) => _onError(),
      );
      return true;
    }
    tries = 0;
    return false;
  }

  static Future<WebSocket?> connect() async {
    try {
      return await WebSocket.connect(apiHost)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      ++tries;
      if (tries > 3) return null;
      debugPrint('CONNECTION TO SERVER FAILED. TRYING TO RECONNECT... $tries');
      await Future.delayed(const Duration(seconds: 2));
      return await connect();
    }
  }

  static void _onDone() {
    connected = false;
    connectionController.sink.add('done');
  }

  static void _onError() {
    connected = false;
    connectionController.sink.add('error');
  }
}
