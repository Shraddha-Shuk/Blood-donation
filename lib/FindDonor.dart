import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:rrd/donor_list.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
class FindDonorsPage extends StatefulWidget {
  final String? initialBloodType;
  final LatLng? initialLocation;
  final String? initialAddress;
  final bool autoSearch;
  
  const FindDonorsPage({
    Key? key, 
    this.initialBloodType,
    this.initialLocation,
    this.initialAddress,
    this.autoSearch = false,
  }) : super(key: key);

  @override
  _FindDonorsPageState createState() => _FindDonorsPageState();
}

class _FindDonorsPageState extends State<FindDonorsPage> {
  LatLng? _currentLocation;
  final TextEditingController locationController = TextEditingController();
  String? selectedBloodGroup;
  final List<String> bloodGroups = ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"];


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

  @override
  void dispose() {
    _debounce?.cancel();
    locationController.dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    
    // Set initial blood group if provided
    if (widget.initialBloodType != null) {
      selectedBloodGroup = widget.initialBloodType;
    }
    
    // Set initial location if provided
    if (widget.initialLocation != null) {
      _currentLocation = widget.initialLocation;
      if (widget.initialAddress != null) {
        locationController.text = widget.initialAddress!;
      } else {
        // Get address from coordinates if not provided
        _getAddressFromCoordinates(widget.initialLocation!).then((address) {
          setState(() {
            locationController.text = address;
          });
        });
      }
    } else {
      // Get current location if no initial location provided
      _getCurrentLocation();
    }
    
    // Auto search if requested
    if (widget.autoSearch && widget.initialBloodType != null && widget.initialLocation != null) {
      // Use a small delay to ensure the UI is built before searching
      Future.delayed(const Duration(milliseconds: 500), () {
        _searchDonors();
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Location permission denied")),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Location permission permanently denied"),
            backgroundColor: Colors.red[700],
          ),
        );
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Convert position to LatLng
      LatLng location = LatLng(position.latitude, position.longitude);

      // Get address from coordinates
      String address = await _getAddressFromCoordinates(location);

      setState(() {
        _currentLocation = location;
        locationController.text = address;
      });
    } catch (e) {
      print("Error getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Unable to get your location. Please check your location settings and try again."),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  /// Fetch user's location from Firestore using their UID
  /// Fetch user's location from Firestore and set it as current location
Future<void> _fetchUserLocation() async {
  try {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not logged in.");
      return;
    }

    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc['location'] != null) {
      String locationString = userDoc['location']; // "19.0760051,72.8751251"
      List<String> latLngParts = locationString.split(',');

      if (latLngParts.length == 2) {
        double latitude = double.parse(latLngParts[0].trim());
        double longitude = double.parse(latLngParts[1].trim());
        LatLng userLocation = LatLng(latitude, longitude);

        String address = await _getAddressFromCoordinates(userLocation);

        setState(() {
          _currentLocation = userLocation;
          locationController.text = address;
        });

        print("User's location set to: $address");
      } else {
        print("Invalid location format in Firestore.");
      }
    } else {
      print("User document not found or location field is missing.");
    }
  } catch (e) {
    print("Error fetching user location: $e");
  }
}


  /// Function to get address from coordinates
  Future<String> _getAddressFromCoordinates(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude, latLng.longitude
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = "${place.street}, ${place.subLocality}, ${place.locality}, "
          "${place.administrativeArea}, ${place.postalCode}";
        return address.isNotEmpty ? address : "${latLng.latitude}, ${latLng.longitude}";
      }
    } catch (e) {
      print("Error in reverse geocoding: $e");
    }
    return "${latLng.latitude}, ${latLng.longitude}";
  }

  /// Open map to select location
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

  /// Search donors based on selected location
  void _searchDonors() async {
    if (_currentLocation == null || selectedBloodGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please select a location and blood group")),
      );
      return;
    }

    // Calculate date 3 months ago for filtering
    final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));

    QuerySnapshot donorDocs = await FirebaseFirestore.instance
      .collection('users')
      .where('bloodType', isEqualTo: selectedBloodGroup)
      .get();

    List<Donor> nearbyDonors = [];

    for (var doc in donorDocs.docs) {
      if (doc['uid'] == FirebaseAuth.instance.currentUser!.uid) {
        continue; // Skip the current user
      }

      // Get latest donation date if available
      DateTime? latestDonation;
      try {
        // Check if latestDonation exists and is not null
        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          if (data.containsKey('latestDonation') && data['latestDonation'] != null) {
            // Convert Firestore timestamp to DateTime
            latestDonation = (data['latestDonation'] as Timestamp).toDate();
          }
        }
      } catch (e) {
        print("Error parsing donation date: $e");
      }
      
      // Skip donors who donated less than 3 months ago
      if (latestDonation != null && !latestDonation.isBefore(threeMonthsAgo)) {
        continue;
      }

      String locationString = doc['location'];
      List<String> latLngParts = locationString.split(',');

      if (latLngParts.length == 2) {
        double donorLat = double.parse(latLngParts[0]);
        double donorLon = double.parse(latLngParts[1]);

        double distance = Geolocator.distanceBetween(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          donorLat,
          donorLon,
          
        ) / 1000; // Convert meters to KM

        // Only add donors within 3 km radius
        if (distance <= 10.0) {
          nearbyDonors.add(Donor(
            name: doc['name'],
            bloodType: doc['bloodType'],
            location: doc['location'],
            phone: doc['contact'],
            distance: distance,
            latestDonation: latestDonation,
          ));
        }
      }
    }

    print("Nearby Eligible Donors within 10km: ${nearbyDonors.length}");
    
    // Sort donors by distance
    nearbyDonors.sort((a, b) => a.distance.compareTo(b.distance));
    
    if (nearbyDonors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("No eligible donors found within 10 km radius"),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DonorList(donors: nearbyDonors),
      ),
    );
     
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Found ${nearbyDonors.length} eligible donors within 10 km!"),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[800],
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 40),
            Text("Find Eligible Donor", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 4),
            Text("Blood donors who can donate now", style: TextStyle(fontSize: 14, color: Colors.white70)),
            
            SizedBox(height: 8),
            Text("(Only showing donors who haven't donated in the last 3 months)", 
                style: TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic)),

            SizedBox(height: 20),

            Text("Choose Blood Group", style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedBloodGroup,
                hint: Text("Select"),
                underline: SizedBox(),
                items: bloodGroups.map((String group) {
                  return DropdownMenuItem<String>(
                    value: group,
                    child: Text(group),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedBloodGroup = value;
                  });
                },
              ),
            ),

            SizedBox(height: 16),

            Text("Location", style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),
           Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Color.fromARGB(255, 255, 255, 255),
                  hintText: "Enter location",
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                      bottomRight: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                    ),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                      bottomRight: Radius.circular(_locationSuggestions.isEmpty ? 4 : 0),
                    ),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                                  _currentLocation = location;
                                });
                                // Open map with the searched location
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MapPage(
                                      initialLocation: location,
                                      onLocationSelected: (LatLng selectedLocation) async {
                                        String address = await _getAddressFromCoordinates(selectedLocation);
                                        setState(() {
                                          _currentLocation = selectedLocation;
                                          locationController.text = address;
                                        });
                                      },
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Could not find the location. Please enter a different address."),
                                    backgroundColor: Colors.red[700],
                                  ),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Error finding location: ${e.toString()}"),
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
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade300),
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
                                _currentLocation = location;
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
                                    ? Colors.grey.shade200
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

            SizedBox(height: 20),

            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                icon: Icon(Icons.search),
                label: Text("Search Eligible Donors"),
                onPressed: _searchDonors,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MapPage with initial location set from Firestore
