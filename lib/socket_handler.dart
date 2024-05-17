import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ntua_ridehailing/constants.dart';

class SocketConnection with ChangeNotifier {
  static final receiveController = StreamController<String>();
  static final receiveSubscription =
      receiveController.stream.listen((event) {});
  static final connectionController = StreamController<String>();
  static final connectionSubscription =
      connectionController.stream.listen((event) {});
  static late WebSocket channel;
  static ValueNotifier<bool?> connected = ValueNotifier(false);

  SocketConnection._();

  static Future<void> create(String token) async {
    SocketConnection._();
    connected.value = null;
    final result = await connect(token);
    if (result != null) {
      connected.value = true;
      channel = result;
      channel.listen(
        (data) => receiveController.add(data),
        onDone: () => _onDone(),
        onError: (error) => _onError(),
      );
    }
  }

  static Future<WebSocket?> connect(String token) async {
    try {
      return await WebSocket.connect(
        apiHost,
        headers: {'Sec-websocket-protocol': token},
      ).timeout(const Duration(seconds: 10));
    } catch (error) {
      await Future.delayed(const Duration(seconds: 2));
      connected.value = false;
      return null;
    }
  }

  static void _onDone() {
    connected.value = false;
    connectionController.sink.add('done');
  }

  static void _onError() {
    connected.value = false;
    connectionController.sink.add('error');
  }
}
