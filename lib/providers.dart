import 'package:flutter/material.dart';

class Car {
  Map<String, dynamic> make = {};
}

class User with ChangeNotifier {
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

  void setUser({Map<String, dynamic>? user}) {
    if (user != null) {
      id = user['id'];
      name = user['name'];
      picture = user['picture'];
      ratingsSum = user['ratings_sum'];
      ratingsCount = user['ratings_count'];
      cars = user['cars'];
    } else {
      id = 'INVALID';
      name = '';
      picture = null;
      ratingsSum = 0;
      ratingsCount = 0;
      cars = {};
    }
    notifyListeners();
  }

  void setUserPicture(String newPicture) {
    picture = newPicture;
    notifyListeners();
  }
}