class MapPage extends StatefulWidget {
  final LatLng initialLocation;
  final Function(LatLng) onLocationSelected;

  MapPage({required this.initialLocation, required this.onLocationSelected});

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng _selectedLocation = LatLng(20.5937, 78.9629);
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _locationSuggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
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

  Future<void> _searchLocation() async {
    final searchText = _searchController.text;
    if (searchText.isEmpty) return;

    setState(() {
      _isSearching = true;
      _locationSuggestions = [];
    });

    try {
      List<Location> locations = await locationFromAddress(searchText);
      if (locations.isNotEmpty) {
        setState(() {
          _selectedLocation = LatLng(
            locations.first.latitude,
            locations.first.longitude,
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not find the location. Please enter a different address."),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Select Location"), 
        backgroundColor: Colors.red[800]
      ),
      body: Column(
        children: [
          // Search bar with suggestions
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: "Search location",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                          suffixIcon: _isSearching 
                            ? Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red[800],
                                ),
                              )
                            : IconButton(
                                icon: Icon(Icons.search),
                                onPressed: _searchLocation,
                              ),
                        ),
                        onChanged: (value) {
                          _getLocationSuggestions(value);
                        },
                        onSubmitted: (_) => _searchLocation(),
                      ),
                    ),
                  ],
                ),
                // Location suggestions dropdown
                if (_locationSuggestions.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
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
                                setState(() {
                                  _selectedLocation = LatLng(
                                    locations.first.latitude,
                                    locations.first.longitude,
                                  );
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
                                      ? Colors.grey.shade200
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
          // Map
          Expanded(
            child: FlutterMap(
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
