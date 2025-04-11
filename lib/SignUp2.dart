import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rrd/FindDonor.dart';
import 'package:rrd/HomePage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class SignUpPage2 extends StatefulWidget {
  final String selectedEntity;

  const SignUpPage2({Key? key, required this.selectedEntity}) : super(key: key);

  @override
  _SignUpPage2State createState() => _SignUpPage2State();
}

class _SignUpPage2State extends State<SignUpPage2> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController contactController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController licenseController = TextEditingController(); // For hospitals and blood banks
  String? selectedBloodType;
  LatLng? selectedLocation;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? user = FirebaseAuth.instance.currentUser;
  bool _isValidPhone = false;
  bool _isValidLicense = false;

  final FocusNode nameFocus = FocusNode();
  final FocusNode contactFocus = FocusNode();
  final FocusNode locationFocus = FocusNode();
  final FocusNode licenseFocus = FocusNode();

  LatLng? _currentLocation;
  bool isSearchingLocation = false;
  List<Map<String, dynamic>> _locationSuggestions = [];
  Timer? _debounce;
  bool _isLoadingLocation = false;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Add phone validation function
  bool _validateIndianPhone(String phone) {
    final RegExp phoneRegex = RegExp(r'^(?:\+91|91|0)?[6789]\d{9}$');
    return phoneRegex.hasMatch(phone);
  }

  void _validatePhone(String phone) {
    setState(() {
      _isValidPhone = _validateIndianPhone(phone);
    });
  }

  // Add license number validation function
  bool _validateLicenseNumber(String license) {
    if (widget.selectedEntity == 'bloodbank') {
      // Blood bank license format: XX-YY-BB-ZZZZZ (e.g., AB-12-BB-12345)
      final RegExp licenseRegex = RegExp(r'^[A-Z]{2}-\d{2}-BB-\d{5}$');
      return licenseRegex.hasMatch(license);
    } else if (widget.selectedEntity == 'hospital') {
      // Hospital license format: XX/YYYY/ZZZZZ (e.g., AB/1234/56789)
      final RegExp licenseRegex = RegExp(r'^[A-Z]{2}/\d{4}/\d{5}$');
      return licenseRegex.hasMatch(license);
    }
    return true; // For user entity, no validation needed
  }

  void _validateLicense(String license) {
    if (widget.selectedEntity != 'user') {
      setState(() {
        _isValidLicense = _validateLicenseNumber(license);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    // Add listener for phone validation
    contactController.addListener(() {
      _validatePhone(contactController.text);
    });
    // Add listener for license validation
    licenseController.addListener(() {
      _validateLicense(licenseController.text);
    });
  }

  @override
  void dispose() {
    contactController.dispose();
    licenseController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location services are disabled. Please enable them.")),
        );
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Location permission denied")),
          );
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permission permanently denied")),
        );
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      // Convert position to LatLng
      LatLng location = LatLng(position.latitude, position.longitude);

      // Get address from coordinates with timeout
      String address = await _getAddressFromCoordinates(location);

      if (mounted) {  // Check if widget is still mounted
        setState(() {
          selectedLocation = location;
          locationController.text = address;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      print("Error getting location: $e");
      if (mounted) {  // Check if widget is still mounted
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error getting location: ${e.toString()}")),
        );
        setState(() {
          _isLoadingLocation = false;
        });
      }

      if (mounted) {  // Check if widget is still mounted
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Unable to get your current location. Please check your location settings and try again."),
            backgroundColor: Colors.red[700],
          ),
        );
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  // Fetch suggestions from OSM Nominatim
  Future<void> _getLocationSuggestions(String query) async {
    // Clear previous timer if it exists
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    
    // Debounce to prevent too many API calls while typing
    _debounce = Timer(Duration(milliseconds: 500), () async {
      if (query.length < 3) {
        setState(() {
          _locationSuggestions = [];
        });
        return;
      }
      
      try {
        final response = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5'
          ),
          headers: {
            'User-Agent': 'YourAppName', // Required by OSM policy
            'Accept': 'application/json',
          },
        );
        
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          
          setState(() {
            _locationSuggestions = data.map((item) {
              return {
                'display_name': item['display_name'],
                'place_id': item['place_id'].toString(),
              };
            }).toList();
          });
        } else {
          setState(() {
            _locationSuggestions = [];
          });
        }
      } catch (e) {
        print('Error fetching location suggestions: $e');
        setState(() {
          _locationSuggestions = [];
        });
      }
    });
  }

  void _registerUser() async {
    if (nameController.text.isEmpty ||
        contactController.text.isEmpty ||
        locationController.text.isEmpty ||
        selectedLocation == null ||
        (widget.selectedEntity != 'user' && licenseController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please fill all the required fields")),
      );
      return;
    }

    if (!_isValidPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a valid Indian phone number")),
      );
      return;
    }

    // Validate license number for hospitals and blood banks
    if (widget.selectedEntity != 'user' && !_isValidLicense) {
      String entityType = widget.selectedEntity == 'bloodbank' ? 'blood bank' : 'hospital';
      String format = widget.selectedEntity == 'bloodbank' ? 'XX-YY-BB-ZZZZZ (e.g., AB-12-BB-12345)' : 'XX/YYYY/ZZZZZ (e.g., AB/1234/56789)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a valid $entityType license number in format: $format")),
      );
      return;
    }

    try {
      if (user != null) {
        String coordinates = "${selectedLocation!.latitude},${selectedLocation!.longitude}";
        
        Map<String, dynamic> userData = {
          'uid': user!.uid,
          'name': nameController.text.trim(),
          'contact': contactController.text.trim(),
          'location': coordinates,
          'createdAt': FieldValue.serverTimestamp(),
        };

        // Add entity-specific fields
        if (widget.selectedEntity == 'user') {
          userData.addAll({
            'bloodType': selectedBloodType,
            'isDonor': false,
            'latestDonation': null,
          });
        } else if (widget.selectedEntity == 'hospital') {
          userData.addAll({
            'license': licenseController.text.trim(),
            'type': 'hospital',
            'bloodInventory': {},
          });
        } else if (widget.selectedEntity == 'bloodbank') {
          userData.addAll({
            'license': licenseController.text.trim(),
            'type': 'bloodbank',
            'bloodInventory': {},
            'operatingHours': {},
          });
        }

        // Request FCM permission and get token
        await _firebaseMessaging.requestPermission();
        String? fcmToken = await _firebaseMessaging.getToken();

        if (fcmToken != null) {
          userData['fcmToken'] = fcmToken;
        }

        await _firestore.collection(widget.selectedEntity + 's').doc(user!.uid).set(userData);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Account created successfully!")),
      );

      Navigator.push(context, MaterialPageRoute(builder: (context) => MainScreen()));
    } catch (e) {
      print("Error during registration: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Registration failed. Please check your connection and try again."),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _searchLocation(String query) async {
    setState(() {
      isSearchingLocation = true;
    });
    
    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        setState(() {
          selectedLocation = LatLng(
            locations.first.latitude,
            locations.first.longitude,
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not find location")),
      );
    } finally {
      setState(() {
        isSearchingLocation = false;
      });
    }
  }

  Future<String> _getAddressFromCoordinates(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = "";
        
        if (place.locality?.isNotEmpty ?? false) {
          address += place.locality!;
        }
        if (place.administrativeArea?.isNotEmpty ?? false) {
          if (address.isNotEmpty) address += ", ";
          address += place.administrativeArea!;
        }
        if (place.country?.isNotEmpty ?? false) {
          if (address.isNotEmpty) address += ", ";
          address += place.country!;
        }
        
        return address.isNotEmpty ? address : "${latLng.latitude}, ${latLng.longitude}";
      }
    } catch (e) {
      print("Error in reverse geocoding: $e");
    }
    return "${latLng.latitude}, ${latLng.longitude}";
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
          initialLocation: selectedLocation ?? LatLng(20.5937, 78.9629),
        ),
      ),
    ).then((value) async {
      if (value != null) {
        String address = await _getAddressFromCoordinates(value);
        setState(() {
          selectedLocation = value;
          locationController.text = address;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Color(0xFFFBF5F3),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                "Complete Your Profile",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B1A),
                ),
              ),
              const SizedBox(height: 24),

              // Name Field
              const Text("Name", style: TextStyle(color: Colors.black54)),
              TextField(
                controller: nameController,
                focusNode: nameFocus,
                decoration: InputDecoration(border: UnderlineInputBorder()),
              ),
              const SizedBox(height: 16),

              // Blood Type Dropdown (only for users)
              if (widget.selectedEntity == 'user') ...[
                const Text("Blood Type", style: TextStyle(color: Colors.black54)),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  hint: const Text("Choose your blood type"),
                  value: selectedBloodType,
                  items: ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"]
                      .map((bloodType) => DropdownMenuItem(
                            value: bloodType,
                            child: Text(bloodType),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBloodType = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],

              // License Number (for hospitals and blood banks)
              if (widget.selectedEntity != 'user') ...[
                Text("License Number", style: TextStyle(color: Colors.black54)),
                TextField(
                  controller: licenseController,
                  focusNode: licenseFocus,
                  decoration: InputDecoration(
                    border: UnderlineInputBorder(),
                    errorText: licenseController.text.isNotEmpty && !_isValidLicense
                        ? widget.selectedEntity == 'bloodbank'
                            ? 'Format: XX-YY-BB-ZZZZZ (e.g., AB-12-BB-12345)'
                            : 'Format: XX/YYYY/ZZZZZ (e.g., AB/1234/56789)'
                        : null,
                    hintText: widget.selectedEntity == 'bloodbank'
                        ? 'XX-YY-BB-ZZZZZ'
                        : 'XX/YYYY/ZZZZZ',
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Contact Number
              const Text("Contact No", style: TextStyle(color: Colors.black54)),
              TextField(
                controller: contactController,
                focusNode: contactFocus,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  border: UnderlineInputBorder(),
                  errorText: contactController.text.isNotEmpty && !_isValidPhone
                      ? 'Please enter a valid Indian phone number'
                      : null,
                ),
                onChanged: (value) {
                  _validatePhone(value);
                },
              ),
              const SizedBox(height: 16),

              // Location
              const Text("Location", style: TextStyle(color: Colors.black54)),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    // Text field for location input
                    TextField(
                      controller: locationController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color.fromARGB(255, 255, 255, 255),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                            bottomRight: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                            bottomRight: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                          ),
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLoadingLocation)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.red[800],
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                icon: Icon(Icons.search, color: Colors.red[800]),
                                onPressed: () async {
                                  if (locationController.text.isNotEmpty) {
                                    try {
                                      List<Location> locations = await locationFromAddress(locationController.text);
                                      if (locations.isNotEmpty) {
                                        LatLng location = LatLng(
                                          locations.first.latitude,
                                          locations.first.longitude,
                                        );
                                        setState(() {
                                          selectedLocation = location;
                                        });
                                        // Open map with the searched location
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => MapLocationPicker(
                                              initialLocation: location,
                                            ),
                                          ),
                                        ).then((value) {
                                          if (value != null) {
                                            setState(() {
                                              selectedLocation = value;
                                            });
                                          }
                                        });
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text("Location not found")),
                                        );
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Could not find the location. Please try a different address."),
                                          backgroundColor: Colors.red[700],
                                        ),
                                      );
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Please enter a location")),
                                    );
                                  }
                                },
                              ),
                            IconButton(
                              icon: Icon(Icons.map, color: Colors.red[800]),
                              onPressed: _isLoadingLocation ? null : _openMap,
                            ),
                          ],
                        ),
                      ),
                      onChanged: (value) {
                        _getLocationSuggestions(value);
                      },
                    ),
                    
                    // Location suggestions dropdown
                    if (_locationSuggestions.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                              spreadRadius: 1,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                          border: Border.all(color: const Color.fromARGB(255, 0, 0, 0)),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: _locationSuggestions.length,
                          itemBuilder: (context, index) {
                            return InkWell(
                              onTap: () async {
                                try {
                                  List<Location> locations = await locationFromAddress(_locationSuggestions[index]['display_name']!);
                                  if (locations.isNotEmpty) {
                                    LatLng location = LatLng(
                                      locations.first.latitude,
                                      locations.first.longitude,
                                    );
                                    setState(() {
                                      locationController.text = _locationSuggestions[index]['display_name']!;
                                      selectedLocation = location;
                                      _locationSuggestions = [];
                                    });
                                  }
                                } catch (e) {
                                  print("Error getting coordinates: $e");
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: index < _locationSuggestions.length - 1
                                          ? const Color.fromARGB(255, 6, 6, 6)
                                          : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _locationSuggestions[index]['display_name']!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Create Account Button
              Center(
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _registerUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF9E3B35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "Complete Registration",
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class MapLocationPicker extends StatefulWidget {
  final LatLng? initialLocation;

  const MapLocationPicker({Key? key, this.initialLocation}) : super(key: key);

  @override
  _MapLocationPickerState createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late LatLng selectedLocation;
  final MapController mapController = MapController();

  @override
  void initState() {
    super.initState();
    selectedLocation = widget.initialLocation ?? LatLng(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Select Location"),
        backgroundColor: Color(0xFF9E3B35),
        actions: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: () {
              Navigator.pop(context, selectedLocation);
            },
          ),
        ],
      ),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          center: selectedLocation,
          zoom: 13.0,
          onTap: (tapPosition, point) {
            setState(() {
              selectedLocation = point;
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: [
              Marker(
                width: 40.0,
                height: 40.0,
                point: selectedLocation,
                child: Icon(
                  Icons.location_pin,
                  color: Color(0xFF9E3B35),
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

  