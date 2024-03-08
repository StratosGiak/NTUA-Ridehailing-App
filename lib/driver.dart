import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:diacritic/diacritic.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/welcome.dart';
import 'package:uni_pool/providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/widgets.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});
  static const name = 'Driver';
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  List<Map<String, dynamic>> passengers = [];
  final Stream _getPassengersStream =
      Stream.periodic(const Duration(seconds: 2), (int count) {});
  late StreamSubscription _getPassengersStreamSubscription;
  late StreamSubscription<Position> positionStream;
  final _modelNameController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final mapController = MapController();
  final moveCameraController = MoveCameraController();
  String? selectedCar;
  late List<String> suggestions;
  bool test = false;
  bool inRadius = false;
  bool driving = false;
  bool waitingForPassengers = false;
  bool requestTimeout = false;
  bool passengersCancelled = false;
  bool arrivedAtBusStop = false;
  bool arrivedAtUniversity = false;
  bool showArrived = false;
  bool followDriver = true;
  Timer? arrivedTimer;
  Timer? refusedCooldownTimer;
  Position? coordinates;
  Timer? passengerAcceptTimer;

  void socketDriverHandler(String message) {
    final decoded = jsonDecode(message);
    if (decoded['type'] == null ||
        decoded['type'] is! String ||
        decoded['data'] == null) {
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
        if (!driving || waitingForPassengers) return;
        if (!_getPassengersStreamSubscription.isPaused) {
          _getPassengersStreamSubscription.pause();
        }
        HapticFeedback.heavyImpact();
        requestTimeout = false;
        passengersCancelled = false;
        _acceptPassengers();
        break;
      case typeUpdatePassenger:
        if (!driving || !waitingForPassengers) return;
        if (passengerAcceptTimer != null) {
          passengerAcceptTimer!.cancel();
        }
        if (data['cancelled'] != null) {
          passengers
              .removeWhere((element) => element['id'] == data['cancelled']);
          if (passengers.isEmpty) {
            debugPrint('DELETED');
            passengersCancelled = true;
            waitingForPassengers = false;
            arrivedAtBusStop = false;
            if (_getPassengersStreamSubscription.isPaused) {
              _getPassengersStreamSubscription.resume();
            }
          }
        } else {
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
        context.read<User>().addCar(Car.fromMap(data));
        break;
      case typeRemoveCar:
        selectedCar = null;
        context.read<User>().removeCar(data);
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
      if (passengerAcceptTimer != null) {
        passengerAcceptTimer!.cancel();
      }
      if (refusedCooldownTimer != null) {
        refusedCooldownTimer!.cancel();
      }
      driving = false;
      inRadius = false;
      waitingForPassengers = false;
      passengersCancelled = false;
      requestTimeout = false;
      passengers = [];
      SocketConnection.channel
          .add(jsonEncode({'type': typeStopDriver, 'data': {}}));
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
      if (pos == null) {
        return;
      }
      coordinates = pos;
      if (Geolocator.distanceBetween(
            coordinates!.latitude,
            coordinates!.longitude,
            busStop.latitude,
            busStop.longitude,
          ) >
          2500) {
        return;
      }
      inRadius = true;
      if (!mounted) return;
      SocketConnection.channel.add(
        jsonEncode({
          'type': typeNewDriver,
          'data': {
            'car': context.read<User>().cars[selectedCar],
            'coords': {
              'latitude': coordinates!.latitude,
              'longitude': coordinates!.longitude,
            },
          },
        }),
      );
    } else {
      SocketConnection.channel.add(
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
    bool? reply = await acceptDialog(context);
    reply ??= false;
    if (reply) {
      waitingForPassengers = true;
      SocketConnection.channel
          .add(jsonEncode({'type': typePingPassengers, 'data': {}}));
      passengerAcceptTimer =
          Timer(const Duration(seconds: pairingRequestTimeout), () {
        requestTimeout = true;
        waitingForPassengers = false;
        arrivedAtBusStop = false;
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

  void _showPassengerPicture(int index) {
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
              Size.square(MediaQuery.of(context).size.width),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FittedBox(
                child: CachedNetworkImage(
                  imageUrl:
                      '$mediaHost/images/users/${passengers[index]['picture']}',
                  placeholder: (context, url) =>
                      const CircularProgressIndicator(),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _createPassengersList() {
    if (waitingForPassengers) {
      if (passengers.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Waiting for passengers to respond...',
                style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              Padding(padding: EdgeInsets.all(10.0)),
              CircularProgressIndicator(),
            ],
          ),
        );
      }
      List<Widget> children = [
        Expanded(
          flex: 1,
          child: CustomMap(
            typeOfUser: TypeOfUser.driver,
            mapController: mapController,
            markers: usersToMarkers(passengers),
            coordinates: coordinates,
            showArrived: showArrived,
            onMove: () => setState(() => followDriver = false),
            moveCameraController: moveCameraController,
            onPressGPS: () {
              moveCameraController.moveCamera(
                LatLng(coordinates!.latitude, coordinates!.longitude),
                mapController.camera.zoom,
              );
              setState(() => followDriver = true);
            },
            centerGPS: followDriver,
          ),
        ),
        Container(
          color: Colors.white,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Passengers',
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  return ListTile(
                    onTap: () => moveCameraController.moveCamera(
                      LatLng(
                        passengers[index]['coords']['latitude'],
                        passengers[index]['coords']['longitude'],
                      ),
                      15.5,
                    ),
                    leading: CircleAvatar(
                      radius: 25.0,
                      child: InkWell(
                        onTap: () => _showPassengerPicture(index),
                        onLongPress: () {},
                        child: Ink(
                          color: Colors.black,
                          child: passengers[index]['picture'] != null
                              ? CachedNetworkImage(
                                  imageUrl:
                                      "$mediaHost/images/users/${passengers[index]['picture']}",
                                  imageBuilder: (context, imageProvider) =>
                                      CircleAvatar(
                                    radius: 25.0,
                                    backgroundImage: imageProvider,
                                  ),
                                  placeholder: (context, url) => const SizedBox(
                                    height: 50.0,
                                    width: 50.0,
                                    child: CircularProgressIndicator(),
                                  ),
                                  errorWidget: (
                                    context,
                                    url,
                                    error,
                                  ) =>
                                      const CircleAvatar(
                                    radius: 26.0,
                                    backgroundImage: AssetImage(
                                      'assets/images/blank_profile.png',
                                    ),
                                  ),
                                )
                              : const CircleAvatar(
                                  radius: 25.0,
                                  backgroundImage: AssetImage(
                                    'assets/images/blank_profile.png',
                                  ),
                                ),
                        ),
                      ),
                    ),
                    title: Text("${passengers[index]['name']}"),
                    subtitle: Row(
                      children: [
                        const Text('Rating:'),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 3.0),
                        ),
                        passengers[index]['ratings_count'] > 0
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RatingBarIndicator(
                                    itemSize: 22.0,
                                    rating: passengers[index]['ratings_sum'] /
                                        passengers[index]['ratings_count'],
                                    itemBuilder: (context, index) => const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 3.0,
                                    ),
                                  ),
                                  Text(
                                    "(${passengers[index]['ratings_count']})",
                                  ),
                                ],
                              )
                            : const Text('N/A'),
                      ],
                    ),
                    tileColor: Colors.white,
                    trailing: Icon(
                      Icons.circle,
                      color: colors[int.parse(
                        passengers[index]['id']
                            [passengers[index]['id'].length - 1],
                      )],
                    ),
                  );
                },
                separatorBuilder: (context, index) => const Divider(),
                itemCount: passengers.length,
              ),
              const Padding(padding: EdgeInsets.all(8.0)),
            ],
          ),
        ),
      ];
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    }
    List<Widget> children = [
      Text(
        'Looking for${requestTimeout || passengersCancelled ? " more" : ""} passengers...',
        style: const TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const Padding(padding: EdgeInsets.all(10.0)),
      const CircularProgressIndicator(),
    ];
    if (requestTimeout || passengersCancelled) {
      children.insert(
        0,
        Text(
          requestTimeout
              ? 'No passengers responded'
              : 'All the passengers cancelled the ride',
          style: const TextStyle(fontSize: 22.0),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _createCarList() {
    return Builder(
      builder: (context) {
        final user = context.watch<User>();
        final cars = user.cars;
        final keys = cars.keys.toList();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color.fromARGB(144, 255, 255, 255),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemBuilder: (context, index) {
              return ListTile(
                onTap: () => setState(() => selectedCar = keys[index]),
                onLongPress: () {},
                title: Text(cars[keys[index]]!.model),
                subtitle: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Seats: ${cars[keys[index]]!.seats}'),
                ),
                leading: Radio<String>(
                  value: keys[index],
                  groupValue: selectedCar,
                  onChanged: (value) => setState(() => selectedCar = value),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        final car = await _createCar(id: keys[index]);
                        if (car != null) {
                          car.id = keys[index];
                          SocketConnection.channel.add(
                            jsonEncode(
                              {'type': typeUpdateCar, 'data': car},
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      onPressed: () async {
                        bool? reply = await showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('Really delete car?'),
                              content: const Text(
                                'This action cannot be undone',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Yes'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('No'),
                                ),
                              ],
                            );
                          },
                        );
                        if (reply ?? false) {
                          SocketConnection.channel.add(
                            jsonEncode({
                              'type': typeRemoveCar,
                              'data': keys[index],
                            }),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete),
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (context, index) =>
                const Divider(indent: 20, endIndent: 20),
            itemCount: cars.length,
          ),
        );
      },
    );
  }

  Future<Car?> _createCar({String? id}) async {
    ValueNotifier<({String? imagePath, String? mimeType})> selectedImage =
        ValueNotifier((imagePath: null, mimeType: null));
    ValueNotifier<Color?> finalColor = ValueNotifier(null);
    final car = id != null ? context.read<User>().cars[id] : null;
    if (car != null && car.color != null) finalColor.value = Color(car.color!);
    final value = await showDialog<Car>(
      context: context,
      builder: (context) {
        ValueNotifier<int> seats = ValueNotifier<int>(2);
        if (car != null) {
          seats.value = car.seats;
          _licensePlateController.text = car.license;
          _modelNameController.text = car.model;
        }
        final formKey = GlobalKey<FormState>();
        return Center(
          child: Stack(
            alignment: const FractionalOffset(0.5, 0),
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(color: Colors.transparent, height: 80, width: 160),
                  Container(
                    width: min(MediaQuery.sizeOf(context).width - 2 * 25, 350),
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
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(24, 40, 24, 0),
                            ),
                            Text(
                              car != null ? 'Edit car' : 'Create a car',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Form(
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
                                        validator: (value) => !suggestions
                                                .contains(value)
                                            ? 'Please select a valid car model'
                                            : null,
                                        onEditingComplete: () {
                                          _modelNameController.text =
                                              textEditingController.text;
                                        },
                                      );
                                    },
                                    optionsBuilder: (textEditingValue) {
                                      if (textEditingValue.text == '') {
                                        return const Iterable<String>.empty();
                                      }
                                      return suggestions.where(
                                        (element) => removeDiacritics(
                                          element.toLowerCase(),
                                        ).contains(
                                          textEditingValue.text.toLowerCase(),
                                        ),
                                      );
                                    },
                                    onSelected: (option) {
                                      _modelNameController.text = option;
                                    },
                                  ),
                                  TextFormField(
                                    controller: _licensePlateController,
                                    decoration: const InputDecoration(
                                      hintText: 'License plate',
                                    ),
                                    validator: (value) => value == null ||
                                            !licensePlateRegex.hasMatch(
                                              value.toUpperCase(),
                                            )
                                        ? 'Please enter a valid license plate number'
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            const Padding(padding: EdgeInsets.all(8.0)),
                            Row(
                              children: [
                                const Text('Available seats'),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10.0,
                                  ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: seats,
                                  builder: (context, value, child) {
                                    return IconButton(
                                      onPressed: value > 1
                                          ? () => --seats.value
                                          : null,
                                      icon: const Icon(Icons.remove),
                                      iconSize: 30,
                                    );
                                  },
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: seats,
                                  builder: (context, value, child) {
                                    return Text(
                                      '$value',
                                      style: const TextStyle(
                                        fontSize: 16,
                                      ),
                                    );
                                  },
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: seats,
                                  builder: (context, value, child) {
                                    return IconButton(
                                      onPressed: value < 3
                                          ? () => ++seats.value
                                          : null,
                                      icon: const Icon(Icons.add),
                                      iconSize: 30,
                                    );
                                  },
                                ),
                              ],
                            ),
                            const Padding(padding: EdgeInsets.all(8.0)),
                            Row(
                              children: [
                                const Text('Choose color'),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 15.0,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    Color? reply = await colorWheelDialog(
                                      context,
                                      finalColor.value,
                                    );
                                    if (reply != null) {
                                      finalColor.value = reply;
                                    }
                                  },
                                  icon: ValueListenableBuilder(
                                    valueListenable: finalColor,
                                    builder: (context, value, child) {
                                      if (value == null) {
                                        return const Icon(
                                          Icons.palette,
                                          size: 30,
                                        );
                                      }
                                      return ColorIndicator(
                                        borderColor: Colors.black45,
                                        hasBorder: true,
                                        color: value,
                                      );
                                    },
                                  ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: finalColor,
                                  builder: (context, value, child) {
                                    return Visibility(
                                      visible: value != null,
                                      child: IconButton(
                                        onPressed: () =>
                                            finalColor.value = null,
                                        icon: const Icon(
                                          Icons.clear,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const Padding(padding: EdgeInsets.all(8)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    if (formKey.currentState!.validate()) {
                                      String? imageName;
                                      if (selectedImage.value.imagePath !=
                                              null &&
                                          selectedImage.value.mimeType !=
                                              null) {
                                        imageName = await uploadImage(
                                          TypeOfImage.cars,
                                          selectedImage.value.imagePath!,
                                          selectedImage.value.mimeType!,
                                        );
                                      }
                                      final modelName =
                                          _modelNameController.text;
                                      final licensePlate =
                                          normalizeLicensePlate(
                                        _licensePlateController.text,
                                      );
                                      if (!mounted) return;
                                      Navigator.pop(
                                        context,
                                        Car.fromMap({
                                          'id': id,
                                          'model': modelName,
                                          'license': licensePlate,
                                          'seats': seats.value,
                                          'picture': imageName ?? car?.picture,
                                          'color': finalColor.value?.value,
                                        }),
                                      );
                                    }
                                  },
                                  child: const Text('Ok'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                            const Padding(padding: EdgeInsets.all(5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () async {
                  final result = await pickImage(imageQuality: carImageQuality);
                  if (result == null || result.mimeType == null) return;
                  selectedImage.value = result;
                  finalColor.value = (await PaletteGenerator.fromImageProvider(
                    Image.file(File(result.imagePath!)).image,
                  ))
                      .dominantColor
                      ?.color;
                },
                iconSize: 40,
                icon: CircleAvatar(
                  radius: 70,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(70),
                    child: ValueListenableBuilder(
                      valueListenable: selectedImage,
                      builder: (context, value, child) {
                        if (value.imagePath != null) {
                          return Image.file(File(value.imagePath!));
                        }
                        return NetworkImageWithPlaceholder(
                          typeOfImage: TypeOfImage.cars,
                          imageUrl: car?.picture,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    Future.delayed(const Duration(milliseconds: 100), () {
      _modelNameController.clear();
      _licensePlateController.clear();
    });
    return value;
  }

  Widget _buildDriverScreen() {
    return Builder(
      builder: (context) {
        var children = <Widget>[];
        if (!driving) {
          if (context.watch<User>().cars.isEmpty) {
            children = [
              const SizedBox(height: 100),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Add a car to continue',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ];
          } else {
            children
              ..add(const SizedBox(height: 10))
              ..add(
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Select car', style: TextStyle(fontSize: 20)),
                ),
              )
              ..add(
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _createCarList(),
                ),
              );
          }
          children.add(
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: context.watch<User>().cars.length >= 3
                    ? null
                    : () async {
                        final car = await _createCar();
                        if (car != null) {
                          SocketConnection.channel.add(
                            jsonEncode({'type': typeAddCar, 'data': car}),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(8.0),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          );
        } else {
          if (!inRadius) {
            children.add(
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      'The app will start looking for passengers once you get close to the bus stop',
                      style: TextStyle(
                        fontSize: 25.0,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            );
          } else {
            return _createPassengersList();
          }
        }
        return Center(
          child: Column(
            children: children,
          ),
        );
      },
    );
  }

  void _onPositionChange(Position? position) async {
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
      _getPassengersStreamSubscription.cancel();
      moveCameraController.moveCamera(
        LatLng(coordinates!.latitude, coordinates!.longitude),
        15.5,
      );
      SocketConnection.channel
          .add(jsonEncode({'type': typeArrivedDestination, 'data': {}}));
      final List<double>? ratings = await arrivedDialog(
        context: context,
        users: passengers,
        typeOfUser: TypeOfUser.passenger,
      );
      if (ratings != null) {
        SocketConnection.channel.add(
          jsonEncode({
            'type': typeSendRatings,
            'data': {
              'users': passengers.map((e) => e['id']).toList(),
              'ratings': ratings,
            },
          }),
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    SocketConnection.receiveSubscription.onData(socketDriverHandler);
    _getPassengersStreamSubscription = _getPassengersStream.listen((event) {
      SocketConnection.channel
          .add(jsonEncode({'type': typeGetPassengers, 'data': {}}));
    });
    _getPassengersStreamSubscription.pause();
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    ).listen(_onPositionChange);
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
    if (passengerAcceptTimer != null) {
      passengerAcceptTimer!.cancel();
    }
    if (refusedCooldownTimer != null) {
      refusedCooldownTimer!.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      appBar: AppBar(
        title: const Text('Driver'),
        leading: Visibility(
          visible: passengers.isNotEmpty,
          child: SwitchUserButton(
            context: context,
            skip: passengers.isEmpty || !inRadius,
            typeOfUser: TypeOfUser.driver,
            back: true,
          ),
        ),
        actions: [
          SwitchUserButton(
            context: context,
            skip: passengers.isEmpty || !inRadius,
            typeOfUser: TypeOfUser.driver,
          ),
          const UserImageButton(),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0)),
        ],
      ),
      body: _buildDriverScreen(),
      floatingActionButton: Visibility(
        visible: selectedCar != null && passengers.isEmpty,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LargeFAB(
              inProgress: driving,
              onPressed: selectedCar != null ? _toggleDriving : null,
              tooltip: driving ? 'Stop driving' : 'Start driving',
            ),
          ),
        ),
      ),
    );
  }
}
