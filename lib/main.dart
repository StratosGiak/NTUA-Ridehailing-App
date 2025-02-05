import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ntua_ridehailing/socket_handler.dart';
import 'package:provider/provider.dart';
import 'package:ntua_ridehailing/providers.dart';
import 'package:ntua_ridehailing/welcome.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitDown, DeviceOrientation.portraitUp],
  );
  runApp(const RidehailingApp());
}

class RidehailingApp extends StatelessWidget {
  const RidehailingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => User()),
        ChangeNotifierProvider(create: (_) => SocketConnection()),
      ],
      child: MaterialApp(
        title: 'NTUA-Ridehailing',
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
        ),
        home: const WelcomePage(),
      ),
    );
  }
}
