import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'DonationStatistics.dart';

class DonationTracker extends StatefulWidget {
  @override
  _DonationTrackerState createState() => _DonationTrackerState();
}

class _DonationTrackerState extends State<DonationTracker> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<DonationRecord> _donationHistory = [];
  bool _isLoading = true;
  
  // Controller for the donation location
  final TextEditingController _locationController = TextEditingController();
  
  // Selected date for new donation
  DateTime _selectedDate = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _fetchDonationHistory();
  }
  
  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }
  
  // Fetch donation history from Firestore
  Future<void> _fetchDonationHistory() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Get user document
        QuerySnapshot userQuery = await _firestore
            .collection('users')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
            
        if (userQuery.docs.isNotEmpty) {
          DocumentSnapshot userDoc = userQuery.docs.first;
          String userId = userDoc.id;
          
          // Get donation history
          QuerySnapshot donationQuery = await _firestore
              .collection('users')
              .doc(userId)
              .collection('donations')
              .orderBy('date', descending: true)
              .get();
              
          List<DonationRecord> donations = [];
          for (var doc in donationQuery.docs) {
            donations.add(DonationRecord.fromFirestore(doc));
          }
          
          setState(() {
            _donationHistory = donations;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error loading donation history: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Unable to load your donation history. Please try again later."),
          backgroundColor: Colors.red[700],
        )
      );
    }
  }
  
  // Add new donation record
  Future<void> _addDonation() async {
    // Validate input
    if (_locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter donation location"))
      );
      return;
    }
    
    // Check if selected date is in the future
    if (_selectedDate.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Donation date cannot be in the future"))
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Get user document
        QuerySnapshot userQuery = await _firestore
            .collection('users')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
            
        if (userQuery.docs.isNotEmpty) {
          DocumentSnapshot userDoc = userQuery.docs.first;
          String userId = userDoc.id;
          
          // Create new donation record
          Map<String, dynamic> donationData = {
            'date': Timestamp.fromDate(_selectedDate),
            'location': _locationController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          };
          
          // Add to donations subcollection
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('donations')
              .add(donationData);
              
          // Update user's latestDonation field
          await _firestore
              .collection('users')
              .doc(userId)
              .update({
                'latestDonation': Timestamp.fromDate(_selectedDate),
                'donations': FieldValue.increment(1),
              });
              
          // Reset form
          _locationController.clear();
          setState(() {
            _selectedDate = DateTime.now();
          });
          
          // Refresh donation history
          await _fetchDonationHistory();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Donation record added successfully"))
          );
        }
      }
    } catch (e) {
      print("Error adding donation: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not add your donation record. Please try again."),
          backgroundColor: Colors.red[700],
        )
      );
    }
  }
  
  // Show date picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(0xffA5231D),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Donation Tracker"),
        backgroundColor: Color(0xffA5231D),
        foregroundColor: Colors.white,
        actions: [
          // Statistics button
          IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => DonationStatistics()),
              );
            },
            tooltip: "View Statistics",
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xffA5231D)))
          : Column(
              children: [
                // Add new donation section
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Add New Donation",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      
                      // Date picker
                      InkWell(
                        onTap: () => _selectDate(context),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}",
                                style: TextStyle(fontSize: 16),
                              ),
                              Icon(Icons.calendar_today, color: Color(0xffA5231D)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      
                      // Location input
                      TextField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          labelText: "Donation Location",
                          hintText: "Enter hospital or blood bank name",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Color(0xffA5231D), width: 2),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      
                      // Add button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _addDonation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xffA5231D),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            "Add Donation Record",
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Donation history section
                Expanded(
                  child: _donationHistory.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bloodtype_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                "No donation records yet",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Add your first donation record above",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.all(16),
                          itemCount: _donationHistory.length,
                          itemBuilder: (context, index) {
                            final donation = _donationHistory[index];
                            return Card(
                              margin: EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: Color(0xffA5231D).withOpacity(0.1),
                                  child: Icon(
                                    Icons.bloodtype,
                                    color: Color(0xffA5231D),
                                  ),
                                ),
                                title: Text(
                                  DateFormat('dd MMMM yyyy').format(donation.date),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 4),
                                    Text(donation.location),
                                    SizedBox(height: 4),
                                    Text(
                                      _getDaysAgoText(donation.date),
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _confirmDeleteDonation(donation),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
  
  // Get "X days ago" text
  String _getDaysAgoText(DateTime date) {
    final difference = DateTime.now().difference(date);
    final days = difference.inDays;
    
    if (days == 0) {
      return "Today";
    } else if (days == 1) {
      return "Yesterday";
    } else {
      return "$days days ago";
    }
  }
  
  // Confirm deletion of donation record
  void _confirmDeleteDonation(DonationRecord donation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Donation Record"),
        content: Text("Are you sure you want to delete this donation record? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDonation(donation);
            },
            child: Text(
              "DELETE",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
  
  // Delete donation record
  Future<void> _deleteDonation(DonationRecord donation) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Get user document
        QuerySnapshot userQuery = await _firestore
            .collection('users')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
            
        if (userQuery.docs.isNotEmpty) {
          DocumentSnapshot userDoc = userQuery.docs.first;
          String userId = userDoc.id;
          
          // Delete donation record
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('donations')
              .doc(donation.id)
              .delete();
              
          // Update donation count
          await _firestore
              .collection('users')
              .doc(userId)
              .update({
                'donations': FieldValue.increment(-1),
              });
              
          // Find new latest donation
          QuerySnapshot latestQuery = await _firestore
              .collection('users')
              .doc(userId)
              .collection('donations')
              .orderBy('date', descending: true)
              .limit(1)
              .get();
              
          if (latestQuery.docs.isNotEmpty) {
            DocumentSnapshot latestDoc = latestQuery.docs.first;
            Timestamp latestDate = latestDoc['date'];
            
            // Update latest donation date
            await _firestore
                .collection('users')
                .doc(userId)
                .update({
                  'latestDonation': latestDate,
                });
          } else {
            // No donations left, clear latest donation
            await _firestore
                .collection('users')
                .doc(userId)
                .update({
                  'latestDonation': null,
                });
          }
          
          // Refresh donation history
          await _fetchDonationHistory();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Donation record deleted"))
          );
        }
      }
    } catch (e) {
      print("Error deleting donation: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not delete the donation record. Please try again."),
          backgroundColor: Colors.red[700],
        )
      );
    }
  }
}

// Donation record model
class DonationRecord {
  final String id;
  final DateTime date;
  final String location;
  
  DonationRecord({
    required this.id,
    required this.date,
    required this.location,
  });
  
  // Create from Firestore document
  factory DonationRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DonationRecord(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      location: data['location'] ?? 'Unknown location',
    );
  }
} 