import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uni_pool/constants.dart';

class SocketConnection {
  static final receiveController = StreamController();
  static final receiveSubscription =
      receiveController.stream.listen((event) {});
  static final connectionController = StreamController();
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
    channel.listen((data) {
      receiveController.add(data);
    }, onDone: () {
      _onDone();
    }, onError: (error) {
      _onError();
    });
  }

  static Future<WebSocket?> connect() async {
    try {
      return await WebSocket.connect("ws://$apiHost/api");
    } catch (error) {
      if (tries > 4) {
        return null;
      }
      ++tries;
      debugPrint("CONNECTION TO SERVER FAILED. TRYING TO RECONNECT... $tries");
      await Future.delayed(const Duration(seconds: 2));
      return await connect();
    }
  }

  static void _onDone() {
    connectionController.sink.add("done");
  }

  static void _onError() {
    connectionController.sink.add("error");
  }
}
