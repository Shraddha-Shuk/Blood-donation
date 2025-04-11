import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class BloodBankMapScreen extends StatefulWidget {
  final Position position;
  final List<Map<String, dynamic>> bloodBanks;
  final bool isLoading;

  const BloodBankMapScreen({
    required this.position,
    required this.bloodBanks,
    this.isLoading = false,
  });
  
  @override
  _BloodBankMapScreenState createState() => _BloodBankMapScreenState();
}

class _BloodBankMapScreenState extends State<BloodBankMapScreen> {
  late final MapController _mapController;
  double _currentZoom = 14.0;
  bool isLoading = false;
  late List<Map<String, dynamic>> bloodBanks;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    isLoading = widget.isLoading;
    bloodBanks = [...widget.bloodBanks]; // Create a copy to avoid reference issues
    
    // If initially loading, fetch data
    if (isLoading && bloodBanks.isEmpty) {
      _fetchBloodBanks();
    }
    
    print("🔄 Initializing map with ${bloodBanks.length} blood banks");
    for (var bank in bloodBanks) {
      print("✅ Blood Bank: ${bank["name"]}, Lat: ${bank["lat"]}, Lon: ${bank["lon"]}");
    }
  }

  @override
  void dispose() {
    // Clean up resources when widget is disposed
    super.dispose();
  }

  Future<void> _fetchBloodBanks() async {
    if (!mounted) return;
    
    try {
      // Use the user's current position for the search query
      double lat = widget.position.latitude;
      double lon = widget.position.longitude;
      
      // Create a bounding box around the user's location
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=blood+bank&bounded=1&viewbox=${lon - 0.05},${lat + 0.05},${lon + 0.05},${lat - 0.05}&limit=5'),
        headers: {
          'User-Agent': 'YourAppName/1.0 (garychettiar@gmail.com)',
        },
      ).timeout(Duration(seconds: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<Map<String, dynamic>> fetchedBanks = data.map<Map<String, dynamic>>((item) {
          return {
            "name": item["display_name"],
            "lat": double.parse(item["lat"]),
            "lon": double.parse(item["lon"]),
            "address": item["display_name"],
            "display_name": item["display_name"],
          };
        }).toList();
        
        if (mounted) {
          setState(() {
            bloodBanks = fetchedBanks;
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
      print("Error fetching blood banks: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        // Show error only if still mounted
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load blood banks. Please try again later.")),
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

  // Open directions to a blood bank
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
    print("📌 Rebuilding UI with ${bloodBanks.length} blood banks");

    return Scaffold(
      appBar: AppBar(
        title: Text("Blood Banks"),
        backgroundColor: Color(0xFFA22322),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Map with fixed height
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
                        // User's location marker
                        Marker(
                          width: 40.0,
                          height: 40.0,
                          point: LatLng(widget.position.latitude, widget.position.longitude),
                          child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                        ),
                        // Blood Bank Markers
                        ...bloodBanks.map((bank) => Marker(
                              width: 40.0,
                              height: 40.0,
                              point: LatLng(bank["lat"], bank["lon"]),
                              child: Icon(Icons.bloodtype, color: Colors.red, size: 40),
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
                        heroTag: "zoomInBloodBank",
                      ),
                      SizedBox(height: 10),
                      FloatingActionButton(
                        mini: true,
                        onPressed: _zoomOut,
                        child: Icon(Icons.remove),
                        heroTag: "zoomOutBloodBank",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List of Blood Banks Below
          Expanded(
            child: isLoading 
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFA22322)),
                      SizedBox(height: 12),
                      Text("Finding nearby blood banks...", 
                           style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ))
              : bloodBanks.isNotEmpty
                ? ListView.builder(
                    itemCount: bloodBanks.length,
                    itemBuilder: (context, index) {
                      final bank = bloodBanks[index];
                      return Card(
                        elevation: 2,
                        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Icon(Icons.bloodtype, color: Color(0xFFA22322), size: 28),
                          title: Text(
                            bank["name"] ?? "Unknown Blood Bank",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            bank["display_name"] ?? "Location not available",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: ElevatedButton.icon(
                            icon: Icon(Icons.directions),
                            label: Text("Directions"),
                            onPressed: () => _openDirections(
                              bank["lat"],
                              bank["lon"],
                              bank["name"] ?? "Blood Bank",
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
                          "No blood banks found nearby",
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