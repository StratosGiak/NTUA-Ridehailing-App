import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntua_ridehailing/authenticator.dart';
import 'package:ntua_ridehailing/socket_handler.dart';
import 'package:ntua_ridehailing/widgets/common_widgets.dart';
import 'package:mime/mime.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'constants.dart';

Color? getAverageColor(File file) {
  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) return null;
  double red = 0;
  double green = 0;
  double blue = 0;
  final start = (image.height + 1) ~/ 4;
  final end = start + image.height ~/ 2;
  for (int i = 0; i < image.width; i++) {
    for (int j = start; j < end; j++) {
      final pixel = image.getPixel(i, j);
      red += pixel.r;
      green += pixel.g;
      blue += pixel.b;
    }
  }
  final count = image.width * (image.height ~/ 2);
  return Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count);
}

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
        IOSUiSettings(aspectRatioLockEnabled: true),
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
  BuildContext context,
  TypeOfImage typeOfImage,
  String path,
  String fileType,
) async {
  if (fileType != 'image/jpeg' && fileType != 'image/png') return null;
  var request = http.MultipartRequest(
    'POST',
    Uri.parse('$mediaHost/post/images/${typeOfImage.name}'),
  );
  request.files.add(
    await http.MultipartFile.fromPath(
      'file',
      path,
      contentType: MediaType('image', fileType.split('/')[1]),
    ),
  );
  request.headers
      .addAll({HttpHeaders.authorizationHeader: Authenticator.idToken ?? ''});
  final response = await http.Response.fromStream(await request.send());
  if (response.statusCode == 200) {
    return response.body;
  }
  if (response.statusCode == 401) {
    await Authenticator.authenticate();
    if (!context.mounted) return null;
    return uploadImage(context, typeOfImage, path, fileType);
  }
  if (response.statusCode == 413 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(snackBarFileSize);
  }
  return null;
}

Future<bool> signOutAlert({
  required BuildContext context,
}) async {
  void onConfirmPressed(BuildContext context) async {
    final socket = context.read<SocketConnection>();
    await Authenticator.endSession();
    socket.channel.add(jsonEncode({'type': typeSignout, 'data': {}}));
    socket.setStatus(SocketStatus.disconnected);
    if (!context.mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Sign out');
  const cancelChild = Text('Cancel');

  final reply = await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog.adaptive(
      icon: const Icon(Icons.logout),
      title: const Text('Really sign out?'),
      content: const Text('This action will sign you out of your account'),
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
  return reply == true;
}

Future<void> locationPermissionAlert({
  required BuildContext context,
  required LocationPermission permission,
}) async {
  void onConfirmPressed(BuildContext context) async {
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    if (context.mounted) Navigator.pop(context);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context);
  }

  const confirmChild = Text('Ok');
  const cancelChild = Text('Cancel');
  final content =
      'The app requires location services in order to function. ${permission == LocationPermission.denied ? 'Request permission to access location?' : 'Go to your phone\'s settings to enable location access'}';

  await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog.adaptive(
      title: const Text('Location permission required'),
      content: Text(content),
      actions: Platform.isIOS
          ? [
              CupertinoDialogAction(
                onPressed: () => onCancelPressed(context),
                child: cancelChild,
              ),
              CupertinoDialogAction(
                onPressed: () => onConfirmPressed(context),
                isDefaultAction: true,
                child: confirmChild,
              ),
            ]
          : [
              if (permission == LocationPermission.denied)
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
}

Future<bool?> acceptDialog(
  BuildContext context,
  TypeOfUser typeOfUser, {
  Widget? timerDisplay,
}) {
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
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Text(
              '${typeOfUser == TypeOfUser.driver ? "Passengers are" : "A driver is"} available. Accept them?',
              style: const TextStyle(
                fontSize: 25.0,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (timerDisplay != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_sharp,
                  size: 30,
                ),
                const SizedBox(
                  width: 10.0,
                ),
                timerDisplay,
              ],
            ),
          const Padding(padding: EdgeInsets.all(10.0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filled(
                onPressed: () => Navigator.pop(context, true),
                style: ButtonStyle(
                  backgroundColor:
                      WidgetStatePropertyAll(Colors.green.shade300),
                ),
                iconSize: 55.0,
                icon: const Icon(Icons.check_rounded),
              ),
              IconButton.filled(
                onPressed: () => Navigator.pop(context, false),
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.red.shade300),
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

Future<void> arrivedDialog({
  required BuildContext context,
  required List<Map<String, dynamic>> users,
  required TypeOfUser typeOfUser,
}) async {
  final socket = context.read<SocketConnection>();
  List<ValueNotifier<double>> ratings = List.generate(
    users.length,
    (index) => ValueNotifier(0),
  );
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
              'Please rate your experience with the ${typeOfUser.name} (optional)',
              style: const TextStyle(fontSize: 16.0),
              textAlign: TextAlign.center,
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 5.0)),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(
                    "${users[index]['full_name']}",
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: UserAvatar(
                      url: users[index]['picture'],
                      size: 26.0,
                    ),
                  ),
                  subtitle: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ratingBars[index],
                  ),
                );
              },
              separatorBuilder: (context, index) =>
                  const Padding(padding: EdgeInsets.symmetric(vertical: 6.0)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
  if (ModalRoute.of(context)?.isCurrent != true) Navigator.pop(context);
  final reply = await Navigator.push<bool>(context, dialogRoute);
  if (reply != true) return;
  List<Map<String, dynamic>> ratingList = [];
  for (var i = 0; i < users.length; i++) {
    ratingList
        .add({'id': users[i]['id'] as String, 'rating': ratings[i].value});
  }
  socket.channel.add(
    jsonEncode({
      'type': typeSendRatings,
      'data': ratingList,
    }),
  );
}

Future<bool> switchModeDialog(
  BuildContext context,
  TypeOfUser typeOfUser,
) async {
  void onConfirmPressed(BuildContext context) {
    Navigator.pop(context, true);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Yes');
  const cancelChild = Text('No');

  final reply = await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog.adaptive(
        title: Text(
          'Really switch to ${typeOfUser == TypeOfUser.driver ? 'passenger' : 'driver'} mode?',
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
  return reply == true;
}

Future<bool> stopDrivingDialog(BuildContext context) async {
  void onConfirmPressed(BuildContext context) {
    Navigator.pop(context, true);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Yes');
  const cancelChild = Text('No');

  final reply = await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog.adaptive(
        title: const Text('Really stop driving?'),
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
  return reply == true;
}

Future<bool> stopPassengerDialog(BuildContext context) async {
  void onConfirmPressed(BuildContext context) {
    Navigator.pop(context, true);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Yes');
  const cancelChild = Text('No');

  final reply = await showAdaptiveDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog.adaptive(
        title: const Text('Really cancel ride?'),
        content: const Text('You will lose your driver'),
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
  return reply == true;
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
                        : colors[user['id'].hashCode % 10];
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

Future<bool?> showDeleteCarDialog(BuildContext context) {
  void onConfirmPressed(BuildContext context) {
    Navigator.pop(context, true);
  }

  void onCancelPressed(BuildContext context) {
    Navigator.pop(context, false);
  }

  const confirmChild = Text('Delete');
  const cancelChild = Text('Cancel');

  return showAdaptiveDialog<bool>(
    barrierDismissible: true,
    context: context,
    builder: (context) => AlertDialog.adaptive(
      icon: const Icon(Icons.delete_outline),
      title: const Text('Really delete car?'),
      content: const Text(
        'This action cannot be undone',
      ),
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
}
