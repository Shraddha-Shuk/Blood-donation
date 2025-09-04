import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationPermissionCustom{

  Future<bool> locationPermissionRequest()async{
    LocationPermission permission;
    permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied || permission == LocationPermission.deniedForever){
      permission = await Geolocator.requestPermission();
    }
    permission = await Geolocator.checkPermission();
    if(permission != LocationPermission.denied && permission != LocationPermission.deniedForever){
      return true;
    }
    return false;
  }

  Future<String> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      Placemark placemark = placemarks[0];
      return '${placemark.locality}${placemark.locality != null && placemark.locality != "" ? ", ":""}${placemark.administrativeArea}${placemark.administrativeArea != null && placemark.administrativeArea != "" ? ", ":""}${placemark.country}';
    } catch (e) {
      print('Error getting coordinates: $e');
      return "";
    }
  }

  Future<Position> determinePosition(context) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _emptyPosition();
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permissions are permanently denied.")),
        );
        permission = await Geolocator.requestPermission();

        return _emptyPosition();
      }

      if (permission != LocationPermission.whileInUse) {
        return _emptyPosition();
      }

      Position position = await Geolocator.getCurrentPosition();
      print("User's Location: ${position.latitude}, ${position.longitude}");
      return position;
    } catch (e) {
      print("Exception : $e");
      return _emptyPosition();
    }
  }

  Position _emptyPosition() {
    return Position(latitude: 0.0, longitude: 0.0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,);
  }
}