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
  bool _loggedIn = false;
  bool? _connected;

  void _socketLoginHandler(message) {
    final decoded = jsonDecode(message);
    final type = decoded['type'];
    final data = decoded['data'];
    debugPrint('received $data');
    switch (type) {
      case typeLogin:
        if (data['id'] == null || data['name'] == null) return;
        context.read<User>().setUser(data);
        SecureStorage.storeValueSecure(LoginInfo.id, data['id']);
        SecureStorage.storeValueSecure(LoginInfo.name, data['name']);
        SecureStorage.storeValueSecure(LoginInfo.token, data['token']);
        _loggedIn = true;
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
      _loggedIn = false;
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
    final response = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WebViewScreen(
          url:
              'https://google.com', //'https://login.ntua.gr/idp/profile/SAML2/Redirect/SSO'
        ),
      ),
    );
    debugPrint(response.body);
    if (response!.statusCode == 200) {
      final jsonResponse = jsonDecode(response!.body);
      SocketConnection.channel
          .add(jsonEncode({'type': typeLogin, 'data': jsonResponse}));
    }
  }

  void _connect() async {
    _connected = null;
    setState(() {});
    _connected = await SocketConnection.create();
    if (_connected!) await _checkLoggedIn();
    setState(() {});
  }

  Future<void> _checkLoggedIn() async {
    final String? savedID = await SecureStorage.readValueSecure(LoginInfo.id);
    final String? savedName =
        await SecureStorage.readValueSecure(LoginInfo.name);
    final String? savedToken =
        await SecureStorage.readValueSecure(LoginInfo.token);
    if (savedID != null && savedName != null && savedToken != null) {
      SocketConnection.channel.add(
        jsonEncode({
          'type': typeLogin,
          'data': {'id': savedID, 'name': savedName, 'token': savedToken},
        }),
      );
    }
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
    if (SocketConnection.connected) {
      _connected = true;
      _loggedIn = true;
    }
    SocketConnection.receiveSubscription.onData(_socketLoginHandler);
    SocketConnection.connectionSubscription.onData(_connectionHandler);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _getLocationPermission();
      if (!SocketConnection.connected) _connect();
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
                  UserImageButton(enablePress: _loggedIn, showSignout: false),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0)),
                ],
              ),
              const Spacer(flex: 10),
              const Text(
                'LOGO',
                style: TextStyle(fontSize: 50, fontWeight: FontWeight.w900),
              ),
              const Spacer(flex: 10),
              Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: _connected == null || _loggedIn
                        ? null
                        : _connected!
                            ? _logInRequest
                            : _connect,
                    child: Selector<User, String>(
                      selector: (_, user) => user.name,
                      builder: (_, name, __) {
                        return Text(
                          _connected == null
                              ? 'Connecting...'
                              : !_connected!
                                  ? 'Connection failed\nPress to retry'
                                  : _loggedIn
                                      ? 'Logged in as $name'
                                      : 'Login',
                          style: const TextStyle(fontSize: 30),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  );
                },
              ),
              Visibility(
                visible: !_loggedIn,
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
                    onPressed: _loggedIn
                        ? () => _navigateToMain(TypeOfUser.driver)
                        : null,
                  ),
                  const Padding(padding: EdgeInsets.all(35)),
                  SubtitledButton(
                    icon: const Icon(Icons.directions_walk),
                    subtitle: const Text('I am a passenger'),
                    onPressed: _loggedIn
                        ? () => _navigateToMain(TypeOfUser.passenger)
                        : null,
                  ),
                ],
              ),
              const Spacer(flex: 20),
              Visibility(
                visible: _loggedIn,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: TextButton(
                  onPressed: () async {
                    bool reply = await signOutAlert(
                      context: context,
                      content: const SizedBox(),
                    );
                    if (reply) setState(() => _loggedIn = false);
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
