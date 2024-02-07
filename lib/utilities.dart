import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/sensitive_storage.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/widgets.dart';
import 'package:mime/mime.dart';
import 'constants.dart';

StreamController<String> wsStreamController = StreamController.broadcast();

String convertCharacter(String c) {
  switch (c) {
    case 'Α':
      return 'A';
    case 'Β':
      return 'B';
    case 'Ε':
      return 'E';
    case 'Ζ':
      return 'Z';
    case 'Η':
      return 'H';
    case 'Ι':
      return 'I';
    case 'Κ':
      return 'K';
    case 'Μ':
      return 'M';
    case 'Ν':
      return 'N';
    case 'Ο':
      return 'O';
    case 'Ρ':
      return 'P';
    case 'Τ':
      return 'T';
    case 'Υ':
      return 'Y';
    case 'Χ':
      return 'X';
    default:
      return c;
  }
}

String normalizeLicensePlate(String text) {
  var normalized = text.toUpperCase().characters.map(convertCharacter).toList();
  switch (normalized[3]) {
    case '-':
      break;
    case ' ':
      normalized[3] = '-';
      break;
    default:
      normalized.insert(3, '-');
      break;
  }
  return normalized.join();
}

Future<({String? imagePath, String? mimeType})?> pickImage(
    {int? imageQuality = 100}) async {
  try {
    final selection = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: imageQuality,
        requestFullMetadata: false);
    if (selection == null) return null;
    CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: selection.path,
        aspectRatioPresets: [CropAspectRatioPreset.square],
        uiSettings: [AndroidUiSettings()]);
    if (cropped == null) return null;
    final mimeType = lookupMimeType(cropped.path);
    return (imagePath: cropped.path, mimeType: mimeType);
  } on PlatformException catch (e) {
    debugPrint("Error: $e");
    return null;
  }
}

Future<String?> uploadImage(
    TypeOfImage typeOfImage, String path, String fileType) async {
  if (fileType != "image/jpeg" && fileType != "image/png") return null;
  var request = http.MultipartRequest(
      'POST', Uri.parse('http://$mediaHost/images/${typeOfImage.name}'));
  request.files.add(await http.MultipartFile.fromPath('file', path,
      contentType: MediaType('image', fileType.split('/')[1])));
  final response = await http.Response.fromStream(await request.send());
  if (response.statusCode == 200) {
    return response.body;
  }
  return null;
}

Future showProfile(
    {required BuildContext context, required bool showSignout}) async {
  await showDialog(
    context: context,
    builder: (context) {
      return UserProfileCard(showSignout: showSignout);
    },
  );
}

Future<bool> signOutAlert(
    {required BuildContext context, required Widget content}) async {
  bool? reply = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Really sign out?'),
      content: content,
      actions: [
        TextButton(
            onPressed: () {
              SecureStorage.deleteAllSecure();
              SocketConnection.channel
                  .add(jsonEncode({'type': typeSignout, 'data': {}}));
              context.read<User>().setUser();
              Navigator.pop(context, true);
            },
            child: const Text('Yes')),
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'))
      ],
    ),
  );
  return reply ?? false;
}

Future<List<double>?> arrivedDialog(
    {required BuildContext context,
    required List<Map<String, dynamic>> users,
    required TypeOfUser typeOfUser}) async {
  List<ValueNotifier<double>> ratings =
      List.generate(users.length, (index) => ValueNotifier(0));
  List<Widget> ratingBars = List.generate(
      users.length,
      (index) => ValueListenableBuilder(
          valueListenable: ratings[index],
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
                    onRatingUpdate: (rating) {
                      ratings[index].value = rating;
                    }),
                Visibility(
                  visible: value != 0,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                      onPressed: () {
                        ratings[index].value = 0;
                      },
                      iconSize: 30,
                      icon: const Icon(Icons.close)),
                ),
              ],
            );
          }));
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
                  style: TextStyle(fontSize: 26.0, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 6.0)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  "Please rate your experience with the ${typeOfUser.name}${users.length == 1 ? '' : 's'} (optional)",
                  style: const TextStyle(fontSize: 16.0),
                  textAlign: TextAlign.center,
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
              ListView.separated(
                shrinkWrap: true,
                itemCount: users.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text("${users[index]['name']}"),
                    leading: UserAvatar(
                      url: users[index]['picture'],
                      size: 26.0,
                    ),
                    subtitle: ratingBars[index],
                  );
                },
                separatorBuilder: (context, index) =>
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6.0)),
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
  final ratingsList = ratings.map((e) => e.value).toList();
  if (ratingsList.any((element) => element != 0)) return null;
  return ratingsList;
}

void moveCamera(TickerProvider tickerProvider, MapController mapController,
    LatLng dest, double zoom) {
  final camera = mapController.camera;
  final latTween =
      Tween<double>(begin: camera.center.latitude, end: dest.latitude);
  final lngTween =
      Tween<double>(begin: camera.center.longitude, end: dest.longitude);
  final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);
  final controller = AnimationController(
      vsync: tickerProvider, duration: const Duration(milliseconds: 1000));
  final Animation<double> animation =
      CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);
  controller.addListener(() {
    // if (!waitingForPassengers) {
    //   controller.dispose();
    //   return;
    // }
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

Future<bool> stopDialog(
    BuildContext context, bool skip, TypeOfUser typeOfUser) async {
  if (skip) return Future.value(true);
  bool? reply = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
              'Really switch to ${typeOfUser == TypeOfUser.driver ? 'passenger' : 'driver'} mode?'),
          content: const Text('The current ride will be cancelled'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes')),
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'))
          ],
        );
      });
  return reply ?? false;
}
