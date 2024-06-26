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
  void _socketLoginHandler(message) {
    final decoded = jsonDecode(message);
    final type = decoded['type'];
    final data = decoded['data'];
    debugPrint('received $type: $data');
    switch (type) {
      case typeLogin:
        if (data['id'] == null || data['full_name'] == null) break;
        context.read<User>().setUser(data);
        break;
      case typeDeleteUserPicture:
        ScaffoldMessenger.of(context).showSnackBar(snackBarNSFW);
        context.read<User>().setUserPicture(null);
        break;
      case typeDeleteCarPicture:
        ScaffoldMessenger.of(context).showSnackBar(snackBarNSFW);
        context.read<User>().setCarPicture(data.toString(), null);
        break;
    }
    setState(() {});
  }

  void _connectionHandler(message) async {
    if (!mounted) return;
    if (message == 'done' || message == 'error') {
      context.read<User>().setUser(null);
      if (SocketConnection.channel.closeCode == 4001) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarDuplicate);
      } else if (SocketConnection.channel.closeCode != 1000) {
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
    await SocketConnection.create(idToken);
    if (mounted && SocketConnection.connected.value != true) {
      ScaffoldMessenger.of(context).showSnackBar(snackBarAuthentication);
    }
  }

  void _setHandlers() {
    SocketConnection.receiveSubscription.onData(_socketLoginHandler);
    SocketConnection.connectionSubscription.onData(_connectionHandler);
  }

  @override
  void initState() {
    super.initState();
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
                  ValueListenableBuilder(
                    valueListenable: SocketConnection.connected,
                    builder: (context, value, child) => UserImageButton(
                      enablePress: value == true,
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
            ValueListenableBuilder(
              valueListenable: SocketConnection.connected,
              builder: (context, value, child) => TextButton(
                onPressed: value ?? true ? null : _connectToServer,
                child: Selector<User, String>(
                  selector: (_, user) => user.givenName,
                  builder: (_, givenName, __) => Text(
                    value == null || value && givenName.isEmpty
                        ? 'Connecting...'
                        : value
                            ? 'Logged in as $givenName'
                            : 'Log in',
                    style: const TextStyle(fontSize: 30),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: SocketConnection.connected,
              builder: (context, value, child) => Visibility(
                visible: value != true,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: const Text('You must be logged in to use the app'),
              ),
            ),
            const Spacer(flex: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ValueListenableBuilder(
                  valueListenable: SocketConnection.connected,
                  builder: (context, value, child) => SubtitledButton(
                    icon: const Icon(Icons.directions_car),
                    subtitle: const Text('I am a driver'),
                    onPressed: value == true
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DriverPage(),
                              ),
                            ).then((_) => _setHandlers())
                        : null,
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: SocketConnection.connected,
                  builder: (context, value, child) => SubtitledButton(
                    icon: const Icon(Icons.directions_walk),
                    subtitle: const Text('I am a passenger'),
                    onPressed: value == true
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PassengerPage(),
                              ),
                            ).then((_) => _setHandlers())
                        : null,
                  ),
                ),
              ],
            ),
            const Spacer(flex: 2),
            ValueListenableBuilder(
              valueListenable: SocketConnection.connected,
              builder: (context, value, child) => Visibility(
                visible: value == true,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: TextButton(
                  onPressed: () async {
                    bool reply = await signOutAlert(
                      context: context,
                      content: const SizedBox(),
                    );
                    if (reply) SocketConnection.connected.value = false;
                  },
                  child: const Text('Sign out', style: TextStyle(fontSize: 25)),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.all(12)),
          ],
        ),
      ),
    );
  }
}
