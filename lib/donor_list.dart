import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';

class Donor {
  final String name;
  final String bloodType;
  final String location; // Stored as "lat,lng"
  final String phone;
  final double distance;
  final DateTime? latestDonation; // Latest donation date
  String address = "Fetching address..."; // Human-readable address

  Donor({
    required this.name,
    required this.bloodType,
    required this.location, // This will be "lat,lng"
    required this.phone,
    required this.distance,
    this.latestDonation,
  });

  // Convert "lat,lng" string to actual address
  Future<void> fetchAddress() async {
    try {
      // Split "lat,lng" and convert to double
      List<String> latLng = location.split(",");
      double latitude = double.parse(latLng[0]);
      double longitude = double.parse(latLng[1]);

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        address = "${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.country}";
      }
    } catch (e) {
      address = "Address not found";
    }
  }
  
  // Check if donor is eligible (last donation was at least 3 months ago)
  bool isEligibleToDonate() {
    if (latestDonation == null) {
      return true; // If no donation date is recorded, assume eligible
    }
    
    final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
    return latestDonation!.isBefore(threeMonthsAgo);
  }
  
  // Get formatted last donation date
  String getLastDonationText() {
    if (latestDonation == null) {
      return "No donation record";
    }
    
    return "Last donated: ${latestDonation!.day}/${latestDonation!.month}/${latestDonation!.year}";
  }
}

class DonorList extends StatefulWidget {
  final List<Donor> donors;

  const DonorList({Key? key, required this.donors}) : super(key: key);

  @override
  _DonorListState createState() => _DonorListState();
}

class _DonorListState extends State<DonorList> {
  @override
  void initState() {
    super.initState();
    _fetchAllAddresses();
  }

  // Fetch addresses for all donors
  void _fetchAllAddresses() async {
    for (var donor in widget.donors) {
      await donor.fetchAddress();
    }
    setState(() {}); // Refresh UI after fetching addresses
  }

  // Function to initiate a phone call
  void _callDonor(String phoneNumber) async {
    final String phoneUrl = 'tel:+91$phoneNumber';
    print('Attempting to launch: $phoneUrl'); // Debugging log
    
    try {
      launchUrl(Uri.parse(phoneUrl), mode: LaunchMode.externalApplication);
      if (await canLaunchUrl(Uri.parse(phoneUrl))) {
        await launchUrl(Uri.parse(phoneUrl), mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $phoneUrl';
      }
    } catch (e) {
      print('Error launching phone call: $e'); // Additional debug log
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Nearby Donors"),
        backgroundColor: Color(0xffA5231D),
      ),
      body: widget.donors.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No eligible donors found",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Try expanding your search area or try a different blood type",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: widget.donors.length,
              itemBuilder: (context, index) {
                final donor = widget.donors[index];
                return Card(
                  margin: EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: Icon(Icons.bloodtype, color: Colors.red),
                    title: Text("${donor.name} - ${donor.bloodType}"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 16, color: Colors.grey),
                            SizedBox(width: 5),
                            Expanded(
                              child: Text(donor.address, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                            SizedBox(width: 5),
                            Text("${donor.distance.toStringAsFixed(1)} Km"),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                            SizedBox(width: 5),
                            Text(donor.getLastDonationText()),
                          ],
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.call, color: Colors.green),
                      onPressed: () => _callDonor(donor.phone),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
