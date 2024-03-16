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
  static int tries = 0;

  SocketConnection._internal();

  static Future<bool> create() async {
    SocketConnection._internal();
    return await initConnection();
  }

  static Future<bool> initConnection() async {
    final result = await connect();
    if (result != null) {
      channel = result;
      broadcast();
      return true;
    }
    tries = 0;
    return false;
  }

  static void broadcast() {
    channel.listen(
      (data) => receiveController.add(data),
      onDone: () => _onDone(),
      onError: (error) => _onError(),
    );
  }

  static Future<WebSocket?> connect() async {
    try {
      return await WebSocket.connect(apiHost)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      ++tries;
      if (tries > 2) return null;
      debugPrint('CONNECTION TO SERVER FAILED. TRYING TO RECONNECT... $tries');
      await Future.delayed(const Duration(seconds: 2));
      return await connect();
    }
  }

  static void _onDone() {
    connectionController.sink.add('done');
  }

  static void _onError() {
    connectionController.sink.add('error');
  }
}
