import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ntua_ridehailing/constants.dart';
import 'package:ntua_ridehailing/providers.dart';
import 'package:ntua_ridehailing/utilities.dart';
import 'package:ntua_ridehailing/socket_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntua_ridehailing/widgets/common_widgets.dart';
import 'package:ntua_ridehailing/widgets/passenger_widgets.dart';

class PassengerPage extends StatefulWidget {
  const PassengerPage({super.key});
  @override
  State<PassengerPage> createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? driver;
  late StreamSubscription<Position> positionStream;
  ListQueue<LatLng> driverPositions = ListQueue();
  final mapController = MapController();
  final moveCameraController = MoveCameraController();
  Position? coordinates;
  bool inRadius = false;
  bool requestTimedOut = false;
  bool driverRefused = false;
  bool driverArrived = false;
  bool showArrived = false;
  bool followDriver = false;
  Timer? arrivedTimer;
  Timer? refusedCooldownTimer;

  void connectionHandler(String message) {
    if (!mounted) return;
    if (message == 'done' || message == 'error') {
      context.read<User>().setUser(null);
      Navigator.pop(context);
      if (SocketConnection.channel.closeCode != 1000) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarConnectionLost);
      }
    }
  }

  void socketPassengerHandler(message) async {
    final decoded = jsonDecode(message);
    if (decoded['type'] == null || decoded['type'] is! String) {
      debugPrint('Received bad json: $message');
      return;
    }
    final type = decoded['type'] as String;
    final data = decoded['data'];
    debugPrint('received $type : $data');
    switch (type) {
      case typeGetDriver:
        if (driver == null) return;
        driver = data;
        if (data == null) {
          HapticFeedback.heavyImpact();
          driver = null;
          driverArrived = false;
          driverPositions.clear();
          driverRefused = true;
          requestTimedOut = false;
        } else {
          if (driverArrived) {
            final driverPassengerDistance = Geolocator.distanceBetween(
              driver!['coords']['latitude'],
              driver!['coords']['longitude'],
              coordinates!.latitude,
              coordinates!.longitude,
            );
            if (driverPassengerDistance > maxSeperation) {
              HapticFeedback.heavyImpact();
              driver = null;
              driverArrived = false;
              driverPositions.clear();
              driverRefused = true;
              SocketConnection.channel
                  .add(jsonEncode({'type': typeOutOfRange, 'data': {}}));
              break;
            }
            if (followDriver) {
              moveCameraController.moveCamera(
                LatLng(
                  driver!['coords']['latitude'],
                  driver!['coords']['longitude'],
                ),
                mapController.camera.zoom,
              );
            }
          }
          if (driverPositions.length > 50) {
            driverPositions.removeFirst();
          }
          final pos = LatLng(
            driver!['coords']['latitude'],
            driver!['coords']['longitude'],
          );
          if (Geolocator.distanceBetween(
                    pos.latitude,
                    pos.longitude,
                    busStop.latitude,
                    busStop.longitude,
                  ) <
                  arrivalRange &&
              !driverArrived) {
            moveCameraController.moveCamera(pos, 15.5);
            driverArrived = true;
            showArrived = true;
            followDriver = true;
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
        if (data == null) requestTimedOut = true;
        driver = data;
        break;
      case typeArrivedDestination:
        if (driver == null) return;
        positionStream.cancel();
        HapticFeedback.heavyImpact();
        followDriver = false;
        moveCameraController.moveCamera(
          LatLng(coordinates!.latitude, coordinates!.longitude),
          15.5,
        );
        await arrivedDialog(
          context: context,
          users: [driver!],
          typeOfUser: TypeOfUser.driver,
        );
        if (!mounted) return;
        Navigator.popUntil(context, (route) => route.isFirst);
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
        busStop.longitude,
      );
      if (distanceToBusStop > busStopPassengerRange) return;
      inRadius = true;
      SocketConnection.channel.add(
        jsonEncode({
          'type': typeNewPassenger,
          'data': {
            'coords': {
              'latitude': coordinates!.latitude,
              'longitude': coordinates!.longitude,
            },
            'timestamp': coordinates!.timestamp.toIso8601String(),
          },
        }),
      );
    } else {
      SocketConnection.channel.add(
        jsonEncode({
          'type': typeUpdatePassenger,
          'data': {
            'coords': {
              'latitude': coordinates!.latitude,
              'longitude': coordinates!.longitude,
            },
          },
        }),
      );
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
    Timer countdownDismissTimer = Timer(
      Duration(seconds: initalSeconds),
      () => Navigator.of(context, rootNavigator: true).pop(false),
    );
    final reply = await acceptDialog(
      context,
      TypeOfUser.passenger,
      timerDisplay: ValueListenableBuilder(
        valueListenable: remainingSeconds,
        builder: (context, value, child) {
          return Text(
            '$value',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 30.0,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          );
        },
      ),
    );
    countdownSecTimer.cancel();
    countdownDismissTimer.cancel();
    if (reply == true) {
      SocketConnection.channel
          .add(jsonEncode({'type': typePingDriver, 'data': true}));
    } else {
      if (remainingSeconds.value == 0) {
        requestTimedOut = true;
      } else {
        SocketConnection.channel
            .add(jsonEncode({'type': typeStopPassenger, 'data': {}}));
        refusedCooldownTimer = Timer(
          const Duration(seconds: 30),
          () => SocketConnection.channel.add(
            jsonEncode({
              'type': typeNewPassenger,
              'data': {
                'coords': {
                  'latitude': coordinates!.latitude,
                  'longitude': coordinates!.longitude,
                },
                'timestamp': coordinates!.timestamp.toIso8601String(),
              },
            }),
          ),
        );
      }
      SocketConnection.channel
          .add(jsonEncode({'type': typePingDriver, 'data': false}));
      setState(() {});
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
    SocketConnection.connectionSubscription.onData(connectionHandler);
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen(_onPositionChanged);
    _sendPassenger();
  }

  @override
  void dispose() {
    positionStream.cancel();
    mapController.dispose();
    refusedCooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (SocketConnection.connected.value != true || !inRadius) {
          Navigator.pop(context);
        } else if (driver == null || await stopPassengerDialog(context)) {
          SocketConnection.channel.add(
            jsonEncode({'type': typeStopPassenger, 'data': {}}),
          );
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Passenger'),
          actions: [
            SwitchModeButton(
              context: context,
              skipSendMessage:
                  SocketConnection.connected.value != true || !inRadius,
              skipDialog: driver == null,
              typeOfUser: TypeOfUser.passenger,
            ),
            const UserImageButton(),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0)),
          ],
        ),
        body: !inRadius || driver == null
            ? PassengerStatusScreen(
                inRadius: inRadius,
                driverRefused: driverRefused,
                requestTimedOut: requestTimedOut,
              )
            : MapScreen(
                context: context,
                driver: driver!,
                mapController: mapController,
                coordinates: coordinates,
                showArrived: showArrived,
                showDistance: driverArrived,
                onMove: () => setState(() => followDriver = false),
                moveCameraController: moveCameraController,
                onPressGPS: () => setState(() => followDriver = true),
                followGPS: followDriver,
                driverPositions: driverPositions,
              ),
      ),
    );
  }
}
