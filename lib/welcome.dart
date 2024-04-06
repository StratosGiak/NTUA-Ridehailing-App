import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/driver.dart';
import 'package:uni_pool/passenger.dart';
import 'package:uni_pool/sensitive_storage.dart';
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/webview.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/widgets/common_widgets.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  static const name = 'Welcome';
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool? _connected = false;

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
      _connected = false;
      if (SocketConnection.channel.closeCode != 1000) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarConnectionLost);
      }
      setState(() {});
    }
  }

  void _navigateToMain(typeOfUser) {
    switch (typeOfUser) {
      case TypeOfUser.driver:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DriverPage()),
        );
        break;
      case TypeOfUser.passenger:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PassengerPage()),
        );
        break;
      default:
    }
  }

  void _logInRequest() async {
    final code = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WebViewScreen(url: authHost),
      ),
    );
    debugPrint(code);
    if (code == null) return;
    setState(() => _connected = null);
    _connected = await SocketConnection.create(code);
    setState(() {});
  }

  void _getLocationPermission() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      _getLocationPermission();
    }
  }

  @override
  void initState() {
    super.initState();
    if (SocketConnection.connected) _connected = true;
    SocketConnection.receiveSubscription.onData(_socketLoginHandler);
    SocketConnection.connectionSubscription.onData(_connectionHandler);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _getLocationPermission();
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
                  UserImageButton(
                    enablePress: _connected ?? false,
                    showSignout: false,
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
              TextButton(
                onPressed: _connected ?? true ? null : _logInRequest,
                child: Selector<User, String>(
                  selector: (_, user) => user.name,
                  builder: (_, name, __) => Text(
                    _connected == null
                        ? 'Connecting...'
                        : _connected!
                            ? 'Logged in as\n$name'
                            : 'Log in',
                    style: const TextStyle(fontSize: 30),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Visibility(
                visible: !(_connected ?? false),
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: const Text('You must be logged in to use the app'),
              ),
              const Spacer(flex: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SubtitledButton(
                    icon: const Icon(Icons.directions_car),
                    subtitle: const Text('I am a driver'),
                    onPressed: _connected ?? false
                        ? () => _navigateToMain(TypeOfUser.driver)
                        : null,
                  ),
                  const Padding(padding: EdgeInsets.all(35)),
                  SubtitledButton(
                    icon: const Icon(Icons.directions_walk),
                    subtitle: const Text('I am a passenger'),
                    onPressed: _connected ?? false
                        ? () => _navigateToMain(TypeOfUser.passenger)
                        : null,
                  ),
                ],
              ),
              const Spacer(flex: 20),
              Visibility(
                visible: _connected ?? false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: TextButton(
                  onPressed: () async {
                    bool reply = await signOutAlert(
                      context: context,
                      content: const SizedBox(),
                    );
                    if (reply) setState(() => _connected = false);
                  },
                  child: const Text('Sign out', style: TextStyle(fontSize: 25)),
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
