import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const apiHost = 'wss://ntua-ridehailing.dslab.ece.ntua.gr/api';
const mediaHost = 'https://ntua-ridehailing.dslab.ece.ntua.gr/media';
const authIssuer = 'https://stg-keycloak.dslab.ece.ntua.gr/realms/osreg/';
const authClientID = 'bbeee61f9adf603c75ae815be.ntua.ridehailing';
const appScheme = 'gr.ntua.ece.ridehailing';
const mapUrl = 'assets/map_tiles/{z}/{x}/{y}.png';

enum TypeOfUser { driver, passenger }

enum TypeOfImage { users, cars }

const busStop = LatLng(37.9923, 23.7764);
const university = LatLng(37.978639, 23.782778);
final mapBounds = LatLngBounds(
  const LatLng(38.01304, 23.74121),
  const LatLng(37.97043, 23.80078),
);

const busStopRange = 100;
const maxSeperation = 500;
const arrivalRange = 100;
const distanceFilter = 10;

const userImageQuality = 75;
const carImageQuality = 75;

const connectionTimeout = 5;
const pairingRequestTimeout = 20;

final licensePlateRegex =
    RegExp(r'^[AΑBΒEΕZΖHΗIΙKΚMΜNΝOΟPΡTΤYΥXΧ]{3}[- ]?[1-9]\d{3}$');

const List<Color> colors = [
  Colors.blue,
  Colors.orange,
  Colors.yellow,
  Colors.green,
  Colors.red,
  Colors.lightGreen,
  Colors.indigo,
  Colors.pink,
  Colors.teal,
  Colors.cyan,
];

const typeLogin = '!LOGIN';
const typeUpdateDriver = '!UPDATEDRIVER';
const typeUpdatePassenger = '!UPDATEPASSENGER';
const typeNewDriver = '!NEWDRIVER';
const typeNewPassenger = '!NEWPASSENGER';
const typeStopDriver = '!STOPDRIVER';
const typeStopPassenger = '!STOPPASSENGER';
const typeOutOfRange = '!OUTOFRANGE';
const typeArrivedDestination = '!ARRIVEDDESTINATION';
const typeSendRatings = '!SENDRATINGS';
const typeAddCar = '!ADDCAR';
const typeUpdateCar = '!UPDATECAR';
const typeUpdateUserPicture = '!UPDATEUSERPICTURE';
const typeDeletePicture = '!DELETEPICTURE';
const typeDeleteUserPicture = '!DELETEUSERPICTURE';
const typeDeleteCarPicture = '!DELETECARPICTURE';
const typeRemoveCar = '!REMOVECAR';
const typeGetDriver = '!GETDRIVER';
const typeGetPassengers = '!GETPASSENGERS';
const typePingPassengers = '!PINGPASSENGERS';
const typePingDriver = '!PINGDRIVER';
const typeBadRequest = '!BADREQUEST';
const typeMessage = '!MESSAGE';
const typeSignout = '!SIGNOUT';

class CustomCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'libCustomCachedImageData';

  static final CustomCacheManager _instance = CustomCacheManager._();

  factory CustomCacheManager() {
    return _instance;
  }

  CustomCacheManager._()
      : super(Config(key, stalePeriod: const Duration(seconds: 10)));
}
