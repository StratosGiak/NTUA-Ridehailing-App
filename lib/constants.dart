import 'dart:async';

import 'package:latlong2/latlong.dart';

const apiHost = "192.168.1.119:16820";
const mediaHost = "192.168.1.119:28563";
String mapUrl = "";
StreamController<String> wsStreamController = StreamController.broadcast();

enum TypeOfUser { driver, passenger }

enum TypeOfImage { users, cars }

const busStop = LatLng(37.9923, 23.7764);
const university = LatLng(37.978639, 23.782778);

const userImageQuality = 75;
const carImageQuality = 75;

const connectionTimeout = 5;

const typeLogin = "!LOGIN";
const typeUpdateDriver = "!UPDATEDRIVER";
const typeUpdatePassenger = "!UPDATEPASSENGER";
const typeNewDriver = "!NEWDRIVER";
const typeNewPassenger = "!NEWPASSENGER";
const typeStopDriver = "!STOPDRIVER";
const typeStopPassenger = "!STOPPASSENGER";
const typeOutOfRange = "!OUTOFRANGE";
const typeArrivedDestination = "!ARRIVEDDESTINATION";
const typeSendRatings = "!SENDRATINGS";
const typeAddCar = "!ADDCAR";
const typeUpdateCar = "!UPDATECAR";
const typeUpdateUserPicture = "!UPDATEUSERPICTURE";
const typeDeletePicture = "!DELETEPICTURE";
const typeRemoveCar = "!REMOVECAR";
const typeGetDriver = "!GETDRIVER";
const typeGetPassengers = "!GETPASSENGERS";
const typePingPassengers = "!PINGPASSENGERS";
const typePingDriver = "!PINGDRIVER";
const typeBadRequest = "!BADREQUEST";
const typeMessage = "!MESSAGE";
const typeSignout = "!SIGNOUT";
