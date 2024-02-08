import 'dart:math';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/driver.dart';
import 'package:uni_pool/passenger.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/sensitive_storage.dart';
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/welcome.dart';
import 'constants.dart';
import 'package:uni_pool/socket_handler.dart';

class NetworkImageWithPlaceholder extends StatelessWidget {
  const NetworkImageWithPlaceholder(
      {super.key, required this.typeOfImage, this.imageUrl});

  final String? imageUrl;
  final TypeOfImage typeOfImage;

  @override
  Widget build(context) {
    if (imageUrl != null) {
      return CachedNetworkImage(
          imageUrl: 'http://$mediaHost/images/${typeOfImage.name}/$imageUrl',
          placeholder: (_, __) => const CircularProgressIndicator(),
          errorWidget: (_, __, ___) => const Icon(Icons.error_outline));
    }
    return Stack(alignment: AlignmentDirectional.center, children: [
      Container(
          height: 160,
          width: 160,
          color: Colors.grey.shade50,
          child: Icon(Icons.add_photo_alternate,
              color: Colors.grey.shade600, size: 50)),
      Positioned(
          bottom: 24,
          child: Text('Add photo',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 15)))
    ]);
  }
}

class UserProfileInfo extends StatelessWidget {
  const UserProfileInfo({super.key, required this.showSignout});

  final bool showSignout;

  @override
  Widget build(context) {
    return Selector<User,
            ({String name, String id, int ratingsSum, int ratingsCount})>(
        selector: (_, user) => (
              name: user.name,
              id: user.id,
              ratingsSum: user.ratingsSum,
              ratingsCount: user.ratingsCount
            ),
        builder: (context, user, child) {
          return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(24, 40, 24, 0)),
                Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                const Padding(padding: EdgeInsets.symmetric(vertical: 2.0)),
                Text(user.id, style: Theme.of(context).textTheme.titleMedium),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8.0)),
                RatingBarIndicator(
                    itemSize: 36.0,
                    rating: user.ratingsCount != 0
                        ? user.ratingsSum / user.ratingsCount
                        : 0,
                    itemBuilder: (context, index) =>
                        const Icon(Icons.star_rounded, color: Colors.amber)),
                const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
                TextButton(
                    onPressed: () async {
                      bool? reply = await showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                                title: const Text('Really sign out?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Yes')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('No'))
                                ]);
                          });
                      reply = reply ?? false;
                      if (!context.mounted) return;
                      if (reply) {
                        SecureStorage.deleteAllSecure();
                        SocketConnection.channel
                            .add(jsonEncode({'type': typeSignout, 'data': {}}));
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const WelcomePage()));
                      }
                    },
                    child: const Text("Sign out",
                        style: TextStyle(fontSize: 16.0))),
                const Padding(padding: EdgeInsets.symmetric(vertical: 6.0))
              ]);
        });
  }
}

class UserProfileCard extends StatelessWidget {
  const UserProfileCard({super.key, required this.showSignout});

  final bool showSignout;

  @override
  Widget build(context) {
    return Center(
        child: Stack(alignment: const FractionalOffset(0.5, 0), children: [
      Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(color: Colors.transparent, height: 80, width: 160),
            Container(
                width: min(MediaQuery.sizeOf(context).width - 2 * 40, 350),
                clipBehavior: Clip.hardEdge,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(24)),
                child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 34, 24, 0),
                        child: UserProfileInfo(showSignout: showSignout))))
          ]),
      IconButton(
          onPressed: () async {
            final result = await pickImage(imageQuality: userImageQuality);
            if (result == null || result.mimeType == null) return;
            final newImage = await uploadImage(
                TypeOfImage.users, result.imagePath!, result.mimeType!);
            if (newImage == null) return;
            if (!context.mounted) return;
            context.read<User>().setUserPicture(newImage);
            SocketConnection.channel.add(
                jsonEncode({'type': typeUpdateUserPicture, 'data': newImage}));
          },
          iconSize: 40,
          icon: CircleAvatar(
              radius: 70,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(70),
                  child: Selector<User, String?>(
                      selector: (_, user) => user.picture,
                      builder: (_, value, __) => NetworkImageWithPlaceholder(
                          imageUrl: value, typeOfImage: TypeOfImage.users)))))
    ]));
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.url, this.size = 22.0});
  final String? url;
  final double size;

  @override
  Widget build(context) {
    return url != null
        ? CachedNetworkImage(
            imageUrl: "http://$mediaHost/images/users/$url",
            imageBuilder: (context, imageProvider) => CircleAvatar(
              radius: size,
              backgroundImage: imageProvider,
            ),
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => CircleAvatar(
                radius: size,
                backgroundImage:
                    const AssetImage("assets/images/blank_profile.png")),
          )
        : CircleAvatar(
            radius: size,
            backgroundImage:
                const AssetImage('assets/images/blank_profile.png'));
  }
}

class UserImageButton extends StatelessWidget {
  const UserImageButton(
      {super.key, this.enablePress = true, this.showSignout = true});

