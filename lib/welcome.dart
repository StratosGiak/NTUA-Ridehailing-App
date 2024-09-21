import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:ntua_ridehailing/constants.dart';
import 'package:ntua_ridehailing/driver.dart';
import 'package:ntua_ridehailing/passenger.dart';
import 'package:ntua_ridehailing/utilities.dart';
import 'package:ntua_ridehailing/socket_handler.dart';
import 'package:ntua_ridehailing/providers.dart';
import 'package:ntua_ridehailing/authenticator.dart';
import 'package:ntua_ridehailing/widgets/common_widgets.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  late final SocketConnection socketConnection;
  late final User user;

  void _socketLoginHandler(message) {
    final decoded = jsonDecode(message);
    final type = decoded['type'];
    final data = decoded['data'];
    debugPrint('received $type: $data');
    switch (type) {
      case typeLogin:
        if (data['id'] == null || data['full_name'] == null) break;
        user.setUser(data);
        break;
      case typeDeleteUserPicture:
        ScaffoldMessenger.of(context).showSnackBar(snackBarNSFW);
        user.setUserPicture(null);
        break;
      case typeDeleteCarPicture:
        ScaffoldMessenger.of(context).showSnackBar(snackBarNSFW);
        user.setCarPicture(data.toString(), null);
        break;
    }
    setState(() {});
  }

  void _connectionHandler(message) async {
    if (!mounted) return;
    if (message == 'done' || message == 'error') {
      user.setUser(null);
      Navigator.popUntil(context, (route) => route.isFirst);
      if (socketConnection.channel.closeCode == 4001) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarDuplicate);
      } else if (socketConnection.channel.closeCode != 1000) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarConnectionLost);
      }
    }
  }

  void _connectToServer() async {
    final locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied) {
      if (!mounted) return;
      locationPermissionAlert(
        context: context,
        permission: locationPermission,
      );
      return;
    }
    final idToken = await Authenticator.authenticate();
    if (idToken == null) return;
    await socketConnection.create(idToken);
    if (mounted && socketConnection.status != SocketStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(snackBarAuthentication);
    }
  }

  void _setHandlers() {
    socketConnection.receiveSubscription.onData(_socketLoginHandler);
    socketConnection.connectionSubscription.onData(_connectionHandler);
  }

  @override
  void initState() {
    super.initState();
    user = context.read<User>();
    socketConnection = context.read<SocketConnection>();
    _setHandlers();
    Geolocator.requestPermission();
    //_connectToServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.help),
                    iconSize: 35,
                    onPressed: () => (),
                  ),
                  Consumer<SocketConnection>(
                    builder: (context, socket, child) => UserAvatarButton(
                      enablePress: socket.status == SocketStatus.connected,
                      showSignout: false,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 1),
            const Text(
              'LOGO',
              style: TextStyle(fontSize: 50, fontWeight: FontWeight.w900),
            ),
            const Spacer(flex: 1),
            Consumer2<SocketConnection, User>(
              builder: (context, socket, user, child) {
                String displayText;
                if (socket.status == SocketStatus.disconnected) {
                  displayText = 'Log in';
                } else if (socket.status == SocketStatus.connecting ||
                    user.givenName.isEmpty) {
                  displayText = 'Connecting...';
                } else {
                  displayText = 'Logged in as ${user.givenName}';
                }
                return TextButton(
                  onPressed: socket.status == SocketStatus.disconnected
                      ? _connectToServer
                      : null,
                  child: Text(
                    displayText,
                    style: const TextStyle(fontSize: 30),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
            Consumer<SocketConnection>(
              builder: (context, socket, child) => Visibility(
                visible: socket.status != SocketStatus.connected,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: child!,
              ),
              child: const Text('You must be logged in to use the app'),
            ),
            const Spacer(flex: 1),
            Consumer<SocketConnection>(
              builder: (context, socket, child) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SubtitledButton(
                    icon: const Icon(Icons.directions_car),
                    subtitle: const Text('I am a driver'),
                    onPressed: socket.status == SocketStatus.connected
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DriverPage(),
                              ),
                            );
                            _setHandlers();
                          }
                        : null,
                  ),
                  SubtitledButton(
                    icon: const Icon(Icons.directions_walk),
                    subtitle: const Text('I am a passenger'),
                    onPressed: socket.status == SocketStatus.connected
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PassengerPage(),
                              ),
                            );
                            _setHandlers();
                          }
                        : null,
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Consumer<SocketConnection>(
              builder: (context, socket, child) => Visibility(
                visible: socket.status == SocketStatus.connected,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: child!,
              ),
              child: TextButton(
                onPressed: () async {
                  final socket = socketConnection;
                  final reply = await signOutAlert(context: context);
                  if (reply) socket.setStatus(SocketStatus.disconnected);
                },
                child: const Text('Sign out', style: TextStyle(fontSize: 25)),
              ),
            ),
            const Padding(padding: EdgeInsets.all(12)),
          ],
        ),
      ),
    );
  }
}
