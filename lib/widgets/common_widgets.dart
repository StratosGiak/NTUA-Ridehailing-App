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
import 'package:uni_pool/utilities.dart';
import 'package:uni_pool/constants.dart';
import 'package:uni_pool/socket_handler.dart';

const snackBarNSFW = SnackBar(
  duration: Duration(seconds: 5),
  content: Text(
    'An inappropriate image was detected and taken down',
  ),
);

const snackBarFileSize = SnackBar(
  duration: Duration(seconds: 5),
  content: Text(
    'Image exceeds maximum file size (2MB). Please try choosing a smaller image',
  ),
);

class ImageWithPlaceholder extends StatelessWidget {
  const ImageWithPlaceholder({
    super.key,
    this.imageProvider,
    this.onTap,
  });

  final ImageProvider? imageProvider;
  final void Function()? onTap;

  @override
  Widget build(context) {
    Widget child = imageProvider != null
        ? Ink(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: imageProvider!,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              splashFactory: InkSplash.splashFactory,
            ),
          )
        : Ink(
            color: Colors.white,
            child: Stack(
              alignment: AlignmentDirectional.center,
              children: [
                Icon(
                  Icons.add_photo_alternate,
                  color: Colors.grey.shade600,
                  size: 50,
                ),
                Positioned(
                  bottom: 24,
                  child: Text(
                    'Add photo',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                  ),
                ),
                Positioned.fill(
                  child: InkWell(
                    splashFactory: InkSplash.splashFactory,
                    onTap: onTap,
                  ),
                ),
              ],
            ),
          );
    return SizedBox(
      width: 140,
      height: 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(70),
        child: Material(
          borderRadius: BorderRadius.circular(70),
          child: child,
        ),
      ),
    );
  }
}

class NetworkImageWithPlaceholder extends StatelessWidget {
  const NetworkImageWithPlaceholder({
    super.key,
    required this.typeOfImage,
    this.imageUrl,
    this.onTap,
  });

  final String? imageUrl;
  final TypeOfImage typeOfImage;
  final void Function()? onTap;

  @override
  Widget build(context) {
    Widget child = imageUrl != null
        ? CachedNetworkImage(
            cacheManager: CustomCacheManager(),
            imageUrl: '$mediaHost/images/${typeOfImage.name}/$imageUrl',
            imageBuilder: (context, imageProvider) => Ink(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: imageProvider,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                splashFactory: InkSplash.splashFactory,
              ),
            ),
            placeholder: (_, __) => const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
            errorWidget: (_, __, ___) => Ink(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 50,
                    color: Colors.red.shade900,
                  ),
                  Positioned.fill(
                    child: InkWell(
                      splashFactory: InkSplash.splashFactory,
                      onTap: onTap,
                    ),
                  ),
                ],
              ),
            ),
          )
        : Ink(
            color: Colors.white,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate,
                  color: Colors.grey.shade600,
                  size: 50,
                ),
                Positioned(
                  bottom: 24,
                  child: Text(
                    'Add photo',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                  ),
                ),
                Positioned.fill(
                  child: InkWell(
                    splashFactory: InkSplash.splashFactory,
                    onTap: onTap,
                  ),
                ),
              ],
            ),
          );
    return SizedBox(
      width: 140,
      height: 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(70),
        child: Material(
          borderRadius: BorderRadius.circular(70),
          child: child,
        ),
      ),
    );
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
                  const Icon(Icons.star_rounded, color: Colors.amber),
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
            TextButton(
              onPressed: () async {
                await signOutAlert(
                  context: context,
                  content: const SizedBox(),
                );
              },
              child: const Text(
                'Sign out',
                style: TextStyle(fontSize: 16.0),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 6.0)),
          ],
        );
      },
    );
  }
}

class UserProfileCard extends StatelessWidget {
  const UserProfileCard({super.key, required this.showSignout});

  final bool showSignout;

