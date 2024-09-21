import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ntua_ridehailing/constants.dart';

class SocketConnection with ChangeNotifier {
  final receiveController = StreamController<String>();
  final connectionController = StreamController<String>();
  late final StreamSubscription<String> receiveSubscription;
  late final StreamSubscription<String> connectionSubscription;
  late WebSocket channel;
  SocketStatus status = SocketStatus.disconnected;

  SocketConnection() {
    receiveSubscription = receiveController.stream.listen((event) {});
    connectionSubscription = connectionController.stream.listen((event) {});
  }

  Future<void> create(String token) async {
    setStatus(SocketStatus.connecting);
    final result = await connect(token);
    if (result != null) {
      setStatus(SocketStatus.connected);
      channel = result;
      channel.listen(
        (data) => receiveController.add(data),
        onDone: () => _onDone(),
        onError: (error) => _onError(error),
      );
    }
  }

  Future<WebSocket?> connect(String token) async {
    try {
      return await WebSocket.connect(
        apiHost,
        headers: {'Sec-websocket-protocol': token},
      ).timeout(const Duration(seconds: 10));
    } catch (error) {
      await Future.delayed(const Duration(seconds: 2));
      setStatus(SocketStatus.disconnected);
      return null;
    }
  }

  void send(dynamic data) {
    channel.add(data);
  }

  void _onDone() {
    setStatus(SocketStatus.disconnected);
    connectionController.sink.add('done');
  }

  void _onError(error) {
    setStatus(SocketStatus.disconnected);
    connectionController.sink.add('error');
  }

  void setStatus(SocketStatus newStatus) {
    status = newStatus;
    notifyListeners();
  }
}
