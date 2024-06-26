import 'package:flutter/material.dart';

class Car {
  String id;
  String model;
  int seats;
  String license;
  String? picture;
  int? color;

  Car.fromMap(Map<String, dynamic> car)
      : id = car['id'].toString(),
        model = car['model'],
        seats = car['seats'],
        license = car['license'],
        picture = car['picture'],
        color = car['color'];
  Map<String, dynamic> toJson() => {
        'id': id,
        'model': model,
        'seats': seats,
        'license': license,
        'picture': picture,
        'color': color,
      };
}

class User with ChangeNotifier {
  String id;
  String fullName;
  String givenName;
  String? picture;
  int ratingsSum;
  int ratingsCount;
  Map<String, Car> cars;

  User({
    this.id = 'INVALID',
    this.fullName = '',
    this.givenName = '',
    this.ratingsSum = 0,
    this.ratingsCount = 0,
    this.cars = const {},
  });

  User.userFromMap(Map<String, dynamic> user)
      : id = user['id'],
        fullName = user['full_name'],
        givenName = user['given_name'] ?? user['full_name'],
        picture = user['picture'],
        ratingsSum = user['ratings_sum'],
        ratingsCount = user['ratings_count'],
        cars = (user['cars'] as Map<String, Map<String, dynamic>>)
            .map((key, value) => MapEntry(key, Car.fromMap(value)));

  void setUser(Map<String, dynamic>? user) {
    if (user != null) {
      id = user['id'];
      fullName = user['full_name'];
      givenName = user['given_name'] ?? user['full_name'];
      picture = user['picture'];
      ratingsSum = user['ratings_sum'];
      ratingsCount = user['ratings_count'];
      cars = (user['cars'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, Car.fromMap(value)));
    } else {
      id = 'INVALID';
      fullName = '';
      givenName = '';
      picture = null;
      ratingsSum = 0;
      ratingsCount = 0;
      cars = {};
    }
    notifyListeners();
  }

  void setUserPicture(String? newPicture) {
    picture = newPicture;
    notifyListeners();
  }

  void addCar(Car car) {
    cars[car.id] = car;
    notifyListeners();
  }

  void removeCar(String carID) {
    cars.remove(carID);
    notifyListeners();
  }

  void setCarPicture(String id, String? picture) {
    if (cars[id] != null) cars[id]!.picture = picture;
    notifyListeners();
  }
}