  @override
  Widget build(context) {
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
                width: min(MediaQuery.sizeOf(context).width - 2 * 40, 350),
                clipBehavior: Clip.hardEdge,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(24)),
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 34, 24, 0),
                    child: UserProfileInfo(showSignout: showSignout),
                  ),
                ),
              ),
            ],
          ),
          Selector<User, String?>(
            selector: (_, user) => user.picture,
            builder: (_, value, __) => NetworkImageWithPlaceholder(
              typeOfImage: TypeOfImage.users,
              imageUrl: value,
              onTap: () async {
                final result = await pickImage(imageQuality: userImageQuality);
                if (result == null || result.mimeType == null) return;
                final newImage = await uploadImage(
                  context.mounted ? context : null,
                  TypeOfImage.users,
                  result.imagePath!,
                  result.mimeType!,
                );
                if (newImage == null) return;
                if (!context.mounted) return;
                context.read<User>().setUserPicture(newImage);
                SocketConnection.channel.add(
                  jsonEncode({'type': typeUpdateUserPicture, 'data': newImage}),
                );
              },
            ),
          ),
        ],
      ),
    );
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
            cacheManager: CustomCacheManager(),
            imageUrl: '$mediaHost/images/users/$url',
            imageBuilder: (context, imageProvider) => CircleAvatar(
              radius: size,
              backgroundImage: imageProvider,
            ),
            placeholder: (context, url) =>
                const CircularProgressIndicator.adaptive(),
            errorWidget: (context, url, error) => CircleAvatar(
              radius: size,
              backgroundImage:
                  const AssetImage('assets/images/blank_profile.png'),
            ),
          )
        : CircleAvatar(
            radius: size,
            backgroundImage:
                const AssetImage('assets/images/blank_profile.png'),
          );
  }
}

class UserImageButton extends StatelessWidget {
  const UserImageButton({
    super.key,
    this.enablePress = true,
    this.showSignout = true,
  });

  final bool enablePress;
  final bool showSignout;

  @override
  Widget build(context) {
    return IconButton(
      onPressed: enablePress
          ? () => showAdaptiveDialog<void>(
                barrierDismissible: true,
                context: context,
                builder: (context) => UserProfileCard(showSignout: showSignout),
              )
          : null,
      icon: Selector<User, String?>(
        builder: (_, value, __) => UserAvatar(url: value),
        selector: (_, user) => user.picture,
      ),
      tooltip: 'Account info',
    );
  }
}

class SubtitledButton extends StatelessWidget {
  const SubtitledButton({
    super.key,
    required this.icon,
    required this.subtitle,
    required this.onPressed,
  });

  final void Function()? onPressed;
  final Icon icon;
  final Widget subtitle;

  @override
  Widget build(context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: icon,
          iconSize: 70,
          color: Theme.of(context).primaryColor,
        ),
        const Padding(padding: EdgeInsets.all(5)),
        subtitle,
      ],
    );
  }
}

class SwitchModeButton extends StatelessWidget {
  const SwitchModeButton({
    super.key,
    required this.context,
    required this.skip,
    required this.typeOfUser,
    this.back = false,
  });

  final BuildContext context;
  final bool skip;
  final TypeOfUser typeOfUser;
  final bool back;

  @override
  Widget build(context) {
    return IconButton(
      onPressed: () async {
        if (await stopDialog(context, skip, back, typeOfUser) &&
            context.mounted) {
          SocketConnection.channel.add(
            jsonEncode({
              'type': typeOfUser == TypeOfUser.driver
                  ? typeStopDriver
                  : typeStopPassenger,
              'data': {},
            }),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => (typeOfUser == TypeOfUser.driver) ^ back
                  ? const PassengerPage()
                  : const DriverPage(),
            ),
          );
        }
      },
      iconSize: 26.0,
      icon: back
          ? Icon(Icons.adaptive.arrow_back)
          : typeOfUser == TypeOfUser.driver
              ? const Icon(Icons.directions_walk)
              : const Icon(Icons.directions_car),
      tooltip: back
          ? "Stop ${typeOfUser == TypeOfUser.driver ? 'driving' : 'waiting for drivers'}"
          : 'Switch to ${typeOfUser == TypeOfUser.driver ? 'passenger' : 'driver'} mode',
    );
  }
}

