import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/welcome.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => User(),
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          scaffoldBackgroundColor: const Color.fromARGB(255, 236, 242, 248),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 110, 169, 236),
          ),
          useMaterial3: true,
        ),
        home: const WelcomePage(),
      ),
    );
  }
}
