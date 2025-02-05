import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ntua_ridehailing/constants.dart';
import 'package:ntua_ridehailing/providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ntua_ridehailing/socket_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntua_ridehailing/utilities.dart';
import 'package:ntua_ridehailing/widgets/driver_widgets.dart';
import 'package:ntua_ridehailing/widgets/common_widgets.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  late final SocketConnection socketConnection =
      context.read<SocketConnection>();
  late final User user = context.read<User>();
  List<Map<String, dynamic>> passengers = [];
  final Stream _getPassengersStream =
      Stream.periodic(const Duration(seconds: 2), (int count) {});
  late StreamSubscription _getPassengersStreamSubscription;
  late StreamSubscription<Position> positionStream;
  final _modelNameController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final mapController = MapController();
  final moveCameraController = MoveCameraController();
  ValueNotifier<String?> selectedCar = ValueNotifier(null);
  late List<String> suggestions;
  bool inRadius = false;
  bool driving = false;
  bool waitingForResponse = false;
  bool requestTimedOut = false;
  bool passengersCancelled = false;
  bool arrivedAtBusStop = false;
  bool arrivedAtUniversity = false;
  bool showArrived = false;
  bool followDriver = false;
  Timer? arrivedTimer;
  Timer? refusedCooldownTimer;
  Position? coordinates;
  Timer? passengerAcceptTimer;

  void connectionHandler(String message) {
    if (!mounted) return;
    if (message == 'done' || message == 'error') {
      user.setUser(null);
      Navigator.popUntil(context, (route) => route.isFirst);
      if (socketConnection.channel.closeCode != 1000) {
        ScaffoldMessenger.of(context).showSnackBar(snackBarConnectionLost);
      }
    }
  }

  void socketDriverHandler(String message) {
    final decoded = jsonDecode(message);
    if (decoded['type'] == null || decoded['type'] is! String) {
      debugPrint('Received bad json: $message');
      return;
    }
    final type = decoded['type'] as String;
    final data = decoded['data'];
    debugPrint('received $type : $data');
    switch (type) {
      case typeNewDriver:
        if (_getPassengersStreamSubscription.isPaused) {
          _getPassengersStreamSubscription.resume();
        }
        break;
      case typeGetPassengers:
        if (!driving || waitingForResponse) return;
        if (!_getPassengersStreamSubscription.isPaused) {
          _getPassengersStreamSubscription.pause();
        }
        HapticFeedback.heavyImpact();
        requestTimedOut = false;
        passengersCancelled = false;
        _acceptPassengers();
        break;
      case typeUpdatePassenger:
        if (!driving || !waitingForResponse) return;
        passengerAcceptTimer?.cancel();
        if (data['cancelled'] != null) {
          passengers
              .removeWhere((element) => element['id'] == data['cancelled']);
          if (passengers.isEmpty) {
            passengersCancelled = true;
            waitingForResponse = false;
            arrivedAtBusStop = false;
            if (_getPassengersStreamSubscription.isPaused) {
              _getPassengersStreamSubscription.resume();
            }
          }
        } else {
          if (data['id'] == null) return;
          final index =
              passengers.indexWhere((element) => element['id'] == data['id']);
          if (index == -1) {
            passengers.add(data);
          } else {
            passengers[index] = data;
          }
        }
        break;
      case typeAddCar:
        user.addCar(Car.fromMap(data));
        break;
      case typeRemoveCar:
        selectedCar.value = null;
        user.removeCar(data);
        break;
      case typeDeleteUserPicture:
        ScaffoldMessenger.of(context).showSnackBar(snackBarNSFW);
        user.setUserPicture(null);
        break;
      case typeDeleteCarPicture:
        ScaffoldMessenger.of(context).showSnackBar(snackBarNSFW);
        user.setCarPicture(data.toString(), null);
        break;
      default:
        debugPrint('Invalid type: $type');
        break;
    }
    setState(() {});
  }

  void _toggleDriving() {
    if (driving) {
      if (!_getPassengersStreamSubscription.isPaused) {
        _getPassengersStreamSubscription.pause();
      }
      if (!positionStream.isPaused) {
        positionStream.pause();
      }
      passengerAcceptTimer?.cancel();
      refusedCooldownTimer?.cancel();
      driving = false;
      waitingForResponse = false;
      passengersCancelled = false;
      requestTimedOut = false;
      passengers = [];
      if (inRadius) {
        socketConnection.send(jsonEncode({'type': typeStopDriver, 'data': {}}));
      }
    } else {
      if (positionStream.isPaused) {
        positionStream.resume();
      }
      driving = true;
      _sendDriver();
    }
    setState(() {});
  }

  void _sendDriver() async {
    if (!inRadius) {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return;
      coordinates = pos;
      if (Geolocator.distanceBetween(
            coordinates!.latitude,
            coordinates!.longitude,
            busStop.latitude,
            busStop.longitude,
          ) >
          busStopDriverRange) {
        return;
      }
      inRadius = true;
      if (!mounted) return;
      socketConnection.send(
        jsonEncode({
          'type': typeNewDriver,
          'data': {
            'car': user.cars[selectedCar.value],
            'coords': {
              'latitude': coordinates!.latitude,
              'longitude': coordinates!.longitude,
            },
          },
        }),
      );
    } else {
      socketConnection.send(
        jsonEncode({
          'type': typeUpdateDriver,
          'data': {
            'coords': {
              'latitude': coordinates!.latitude,
              'longitude': coordinates!.longitude,
            },
          },
        }),
      );
    }
  }

  void _acceptPassengers() async {
    final reply = await acceptDialog(context, TypeOfUser.driver) ?? false;
    if (reply) {
      waitingForResponse = true;
      socketConnection
          .send(jsonEncode({'type': typePingPassengers, 'data': {}}));
      passengerAcceptTimer =
          Timer(const Duration(seconds: pairingRequestTimeout), () {
        requestTimedOut = true;
        waitingForResponse = false;
        arrivedAtBusStop = false;
        if (_getPassengersStreamSubscription.isPaused) {
          _getPassengersStreamSubscription.resume();
        }
        setState(() {});
      });
    } else {
      if (!_getPassengersStreamSubscription.isPaused) {
        _getPassengersStreamSubscription.pause();
      }
      refusedCooldownTimer = Timer(const Duration(seconds: 60), () {
        if (_getPassengersStreamSubscription.isPaused) {
          _getPassengersStreamSubscription.resume();
        }
      });
    }
    setState(() {});
  }

  Future<void> _createCar(String? id) async {
    final node = FocusNode();
    bool imageChanged = false;
    ValueNotifier<({String? imagePath, String? mimeType})> selectedImage =
        ValueNotifier((imagePath: null, mimeType: null));
    ValueNotifier<Color?> finalColor = ValueNotifier(null);
    ValueNotifier<int> seats = ValueNotifier<int>(2);
    final car = id != null ? user.cars[id] : null;
    if (car != null && car.color != null) finalColor.value = Color(car.color!);
    final formKey = GlobalKey<FormState>();
    final carForm = Form(
      key: formKey,
      child: Column(
        children: [
          Autocomplete<String>(
            fieldViewBuilder: (
              context,
              textEditingController,
              focusNode,
              onFieldSubmitted,
            ) {
              if (car != null) {
                textEditingController.text = car.model;
              }
              return TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  hintText: 'Car model',
                ),
                validator: (value) => suggestions.contains(value)
                    ? null
                    : 'Please select a valid car model',
                onEditingComplete: () =>
                    _modelNameController.text = textEditingController.text,
              );
            },
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text == '') {
                return const Iterable<String>.empty();
              }
              return suggestions.where(
                (element) => removeDiacritics(element.toLowerCase())
                    .contains(textEditingValue.text.toLowerCase()),
              );
            },
            onSelected: (option) => _modelNameController.text = option,
          ),
          TextFormField(
            controller: _licensePlateController,
            decoration: const InputDecoration(hintText: 'License plate'),
            validator: (value) =>
                value == null || licensePlateRegex.hasMatch(value.toUpperCase())
                    ? null
                    : 'Please enter a valid license plate number',
          ),
        ],
      ),
    );
    final dialogChildren = [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 40, 24, 0),
      ),
      Text(
        car != null ? 'Edit car' : 'Create a car',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      carForm,
      const Padding(padding: EdgeInsets.all(8.0)),
      Row(
        children: [
          const Text('Available seats'),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10.0)),
          ValueListenableBuilder(
            valueListenable: seats,
            builder: (context, value, child) {
              return IconButton(
                onPressed: value > 1 ? () => --seats.value : null,
                icon: const Icon(Icons.remove),
                iconSize: 30,
              );
            },
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6)),
          ValueListenableBuilder(
            valueListenable: seats,
            builder: (context, value, child) =>
                Text('$value', style: const TextStyle(fontSize: 16)),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6)),
          ValueListenableBuilder(
            valueListenable: seats,
            builder: (context, value, child) => IconButton(
              onPressed: value < 3 ? () => ++seats.value : null,
              icon: const Icon(Icons.add),
              iconSize: 30,
            ),
          ),
        ],
      ),
      const Padding(padding: EdgeInsets.all(8.0)),
      Row(
        children: [
          const Text('Choose color'),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 15.0)),
          ColorPickerPopover(colorNotifier: finalColor),
          ValueListenableBuilder(
            valueListenable: finalColor,
            builder: (context, value, child) => Visibility(
              visible: value != null,
              child: IconButton(
                onPressed: () => finalColor.value = null,
                icon: const Icon(Icons.clear),
              ),
            ),
          ),
        ],
      ),
      const Padding(padding: EdgeInsets.all(8)),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final modelName = _modelNameController.text;
              final licensePlate =
                  normalizeLicensePlate(_licensePlateController.text);
              if (!mounted) return;
              Navigator.pop(
                context,
                ({
                  'id': id,
                  'model': modelName,
                  'license': licensePlate,
                  'seats': seats.value,
                  'picture': car?.picture,
                  'color': finalColor.value?.value,
                }),
              );
            },
            child: const Text('Ok'),
          ),
        ],
      ),
      const Padding(padding: EdgeInsets.all(5)),
    ];
    void onTap() async {
      final result = await pickImage(imageQuality: carImageQuality);
      if (result == null || result.mimeType == null) return;
      imageChanged = true;
      selectedImage.value = result;
      finalColor.value = getAverageColor(File(result.imagePath!));
    }

    final newCar = await showAdaptiveDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        if (car != null) {
          seats.value = car.seats;
          _licensePlateController.text = car.license;
          _modelNameController.text = car.model;
        }
        return GestureDetector(
          onTap: () => FocusScope.of(context).requestFocus(node),
          child: Center(
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
                      width:
                          min(MediaQuery.sizeOf(context).width - 2 * 25, 350),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 34, 24, 0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: dialogChildren,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ValueListenableBuilder(
                  valueListenable: selectedImage,
                  builder: (context, value, child) {
                    if (value.imagePath != null) {
                      return ImageWithPrompt(
                        imageProvider: Image.file(File(value.imagePath!)).image,
                        onTap: onTap,
                      );
                    }
                    return NetworkImageWithPlaceholder(
                      onTap: onTap,
                      typeOfImage: TypeOfImage.cars,
                      imageUrl: car?.picture,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      _modelNameController.clear();
      _licensePlateController.clear();
    });
    if (newCar == null) return;
    if (imageChanged) {
      if (selectedImage.value.imagePath != null &&
          selectedImage.value.mimeType != null) {
        final image = await uploadImage(
          // ignore: use_build_context_synchronously
          context,
          TypeOfImage.cars,
          selectedImage.value.imagePath!,
          selectedImage.value.mimeType!,
        );
        if (image != null) newCar['picture'] = image;
      } else {
        newCar['picture'] = null;
      }
    }
    if (id != null) {
      socketConnection.send(
        jsonEncode({'type': typeUpdateCar, 'data': newCar}),
      );
    } else {
      socketConnection.send(
        jsonEncode({'type': typeAddCar, 'data': newCar}),
      );
    }
  }

  void _onPositionChanged(Position? position) async {
    if (position == null) return;
    coordinates = position;
    _sendDriver();
    if (arrivedAtBusStop && followDriver) {
      moveCameraController.moveCamera(
        LatLng(coordinates!.latitude, coordinates!.longitude),
        mapController.camera.zoom,
      );
    }
    if (passengers.isNotEmpty &&
        Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              busStop.latitude,
              busStop.longitude,
            ) <
            100 &&
        !arrivedAtBusStop) {
      arrivedAtBusStop = true;
      followDriver = true;
      showArrived = true;
      moveCameraController.moveCamera(busStop, 15.5);
      arrivedTimer = Timer(
        const Duration(seconds: 5),
        () => setState(() => showArrived = false),
      );
    }
    if (passengers.isNotEmpty &&
        Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              university.latitude,
              university.longitude,
            ) <
            300 &&
        arrivedAtBusStop &&
        !arrivedAtUniversity) {
      arrivedAtUniversity = true;
      followDriver = false;
      _getPassengersStreamSubscription.cancel();
      positionStream.cancel();
      moveCameraController.moveCamera(
        LatLng(coordinates!.latitude, coordinates!.longitude),
        15.5,
      );
      socketConnection
          .send(jsonEncode({'type': typeArrivedDestination, 'data': {}}));
      await arrivedDialog(
        context: context,
        users: passengers,
        typeOfUser: TypeOfUser.passenger,
      );
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    socketConnection.receiveSubscription.onData(socketDriverHandler);
    socketConnection.connectionSubscription.onData(connectionHandler);
    _getPassengersStreamSubscription = _getPassengersStream.listen((event) {
      socketConnection
          .send(jsonEncode({'type': typeGetPassengers, 'data': {}}));
    });
    _getPassengersStreamSubscription.pause();
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    ).listen(_onPositionChanged);
    positionStream.pause();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async => suggestions =
          (await DefaultAssetBundle.of(context).loadString('assets/cars.txt'))
              .split('\n'),
    );
  }

  @override
  void dispose() {
    _getPassengersStreamSubscription.cancel();
    positionStream.cancel();
    _modelNameController.dispose();
    _licensePlateController.dispose();
    mapController.dispose();
    arrivedTimer?.cancel();
    passengerAcceptTimer?.cancel();
    refusedCooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (socketConnection.status != SocketStatus.connected || !inRadius) {
          Navigator.pop(context);
        } else if (passengers.isEmpty || await stopDrivingDialog(context)) {
          socketConnection
              .send(jsonEncode({'type': typeStopDriver, 'data': {}}));
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        appBar: AppBar(
          title: const Text('Driver'),
          actions: [
            SwitchModeButton(
              context: context,
              skipSendMessage:
                  socketConnection.status != SocketStatus.connected ||
                      !inRadius,
              skipDialog: passengers.isEmpty,
              typeOfUser: TypeOfUser.driver,
            ),
            const UserAvatarButton(),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0)),
          ],
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: !driving
              ? CarListScreen(
                  carList: CarList(
                    selected: selectedCar,
                    onTap: () => setState(() {}),
                    onEditPressed: (id) => _createCar(id),
                  ),
                  onPressed: context.watch<User>().cars.length < 3
                      ? () => _createCar(null)
                      : null,
                )
              : !waitingForResponse || passengers.isEmpty
                  ? DriverStatusScreen(
                      inRadius: inRadius,
                      waitingForPassengers: waitingForResponse,
                      requestTimeout: requestTimedOut,
                      passengersCancelled: passengersCancelled,
                    )
                  : MapScreen(
                      context: context,
                      passengers: passengers,
                      mapController: mapController,
                      coordinates: coordinates,
                      showArrived: showArrived,
                      onMove: () => setState(() => followDriver = false),
                      moveCameraController: moveCameraController,
                      onPressGPS: () => setState(() => followDriver = true),
                      followGPS: followDriver,
                    ),
        ),
        floatingActionButton: Visibility(
          visible: selectedCar.value != null && passengers.isEmpty,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LargeFAB(
                inProgress: driving,
                onPressed: selectedCar.value != null ? _toggleDriving : null,
                tooltip: driving ? 'Stop driving' : 'Start driving',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
