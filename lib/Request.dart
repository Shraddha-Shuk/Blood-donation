import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

class RequestPage extends StatefulWidget {
  final VoidCallback? onRequestSubmitted;

  const RequestPage({Key? key, this.onRequestSubmitted}) : super(key: key);

  @override
  _RequestPageState createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController unitsController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController hospitalController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? selectedBloodGroup;
  String? selectedGender;
  String? selectedTime;
  LatLng? _currentLocation;
  final List<String> bloodGroups = [
    "A+",
    "A-",
    "B+",
    "B-",
    "O+",
    "O-",
    "AB+",
    "AB-"
  ];
  final List<String> genders = ["Male", "Female", "Other"];
  List<Map<String, dynamic>> _locationSuggestions = [];
  Timer? _debounce;

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
              'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5'),
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

  Future<String> _getAddressFromCoordinates(LatLng latLng) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latLng.latitude, latLng.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address =
            "${place.street}, ${place.subLocality}, ${place.locality}, "
            "${place.administrativeArea}, ${place.postalCode}";
        return address.isNotEmpty
            ? address
            : "${latLng.latitude}, ${latLng.longitude}";
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
        builder: (context) => MapPage(
          initialLocation: _currentLocation ?? LatLng(20.5937, 78.9629),
          onLocationSelected: (LatLng location) async {
            String address = await _getAddressFromCoordinates(location);
            setState(() {
              _currentLocation = location;
              locationController.text = address;
            });
          },
        ),
      ),
    );
  }

  Future<void> pickDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030, 12, 31),
    );

    if (pickedDate != null) {
      setState(() {
        dateController.text =
            "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
      });
    }
  }

  Future<void> pickTime() async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime != null) {
      setState(() {
        selectedTime = pickedTime.format(context);
      });
    }
  }

  Future<void> submitRequest() async {
    User? user = _auth.currentUser;
    String uid = user!.uid;

    if (nameController.text.isEmpty ||
        selectedBloodGroup == null ||
        unitsController.text.isEmpty ||
        dateController.text.isEmpty ||
        selectedTime == null ||
        selectedGender == null ||
        hospitalController.text.isEmpty ||
        locationController.text.isEmpty ||
        phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('request');
      // functions.useFunctionsEmulator("127.0.0.1", 5001);
      // final callable = functions.httpsCallable('request');
      final requestData = {
        "name": nameController.text,
        "bloodGroup": selectedBloodGroup,
        "units": int.parse(unitsController.text),
        "date": dateController.text,
        "time": selectedTime,
        "gender": selectedGender,
        "hospital": hospitalController.text,
        "location": locationController.text,
        "phone": phoneController.text,
        "userId": user.uid,
      };

      print("Request Data: $requestData");
        if (widget.onRequestSubmitted != null) {
        widget.onRequestSubmitted!();
      }
      await callable.call(requestData);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Request submitted successfully")),
      );

      // Reset form fields
      nameController.clear();
      selectedBloodGroup = null;
      unitsController.clear();
      dateController.clear();
      selectedTime = null;
      selectedGender = null;
      hospitalController.clear();
      locationController.clear();
      phoneController.clear();

      // Call the callback to navigate to home page
  
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please check your connection and try again $e"),
          backgroundColor: const Color.fromARGB(255, 224, 74, 74),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _textField("Name", nameController),
                  _dropdownField("Blood group", bloodGroups, (value) {
                    setState(() => selectedBloodGroup = value);
                  }),
                  _textField("Number of Units", unitsController,
                      isNumeric: true),
                  _datePickerField("Date", dateController, pickDate),
                  _timePickerField("Time", pickTime),
                  _dropdownField("Gender", genders, (value) {
                    setState(() => selectedGender = value);
                  }),
                  _textField("Hospital name", hospitalController),
                  Text("Location",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                                bottomLeft: Radius.circular(
                                    _locationSuggestions.isEmpty ? 4 : 0),
                                bottomRight: Radius.circular(
                                    _locationSuggestions.isEmpty ? 4 : 0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                                bottomLeft: Radius.circular(
                                    _locationSuggestions.isEmpty ? 4 : 0),
                                bottomRight: Radius.circular(
                                    _locationSuggestions.isEmpty ? 4 : 0),
                              ),
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.search,
                                      color: Colors.red[800]),
                                  onPressed: () async {
                                    if (locationController.text.isNotEmpty) {
                                      try {
                                        List<Location> locations =
                                            await locationFromAddress(
                                                locationController.text);
                                        if (locations.isNotEmpty) {
                                          LatLng location = LatLng(
                                            locations.first.latitude,
                                            locations.first.longitude,
                                          );
                                          setState(() {
                                            _currentLocation = location;
                                          });
                                          // Open map with the searched location
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => MapPage(
                                                initialLocation: location,
                                                onLocationSelected: (LatLng
                                                    selectedLocation) async {
                                                  String address =
                                                      await _getAddressFromCoordinates(
                                                          selectedLocation);
                                                  setState(() {
                                                    _currentLocation =
                                                        selectedLocation;
                                                    locationController.text =
                                                        address;
                                                  });
                                                },
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content:
                                                    Text("Location not found")),
                                          );
                                        }
                                      } catch (e) {
                                        print("Error finding location: $e");
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                "Could not find the location. Please check the address and try again."),
                                            backgroundColor: Colors.red[700],
                                          ),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                "Please enter a location")),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.map, color: Colors.red[800]),
                                  onPressed: _openMap,
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
                                  color: const Color.fromARGB(255, 0, 0, 0)
                                      .withOpacity(0.2),
                                  spreadRadius: 1,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                              border: Border.all(
                                  color: const Color.fromARGB(255, 0, 0, 0)),
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
                                      List<Location> locations =
                                          await locationFromAddress(
                                              _locationSuggestions[index]
                                                  ['display_name']!);
                                      if (locations.isNotEmpty) {
                                        LatLng location = LatLng(
                                          locations.first.latitude,
                                          locations.first.longitude,
                                        );
                                        setState(() {
                                          locationController.text =
                                              _locationSuggestions[index]
                                                  ['display_name']!;
                                          _currentLocation = location;
                                          _locationSuggestions = [];
                                        });
                                      }
                                    } catch (e) {
                                      print("Error getting coordinates: $e");
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: index <
                                                  _locationSuggestions.length -
                                                      1
                                              ? const Color.fromARGB(
                                                  255, 6, 6, 6)
                                              : Colors.transparent,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      _locationSuggestions[index]
                                          ['display_name']!,
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
                  _textField("Phone number", phoneController, isNumeric: true),
                  SizedBox(height: 20),
                  _submitButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade900,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: [
          SizedBox(width: 10),
          Text("Requests",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              )),
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller,
      {bool isNumeric = false, bool hasIcon = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: hasIcon
                ? IconButton(
                    onPressed: _openMap,
                    icon: Icon(
                      Icons.location_on,
                      color: Colors.red,
                    ))
                : null,
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  Widget _dropdownField(
      String label, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        SizedBox(height: 5),
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
        SizedBox(height: 10),
      ],
    );
  }

  Widget _datePickerField(
      String label, TextEditingController controller, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        SizedBox(height: 5),
        TextField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: Icon(Icons.calendar_today, color: Colors.red),
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  Widget _timePickerField(String label, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        SizedBox(height: 5),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black),
            ),
            child: Text(
              selectedTime ?? "Select Time",
              style: GoogleFonts.poppins(fontSize: 16),
            ),
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  Widget _submitButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: submitRequest,
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: Text(
            "Next",
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  final LatLng initialLocation;
  final Function(LatLng) onLocationSelected;

  MapPage({required this.initialLocation, required this.onLocationSelected});

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng _selectedLocation = LatLng(20.5937, 78.9629);

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text("Select Location"), backgroundColor: Colors.red[800]),
      body: FlutterMap(
        options: MapOptions(
          center: _selectedLocation,
          zoom: 15.0,
          onTap: (tapPosition, point) {
            setState(() {
              _selectedLocation = point;
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _selectedLocation,
                width: 40,
                height: 40,
                child: Icon(Icons.location_pin, color: Colors.red, size: 40),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          widget.onLocationSelected(_selectedLocation);
          Navigator.pop(context);
        },
        label: Text("Select"),
        icon: Icon(Icons.check),
        backgroundColor: Colors.red[800],
      ),
    );
  }
}
