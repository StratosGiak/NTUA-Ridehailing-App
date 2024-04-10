import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/driver.dart';
import 'package:uni_pool/passenger.dart';
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/authenticator.dart';
import 'package:uni_pool/widgets/common_widgets.dart';

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
    debugPrint('received $data');
    switch (type) {
      case typeLogin:
        if (data['id'] == null || data['name'] == null) return;
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
      default:
        debugPrint('Invalid type: $type');
        break;
    }
    setState(() {});
  }

  void _connectionHandler(message) async {
    if (!mounted) return;
    if (message == 'done' || message == 'error') {
      context.read<User>().setUser(null);
      if (SocketConnection.channel.closeCode == 4000) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarAuth);
      } else if (SocketConnection.channel.closeCode == 4001) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarDuplicate);
      } else if (SocketConnection.channel.closeCode != 1000) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarConnectionLost);
      }
    }
  }

  void _logInRequest() async {
    final idToken = await Authenticator.authenticate();
    if (idToken == null) return;
    await SocketConnection.create(idToken);
  }

  void _getLocationPermission() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      _getLocationPermission();
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _getLocationPermission();
      _logInRequest();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Padding(padding: EdgeInsets.symmetric(vertical: 2.0)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(Icons.help),
                      iconSize: 35,
                      onPressed: () => (),
                    ),
                  ),
                  const Spacer(flex: 1),
                  ValueListenableBuilder(
                    valueListenable: SocketConnection.connected,
                    builder: (context, value, child) => UserImageButton(
                      enablePress: value ?? false,
                      showSignout: false,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0)),
                ],
              ),
              const Spacer(flex: 10),
              const Text(
                'LOGO',
                style: TextStyle(fontSize: 50, fontWeight: FontWeight.w900),
              ),
              const Spacer(flex: 10),
              ValueListenableBuilder(
                valueListenable: SocketConnection.connected,
                builder: (context, value, child) => TextButton(
                  onPressed: value ?? true ? null : _logInRequest,
                  child: Selector<User, String>(
                    selector: (_, user) => user.name,
                    builder: (_, name, __) => Text(
                      value == null
                          ? 'Connecting...'
                          : value
                              ? 'Logged in as\n$name'
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
                  visible: !(value ?? false),
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: const Text('You must be logged in to use the app'),
                ),
              ),
              const Spacer(flex: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ValueListenableBuilder(
                    valueListenable: SocketConnection.connected,
                    builder: (context, value, child) => SubtitledButton(
                      icon: const Icon(Icons.directions_car),
                      subtitle: const Text('I am a driver'),
                      onPressed: value ?? false
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const DriverPage(),
                                ),
                              ).then((_) => _setHandlers())
                          : null,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.all(35)),
                  ValueListenableBuilder(
                    valueListenable: SocketConnection.connected,
                    builder: (context, value, child) => SubtitledButton(
                      icon: const Icon(Icons.directions_walk),
                      subtitle: const Text('I am a passenger'),
                      onPressed: value ?? false
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
              const Spacer(flex: 20),
              ValueListenableBuilder(
                valueListenable: SocketConnection.connected,
                builder: (context, value, child) => Visibility(
                  visible: value ?? false,
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
                    child:
                        const Text('Sign out', style: TextStyle(fontSize: 25)),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.all(12)),
            ],
          ),
        ),
      ),
    );
  }
}
