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
import "package:latlong2/latlong.dart";
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/widgets.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});
  static const name = "Driver";
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> passengers = [];
  final Stream _getPassengersStream =
      Stream.periodic(const Duration(seconds: 2), (int count) {});
  late StreamSubscription _getPassengersStreamSubscription;
  late StreamSubscription<Position> positionStream;
  final _modelNameController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final mapController = MapController();
  String? selectedCar;
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
      debugPrint("Received bad json: $message");
      return;
    }
    final type = decoded['type'] as String;
    final data = decoded['data'];
    debugPrint("received $type : $data");
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
          debugPrint("${data['cancelled']}");
          debugPrint("$passengers");
          passengers
              .removeWhere((element) => element['id'] == data['cancelled']);
          debugPrint("$passengers");
          if (passengers.isEmpty) {
            debugPrint("DELETED");
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
        Provider.of<User>(context, listen: false).cars['${data['car_id']}'] =
            data;
        break;
      case typeRemoveCar:
        Provider.of<User>(context, listen: false).cars.remove(data);
        if (Provider.of<User>(context, listen: false).cars.isEmpty) {
          selectedCar = null;
        } else {
          selectedCar = Provider.of<User>(context, listen: false).cars[
              Provider.of<User>(context, listen: false)
                  .cars
                  .keys
                  .toList()[0]]!['car_id'];
        }
        break;
      default:
        debugPrint("Invalid type: $type");
        break;
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
      if (Geolocator.distanceBetween(coordinates!.latitude,
              coordinates!.longitude, busStop.latitude, busStop.longitude) >
          2500) {
        return;
      }
      inRadius = true;
      if (!mounted) return;
      SocketConnection.channel.add(jsonEncode({
        'type': typeNewDriver,
        'data': {
          'car': Provider.of<User>(context, listen: false).cars[selectedCar],
          'coords': {
            "latitude": coordinates!.latitude,
            "longitude": coordinates!.longitude
          }
        }
      }));
    } else {
      SocketConnection.channel.add(jsonEncode({
        'type': typeUpdateDriver,
        'data': {
          'coords': {
            "latitude": coordinates!.latitude,
            "longitude": coordinates!.longitude
          }
        }
      }));
    }
  }

  void _acceptPassengers() async {
    bool? reply = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(padding: EdgeInsets.all(10.0)),
                  const Text(
                    "Passengers are available. Accept them?",
                    style:
                        TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const Padding(padding: EdgeInsets.all(20.0)),
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
                        iconSize: 50.0,
                        icon: const Icon(Icons.check_rounded),
                      ),
                      IconButton.filled(
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        style: ButtonStyle(
                            backgroundColor:
                                MaterialStatePropertyAll(Colors.red.shade300)),
                        iconSize: 50.0,
                        icon: const Icon(Icons.close_rounded),
                      )
                    ],
                  ),
                  const Padding(padding: EdgeInsets.all(10.0))
                ],
              ));
        });
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

  List<Marker> _passengersToMarkers() {
    List<Marker> markers = [];
    for (var passenger in passengers) {
      markers.add(Marker(
          height: 22,
          width: 22,
          point: LatLng(passenger["coords"]["latitude"],
              passenger["coords"]["longitude"]),
          child: Stack(children: [
            Container(
              decoration: const BoxDecoration(shape: BoxShape.circle),
            ),
            Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[
                      int.parse(passenger["id"][passenger["id"].length - 1])],
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(spreadRadius: 0.1, blurRadius: 3)
                  ]),
            ),
          ])));
    }
    return markers;
  }

  Widget _buildMap() {
    if (mapUrl.isEmpty) return Container();
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: const LatLng(37.9923, 23.7764),
        initialZoom: 14.5,
        minZoom: 14,
        maxZoom: 16,
        cameraConstraint: CameraConstraint.contain(bounds: mapBounds),
        interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all - InteractiveFlag.rotate),
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            followDriver = false;
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=umhAaMGooyIsumfuR9Fi',
          tileProvider: NetworkTileProvider(),
          // tileBounds: LatLngBounds(const LatLng(38.01304, 23.74121),
          //     const LatLng(37.97043, 23.80078)),
          errorTileCallback: (tile, error, stackTrace) {},
          evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        ),
        MarkerLayer(markers: _passengersToMarkers()),
        coordinates == null
            ? Container()
            : MarkerLayer(markers: [
                Marker(
                    point:
                        LatLng(coordinates!.latitude, coordinates!.longitude),
                    height: 16,
                    width: 16,
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
                        followDriver = true;
                        setState(() {});
                        moveCamera(
                            this,
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
                child: Icon(
                  followDriver ? Icons.gps_fixed : Icons.gps_not_fixed,
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
                    'Please wait for all passengers to board the car',
                    style: TextStyle(fontSize: 30),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ))
      ],
    );
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
                      Size.square(MediaQuery.of(context).size.width)),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: FittedBox(
                      child: CachedNetworkImage(
                        imageUrl:
                            'http://$mediaHost/images/users/${passengers[index]['picture']}',
                        placeholder: (context, url) =>
                            const CircularProgressIndicator(),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.error),
                      ),
                    ),
                  )));
        });
  }

  Widget _createPassengersList() {
    if (waitingForPassengers) {
      if (passengers.isEmpty) {
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Waiting for passengers to respond...',
                style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            Padding(padding: EdgeInsets.all(10.0)),
            CircularProgressIndicator(),
          ]),
        );
      }
      List<Widget> children = [
        Expanded(flex: 1, child: _buildMap()),
        Container(
          color: Colors.white,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  "Passengers",
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
              ),
              ListView.separated(
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    return ListTile(
                        onTap: () {
                          moveCamera(
                              this,
                              mapController,
                              LatLng(passengers[index]["coords"]["latitude"],
                                  passengers[index]["coords"]["longitude"]),
                              15.5);
                        },
                        leading: CircleAvatar(
                          radius: 25.0,
                          child: InkWell(
                            onTap: () {
                              _showPassengerPicture(index);
                            },
                            onLongPress: () {},
                            child: Ink(
                              color: Colors.black,
                              child: passengers[index]['picture'] != null
                                  ? CachedNetworkImage(
                                      imageUrl:
                                          "http://$mediaHost/images/users/${passengers[index]['picture']}",
                                      imageBuilder: (context, imageProvider) =>
                                          CircleAvatar(
                                        radius: 25.0,
                                        backgroundImage: imageProvider,
                                      ),
                                      placeholder: (context, url) =>
                                          const SizedBox(
                                              height: 50.0,
                                              width: 50.0,
                                              child:
                                                  CircularProgressIndicator()),
                                      errorWidget: (context, url, error) =>
                                          const CircleAvatar(
                                        radius: 26.0,
                                        backgroundImage: AssetImage(
                                            "assets/images/blank_profile.png"),
                                      ),
                                    )
                                  : const CircleAvatar(
                                      radius: 25.0,
                                      backgroundImage: AssetImage(
                                          "assets/images/blank_profile.png"),
                                    ),
                            ),
                          ),
                        ),
                        title: Text("${passengers[index]['name']}"),
                        subtitle: Row(
                          children: [
                            const Text("Rating:"),
                            const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 3.0)),
                            passengers[index]['ratings_count'] > 0
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RatingBarIndicator(
                                        itemSize: 22.0,
                                        rating: passengers[index]
                                                ['ratings_sum'] /
                                            passengers[index]['ratings_count'],
                                        itemBuilder: (context, index) =>
                                            const Icon(
                                          Icons.star_rounded,
                                          color: Colors.amber,
                                        ),
                                      ),
                                      const Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 3.0)),
                                      Text(
                                          "(${passengers[index]['ratings_count']})"),
                                    ],
                                  )
                                : const Text("N/A"),
                          ],
                        ),
                        tileColor: Colors.white,
                        trailing: Icon(
                          Icons.circle,
                          color: colors[int.parse(passengers[index]['id']
                              [passengers[index]['id'].length - 1])],
                        ));
                  },
                  separatorBuilder: (context, index) => const Divider(),
                  itemCount: passengers.length),
              const Padding(padding: EdgeInsets.all(8.0))
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
          ));
    }
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: children));
  }

  Widget _createCarList() {
    final user = Provider.of<User>(context);
    final cars = user.cars;
    final keys = cars.keys.toList();
    return Container(
      color: const Color.fromARGB(123, 255, 255, 255),
      child: ListView.separated(
          shrinkWrap: true,
          itemBuilder: (context, index) {
            return ListTile(
              onTap: () {},
              onLongPress: () {},
              title: Text(cars[keys[index]]!["model"]),
              subtitle: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Seats: ${cars[keys[index]]!["seats"]}")),
              leading: Radio<String>(
                  value: keys[index],
                  groupValue: selectedCar,
                  onChanged: (value) {
                    selectedCar = value!;
                    setState(() {});
                  }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () async {
                      final car = await _createCar(id: int.parse(keys[index]));
                      if (car != null) {
                        car["car_id"] = int.parse(keys[index]);
                        SocketConnection.channel.add(
                            jsonEncode({'type': typeUpdateCar, 'data': car}));
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
                              content:
                                  const Text('This action cannot be undone'),
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
                      if (reply ?? false) {
                        SocketConnection.channel.add(jsonEncode(
                            {'type': typeRemoveCar, 'data': keys[index]}));
                      }
                    },
                    icon: const Icon(Icons.delete),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (context, index) => const Divider(),
          itemCount: cars.length),
    );
  }

  Future<Map<String, dynamic>?> _createCar({int? id}) async {
    ValueNotifier<({String? imagePath, String? mimeType})> selectedImage =
        ValueNotifier((imagePath: null, mimeType: null));
    ValueNotifier<Color?> finalColor = ValueNotifier(null);
    final car = id != null
        ? Provider.of<User>(context, listen: false).cars['$id']
        : null;
    if (car != null && car['color'] != null) {
      finalColor.value = Color(int.parse(car['color']));
    }
    List<String> suggestions =
        (await DefaultAssetBundle.of(context).loadString('assets/cars.txt'))
            .split('\n');
    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          ValueNotifier<int> seats = ValueNotifier<int>(2);
          if (car != null) {
            seats.value = car['seats'];
            _licensePlateController.text = car['license'];
            _modelNameController.text = car['model'];
          }
          final formKey = GlobalKey<FormState>();
          return Center(
            child: Stack(alignment: const FractionalOffset(0.5, 0), children: [
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
                              car != null ? 'Edit car' : 'Create a car',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Form(
                              key: formKey,
                              child: Column(
                                children: [
                                  Autocomplete<String>(
                                    fieldViewBuilder: (context,
                                        textEditingController,
                                        focusNode,
                                        onFieldSubmitted) {
                                      if (car != null) {
                                        textEditingController.text =
                                            car['model'];
                                      }
                                      return TextFormField(
                                        controller: textEditingController,
                                        focusNode: focusNode,
                                        decoration: const InputDecoration(
                                            hintText: "Car model"),
                                        validator: (value) => !suggestions
                                                .contains(value)
                                            ? "Please select a valid car model"
                                            : null,
                                        onEditingComplete: () {
                                          _modelNameController.text =
                                              textEditingController.text;
                                        },
                                      );
                                    },
                                    optionsBuilder: ((textEditingValue) {
                                      if (textEditingValue.text == '') {
                                        return const Iterable<String>.empty();
                                      }
                                      return suggestions.where((element) =>
                                          removeDiacritics(
                                                  element.toLowerCase())
                                              .contains(textEditingValue.text
                                                  .toLowerCase()));
                                    }),
                                    onSelected: (option) {
                                      _modelNameController.text = option;
                                    },
                                  ),
                                  TextFormField(
                                      controller: _licensePlateController,
                                      decoration: const InputDecoration(
                                          hintText: "License plate"),
                                      validator: (value) => value == null ||
                                              !licensePlateRegex
                                                  .hasMatch(value.toUpperCase())
                                          ? "Please enter a valid license plate number"
                                          : null),
                                ],
                              ),
                            ),
                            const Padding(padding: EdgeInsets.all(8.0)),
                            Row(
                              children: [
                                const Text("Available seats"),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 10.0)),
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
                                    }),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 6)),
                                ValueListenableBuilder(
                                    valueListenable: seats,
                                    builder: (context, value, child) {
                                      return Text(
                                        '$value',
                                        style: const TextStyle(fontSize: 16),
                                      );
                                    }),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 6)),
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
                                    }),
                              ],
                            ),
                            const Padding(padding: EdgeInsets.all(8.0)),
                            Row(
                              children: [
                                const Text("Choose color"),
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 15.0)),
                                IconButton(
                                  onPressed: () async {
                                    Color? reply = await showDialog(
                                        context: context,
                                        builder: (context) {
                                          ValueNotifier<Color> newColor =
                                              finalColor.value != null
                                                  ? ValueNotifier(
                                                      finalColor.value!)
                                                  : ValueNotifier(
                                                      Colors.red.shade900);
                                          return Dialog(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  height: 300,
                                                  width: 300,
                                                  child: StatefulBuilder(
                                                      builder:
                                                          (context, setState) {
                                                    return ColorWheelPicker(
                                                      wheelWidth: 30,
                                                      color: newColor.value,
                                                      onChanged: (color) {
                                                        newColor.value = color;
                                                        setState(() {});
                                                      },
                                                      onWheel: (wheel) {},
                                                    );
                                                  }),
                                                ),
                                                const Padding(
                                                    padding:
                                                        EdgeInsets.all(8.0)),
                                                ValueListenableBuilder(
                                                    valueListenable: newColor,
                                                    builder: (context, value,
                                                        child) {
                                                      return ColorIndicator(
                                                        height: 60,
                                                        width: 60,
                                                        borderColor:
                                                            Colors.black45,
                                                        hasBorder: true,
                                                        color: value,
                                                      );
                                                    }),
                                                const Padding(
                                                    padding:
                                                        EdgeInsets.all(10.0)),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    ValueListenableBuilder(
                                                        valueListenable:
                                                            newColor,
                                                        builder: (context,
                                                            value, child) {
                                                          return TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context,
                                                                      value),
                                                              child: const Text(
                                                                  "Select"));
                                                        }),
                                                    const Padding(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                horizontal:
                                                                    8.0)),
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, null),
                                                        child: const Text(
                                                            "Cancel"))
                                                  ],
                                                )
                                              ],
                                            ),
                                          );
                                        });
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
                                      }),
                                ),
                                ValueListenableBuilder(
                                    valueListenable: finalColor,
                                    builder: (context, value, child) {
                                      return Visibility(
                                        visible: value != null,
                                        child: IconButton(
                                            onPressed: () =>
                                                finalColor.value = null,
                                            icon: const Icon(Icons.clear)),
                                      );
                                    })
                              ],
                            ),
                            const Padding(padding: EdgeInsets.all(8)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ValueListenableBuilder(
                                    valueListenable: selectedImage,
                                    builder: (context, value, child) {
                                      return TextButton(
                                          onPressed: () async {
                                            if (formKey.currentState!
                                                .validate()) {
                                              String? imageName;

                                              if (value.imagePath != null &&
                                                  value.mimeType != null) {
                                                imageName = await uploadImage(
                                                    TypeOfImage.cars,
                                                    value.imagePath!,
                                                    value.mimeType!);
                                              }
                                              final modelName =
                                                  _modelNameController.text;
                                              final licensePlate =
                                                  normalizeLicensePlate(
                                                      _licensePlateController
                                                          .text);
                                              if (!mounted) return;
                                              Navigator.pop(context, {
                                                "model": modelName,
                                                "license": licensePlate,
                                                "seats": seats.value,
                                                "picture": imageName ??
                                                    car?['picture'],
                                                "color": finalColor.value?.value
                                                    .toString(),
                                              });
                                            }
                                          },
                                          child: const Text("Ok"));
                                    }),
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Cancel")),
                              ],
                            ),
                            const Padding(padding: EdgeInsets.all(5))
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
                          Image.file(File(result.imagePath!)).image))
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
                                imageUrl: car?['picture']);
                          })),
                ),
              ),
            ]),
          );
        }).then((value) {
      _modelNameController.clear();
      _licensePlateController.clear();
      return value;
    });
  }

  Widget _buildDriverScreen() {
    var children = <Widget>[];
    if (!driving) {
      if (Provider.of<User>(context).cars.isEmpty) {
        children = [
          const SizedBox(
            height: 100,
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              "Add a car to continue",
              style: TextStyle(fontSize: 20),
            ),
          )
        ];
      } else {
        children
          ..add(
            const SizedBox(
              height: 10,
            ),
          )
          ..add(const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Select car",
                style: TextStyle(fontSize: 20),
              )))
          ..add(Padding(
            padding: const EdgeInsets.all(8.0),
            child: _createCarList(),
          ));
      }
      children.add(Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: Provider.of<User>(context).cars.length >= 3
              ? null
              : () async {
                  final car = await _createCar();
                  if (car != null) {
                    SocketConnection.channel
                        .add(jsonEncode({'type': typeAddCar, 'data': car}));
                  }
                },
          style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(8.0)),
          child: const Icon(Icons.add),
        ),
      ));
    }
    if (driving) {
      if (!inRadius) {
        children.add(const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "The app will start looking for passengers once you get close to the bus stop",
                style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ));
      } else {
        return _createPassengersList();
      }
    }
    return Center(
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.large(
        heroTag: 'FAB1',
        tooltip: driving ? 'Stop driving' : 'Start driving',
        shape: const CircleBorder(),
        onPressed: selectedCar != null
            ? () {
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
                  setState(() {});
                } else {
                  if (positionStream.isPaused) {
                    positionStream.resume();
                  }
                  driving = true;
                  _sendDriver();
                  setState(() {});
                }
              }
            : null,
        child: Icon(
          !driving ? Icons.play_arrow_rounded : Icons.stop_rounded,
          size: 50,
        ));
  }

  void _onPositionChange(Position? position) async {
    if (position == null) {
      debugPrint('Unknown position');
      return;
    }
    coordinates = position;
    _sendDriver();
    if (arrivedAtBusStop && followDriver) {
      moveCamera(
          this,
          mapController,
          LatLng(coordinates!.latitude, coordinates!.longitude),
          mapController.camera.zoom);
    }
    if (passengers.isNotEmpty &&
        Geolocator.distanceBetween(position.latitude, position.longitude,
                busStop.latitude, busStop.longitude) <
            100 &&
        !arrivedAtBusStop) {
      arrivedAtBusStop = true;
      showArrived = true;
      moveCamera(this, mapController, busStop, 15.5);
      arrivedTimer = Timer(const Duration(seconds: 5), () {
        showArrived = false;
        setState(() {});
      });
    }
    if (passengers.isNotEmpty &&
        Geolocator.distanceBetween(position.latitude, position.longitude,
                university.latitude, university.longitude) <
            300 &&
        arrivedAtBusStop &&
        !arrivedAtUniversity) {
      arrivedAtUniversity = true;
      _getPassengersStreamSubscription.cancel();
      moveCamera(this, mapController,
          LatLng(coordinates!.latitude, coordinates!.longitude), 15.5);
      SocketConnection.channel
          .add(jsonEncode({'type': typeArrivedDestination, 'data': {}}));
      final List<double>? ratings = await arrivedDialog(
          context: context,
          users: passengers,
          typeOfUser: TypeOfUser.passenger);
      if (ratings == null) return;
      if (!mounted) return;
      SocketConnection.channel.add(jsonEncode({
        'type': typeSendRatings,
        'data': {
          'users': passengers.map((e) => e['id']).toList(),
          'ratings': ratings
        }
      }));
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
    )).listen(_onPositionChange);
    positionStream.pause();
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
                back: true),
          ),
          actions: [
            SwitchUserButton(
              context: context,
              skip: passengers.isEmpty || !inRadius,
              typeOfUser: TypeOfUser.driver,
            ),
            const UserImageButton(),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5.0))
          ]),
      body: _buildDriverScreen(),
      floatingActionButton: Visibility(
        visible: selectedCar != null && passengers.isEmpty,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Align(alignment: Alignment.bottomCenter, child: _buildFAB()),
        ),
      ),
    );
  }
}
