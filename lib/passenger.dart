import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/welcome.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import "package:latlong2/latlong.dart";
import 'package:uni_pool/widgets.dart';

class PassengerPage extends StatefulWidget {
  const PassengerPage({super.key});
  static const name = "Passenger";
  @override
  State<PassengerPage> createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage>
    with SingleTickerProviderStateMixin {
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
  Timer? refusedCooldownTimer;

  void socketPassengerHandler(message) async {
    final decoded = jsonDecode(message);
    if (decoded['type'] == null ||
        decoded['type'] is! String ||
        decoded['data'] == null) {
      debugPrint("Received bad json: $message");
      return;
    }
    final type = decoded['type'] as String;
    final data = decoded['data'];
    debugPrint("received $type : $data");
    switch (type) {
      case typeGetDriver:
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
            final driverPassengerDistance = Geolocator.distanceBetween(
                driver!['coords']['latitude'],
                driver!['coords']['longitude'],
                coordinates!.latitude,
                coordinates!.longitude);
            if (driverPassengerDistance > maxSeperation) {
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
              moveCamera(
                  this,
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
                  arrivalRange &&
              !driverArrived) {
            moveCamera(this, mapController, pos, 15.5);
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
        break;
      case typePingPassengers:
        HapticFeedback.heavyImpact();
        _acceptDriver();
        break;
      case typePingDriver:
        if (data == null) {
          requestTimeout = true;
        }
        driver = data;
        break;
      case typeArrivedDestination:
        if (driver == null) return;
        HapticFeedback.heavyImpact();
        moveCamera(this, mapController,
            LatLng(coordinates!.latitude, coordinates!.longitude), 15.5);
        final List<double>? rating = await arrivedDialog(
            context: context, users: [driver!], typeOfUser: TypeOfUser.driver);
        if (rating == null) return;
        if (!mounted) return;
        SocketConnection.channel.add(jsonEncode({
          'type': typeSendRatings,
          'data': {
            'users': [driver!['id']],
            'ratings': rating
          }
        }));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WelcomePage()),
        );
        break;
    }
    if (!mounted) return;
    setState(() {});
  }

  void _sendPassenger() async {
    if (!inRadius) {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return;
      coordinates = pos;
      final distanceToBusStop = Geolocator.distanceBetween(
          coordinates!.latitude,
          coordinates!.longitude,
          busStop.latitude,
          busStop.longitude);
      if (distanceToBusStop > busStopRange) return;
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
    int initalSeconds = pairingRequestTimeout;
    ValueNotifier<int> remainingSeconds = ValueNotifier(initalSeconds);
    Timer countdownSecTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 0) {
        --remainingSeconds.value;
      } else {
        timer.cancel();
      }
    });
    Timer countdownDismissTimer = Timer(Duration(seconds: initalSeconds), () {
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
      countdownSecTimer.cancel();
      countdownDismissTimer.cancel();
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
        refusedCooldownTimer = Timer(const Duration(seconds: 30), () {
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
          moveCamera(
              this,
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
                            'http://$mediaHost/images/users/${driver['picture']}',
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
            imageUrl: 'http://$mediaHost/images/users/${driver!['picture']}',
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
                'http://$mediaHost/images/cars/${driver!['car']['picture']}',
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
        Expanded(
            flex: 1,
            child: CustomMap(
                typeOfUser: TypeOfUser.passenger,
                mapController: mapController,
                markers: usersToMarkers([if (driver != null) driver!]),
                coordinates: coordinates,
                showArrived: showArrived,
                onMove: () => setState(() => followDriver = false),
                onPressGPS: () => moveCamera(
                    this,
                    mapController,
                    LatLng(coordinates!.latitude, coordinates!.longitude),
                    mapController.camera.zoom),
                centerGPS: true)),
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

  void _onPositionChanged(Position? position) {
    if (position == null) {
      debugPrint('Error position');
      return;
    }
    coordinates = position;
    _sendPassenger();
  }

  @override
  void initState() {
    super.initState();
    SocketConnection.receiveSubscription.onData(socketPassengerHandler);
    positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    )).listen(_onPositionChanged);
    _sendPassenger();
  }

  @override
  void dispose() {
    positionStream.cancel();
    mapController.dispose();
    if (refusedCooldownTimer != null) {
      refusedCooldownTimer!.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Passenger'), actions: [
          SwitchUserButton(
              context: context,
              skip: driver == null || !inRadius,
              typeOfUser: TypeOfUser.passenger),
          const UserImageButton(),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0))
        ]),
        body: _buildPassengerScreen());
  }
}
