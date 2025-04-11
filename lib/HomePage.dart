import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:rrd/BloodBankMapScreen.dart';
import 'package:rrd/ChatScreen.dart';
import 'package:rrd/FindDonor.dart' as find_donor; // Alias the FindDonor import
import 'package:rrd/HospitalScreen.dart';
import 'package:rrd/ProfilePage.dart';
import 'package:rrd/Request.dart';
import 'package:rrd/Verification.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; // Add this for location services
import 'package:http/http.dart' as http; // Add this for making HTTP requests
import 'dart:convert'; // Add this for JSON decoding
import 'package:geocoding/geocoding.dart'; // Add this for reverse geocoding
import 'package:latlong2/latlong.dart'; // Add this import for LatLng

class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

Future<void> _showLocationPermissionDialog() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permission is required.")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permissions are permanently denied.")),
      );
      return;
    }
  }
  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(),
      find_donor.FindDonorsPage(),
      RequestPage(
        onRequestSubmitted: () {
          setState(() {
            _selectedIndex = 0;
          });
        },
      ),
      ProfilePage(),
    ];
    // Check for location permission

  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFBF5F3),
      
      body: SafeArea(child: _pages[_selectedIndex]), // Show the selected page

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Color(0xFFA22322),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Find Donor"),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: "Request"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}


class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  
  bool isVerified = false;
  Map<String, bool> answers = {};
  bool isDonor = false;
  String currentLocation = "Fetching location..."; // Add this to store the user's location
  LatLng? _currentLocation; // Add this to store the coordinates

  Future<void> checkDonorStatus() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        String uid = user.uid;

        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users') // Change if your collection name is different
            .doc(uid) // Finding document by UID
            .get();

        if (userDoc.exists) {
          setState(() {
            isDonor = userDoc['isDonor'] ?? false;
          });
        }
      }
    } catch (e) {
      print("Error fetching donor status: $e");
    }
  }


  Future<void> updateDonorStatus() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        String uid = user.uid;

        await FirebaseFirestore.instance
            .collection('users') // Change if your collection name is different
            .doc(uid) // Finding document by UID
            .update({'isDonor': true}); // Updating the field

        print("Donor status updated successfully!");
      }
    } catch (e) {
      print("Error updating donor status: $e");
    }
  }

  Future<void> fetchCurrentLocation() async {
    // Request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permission is required.")),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permissions are permanently denied.")),
      );
      return;
    }
    // Fetch the current location
    // Use Geolocator to get the current position
    // Use the geocoding package to convert coordinates to address
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude); // Use geocoding package
      Placemark place = placemarks[0];
      setState(() {
        currentLocation =
            "${place.locality}, ${place.administrativeArea}, ${place.country}";
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      print("Error fetching location: $e");
      setState(() {
        currentLocation = "Unable to fetch location";
      });
    }
  }

  Future<void> openMapToChangeLocation() async {
    LatLng initialLocation = LatLng(20.5937, 78.9629); // Default location (India)
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      initialLocation = LatLng(position.latitude, position.longitude);
    } catch (e) {
      print("Error fetching current position: $e");
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => find_donor.MapPage( // Use the aliased MapPage
          initialLocation: initialLocation,
          onLocationSelected: (LatLng location) async {
            String address = await _getAddressFromCoordinates(location);
            setState(() {
              currentLocation = address;
              _currentLocation = location;
            });
          },
        ),
      ),
    );
  }

  Future<String> _getAddressFromCoordinates(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          latLng.latitude, latLng.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        return "${place.locality}, ${place.administrativeArea}, ${place.country}";
      }
    } catch (e) {
      print("Error in reverse geocoding: $e");
    }
    return "${latLng.latitude}, ${latLng.longitude}";
  }

  final List<String> bannerImages = [
    "assets/banner1.png",
    "assets/banner2.png",
    "assets/banner3.png",
    "assets/banner4.png",
    "assets/banner5.png"
  ];

  final List<Map<String, dynamic>> activities = [
    {"icon": "assets/blood-transfusion.png", "label": "Blood banks"},
    {"icon": "assets/hospital.png", "label": "Hospital"},
  ];

