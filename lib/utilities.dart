import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uni_pool/providers.dart';
import 'package:uni_pool/sensitive_storage.dart';
import 'package:uni_pool/socket_handler.dart';
import 'package:uni_pool/widgets.dart';
import 'package:mime/mime.dart';
import 'constants.dart';

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

Future<({String pickedImage, String? mimeType})?> pickImage(
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
    return (pickedImage: cropped.path, mimeType: mimeType);
  } on PlatformException catch (e) {
    debugPrint("Error: $e");
    return null;
  }
}

Future<String?> uploadImage(
    TypeOfImage typeOfImage, String path, String fileType) async {
  if (fileType != "image/jpeg" && fileType != "image/png") return null;
  var request = http.MultipartRequest(
      'POST', Uri.parse('http://$mediaHost/media/images/${typeOfImage.name}'));
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
