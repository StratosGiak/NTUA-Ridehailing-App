import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:uni_pool/widgets/common_widgets.dart';
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

Future<({String? imagePath, String? mimeType})?> pickImage({
  int? imageQuality = 100,
}) async {
  try {
    final selection = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: imageQuality,
      requestFullMetadata: false,
    );
    if (selection == null) return null;
    CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: selection.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      aspectRatioPresets: [CropAspectRatioPreset.square],
      uiSettings: [
        AndroidUiSettings(lockAspectRatio: true),
        IOSUiSettings(aspectRatioLockEnabled: true)
      ],
    );
    if (cropped == null) return null;
    final mimeType = lookupMimeType(cropped.path);
    return (imagePath: cropped.path, mimeType: mimeType);
  } on PlatformException catch (e) {
    debugPrint('Error: $e');
    return null;
  }
}

Future<String?> uploadImage(
  BuildContext? context,
  TypeOfImage typeOfImage,
  String path,
  String fileType,
) async {
  if (fileType != 'image/jpeg' && fileType != 'image/png') return null;
  var request = http.MultipartRequest(
    'POST',
    Uri.parse('$mediaHost/images/${typeOfImage.name}'),
  );
  request.files.add(
    await http.MultipartFile.fromPath(
      'file',
      path,
      contentType: MediaType('image', fileType.split('/')[1]),
    ),
  );
  final response = await http.Response.fromStream(await request.send());
  if (response.statusCode == 200) {
    return response.body;
  }
  if (response.statusCode == 413) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(snackBarFileSize);
    }
  }
  return null;
}

Future<bool> signOutAlert({
  required BuildContext context,
  required Widget content,
}) async {
  void onConfirmPressed(BuildContext context) {
    SecureStorage.deleteAllSecure();
    SocketConnection.channel.add(jsonEncode({'type': typeSignout, 'data': {}}));
    context.read<User>().setUser(null);
    Navigator.pop(context, true);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Sign out');
  const cancelChild = Text('Cancel');

  bool? reply = await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog.adaptive(
      title: const Text('Really sign out?'),
      content: content,
      actions: Platform.isIOS
          ? [
              CupertinoDialogAction(
                onPressed: () => onCancelPressed(context),
                isDefaultAction: true,
                child: cancelChild,
              ),
              CupertinoDialogAction(
                onPressed: () => onConfirmPressed(context),
                isDestructiveAction: true,
                child: confirmChild,
              ),
            ]
          : [
              TextButton(
                onPressed: () => onCancelPressed(context),
                child: cancelChild,
              ),
              TextButton(
                onPressed: () => onConfirmPressed(context),
                child: confirmChild,
              ),
            ],
    ),
  );
  return reply ?? false;
}

Future<Color?> colorWheelDialog(BuildContext context, Color? initialColor) {
  return showAdaptiveDialog<Color>(
    context: context,
    builder: (context) {
      ValueNotifier<Color> newColor = initialColor != null
          ? ValueNotifier(initialColor)
          : ValueNotifier(Colors.red.shade900);
      return Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 300,
              width: 300,
              child: ValueListenableBuilder(
                valueListenable: newColor,
                builder: (context, value, child) {
                  return ColorWheelPicker(
                    wheelWidth: 30,
                    color: newColor.value,
                    onChanged: (color) => newColor.value = color,
                    onWheel: (wheel) {},
                  );
                },
              ),
            ),
            const Padding(padding: EdgeInsets.all(8.0)),
            ValueListenableBuilder(
              valueListenable: newColor,
              builder: (context, value, child) {
                return ColorIndicator(
                  height: 60,
                  width: 60,
                  borderColor: Colors.black45,
                  hasBorder: true,
                  color: value,
                );
              },
            ),
            const Padding(padding: EdgeInsets.all(10.0)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, newColor.value),
                  child: const Text('Select'),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0)),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

Future<bool?> acceptDialog(BuildContext context, {Widget? timerDisplay}) {
  final dialogRoute = DialogRoute<bool?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(5.0)),
          const Padding(
            padding: EdgeInsets.all(10.0),
            child: Text(
              'A driver is available. Accept them?',
              style: TextStyle(
                fontSize: 25.0,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (timerDisplay != null) timerDisplay,
          const Padding(padding: EdgeInsets.all(10.0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filled(
                onPressed: () => Navigator.pop(context, true),
                style: ButtonStyle(
                  backgroundColor:
                      MaterialStatePropertyAll(Colors.green.shade300),
                ),
                iconSize: 55.0,
                icon: const Icon(Icons.check_rounded),
              ),
              IconButton.filled(
                onPressed: () => Navigator.pop(context, false),
                style: ButtonStyle(
                  backgroundColor:
                      MaterialStatePropertyAll(Colors.red.shade300),
                ),
                iconSize: 55.0,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.all(10.0)),
        ],
      ),
    ),
  );
  if (ModalRoute.of(context)?.isCurrent != true) {
    Navigator.pop(context);
    return Navigator.push<bool?>(context, dialogRoute);
  } else {
    return Navigator.push<bool?>(context, dialogRoute);
  }
}

