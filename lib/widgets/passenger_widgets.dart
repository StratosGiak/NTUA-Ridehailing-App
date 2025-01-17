import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntua_ridehailing/constants.dart';
import 'package:ntua_ridehailing/utilities.dart';
import 'package:ntua_ridehailing/widgets/common_widgets.dart';

class PassengerStatusScreen extends StatelessWidget {
  const PassengerStatusScreen({
    super.key,
    required this.inRadius,
    required this.driverRefused,
    required this.requestTimedOut,
  });

  final bool inRadius;
  final bool driverRefused;
  final bool requestTimedOut;

  @override
  Widget build(BuildContext context) {
    if (!inRadius) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'The app will start looking for drivers once you get close to the bus stop',
            style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final children = [
      if (driverRefused)
        const Text('Ride cancelled', style: TextStyle(fontSize: 22.0)),
      if (requestTimedOut)
        const Text(
          "You didn't get the driver in time",
          style: TextStyle(
            fontSize: 22.0,
          ),
        ),
      const Text(
        'Searching for drivers...',
        style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.w600),
      ),
      const Padding(padding: EdgeInsets.all(20.0)),
      const CircularProgressIndicator.adaptive(),
    ];
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class DriverInfoBox extends StatelessWidget {
  const DriverInfoBox({
    super.key,
    required this.driver,
    required this.showDistance,
    required this.onTileTap,
  });

  final Map<String, dynamic> driver;
  final bool showDistance;
  final void Function() onTileTap;

  @override
  Widget build(BuildContext context) {
    final picture =
        driver['picture'] != null || driver['car']['picture'] != null
            ? CachedNetworkImage(
                cacheManager: CustomCacheManager(),
                imageUrl: driver['car']['picture'] != null
                    ? "$mediaHost/images/cars/${driver['car']['picture']}"
                    : "$mediaHost/images/users/${driver['picture']}",
                imageBuilder: (context, imageProvider) => Ink(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: imageProvider,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => showDriverPictures(
                      context,
                      userPicture: driver['picture'],
                      carPicture: driver['car']['picture'],
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
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text(
            'Driver',
            style: TextStyle(fontSize: 20),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8.0),
        ListTile(
          onTap: onTileTap,
          leading: SizedBox(
            width: 55,
            height: 55,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30.0),
              child: Material(
                borderRadius: BorderRadius.circular(30.0),
                child: picture,
              ),
            ),
          ),
          title: Text("${driver['full_name']}"),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (driver['ratings_count'] > 0) RatingBarWithCount(user: driver),
              Text("Model: ${driver['car']['model']}"),
              Text("License plate: ${driver['car']['license']}"),
              if (driver['car']['color'] != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Color:'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                    ),
                    ColorIndicator(
                      elevation: 1,
                      height: 16,
                      width: 50,
                      color: Color(driver['car']['color']),
                    ),
                  ],
                ),
              if (showDistance)
                Text("Distance: ${(Geolocator.distanceBetween(
                      driver["coords"]["latitude"],
                      driver["coords"]["longitude"],
                      busStop.latitude,
                      busStop.longitude,
                    ) / 25).round() * 25}m"),
            ],
          ),
        ),
      ],
    );
  }
}

class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    required this.context,
    required this.driver,
    required this.mapController,
    required this.coordinates,
    required this.showArrived,
    required this.showDistance,
    required this.onMove,
    required this.moveCameraController,
    required this.onPressGPS,
    required this.followGPS,
    required this.driverPositions,
  });

  final BuildContext context;
  final Map<String, dynamic> driver;
  final MapController mapController;
  final Position? coordinates;
  final bool showArrived;
  final bool showDistance;
  final void Function() onMove;
  final MoveCameraController moveCameraController;
  final void Function() onPressGPS;
  final bool followGPS;
  final ListQueue<LatLng> driverPositions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomMap(
            typeOfUser: TypeOfUser.passenger,
            mapController: mapController,
            markers: usersToMarkers([driver]),
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
            polylinePoints: driverPositions.toList(),
          ),
        ),
        DriverInfoBox(
          driver: driver,
          showDistance: showDistance,
          onTileTap: () {
            moveCameraController.moveCamera(
              LatLng(
                driver['coords']['latitude'],
                driver['coords']['longitude'],
              ),
              15.5,
            );
            onMove();
          },
        ),
      ],
    );
  }
}