  final bool enablePress;
  final bool showSignout;

  @override
  Widget build(context) {
    return IconButton(
        onPressed: enablePress
            ? () => showDialog(
                context: context,
                builder: (context) => UserProfileCard(showSignout: showSignout))
            : null,
        icon: Selector<User, String?>(
            builder: (_, value, __) => UserAvatar(url: value),
            selector: (_, user) => user.picture));
  }
}

class SubtitledButton extends StatelessWidget {
  const SubtitledButton(
      {super.key,
      required this.icon,
      required this.subtitle,
      required this.onPressed});

  final void Function()? onPressed;
  final Icon icon;
  final Widget subtitle;

  @override
  Widget build(context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton.filledTonal(
          onPressed: onPressed,
          icon: icon,
          iconSize: 70,
          color: Theme.of(context).primaryColor),
      const Padding(padding: EdgeInsets.all(5)),
      subtitle
    ]);
  }
}

class SwitchUserButton extends StatelessWidget {
  const SwitchUserButton(
      {super.key,
      required this.context,
      required this.skip,
      required this.typeOfUser,
      this.back = false});

  final BuildContext context;
  final bool skip;
  final TypeOfUser typeOfUser;
  final bool back;

  @override
  Widget build(context) {
    return IconButton(
        onPressed: () async {
          if (await stopDialog(context, skip, typeOfUser) && context.mounted) {
            SocketConnection.channel.add(jsonEncode({
              'type': typeOfUser == TypeOfUser.driver
                  ? typeStopDriver
                  : typeStopPassenger,
              'data': {}
            }));
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        (typeOfUser == TypeOfUser.driver) ^ back
                            ? const DriverPage()
                            : const PassengerPage()));
          }
        },
        iconSize: 26.0,
        icon: back
            ? const Icon(Icons.arrow_back)
            : typeOfUser == TypeOfUser.driver
                ? const Icon(Icons.directions_walk)
                : const Icon(Icons.directions_car),
        tooltip:
            'Switch to ${typeOfUser == TypeOfUser.driver ? 'passenger' : 'driver'} mode');
  }
}

class CustomMap extends StatelessWidget {
  const CustomMap(
      {super.key,
      required this.typeOfUser,
      required this.mapController,
      required this.markers,
      required this.coordinates,
      required this.showArrived,
      required this.onMove,
      required this.onPressGPS,
      required this.centerGPS,
      this.polylinePoints});

  final TypeOfUser typeOfUser;
  final MapController mapController;
  final List<Marker> markers;
  final Position? coordinates;
  final bool showArrived;
  final bool centerGPS;
  final List<LatLng>? polylinePoints;
  final void Function() onMove;
  final void Function() onPressGPS;

  @override
  Widget build(BuildContext context) {
    if (mapUrl.isEmpty) return const SizedBox.shrink();
    return FlutterMap(
        mapController: mapController,
        options: MapOptions(
            initialCenter: const LatLng(37.9923, 23.7764),
            initialZoom: 14.5,
            minZoom: 14,
            maxZoom: 16,
            cameraConstraint: CameraConstraint.contain(bounds: mapBounds),
            interactionOptions:
                const InteractionOptions(flags: ~InteractiveFlag.rotate),
            onPositionChanged: (position, hasGesture) {
              if (hasGesture) onMove();
            }),
        children: [
          TileLayer(
              urlTemplate: mapUrl,
              tileProvider: NetworkTileProvider(),
              // tileBounds: LatLngBounds(const LatLng(38.01304, 23.74121),
              //     const LatLng(37.97043, 23.80078)),
              evictErrorTileStrategy: EvictErrorTileStrategy.dispose),
          if (polylinePoints != null)
            PolylineLayer(polylines: [
              Polyline(
                  points: polylinePoints!,
                  color: Colors.lightBlue.shade400.withAlpha(200),
                  strokeWidth: 6)
            ]),
          MarkerLayer(
              markers: [
                    if (coordinates != null)
                      Marker(
                          point: LatLng(
                              coordinates!.latitude, coordinates!.longitude),
                          height: 14,
                          width: 14,
                          child: Container(
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue,
                                  boxShadow: [
                                BoxShadow(spreadRadius: 0.1, blurRadius: 2)
                              ])))
                  ] +
                  markers),
          const Padding(padding: EdgeInsets.all(30)),
          Align(
              alignment: const Alignment(1, -0.95),
              child: ElevatedButton(
                  onPressed: coordinates != null ? onPressGPS : null,
                  style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(5)),
                  child: Icon(centerGPS ? Icons.gps_fixed : Icons.gps_not_fixed,
                      size: 30))),
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
                          child: Text(
                              typeOfUser == TypeOfUser.driver
                                  ? 'Please wait for all passengers to board the car'
                                  : 'Your driver has arrived. Please board the car',
                              style: const TextStyle(fontSize: 30),
                              textAlign: TextAlign.center)))))
        ]);
  }
}