Future<List<double>?> arrivedDialog({
  required BuildContext context,
  required List<Map<String, dynamic>> users,
  required TypeOfUser typeOfUser,
}) async {
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
              itemBuilder: (context, index) =>
                  const Icon(Icons.star_rounded, color: Colors.amber),
              onRatingUpdate: (rating) {
                ratings[index].value = rating;
              },
            ),
            Visibility(
              visible: value != 0,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: IconButton(
                onPressed: () => ratings[index].value = 0,
                iconSize: 30,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        );
      },
    ),
  );
  final dialogRoute = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 30.0, vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 14.0)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'You have reached your destination!',
              style: TextStyle(
                fontSize: 26.0,
                fontWeight: FontWeight.w500,
              ),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Submit',
                      style: TextStyle(fontSize: 18.0),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 18.0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  bool? reply;
  if (ModalRoute.of(context)?.isCurrent != true) {
    Navigator.pop(context);
    reply = await Navigator.push<bool>(context, dialogRoute);
  } else {
    reply = await Navigator.push<bool>(context, dialogRoute);
  }
  if (!(reply ?? false)) return null;
  final ratingsList = ratings.map((e) => e.value).toList();
  if (ratingsList.every((element) => element == 0)) return null;
  return ratingsList;
}

Future<bool> stopDialog(
  BuildContext context,
  bool skip,
  bool back,
  TypeOfUser typeOfUser,
) async {
  if (skip) return Future.value(true);
  void onConfirmPressed(BuildContext context) {
    Navigator.pop(context, true);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Yes');
  const cancelChild = Text('No');

  bool? reply = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog.adaptive(
        title: Text(
          back
              ? 'Really stop ${typeOfUser == TypeOfUser.driver ? 'driving' : 'waiting for drivers'}'
              : 'Really switch to ${typeOfUser == TypeOfUser.driver ? 'passenger' : 'driver'} mode?',
        ),
        content: const Text('The current ride will be cancelled'),
        actions: Platform.isIOS
            ? [
                CupertinoDialogAction(
                  onPressed: () => onCancelPressed(context),
                  isDefaultAction: true,
                  child: cancelChild,
                ),
                CupertinoDialogAction(
                  onPressed: () => onConfirmPressed(context),
                  isDestructiveAction: true,
                  child: confirmChild,
                ),
              ]
            : [
                TextButton(
                  onPressed: () => onCancelPressed(context),
                  child: cancelChild,
                ),
                TextButton(
                  onPressed: () => onConfirmPressed(context),
                  child: confirmChild,
                ),
              ],
      );
    },
  );
  return reply ?? false;
}

List<Marker> usersToMarkers(List<Map<String, dynamic>> users) => users
    .map(
      (user) => Marker(
        height: 22,
        width: 22,
        point: LatLng(user['coords']['latitude'], user['coords']['longitude']),
        child: Stack(
          children: [
            Builder(
              builder: (context) {
                final color =
                    user['car'] != null && user['car']['color'] != null
                        ? Color(user['car']['color'])
                        : colors[int.parse(user['id'][user['id'].length - 1])];
                // final luma = sqrt(
                //   color.red * color.red * 0.299 +
                //       color.green * color.green * 0.587 +
                //       color.blue * color.blue * 0.114,
                // ).toInt();
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: Colors.white,
                      // color.computeLuminance() < 0.5
                      //     ? Colors.white
                      //     : Colors.black,
                      width: 3,
                    ),
                    boxShadow: const [
                      BoxShadow(spreadRadius: 0.1, blurRadius: 3),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    )
    .toList();

void showPassengerPicture(BuildContext context, String pictureURL) =>
    showAdaptiveDialog<void>(
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
                  cacheManager: CustomCacheManager(),
                  imageUrl: '$mediaHost/images/users/$pictureURL',
                  placeholder: (context, url) =>
                      const CircularProgressIndicator.adaptive(),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ),
          ),
        );
      },
    );

void showDriverPictures(
  BuildContext context,
  String? userPicture,
  String? carPicture,
) {
  List<Widget> images = [
    if (userPicture != null)
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: FittedBox(
          child: CachedNetworkImage(
            cacheManager: CustomCacheManager(),
            imageUrl: '$mediaHost/images/users/$userPicture',
            placeholder: (context, url) =>
                const CircularProgressIndicator.adaptive(),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      ),
    if (carPicture != null)
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: FittedBox(
          child: CachedNetworkImage(
            cacheManager: CustomCacheManager(),
            imageUrl: '$mediaHost/images/cars/$carPicture',
            placeholder: (context, url) =>
                const CircularProgressIndicator.adaptive(),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      ),
  ];
  showAdaptiveDialog<void>(
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
          child: PageView(
            controller: PageController(viewportFraction: 0.85),
            children: images,
          ),
        ),
      );
    },
  );
}
