import 'dart:async';
import 'dart:io';

import 'package:uni_pool/constants.dart';

class SocketConnection {
  static final receiveController = StreamController();
  static final receiveSubscription =
      receiveController.stream.listen((event) {});
  static late WebSocket channel;
  static int tries = 0;

  SocketConnection._internal();

  static Future<SocketConnection> create() async {
    SocketConnection connection = SocketConnection._internal();
    await initConnection();
    return connection;
  }

  static Future<void> initConnection() async {
    channel = await connect();
    broadcast();
  }

  static void broadcast() {
    channel.listen((data) {
      receiveController.add(data);
    }, onDone: () {
      _onDone();
    }, onError: (error) {
      initConnection();
    });
  }

  static connect() async {
    try {
      return await WebSocket.connect("ws://$apiHost/api");
    } catch (error) {
      if (tries > 5) {
        return null;
      }
      ++tries;
      await Future.delayed(const Duration(seconds: 2));
      return await connect();
    }
  }

  static void _onDone() {
    initConnection();
  }
}
