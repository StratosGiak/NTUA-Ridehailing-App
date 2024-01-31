import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/driver.dart';
import 'package:uni_pool/passenger.dart';
import 'package:uni_pool/settings.dart';
import 'package:uni_pool/sensitive_storage.dart';
import 'package:uni_pool/webview.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/providers.dart';
import 'package:http/http.dart' as http;

void main() async {
  debugPaintSizeEnabled = false;
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsHandler.initSettings();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (context) => UserProvider()),
      ],
      builder: (context, child) {
        return MaterialApp(
            title: 'Flutter Demo',
            theme: ThemeData(
              scaffoldBackgroundColor: const Color.fromARGB(255, 236, 242, 248),
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color.fromARGB(255, 110, 169, 236)),
              useMaterial3: true,
            ),
            home: const WelcomePage());
      },
    );
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  static const name = 'Welcome';
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum TypeOfUser { driver, passenger }

class _WelcomePageState extends State<WelcomePage> {
  bool _loggedIn = false;

  void socketLoginHandler(message) {
    final decoded = jsonDecode(message);
    final type = decoded['type'];
    final data = decoded['data'];
    debugPrint("received $data");
    if (type == typeLogin) {
      context.read<UserProvider>().setUser(User.userFromMap(data));
      SecureStorage.storeValueSecure(LoginInfo.id, data['id']);
      SecureStorage.storeValueSecure(LoginInfo.name, data['name']);
      SecureStorage.storeValueSecure(LoginInfo.token, data['token']);
      _loggedIn = true;
      mapUrl = data['mapUrl'];
    }
    setState(() {});
  }

