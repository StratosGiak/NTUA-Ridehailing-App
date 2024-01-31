import 'package:flutter/material.dart';

class Car {
  Map<String, dynamic> make = {};
}

class User {
  String id;
  String name;
  String? picture;
  int ratingsSum;
  int ratingsCount;
  Map<String, dynamic> cars;

  User(
      {this.id = 'INVALID',
      this.name = '',
      this.ratingsSum = 0,
      this.ratingsCount = 0,
      this.cars = const {}});

  User.userFromMap(Map<String, dynamic> map)
      : id = map['id'],
        name = map['name'],
        picture = map['picture'],
        ratingsSum = map['ratings_sum'],
        ratingsCount = map['ratings_count'],
        cars = map['cars'];
}

class UserProvider with ChangeNotifier {
  User _user = User();

  void setUser(User newUser) {
    _user = newUser;
    notifyListeners();
  }

  User get user => _user;
}
