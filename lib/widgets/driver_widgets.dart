import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/widgets/common_widgets.dart';

class CarList extends StatelessWidget {
  const CarList({
    super.key,
    required this.selected,
    required this.onTap,
    required this.onEditPressed,
  });

  final ValueNotifier<String?> selected;
  final void Function() onTap;
  final Future<Car?> Function(String) onEditPressed;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<User>();
    final cars = user.cars;
    final keys = cars.keys.toList();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color.fromARGB(144, 255, 255, 255),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemBuilder: (context, index) {
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            onTap: () {
              selected.value = keys[index];
              onTap();
            },
            onLongPress: () {},
            title: Text(cars[keys[index]]!.model),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: Text('Seats: ${cars[keys[index]]!.seats}'),
            ),
            leading: Radio<String>(
              value: keys[index],
              groupValue: selected.value,
              onChanged: (value) {
                selected.value = value;
                onTap();
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () async {
                    final car = await onEditPressed(keys[index]);
                    if (car != null) {
                      car.id = keys[index];
                      SocketConnection.channel.add(
                        jsonEncode({'type': typeUpdateCar, 'data': car}),
                      );
                    }
                  },
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit',
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
                              onPressed: () => Navigator.pop(context, false),
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
                  tooltip: 'Delete',
                ),
              ],
            ),
          );
        },
        separatorBuilder: (context, index) => const Divider(
          indent: 20,
          endIndent: 20,
          height: 8,
        ),
        itemCount: cars.length,
      ),
    );
  }
}

class CarListScreen extends StatelessWidget {
  const CarListScreen({
    super.key,
    required this.carList,
    required this.onPressed,
  });

  final Widget carList;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final children = [
      if (context.watch<User>().cars.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(8.0, 100.0, 8.0, 8.0),
          child: Text(
            'Add a car to continue',
            style: TextStyle(fontSize: 20),
          ),
        ),
      if (context.watch<User>().cars.isNotEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('Select car', style: TextStyle(fontSize: 20)),
        ),
      if (context.watch<User>().cars.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: carList,
        ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Tooltip(
          message: 'Add car',
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(8.0),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    ];
    return Center(child: Column(children: children));
  }
}

class DriverStatusScreen extends StatelessWidget {
  const DriverStatusScreen({
    super.key,
    required this.inRadius,
    required this.waitingForPassengers,
    required this.requestTimeout,
    required this.passengersCancelled,
  });

  final bool inRadius;
  final bool waitingForPassengers;
  final bool requestTimeout;
  final bool passengersCancelled;

  @override
  Widget build(BuildContext context) {
    if (!inRadius) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'The app will start looking for passengers once you get close to the bus stop',
            style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final children = waitingForPassengers
        ? [
            const Text(
              'Waiting for passengers to respond...',
              style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Padding(padding: EdgeInsets.all(10.0)),
            const CircularProgressIndicator(),
          ]
        : [
            if (requestTimeout)
              const Text(
                'No passengers responded',
                style: TextStyle(fontSize: 22.0),
                textAlign: TextAlign.center,
              ),
            if (passengersCancelled)
              const Text(
                'All the passengers cancelled the ride',
                style: TextStyle(fontSize: 22.0),
                textAlign: TextAlign.center,
              ),
            const Text(
              'Looking for passengers...',
              style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Padding(padding: EdgeInsets.all(10.0)),
            const CircularProgressIndicator(),
          ];
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    required this.context,
    required this.passengers,
    required this.mapController,
    required this.coordinates,
    required this.showArrived,
    required this.onMove,
    required this.moveCameraController,
    required this.onPressGPS,
    required this.followGPS,
  });

  final BuildContext context;
  final List<Map<String, dynamic>> passengers;
  final MapController mapController;
  final Position? coordinates;
  final bool showArrived;
  final void Function() onMove;
  final MoveCameraController moveCameraController;
  final void Function() onPressGPS;
  final bool followGPS;

  @override
  Widget build(BuildContext context) {
    final children = [
      Expanded(
        child: CustomMap(
          typeOfUser: TypeOfUser.driver,
          mapController: mapController,
          markers: usersToMarkers(passengers),
          coordinates: coordinates,
          showArrived: showArrived,
          onMove: onMove,
          moveCameraController: moveCameraController,
          onPressGPS: () {
            moveCameraController.moveCamera(
              LatLng(coordinates!.latitude, coordinates!.longitude),
              15.5,
            );
            onPressGPS();
          },
          followGPS: followGPS,
        ),
      ),
      PassengerInfoBox(
        passengers: passengers,
        onTileTap: (index) {
          moveCameraController.moveCamera(
            LatLng(
              passengers[index]['coords']['latitude'],
              passengers[index]['coords']['longitude'],
            ),
            15.5,
          );
          onMove();
        },
      ),
    ];
    return Column(children: children);
  }
}

class PassengerInfoBox extends StatelessWidget {
  const PassengerInfoBox({
    super.key,
    required this.passengers,
    required this.onTileTap,
  });

  final List<Map<String, dynamic>> passengers;
  final void Function(int) onTileTap;

  @override
  Widget build(BuildContext context) {
    Widget picture(int index) => passengers[index]['picture'] != null
        ? CachedNetworkImage(
            cacheManager: CustomCacheManager(),
            imageUrl: "$mediaHost/images/users/${passengers[index]['picture']}",
            imageBuilder: (context, imageProvider) => Ink(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: imageProvider,
                ),
              ),
              child: InkWell(
                onTap: () => showPassengerPicture(
                  context,
                  passengers[index]['picture'],
                ),
                splashFactory: InkSplash.splashFactory,
              ),
            ),
            placeholder: (context, url) => Image.asset(
              'assets/images/blank_profile.png',
            ),
            errorWidget: (context, url, error) => Image.asset(
              'assets/images/blank_profile.png',
            ),
          )
        : Image.asset('assets/images/blank_profile.png');
    final children = [
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
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
        itemBuilder: (context, index) {
          return ListTile(
            onTap: () => onTileTap(index),
            leading: SizedBox(
              width: 55,
              height: 55,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30.0),
                child: Material(
                  borderRadius: BorderRadius.circular(30.0),
                  child: picture(index),
                ),
              ),
            ),
            title: Text("${passengers[index]['name']}"),
            subtitle: passengers[index]['ratings_count'] > 0
                ? RatingBarWithCount(user: passengers[index])
                : null,
            tileColor: Colors.white,
            trailing: Icon(
              Icons.circle,
              color: colors[int.parse(
                passengers[index]['id'][passengers[index]['id'].length - 1],
              )],
            ),
          );
        },
        separatorBuilder: (context, index) => const Divider(),
        itemCount: passengers.length,
      ),
    ];
    return Container(color: Colors.white, child: Column(children: children));
  }
}