  void _navigateToMain(typeOfUser) {
    switch (typeOfUser) {
      case TypeOfUser.driver:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => const DriverPage()));
        break;
      case TypeOfUser.passenger:
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => const PassengerPage()));
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
                )));
    debugPrint(response.body);
    if (response!.statusCode == 200) {
      final jsonResponse = jsonDecode(response!.body);
      SocketConnection.channel
          .add(jsonEncode({'type': typeLogin, 'data': jsonResponse}));
    }
  }

  Future<bool> _signOutAlert() async {
    bool? reply = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Really sign out?'),
        actions: [
          TextButton(
              onPressed: () {
                _loggedIn = false;
                SecureStorage.deleteAllSecure();
                SocketConnection.channel
                    .add(jsonEncode({'type': typeSignout, 'data': {}}));
                context.read<UserProvider>().setUser(User());
                Navigator.pop(context, true);
              },
              child: const Text('Yes')),
          TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'))
        ],
      ),
    );
    setState(() {});
    return reply ?? false;
  }

  Future<String?> _pickUserImage() async {
    try {
      final selection =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (selection == null) return null;
      CroppedFile? cropped = await ImageCropper().cropImage(
          sourcePath: selection.path,
          aspectRatioPresets: [CropAspectRatioPreset.square],
          uiSettings: [AndroidUiSettings()]);
      if (cropped == null) return null;
      return cropped.path;
    } on PlatformException catch (e) {
      debugPrint("Error: $e");
      return null;
    }
  }

  Future<String?> _uploadUserImage(String path, String? previousImage) async {
    if (previousImage != null) {
      SocketConnection.channel.add(jsonEncode({
        'type': typeDeletePicture,
        'data': {'picture': previousImage}
      }));
    }
    var request = http.MultipartRequest(
        'POST', Uri.parse('http://$mediaHost/media/images/users'));
    request.files.add(await http.MultipartFile.fromPath('file', path,
        contentType: MediaType('image', 'png')));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 200) {
      return response.body;
    }
    return null;
  }

  Future _showProfile() async {
    ValueNotifier<String?> imagePath = ValueNotifier(
        Provider.of<UserProvider>(context, listen: false).user.picture);
    final user = Provider.of<UserProvider>(context, listen: false).user;
    await showDialog(
      context: context,
      builder: (context) {
        return Center(
          child: Stack(
            alignment: const FractionalOffset(0.5, 0),
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    color: Colors.transparent,
                    height: 80,
                    width: 160,
                  ),
                  Container(
                    width: min(MediaQuery.sizeOf(context).width - 2 * 40, 350),
                    clipBehavior: Clip.hardEdge,
                    decoration:
                        BoxDecoration(borderRadius: BorderRadius.circular(24)),
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 34, 24, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const Padding(
                                padding: EdgeInsets.fromLTRB(24, 40, 24, 0)),
                            Text(
                              user.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 2.0)),
                            Text(
                              user.id,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0)),
                            RatingBarIndicator(
                              itemSize: 36.0,
                              rating: user.ratingsSum / user.ratingsCount,
                              itemBuilder: (context, index) => const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                              ),
                            ),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 5.0)),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6.0)),
                          ],
                        ),
                      ),
                    ),
                  )
                ],
              ),
              IconButton(
                onPressed: () async {
                  final newImage = await _pickUserImage();
                  if (newImage != null) {
                    imagePath.value =
                        await _uploadUserImage(newImage, imagePath.value);
                    if (!mounted) return;
                    SocketConnection.channel.add(jsonEncode({
                      'type': typeUpdateUserPicture,
                      'data': imagePath.value
                    }));
                    Provider.of<UserProvider>(context, listen: false)
                        .user
                        .picture = imagePath.value;
                    setState(() {});
                  }
                },
                iconSize: 40,
                icon: CircleAvatar(
                  radius: 70,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(70),
                      child: ValueListenableBuilder(
                          valueListenable: imagePath,
                          builder: (context, value, child) {
                            if (value != null) {
                              return CachedNetworkImage(
                                imageUrl:
                                    'http://$mediaHost/media/images/users/$value',
                                placeholder: (context, url) {
                                  return const CircularProgressIndicator();
                                },
                              );
                            }
                            return Stack(
                                alignment: AlignmentDirectional.center,
                                children: [
                                  Container(
                                      height: 160,
                                      width: 160,
                                      color: Colors.grey.shade50,
                                      child: Icon(
                                        Icons.add_photo_alternate,
                                        color: Colors.grey.shade600,
                                        size: 50,
                                      )),
                                  Positioned(
                                      bottom: 24,
                                      child: Text(
                                        'Add photo',
                                        style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 15),
                                      ))
                                ]);
                          })),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _checkLoggedIn() async {
    final String? savedID = await SecureStorage.readValueSecure(LoginInfo.id);
    final String? savedName =
        await SecureStorage.readValueSecure(LoginInfo.name);
    final String? savedToken =
        await SecureStorage.readValueSecure(LoginInfo.token);
    if (savedID != null && savedName != null && savedToken != null) {
      SocketConnection.channel.add(jsonEncode({
        'type': typeLogin,
        'data': {'id': savedID, 'name': savedName, 'token': savedToken}
      }));
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
    SocketConnection.receiveSubscription.onData(socketLoginHandler);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _getLocationPermission();
      if (await SocketConnection.create() == null) {}
      _checkLoggedIn();
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
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  icon: const Icon(
                    Icons.help,
                  ),
                  iconSize: 35,
                  onPressed: () {},
                ),
              ),
              const Spacer(
                flex: 1,
              ),
              IconButton(
                  onPressed: _loggedIn ? _showProfile : null,
                  icon: Provider.of<UserProvider>(context, listen: false)
                              .user
                              .picture !=
                          null
                      ? CachedNetworkImage(
                          imageUrl:
                              "http://$mediaHost/media/images/users/${Provider.of<UserProvider>(context, listen: false).user.picture}",
                          imageBuilder: (context, imageProvider) =>
                              CircleAvatar(
                            radius: 22.0,
                            backgroundImage: imageProvider,
                          ),
                          placeholder: (context, url) =>
                              const CircularProgressIndicator(),
                          errorWidget: (context, url, error) =>
                              const CircleAvatar(
                            radius: 22.0,
                            backgroundImage:
                                AssetImage("assets/images/blank_profile.png"),
                          ),
                        )
                      : const CircleAvatar(
                          radius: 22.0,
                          backgroundImage:
                              AssetImage('assets/images/blank_profile.png'),
                        )),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0))
            ]),
            const Spacer(
              flex: 10,
            ),
            const Text(
              'LOGO',
              style: TextStyle(fontSize: 50, fontWeight: FontWeight.w900),
            ),
            const Spacer(flex: 10),
            TextButton(
                onPressed: _loggedIn ? null : _logInRequest,
                child: Text(
                  _loggedIn
                      ? 'Logged in as ${Provider.of<UserProvider>(context).user.name}'
                      : 'Login',
                  style: const TextStyle(fontSize: 30),
                )),
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
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: _loggedIn
                          ? () {
                              _navigateToMain(TypeOfUser.driver);
                            }
                          : null,
                      icon: const Icon(Icons.directions_car),
                      iconSize: 70,
                      color: Theme.of(context).primaryColor,
                    ),
                    const Padding(padding: EdgeInsets.all(5)),
                    const Text('I am a driver'),
                  ],
                ),
                const Padding(padding: EdgeInsets.all(35)),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: _loggedIn
                          ? () {
                              _navigateToMain(TypeOfUser.passenger);
                            }
                          : null,
                      icon: const Icon(Icons.directions_walk),
                      iconSize: 70,
                      color: Theme.of(context).primaryColor,
                    ),
                    const Padding(padding: EdgeInsets.all(5)),
                    const Text('I am a passenger'),
                  ],
                ),
              ],
            ),
            const Spacer(
              flex: 20,
            ),
            Visibility(
              visible: _loggedIn,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(
                  onPressed: _signOutAlert,
                  child: const Text(
                    'Sign out',
                    style: TextStyle(fontSize: 25),
                  )),
            ),
            const Padding(padding: EdgeInsets.all(12))
          ],
        ),
      ),
    ));
  }
}
