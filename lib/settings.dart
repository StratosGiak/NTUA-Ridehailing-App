import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Color> colors = [
  Colors.blue,
  Colors.orange,
  Colors.yellow,
  Colors.green,
  Colors.red,
  Colors.lightGreen,
  Colors.indigo,
  Colors.pink,
  Colors.teal,
  Colors.cyan
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  static const name = "Settings";
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int _test1;

  Future<void> _saveTestValue() async {
    SettingsHandler.setSetting(Settings.test1, _test1);
  }

  void _updateTestValue() {
    ++_test1;
    setState(() {});
  }

  void _resetTestValue() {
    _test1 = 0;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _test1 = SettingsHandler.getSetting(Settings.test1) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
              onPressed: () {
                _saveTestValue();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check))
        ],
      ),
      body: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('I am $_test1'),
          const Padding(padding: EdgeInsets.all(10)),
          ElevatedButton(
            onPressed: _updateTestValue,
            child: const Text('Increment'),
          ),
          ElevatedButton(
            onPressed: _resetTestValue,
            child: const Text('Clear'),
          )
        ],
      )),
    );
  }
}

enum Settings {
  test1(int),
  test2(String);

  final Type type;
  const Settings(this.type);
}

class SettingsHandler {
  static late SharedPreferences settings;

  static initSettings() async {
    settings = await SharedPreferences.getInstance();
  }

  static dynamic getSetting(Settings setting) {
    switch (setting.type) {
      case int:
        return settings.getInt(setting.name);
      case String:
        return settings.getString(setting.name);
      case bool:
        return settings.getBool(setting.name);
      case double:
        return settings.getDouble(setting.name);
    }
    return null;
  }

  static Future<bool> setSetting(Settings setting, dynamic val) {
    if (val.runtimeType != setting.type) {
      throw TypeError();
    }
    switch (setting.type) {
      case int:
        return settings.setInt(setting.name, val);
      case String:
        return settings.setString(setting.name, val);
      case bool:
        return settings.setBool(setting.name, val);
      case double:
        return settings.setDouble(setting.name, val);
      default:
        throw UnimplementedError();
    }
  }
}