class MoveCameraController {
  void Function(LatLng, double) moveCamera =
      (_, __) => debugPrint('Move camera controller error');
}

class CustomMap extends StatefulWidget {
  const CustomMap({
    super.key,
    required this.typeOfUser,
    required this.mapController,
    required this.markers,
    required this.coordinates,
    required this.showArrived,
    required this.onMove,
    required this.onPressGPS,
    required this.followGPS,
    required this.moveCameraController,
    this.polylinePoints,
  });

  final TypeOfUser typeOfUser;
  final MapController mapController;
  final List<Marker> markers;
  final Position? coordinates;
  final bool showArrived;
  final bool followGPS;
  final List<LatLng>? polylinePoints;
  final void Function() onMove;
  final void Function() onPressGPS;
  final MoveCameraController moveCameraController;

  @override
  State<CustomMap> createState() => _CustomMapState();
}

class _CustomMapState extends State<CustomMap> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.moveCameraController.moveCamera = moveCamera;
  }

  void moveCamera(LatLng dest, double zoom) {
    final camera = widget.mapController.camera;
    final latTween =
        Tween<double>(begin: camera.center.latitude, end: dest.latitude);
    final lngTween =
        Tween<double>(begin: camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);
    controller.addListener(() {
      widget.mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
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

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: busStop,
        initialZoom: 14.5,
        minZoom: 14,
        maxZoom: 16,
        cameraConstraint: CameraConstraint.contain(bounds: mapBounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) widget.onMove();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: mapUrl,
          tileProvider: AssetTileProvider(),
          tileBounds: LatLngBounds(
            const LatLng(38.01304, 23.74121),
            const LatLng(37.97043, 23.80078),
          ),
        ),
        if (widget.polylinePoints != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.polylinePoints!,
                color: Colors.lightBlue.shade400.withAlpha(200),
                strokeWidth: 6,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
                if (widget.coordinates != null)
                  Marker(
                    point: LatLng(
                      widget.coordinates!.latitude,
                      widget.coordinates!.longitude,
                    ),
                    height: 14,
                    width: 14,
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        boxShadow: [
                          BoxShadow(spreadRadius: 0.1, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
              ] +
              widget.markers,
        ),
        const Padding(padding: EdgeInsets.all(30)),
        Align(
          alignment: const Alignment(1, -0.95),
          child: ElevatedButton(
            onPressed: widget.coordinates != null ? widget.onPressGPS : null,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(5),
            ),
            child: Icon(
              widget.followGPS ? Icons.gps_fixed : Icons.gps_not_fixed,
              size: 30,
            ),
          ),
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
        Visibility(
          visible: widget.showArrived,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white70,
                ),
                child: Text(
                  widget.typeOfUser == TypeOfUser.driver
                      ? 'Please wait for all passengers to board the car'
                      : 'Your driver has arrived. Please board the car',
                  style: const TextStyle(fontSize: 30),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LargeFAB extends StatelessWidget {
  const LargeFAB({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.inProgress,
  });

  final void Function()? onPressed;
  final String tooltip;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.large(
      heroTag: 'FAB1',
      shape: const CircleBorder(),
      tooltip: tooltip,
      onPressed: onPressed,
      child: Icon(
        inProgress ? Icons.stop_rounded : Icons.play_arrow_rounded,
        size: 50,
      ),
    );
  }
}

class RatingBarWithCount extends StatelessWidget {
  const RatingBarWithCount({
    super.key,
    required this.user,
  });

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RatingBarIndicator(
          itemSize: 22.0,
          rating: user['ratings_sum'] / user['ratings_count'],
          itemBuilder: (context, index) => const Icon(
            Icons.star_rounded,
            color: Colors.amber,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 3.0),
        ),
        Text(
          "(${user['ratings_count']})",
        ),
      ],
    );
  }
}
