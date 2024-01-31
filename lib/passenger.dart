import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/driver.dart';
import 'package:uni_pool/main.dart';
import 'package:uni_pool/settings.dart';
import 'package:uni_pool/sensitive_storage.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import "package:latlong2/latlong.dart";

class PassengerPage extends StatefulWidget {
  const PassengerPage({super.key});
  static const name = "Passenger";
  @override
  State<PassengerPage> createState() => _PassengerPageState();
}

enum PopUpOptions { settings, signout }

class _PassengerPageState extends State<PassengerPage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? driver;
  late StreamSubscription<Position> positionStream;
  ListQueue<LatLng> driverPositions = ListQueue();
  final mapController = MapController();
  Position? coordinates;
  bool inRadius = false;
  bool requestTimeout = false;
  bool driverRefused = false;
  bool driverArrived = false;
  bool showArrived = false;
  bool followDriver = true;
  Timer? arrivedTimer;
  Timer? refusedTimer;

  void socketPassengerHandler(message) async {
    final decoded = jsonDecode(message);
    final type = decoded['type'];
    final data = decoded['data'];
    debugPrint("received $type : $data");
    if (type == typeGetDriver) {
      if (driver == null) return;
      driver = data;
      if (driver == null) {
        HapticFeedback.heavyImpact();
        driver = null;
        driverArrived = false;
        driverPositions.clear();
        driverRefused = true;
      } else {
        if (driverArrived) {
          if (Geolocator.distanceBetween(
                  driver!['coords']['latitude'],
                  driver!['coords']['longitude'],
                  coordinates!.latitude,
                  coordinates!.longitude) >
              500) {
            HapticFeedback.heavyImpact();
            driver = null;
            driverArrived = false;
            driverPositions.clear();
            driverRefused = true;
            SocketConnection.channel
                .add(jsonEncode({'type': typeOutOfRange, 'data': {}}));
            setState(() {});
            return;
          }
          if (followDriver) {
            _moveCamera(
                mapController,
                LatLng(driver!['coords']['latitude'],
                    driver!['coords']['longitude']),
                mapController.camera.zoom);
          }
        }
        if (driverPositions.length > 50) {
          driverPositions.removeFirst();
        }
        final pos = LatLng(
            driver!['coords']['latitude'], driver!['coords']['longitude']);
        if (Geolocator.distanceBetween(pos.latitude, pos.longitude,
                    busStop.latitude, busStop.longitude) <
                100 &&
            !driverArrived) {
          _moveCamera(mapController, pos, 15.5);
          driverArrived = true;
          showArrived = true;
          arrivedTimer = Timer(const Duration(seconds: 5), () {
            showArrived = false;
            setState(() {});
          });
          HapticFeedback.heavyImpact();
        }
        if (driverPositions.isEmpty || driverPositions.last != pos) {
          driverPositions.addLast(pos);
        }
      }
    }
    if (type == typePingPassengers) {
      HapticFeedback.heavyImpact();
      _acceptDriver();
    }
    if (type == typePingDriver) {
      if (data == null) {
        requestTimeout = true;
      }
      driver = data;
    }
    if (type == typeArrivedDestination) {
      HapticFeedback.heavyImpact();
      _moveCamera(mapController,
          LatLng(coordinates!.latitude, coordinates!.longitude), 15.5);
      final double rating = await _arrivedDialog();
      if (!mounted) return;
      SocketConnection.channel.add(jsonEncode({
        'type': typeSendRatings,
        'data': {
          'users': [driver!['id']],
          'ratings': [rating]
        }
      }));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  Future _arrivedDialog() async {
    ValueNotifier<double> rating = ValueNotifier(0);
    Widget ratingBar = ValueListenableBuilder(
        valueListenable: rating,
        builder: (context, value, child) {
          return Row(
            children: [
              RatingBar.builder(
                  itemSize: 36,
                  glow: false,
                  initialRating: value,
                  minRating: 1,
                  itemBuilder: (context, index) => const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                      ),
                  onRatingUpdate: (value) {
                    rating.value = value;
                  }),
              Visibility(
                visible: value != 0,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: IconButton(
                    onPressed: () {
                      rating.value = 0;
                    },
                    iconSize: 30,
                    icon: const Icon(Icons.close)),
              ),
            ],
          );
        });
    await showDialog<List<double>>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 30.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(padding: EdgeInsets.symmetric(vertical: 14.0)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    "You have reached your destination!",
                    style:
                        TextStyle(fontSize: 26.0, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 6.0)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    "Please rate your experience with the driver (optional)",
                    style: TextStyle(fontSize: 16.0),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
                ListTile(
                  title: Text("${driver!['name']}"),
                  leading: driver!['picture'] != null
                      ? CachedNetworkImage(
                          imageUrl:
                              "http://$mediaHost/media/images/users/${driver!['picture']}",
                          imageBuilder: (context, imageProvider) =>
                              CircleAvatar(
                            radius: 26.0,
                            backgroundImage: imageProvider,
                          ),
                          placeholder: (context, url) =>
                              const CircularProgressIndicator(),
                          errorWidget: (context, url, error) =>
                              const CircleAvatar(
                            radius: 26.0,
                            backgroundImage:
                                AssetImage("assets/images/blank_profile.png"),
                          ),
                        )
                      : const CircleAvatar(
                          radius: 26.0,
                          backgroundImage:
                              AssetImage("assets/images/blank_profile.png"),
                        ),
                  subtitle: ratingBar,
                ),
                Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Submit",
                            style: TextStyle(fontSize: 18.0),
                          )),
                    )),
              ],
            ),
          );
        });
    return rating.value;
  }

  void _sendPassenger() async {
    if (!inRadius) {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        return;
      }
      coordinates = pos;
      if (Geolocator.distanceBetween(coordinates!.latitude,
              coordinates!.longitude, busStop.latitude, busStop.longitude) >
          100) {
        return;
      }
      inRadius = true;
      SocketConnection.channel.add(jsonEncode({
        'type': typeNewPassenger,
        'data': {
          'coords': {
            "latitude": coordinates!.latitude,
            "longitude": coordinates!.longitude
          },
          'timestamp': coordinates!.timestamp!.toIso8601String(),
        }
      }));
    } else {
      SocketConnection.channel.add(jsonEncode({
        'type': typeUpdatePassenger,
        'data': {
          'coords': {
            "latitude": coordinates!.latitude,
            "longitude": coordinates!.longitude
          },
        }
      }));
    }
    setState(() {});
  }

  void _acceptDriver() async {
    int initalSeconds = 20;
    ValueNotifier<int> remainingSeconds = ValueNotifier(initalSeconds);
    Timer timerDisplay = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 0) {
        --remainingSeconds.value;
      } else {
        timer.cancel();
      }
    });
    Timer timerDismiss = Timer(Duration(seconds: initalSeconds), () {
      Navigator.of(context, rootNavigator: true).pop(false);
    });
    bool? reply = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(padding: EdgeInsets.all(5.0)),
                  const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Text(
                      "A driver is available. Accept them?",
                      style: TextStyle(
                          fontSize: 25.0, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ValueListenableBuilder(
                      valueListenable: remainingSeconds,
                      builder: (context, value, child) {
                        return Text(
                          "$value",
                          style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 30.0,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        );
                      }),
                  const Padding(padding: EdgeInsets.all(10.0)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filled(
                        onPressed: () {
                          Navigator.pop(context, true);
                        },
                        style: ButtonStyle(
                            backgroundColor: MaterialStatePropertyAll(
                                Colors.green.shade300)),
                        iconSize: 55.0,
                        icon: const Icon(Icons.check_rounded),
                      ),
                      IconButton.filled(
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        style: ButtonStyle(
                            backgroundColor:
                                MaterialStatePropertyAll(Colors.red.shade300)),
                        iconSize: 55.0,
                        icon: const Icon(Icons.close_rounded),
                      )
                    ],
                  ),
                  const Padding(padding: EdgeInsets.all(10.0))
                ],
              ));
        }).then((value) {
      timerDisplay.cancel();
      timerDismiss.cancel();
      return value;
    });
    reply ??= false;
    if (reply) {
      SocketConnection.channel
          .add(jsonEncode({'type': typePingDriver, 'data': true}));
    } else {
      if (remainingSeconds.value == 0) {
        requestTimeout = true;
      } else {
        SocketConnection.channel
            .add(jsonEncode({'type': typeStopPassenger, 'data': {}}));
        refusedTimer = Timer(const Duration(seconds: 30), () {
          SocketConnection.channel.add(jsonEncode({
            'type': typeNewPassenger,
            'data': {
              'coords': {
                "latitude": coordinates!.latitude,
                "longitude": coordinates!.longitude
              },
              'timestamp': coordinates!.timestamp!.toIso8601String(),
            }
          }));
        });
      }
      SocketConnection.channel
          .add(jsonEncode({'type': typePingDriver, 'data': false}));
      setState(() {});
    }
  }

  Widget _showDriver(Map<String, dynamic>? driver) {
    if (driver == null) {
      return const Text('Driver not found');
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListTile(
        onTap: () {
          followDriver = true;
          _moveCamera(
              mapController,
              LatLng(
                  driver['coords']['latitude'], driver['coords']['longitude']),
              16);
        },
        onLongPress: () {},
        leading: CircleAvatar(
          radius: 25.0,
          child: InkWell(
            onTap: () {
              _showDriverPictures();
            },
            onLongPress: () {
              _showDriverPictures();
            },
            child: Ink(
              color: Colors.black,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25.0),
                child: driver['picture'] != null
                    ? CachedNetworkImage(
                        imageUrl:
                            'http://$mediaHost/media/images/users/${driver['picture']}',
                        placeholder: (context, url) =>
                            Image.asset("assets/images/blank_profile.png"),
                        errorWidget: (context, url, error) =>
                            Image.asset("assets/images/blank_profile.png"),
                      )
                    : Image.asset("assets/images/blank_profile.png"),
              ),
            ),
          ),
        ),
        tileColor: Colors.lightBlue,
        title: Text("${driver['name']}"),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Model: ${driver['car']['model']}"),
            Text("License plate: ${driver['car']['license']}"),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Color:'),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4.0)),
                driver['car']['color'] != null
                    ? ColorIndicator(
                        hasBorder: true,
                        height: 16,
                        width: 50,
                        color: Color(int.parse(driver['car']['color'])),
                      )
                    : const Text('N/A')
              ],
            ),
            Row(
              children: [
                const Text("Rating:"),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 3.0)),
                driver['ratings_count'] > 3
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RatingBarIndicator(
                            rating:
                                driver['ratings_sum'] / driver['ratings_count'],
                            itemSize: 22.0,
                            itemBuilder: (context, index) => const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                            ),
                          ),
                          const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3.0)),
                          Text("(${driver['ratings_count']})"),
                        ],
                      )
                    : const Text("N/A"),
              ],
            ),
            // Text("Distance: ${(Geolocator.distanceBetween(
            //       driver["coords"]["latitude"],
            //       driver["coords"]["longitude"],
            //       busStop.latitude,
            //       busStop.longitude,
            //     ) / 25).round() * 25}m")
          ],
        ),
      ),
    );
  }

  void _showDriverPictures() {
    if (driver == null) return;
    List<Widget> images = [];
    if (driver!['picture'] != null) {
      images.add(Padding(
        padding: const EdgeInsets.all(8.0),
        child: FittedBox(
          child: CachedNetworkImage(
            imageUrl:
                'http://$mediaHost/media/images/users/${driver!['picture']}',
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      ));
    }
    if (driver!['car']['picture'] != null) {
      images.add(Padding(
        padding: const EdgeInsets.all(8.0),
        child: FittedBox(
          child: CachedNetworkImage(
            imageUrl:
                'http://$mediaHost/media/images/cars/${driver!['car']['picture']}',
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      ));
    }
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return Dialog(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: ConstrainedBox(
                  constraints: BoxConstraints.tight(
                      Size.square(MediaQuery.of(context).size.width)),
                  child: PageView(
                    children: images,
                  )));
        });
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

  List<Marker> _driverToMarker() {
    if (driver == null) return [];
    return [
      Marker(
          height: 22,
          width: 22,
          point: LatLng(
              driver!["coords"]["latitude"], driver!["coords"]["longitude"]),
          child: Stack(children: [
            Container(
              decoration: const BoxDecoration(shape: BoxShape.circle),
            ),
            Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: driver!['car']['color'] != null
                      ? Color(int.parse(driver!['car']['color']))
                      : colors[
                          int.parse(driver!['id'][driver!['id'].length - 1])],
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(spreadRadius: 0.1, blurRadius: 3.5)
                  ]),
            ),
          ]))
    ];
  }

  void _moveCamera(MapController mapController, LatLng dest, double zoom) {
    final camera = mapController.camera;
    final latTween =
        Tween<double>(begin: camera.center.latitude, end: dest.latitude);
    final lngTween =
        Tween<double>(begin: camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);
    final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);
    controller.addListener(() {
      mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation));
    });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      } else if (status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });
    controller.forward();
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
          initialCenter: const LatLng(37.9923, 23.7764),
          initialZoom: 14,
          minZoom: 14,
          maxZoom: 16,
          cameraConstraint: CameraConstraint.containCenter(
              bounds: LatLngBounds.fromPoints(const [
            LatLng(38.0043, 23.7532),
            LatLng(37.9746, 23.7532),
            LatLng(37.9746, 23.7994),
            LatLng(38.0043, 23.7994)
          ])),
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all - InteractiveFlag.rotate),
          onPositionChanged: (position, hasGesture) {
            if (hasGesture) {
              followDriver = false;
            }
          }),
      children: [
        TileLayer(
          urlTemplate: mapUrl,
        ),
        PolylineLayer(polylines: [
          Polyline(
              points: driverPositions.toList(),
              color: Colors.lightBlue.shade400.withAlpha(200),
              strokeWidth: 6),
        ]),
        MarkerLayer(markers: _driverToMarker()),
        coordinates == null
            ? Container()
            : MarkerLayer(markers: [
                Marker(
                    point:
                        LatLng(coordinates!.latitude, coordinates!.longitude),
                    height: 14,
                    width: 14,
                    child: Container(
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          boxShadow: [
                            BoxShadow(spreadRadius: 0.1, blurRadius: 2)
                          ]),
                    ))
              ]),
        const Padding(padding: EdgeInsets.all(30)),
        Align(
            alignment: const Alignment(1, -0.95),
            child: ElevatedButton(
                onPressed: coordinates != null
                    ? () {
                        _moveCamera(
                            mapController,
                            LatLng(
                                coordinates!.latitude, coordinates!.longitude),
                            mapController.camera.zoom);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(5)),
                child: const Icon(
                  Icons.gps_fixed,
                  size: 30,
                ))),
        const SimpleAttributionWidget(
            source: Text("OpenStreetMap contributors")),
        Visibility(
            visible: showArrived,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white70),
                  child: const Text(
                    'Your driver has arrived. Please board the car',
                    style: TextStyle(fontSize: 30),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ))
      ],
    );
  }

  Widget _buildPassengerScreen() {
    if (!inRadius) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "The app will start looking for drivers once you get close to the bus stop",
            style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (driver == null) {
      var children = [
        Text("Searching for${requestTimeout ? " more" : ""} drivers...",
            style:
                const TextStyle(fontSize: 25.0, fontWeight: FontWeight.w600)),
        const Padding(padding: EdgeInsets.all(20.0)),
        const CircularProgressIndicator()
      ];
      if (driverRefused) {
        children.insert(
            0,
            const Text("Ride cancelled",
                style: TextStyle(
                  fontSize: 22.0,
                )));
      } else if (requestTimeout) {
        children.insert(
            0,
            const Text("You didn't get the driver in time",
                style: TextStyle(
                  fontSize: 22.0,
                )));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
    } else {
      return Column(children: [
        Expanded(flex: 1, child: _buildMap()),
        Container(
            color: Colors.white,
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  "Driver",
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
              ),
              _showDriver(driver)
            ]))
      ]);
    }
  }

  Future<bool> _stopPassengerDialog() async {
    if (driver == null) return Future.value(true);
    bool? reply = await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Really switch to driver mode?'),
            content: const Text('The current ride will be cancelled'),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  child: const Text('Yes')),
              TextButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: const Text('No'))
            ],
          );
        });
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RatingBarIndicator(
                                  itemSize: 36.0,
                                  rating: user.ratingsSum / user.ratingsCount,
                                  itemBuilder: (context, index) => const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                  ),
                                ),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4.0)),
                                Text("(${user.ratingsCount})"),
                              ],
                            ),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 5.0)),
                            TextButton(
                                onPressed: () async {
                                  bool? reply = await showDialog(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          title: const Text('Really sign out?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () {
                                                  Navigator.pop(context, true);
                                                },
                                                child: const Text('Yes')),
                                            TextButton(
                                                onPressed: () {
                                                  Navigator.pop(context, false);
                                                },
                                                child: const Text('No'))
                                          ],
                                        );
                                      });
                                  reply = reply ?? false;
                                  if (!mounted) return;
                                  if (reply) {
                                    SecureStorage.deleteAllSecure();
                                    SocketConnection.channel.add(jsonEncode(
                                        {'type': typeSignout, 'data': {}}));
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const WelcomePage()),
                                    );
                                  }
                                },
                                child: const Text(
                                  "Sign out",
                                  style: TextStyle(fontSize: 16.0),
                                )),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 2.0)),
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

  @override
  void initState() {
    super.initState();
    SocketConnection.receiveSubscription.onData(socketPassengerHandler);
    positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    )).listen((Position? position) {
      if (position == null) {
        debugPrint('Error position');
        return;
      }
      coordinates = position;
      _sendPassenger();
    });
    _sendPassenger();
  }

  @override
  void dispose() {
    positionStream.cancel();
    mapController.dispose();
    if (refusedTimer != null) {
      refusedTimer!.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Passenger'), actions: [
          IconButton(
            onPressed: () async {
              if (await _stopPassengerDialog() && mounted && inRadius) {
                SocketConnection.channel
                    .add(jsonEncode({'type': typeStopPassenger, 'data': {}}));
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const DriverPage()),
                );
              }
            },
            iconSize: 26.0,
            icon: const Icon(Icons.directions_car),
            tooltip: 'Switch to driver mode',
          ),
          IconButton(
              onPressed: _showProfile,
              icon: Provider.of<UserProvider>(context, listen: false)
                          .user
                          .picture !=
                      null
                  ? CachedNetworkImage(
                      imageUrl:
                          "http://$mediaHost/media/images/users/${Provider.of<UserProvider>(context, listen: false).user.picture}",
                      imageBuilder: (context, imageProvider) => CircleAvatar(
                        radius: 18.0,
                        backgroundImage: imageProvider,
                      ),
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => const CircleAvatar(
                        radius: 18.0,
                        backgroundImage:
                            AssetImage("assets/images/blank_profile.png"),
                      ),
                    )
                  : const CircleAvatar(
                      radius: 18.0,
                      backgroundImage:
                          AssetImage('assets/images/blank_profile.png'),
                    )),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0))
        ]),
        body: _buildPassengerScreen());
  }
}