Future<List<Map<String, dynamic>>> fetchBloodBanks(Position position) async {
  try {
    final response = await http.get(
      Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=blood+bank&bounded=1&viewbox=${position.longitude - 0.05},${position.latitude + 0.05},${position.longitude + 0.05},${position.latitude - 0.05}&limit=5'),
      headers: {
        'User-Agent': 'YourAppName/1.0 (garychettiar@gmail.com)', // Update this
      },
    );

    print("Response Status: ${response.statusCode}");
    print("Response Body: ${response.body}");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data.map<Map<String, dynamic>>((item) {
        return {
          "name": item["display_name"],
          "lat": double.parse(item["lat"]),
          "lon": double.parse(item["lon"]),
          "address": item["display_name"],
        };
      }).toList();
    } else {
      throw Exception('Failed to load blood banks');
    }
  } catch (e) {
    print("Error fetching blood banks: $e");
    return [];
  }
}
Future<List<Map<String, dynamic>>> fetchHospitals(Position position) async {
  try {
    final response = await http.get(
      Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=hospital&bounded=1&viewbox=${position.longitude - 0.1},${position.latitude + 0.1},${position.longitude + 0.1},${position.latitude - 0.1}&limit=10',
      ),
      headers: {
        'User-Agent': 'YourAppName/1.0 (garychettiar@gmail.com)', // Change this!
      },
    );

    print("Response Status: ${response.statusCode}");
    print("Response Body: ${response.body}");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print("Total Hospitals: ${data.length}");

for (var item in data) {
  print("Hospital: ${item['name']}, Latitude: ${item['lat']}, Longitude: ${item['lon']}");
}
      return data.map<Map<String, dynamic>>((item) => {
      "name": item["display_name"] ?? "Unknown Hospital",
      "lat": item["lat"] != null ? double.parse(item["lat"].toString()) : null,
      "lon": item["lon"] != null ? double.parse(item["lon"].toString()) : null,
    })
    .where((item) => item["lat"] != null && item["lon"] != null) // Remove null values
    .toList();

    } else {
      throw Exception('Failed to load hospitals');
    }
  } catch (e) {
    print("Error fetching hospitals: $e");
    return [];
  }
}
Future<void> showHospitals(BuildContext context) async {
  try {
    // Request permission and get the user's location
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permission is required.")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permissions are permanently denied.")),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    print("User's Location: Lat ${position.latitude}, Lon ${position.longitude}");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    print("Fetching hospitals for position: ${position.latitude}, ${position.longitude}");

    List<Map<String, dynamic>> hospitals = await fetchHospitals(position);

    print("Received hospital data:");
    for (var hospital in hospitals) {
      print("Hospital: ${hospital['name']}, Latitude: ${hospital['lat']}, Longitude: ${hospital['lon']}");
    }

    print("Total hospitals received: ${hospitals.length}");

    Navigator.pop(context); // Close loading dialog

    // Pass hospitals directly to the widget
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HospitalMapScreen(
          position: position, 
          hospitals: hospitals, // Pass the data here
        ),
      ),
    );

  } catch (e) {
    // Error handling remains the same
    print("Error: $e");
    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Error"),
          content: Text("Failed to fetch hospitals. Please try again."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        ),
      );
    }
  }
}Future<void> showBloodBanks(BuildContext context) async {
  try {
    // Get permission and location
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permission is required.")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permissions are permanently denied.")),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium, // Reduce accuracy to save time
      timeLimit: Duration(seconds: 5), // Timeout to prevent long waiting
    );

    print("User's Location: ${position.latitude}, ${position.longitude}");

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    // Fetch blood banks
    List<Map<String, dynamic>> bloodBanks = await fetchBloodBanks(position);
    
    // Close loading indicator
    Navigator.pop(context);

    // Navigate to the map screen with the data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BloodBankMapScreen(
          position: position,
          bloodBanks: bloodBanks,
        ),
      ),
    );
  } catch (e) {
    print("Error: $e");
    if (context.mounted) {
      Navigator.pop(context); // Close dialog if open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to fetch blood banks.")),
      );
    }
  }
}


  @override
  void initState() {
    super.initState();
    checkDonorStatus();
    fetchCurrentLocation(); // Fetch the user's location on initialization
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ChatScreen()),
          );
        },
        backgroundColor: Color(0xFFA22322),
        child: Icon(Icons.chat_outlined, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Color(0xFFA22322)),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: openMapToChangeLocation, // Make location text clickable
                  child: Text(
                    currentLocation,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      // decoration: TextDecoration.underline, // Add underline to indicate clickability
                      // color: Colors.blue, 
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
      
            CarouselSlider(
              options: CarouselOptions(autoPlay: true, height: 160, enlargeCenterPage: true),
              items: bannerImages.map((image) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(image: AssetImage(image), fit: BoxFit.cover),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 20),
      
            !isDonor ? ElevatedButton(
              onPressed: () async {
                Map<String, bool>? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VerificationPage(
                      question: "Is your weight less than 50kg?",
                      questionKey: "weight",
                      nextPage: VerificationPage(
                        question: "Are you suffering from any of the below?",
                        questionKey: "suffering",
                        subQuestions: [
                          "Transmittable disease",
                          "Asthma",
                          "Cardiac arrest",
                          "Hypertension",
                          "Blood pressure",
                          "Diabetes",
                          "Cancer"
                        ],
                        nextPage: VerificationPage(
                          question: "Have you undergone tattoo in last 6 months?",
                          questionKey: "tattoo",
                          nextPage: VerificationPage(
                            question: "Have you undergone immunization in the past one month?",
                            questionKey: "immunization",
                            isLastPage: true, // Mark last page
                            nextPage: null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                if (result != null) {
                  setState(() {
                    answers = result;
                    isVerified = answers.values.every((answer) => answer == false);
                  });
                }
                if (isVerified) {
                  updateDonorStatus();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isVerified ? Color(0xff64F472) : Color(0xFFA22322),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(isVerified ? "You're eligible to Donate" : "Please verify for donating",
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                  SizedBox(width: 10),
                  Icon(Icons.info_outline, color: Colors.white),
                ],
              ),
            ) : Container(height: 25),
            SizedBox(height: 16),
      
            InkWell(
              onTap: () {
                // Find the parent MainScreen widget and update its state
                final mainScreenState = context.findAncestorStateOfType<_MainScreenState>();
                if (mainScreenState != null) {
                  mainScreenState.setState(() {
                    mainScreenState._onItemTapped(1); // 1 is the index for FindDonorsPage
                  });
                }
              },
              child: Container(
                height: 100,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 6)],
                ),
                child: Row(
                  
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset("assets/blood-drop.png", width: 40),
                    SizedBox(width: 12),
                    Text("Nearby donors", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
      
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () {
                        if (activities[index]["label"] == "Blood banks") {
                          showBloodBanks(context);
                        } 
                        else  if (activities[index]["label"] == "Hospital") {
                          showHospitals(context);
                        } else {
                          print("Clicked on: ${activities[index]["label"]}");
                        }
                      },
                      child: Column(
                        children: [
                          Container(
                            width: MediaQuery.of(context).size.width * 0.45,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 6)],
                            ),
                            child: Center(child: Image.asset(activities[index]["icon"], width: 50)),
                          ),
                          SizedBox(height: 6),
                          Text(activities[index]["label"], style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Dummy Find Donor Pag

// Dummy Request Page