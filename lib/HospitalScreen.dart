import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class HospitalMapScreen extends StatefulWidget {
  final Position position;
  final List<Map<String, dynamic>> hospitals;
  final bool isLoading;

  const HospitalMapScreen({
    required this.position,
    required this.hospitals,
    this.isLoading = false,
  });
  
  @override
  _HospitalMapScreenState createState() => _HospitalMapScreenState();
}

class _HospitalMapScreenState extends State<HospitalMapScreen> {
  late final MapController _mapController;
  double _currentZoom = 14.0;
  bool isLoading = false;
  late List<Map<String, dynamic>> hospitals;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    isLoading = widget.isLoading;
    hospitals = [...widget.hospitals]; // Create a copy to avoid reference issues
    
    // If initially loading, fetch data
    if (isLoading && hospitals.isEmpty) {
      _fetchHospitals();
    }
    
    print("🔄 Initializing map with ${hospitals.length} hospitals");
    for (var hospital in hospitals) {
      print("✅ Hospital: ${hospital["name"]}, Lat: ${hospital["lat"]}, Lon: ${hospital["lon"]}");
    }
  }

  @override
  void dispose() {
    // Clean up resources when widget is disposed
    super.dispose();
  }

  Future<void> _fetchHospitals() async {
    if (!mounted) return;
    
    try {
      // Use the user's current position for the search query
      double lat = widget.position.latitude;
      double lon = widget.position.longitude;
      
      // Create a bounding box around the user's location
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=hospital&bounded=1&viewbox=${lon - 0.1},${lat + 0.1},${lon + 0.1},${lat - 0.1}&limit=10',
        ),
        headers: {
          'User-Agent': 'YourAppName/1.0 (garychettiar@gmail.com)',
        },
      ).timeout(Duration(seconds: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<Map<String, dynamic>> fetchedHospitals = data.map<Map<String, dynamic>>((item) => {
          "name": item["display_name"] ?? "Unknown Hospital",
          "lat": item["lat"] != null ? double.parse(item["lat"].toString()) : null,
          "lon": item["lon"] != null ? double.parse(item["lon"].toString()) : null,
          "display_name": item["display_name"],
        })
        .where((item) => item["lat"] != null && item["lon"] != null)
        .toList();
        
        if (mounted) {
          setState(() {
            hospitals = fetchedHospitals;
            isLoading = false;
          });
          
          // Center the map on user's location after loading data
          _mapController.move(LatLng(lat, lon), _currentZoom);
        }
      } else {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching hospitals: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        // Show error only if still mounted
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load hospitals. Please try again later.")),
        );
      }
    }
  }

  void _zoomIn() {
    setState(() {
      _currentZoom += 1;
      _mapController.move(_mapController.center, _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom -= 1;
      _mapController.move(_mapController.center, _currentZoom);
    });
  }

  // Open directions to a hospital
  Future<void> _openDirections(double lat, double lon, String name) async {
    // Use Google Maps URL scheme
    final url = 'https://www.google.com/maps/dir/?api=1&origin=${widget.position.latitude},${widget.position.longitude}&destination=$lat,$lon&travelmode=driving&dir_action=navigate';
    
    // Encode the URL 
    final encodedUrl = Uri.encodeFull(url);
    
    try {
      if (await canLaunch(encodedUrl)) {
        await launch(encodedUrl);
      } else {
        throw 'Could not launch $encodedUrl';
      }
    } catch (e) {
      print("Error launching maps: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not open directions. Maps app may not be installed.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print("📌 Rebuilding UI with ${hospitals.length} hospitals");

    return Scaffold(
      appBar: AppBar(
        title: Text("Hospitals"),
        backgroundColor: Color(0xFFA22322),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Map with Fixed Height
          SizedBox(
            height: 300,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: LatLng(widget.position.latitude, widget.position.longitude),
                    zoom: _currentZoom,
                    onMapReady: () {
                      // Ensure the map centers on user's location when ready
                      _mapController.move(
                        LatLng(widget.position.latitude, widget.position.longitude),
                        _currentZoom
                      );
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                      subdomains: ['a', 'b', 'c'],
                    ),
                    MarkerLayer(
                      markers: [
                        // User's Location Marker
                        Marker(
                          width: 40.0,
                          height: 40.0,
                          point: LatLng(widget.position.latitude, widget.position.longitude),
                          child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                        ),
                        // Hospital Markers
                        ...hospitals.map((hospital) => Marker(
                              width: 40.0,
                              height: 40.0,
                              point: LatLng(hospital["lat"], hospital["lon"]),
                              child: Icon(Icons.local_hospital, color: Colors.red, size: 40),
                            )),
                      ],
                    ),
                  ],
                ),
                // Zoom Buttons
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        mini: true,
                        onPressed: _zoomIn,
                        child: Icon(Icons.add),
                        heroTag: "zoomIn",
                      ),
                      SizedBox(height: 10),
                      FloatingActionButton(
                        mini: true,
                        onPressed: _zoomOut,
                        child: Icon(Icons.remove),
                        heroTag: "zoomOut",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List of Hospitals Below
          Expanded(
            child: isLoading 
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFA22322)),
                      SizedBox(height: 12),
                      Text("Finding nearby hospitals...", 
                           style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ))
              : hospitals.isNotEmpty
                ? ListView.builder(
                    itemCount: hospitals.length,
                    itemBuilder: (context, index) {
                      final hospital = hospitals[index];
                      return Card(
                        elevation: 2,
                        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Icon(Icons.local_hospital, color: Color(0xFFA22322), size: 28),
                          title: Text(
                            hospital["name"] ?? "Unknown Hospital",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            hospital["display_name"] ?? "Location not available",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: ElevatedButton.icon(
                            icon: Icon(Icons.directions),
                            label: Text("Directions"),
                            onPressed: () => _openDirections(
                              hospital["lat"],
                              hospital["lon"],
                              hospital["name"] ?? "Hospital",
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFA22322),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "No hospitals found nearby",
                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Try changing your location or expanding search radius",
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}