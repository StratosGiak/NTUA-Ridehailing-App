import 'dart:async';

import 'package:latlong2/latlong.dart';

const apiHost = "ntua-ridehailing.dslab.ece.ntua.gr";
const mediaHost = "ntua-ridehailing.dslab.ece.ntua.gr";
String mapUrl = "";
StreamController<String> wsStreamController = StreamController.broadcast();

const busStop = LatLng(37.9923, 23.7764);
const university = LatLng(37.978639, 23.782778);

const profileImageQuality = 75;
const carImageQuality = 75;

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
