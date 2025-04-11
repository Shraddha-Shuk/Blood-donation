import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DonationTracker.dart';
import 'Login.dart';
import 'package:geocoding/geocoding.dart';

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _userData;
  String? _entityType;
  bool _isLoading = true;
  bool _isEditing = false;
  String? _locationAddress;
  bool _isConvertingLocation = false;

  // Controllers for editing
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  String? _selectedBloodType;
  Map<String, dynamic> _bloodInventory = {};
  Map<String, dynamic> _operatingHours = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _licenseController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final hospitalDoc = await _firestore.collection('hospitals').doc(user.uid).get();
        final bloodbankDoc = await _firestore.collection('bloodbanks').doc(user.uid).get();

        if (userDoc.exists) {
          setState(() {
            _userData = userDoc.data();
            _entityType = 'user';
            _isLoading = false;
          });
          if (_userData!['location'] != null) {
            _convertLocationToAddress(_userData!['location'] as String);
          }
        } else if (hospitalDoc.exists) {
          setState(() {
            _userData = hospitalDoc.data();
            _entityType = 'hospital';
            _isLoading = false;
          });
          if (_userData!['location'] != null) {
            _convertLocationToAddress(_userData!['location'] as String);
          }
        } else if (bloodbankDoc.exists) {
          setState(() {
            _userData = bloodbankDoc.data();
            _entityType = 'bloodbank';
            _isLoading = false;
          });
          if (_userData!['location'] != null) {
            _convertLocationToAddress(_userData!['location'] as String);
          }
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _convertLocationToAddress(String? locationString) async {
    if (locationString == null) return;
    
    setState(() {
      _isConvertingLocation = true;
    });

    try {
      List<String> coordinates = locationString.split(',');
      if (coordinates.length == 2) {
        double latitude = double.parse(coordinates[0].trim());
        double longitude = double.parse(coordinates[1].trim());
        
        List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String address = "";
          
          if (place.street?.isNotEmpty ?? false) {
            address += place.street!;
          }
          if (place.subLocality?.isNotEmpty ?? false) {
            if (address.isNotEmpty) address += ", ";
            address += place.subLocality!;
          }
          if (place.locality?.isNotEmpty ?? false) {
            if (address.isNotEmpty) address += ", ";
            address += place.locality!;
          }
          if (place.administrativeArea?.isNotEmpty ?? false) {
            if (address.isNotEmpty) address += ", ";
            address += place.administrativeArea!;
          }
          if (place.postalCode?.isNotEmpty ?? false) {
            if (address.isNotEmpty) address += " ";
            address += place.postalCode!;
          }
          
          setState(() {
            _locationAddress = address.isNotEmpty ? address : locationString;
          });
        }
      }
    } catch (e) {
      print('Error converting location to address: $e');
      setState(() {
        _locationAddress = locationString;
      });
    } finally {
      setState(() {
        _isConvertingLocation = false;
      });
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _nameController.text = _userData!['name'] ?? '';
      _contactController.text = _userData!['contact'] ?? '';
      _licenseController.text = _userData!['license'] ?? '';
      
      // If we have location as coordinates, convert to address for editing
      if (_userData!['location'] != null && _userData!['location'].contains(',')) {
        _locationController.text = _locationAddress ?? _userData!['location'] ?? '';
      } else {
        _locationController.text = _userData!['location'] ?? '';
      }
      
      _selectedBloodType = _userData!['bloodType'];
      _bloodInventory = Map<String, dynamic>.from(_userData!['bloodInventory'] ?? {});
      _operatingHours = Map<String, dynamic>.from(_userData!['operatingHours'] ?? {});
    });
  }

  Future<void> _saveChanges() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Convert address to coordinates
        String locationValue = _locationController.text.trim();
        if (locationValue.isNotEmpty) {
          try {
            List<Location> locations = await locationFromAddress(locationValue);
            if (locations.isNotEmpty) {
              Location location = locations.first;
              locationValue = "${location.latitude},${location.longitude}";
            }
          } catch (e) {
            print('Error converting address to coordinates: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error converting address to coordinates, using as entered')),
            );
          }
        }

        Map<String, dynamic> updatedData = {
          'name': _nameController.text.trim(),
          'contact': _contactController.text.trim(),
          'location': locationValue,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (_entityType != 'user') {
          updatedData['license'] = _licenseController.text.trim();
          updatedData['bloodInventory'] = _bloodInventory;
          if (_entityType == 'bloodbank') {
            updatedData['operatingHours'] = _operatingHours;
          }
        } else {
          updatedData['bloodType'] = _selectedBloodType;
        }

        await _firestore
            .collection(_entityType! + 's')
            .doc(user.uid)
            .update(updatedData);

        setState(() {
          _userData!.addAll(updatedData);
          _isEditing = false;
        });

        // Convert new location to address
        if (updatedData['location'] != null) {
          _convertLocationToAddress(updatedData['location'] as String);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
    });
  }

  void _updateBloodInventory(String bloodType, int units) {
    setState(() {
      _bloodInventory[bloodType] = units;
    });
  }

  void _updateOperatingHours(String day, String open, String close) {
    setState(() {
      _operatingHours[day] = {
        'open': open,
        'close': close,
      };
    });
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
      );
    } catch (e) {
      print("Error signing out: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to sign out. Please try again.'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_userData == null) {
      return Scaffold(
        body: Center(
          child: Text('No user data found'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile',style: TextStyle(color: Colors.white),),
        backgroundColor: Color(0xFF9E3B35),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: Icon(Icons.edit, color: Colors.white),
              onPressed: _startEditing,
            ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: _signOut,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Color(0xFF9E3B35),
                child: Text(
                  (_isEditing ? _nameController.text : _userData!['name'])[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Center(
              child: _isEditing
                  ? TextField(
                      controller: _nameController,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      _userData!['name'],
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                _entityType!.toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ),
            SizedBox(height: 24),

            // Contact Information
            _buildSection(
              'Contact Information',
              [
                _buildInfoRow(
                  'Phone',
                  _isEditing
                      ? TextField(
                          controller: _contactController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                        )
                      : Text(
                          _userData!['contact'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                _buildInfoRow(
                  'Location',
                  _isEditing
                      ? TextField(
                          controller: _locationController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
                            hintText: 'Enter address',
                          ),
                        )
                      : _isConvertingLocation
                          ? Center(child: CircularProgressIndicator())
                          : Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _locationAddress ?? 'Location not set',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Entity-specific information
            if (_entityType == 'user') ...[
              _buildSection(
                'Blood Information',
                [
                  _buildInfoRow(
                    'Blood Type',
                    _isEditing
                        ? DropdownButtonFormField<String>(
                            value: _selectedBloodType,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12),
                            ),
                            items: ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"]
                                .map((bloodType) => DropdownMenuItem(
                                      value: bloodType,
                                      child: Text(bloodType),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedBloodType = value;
                              });
                            },
                          )
                        : Text(
                            _userData!['bloodType'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                  _buildInfoRow(
                    'Donor Status',
                    Text(
                      _userData!['isDonor'] ? 'Active Donor' : 'Not a Donor',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_userData!['latestDonation'] != null)
                    _buildInfoRow(
                      'Last Donation',
                      Text(
                        _formatDate(_userData!['latestDonation']),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 16),
              
              // Add Donation History button
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DonationTracker(),
                      ),
                    );
                  },
                  icon: Icon(Icons.history, color: Colors.white),
                  label: Text(
                    'View & Edit Donation History',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF9E3B35),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ] else if (_entityType == 'hospital' || _entityType == 'bloodbank') ...[
              _buildSection(
                'License Information',
                [
                  _buildInfoRow(
                    'License Number',
                    _isEditing
                        ? TextField(
                            controller: _licenseController,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12),
                            ),
                          )
                        : Text(
                            _userData!['license'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              _buildSection(
                'Blood Inventory',
                _buildInventoryList(_isEditing ? _bloodInventory : _userData!['bloodInventory']),
              ),
              if (_entityType == 'bloodbank') ...[
                SizedBox(height: 24),
                _buildSection(
                  'Operating Hours',
                  _buildOperatingHours(_isEditing ? _operatingHours : _userData!['operatingHours']),
                ),
              ],
            ],
            SizedBox(height: 24),

            // Edit/Save/Cancel buttons
            if (_isEditing)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _cancelEditing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF9E3B35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text('Save Changes', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF9E3B35),
          ),
        ),
        SizedBox(height: 8),
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, Widget value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ),
          SizedBox(width: 16),
          Flexible(
            flex: 3,
            child: value,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInventoryList(Map<String, dynamic> inventory) {
    if (inventory == null || inventory.isEmpty) {
      return [
        Text(
          'No blood inventory available',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
        if (_isEditing) ...[
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _addBloodInventory,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text(
              'Add Blood Type',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF9E3B35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ];
    }

    return [
      ...inventory.entries.map((entry) {
        return _buildInfoRow(
          '${entry.key}',
          _isEditing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF9E3B35)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF9E3B35)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF9E3B35), width: 2),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9E3B35),
                        ),
                        controller: TextEditingController(text: entry.value.toString()),
                        onChanged: (value) {
                          int? units = int.tryParse(value);
                          if (units != null) {
                            _updateBloodInventory(entry.key, units);
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'units',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9E3B35),
                      ),
                    ),
                    SizedBox(width: 8),
                    InkWell(
                      onTap: () => _removeBloodInventory(entry.key),
                      child: Icon(
                        Icons.delete,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ],
                )
              : Text(
                  '${entry.value} units',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        );
      }).toList(),
      if (_isEditing) ...[
        SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _addBloodInventory,
          icon: Icon(Icons.add, color: Colors.white),
          label: Text(
            'Add Blood Type',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF9E3B35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildOperatingHours(Map<String, dynamic> hours) {
    if (hours == null || hours.isEmpty) {
      return [
        Text(
          'Operating hours not set',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
        if (_isEditing) ...[
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _addOperatingHours,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text(
              'Add Operating Hours',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF9E3B35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ];
    }

    return [
      ...hours.entries.map((entry) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              Expanded(
                child: _isEditing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (time != null) {
                                _updateOperatingHours(
                                  entry.key,
                                  _formatTime(time),
                                  entry.value['close'],
                                );
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Color(0xFF9E3B35)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, 
                                    size: 14,
                                    color: Color(0xFF9E3B35),
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    entry.value['open'],
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF9E3B35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text('-', style: TextStyle(fontSize: 14)),
                          ),
                          InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (time != null) {
                                _updateOperatingHours(
                                  entry.key,
                                  entry.value['open'],
                                  _formatTime(time),
                                );
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Color(0xFF9E3B35)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, 
                                    size: 14,
                                    color: Color(0xFF9E3B35),
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    entry.value['close'],
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF9E3B35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                          InkWell(
                            onTap: () => _removeOperatingHours(entry.key),
                            child: Icon(
                              Icons.delete,
                              size: 18,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '${entry.value['open']} - ${entry.value['close']}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          ),
        );
      }).toList(),
      if (_isEditing) ...[
        SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _addOperatingHours,
          icon: Icon(Icons.add, color: Colors.white),
          label: Text(
            'Add Operating Hours',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF9E3B35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ],
    ];
  }

  void _addBloodInventory() async {
    showDialog(
      context: context,
      builder: (context) {
        String selectedBloodType = "A+";
        String units = "";
        return AlertDialog(
          title: Text('Add Blood Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedBloodType,
                decoration: InputDecoration(
                  labelText: 'Blood Type',
                  border: OutlineInputBorder(),
                ),
                items: ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"]
                    .map((bloodType) => DropdownMenuItem(
                          value: bloodType,
                          child: Text(bloodType),
                        ))
                    .toList(),
                onChanged: (value) {
                  selectedBloodType = value!;
                },
              ),
              SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Units',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  units = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Color(0xFF9E3B35))),
            ),
            ElevatedButton(
              onPressed: () {
                int? unitsInt = int.tryParse(units);
                if (unitsInt != null) {
                  _updateBloodInventory(selectedBloodType, unitsInt);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF9E3B35),
              ),
              child: Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _removeBloodInventory(String bloodType) {
    setState(() {
      _bloodInventory.remove(bloodType);
    });
  }

  void _addOperatingHours() async {
    String selectedDay = "Monday";
    TimeOfDay? openTime;
    TimeOfDay? closeTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Add Operating Hours'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      "Monday",
                      "Tuesday",
                      "Wednesday",
                      "Thursday",
                      "Friday",
                      "Saturday",
                      "Sunday"
                    ].map((day) => DropdownMenuItem(
                          value: day,
                          child: Text(day),
                        )).toList(),
                    onChanged: (value) {
                      selectedDay = value!;
                    },
                  ),
                  SizedBox(height: 16),
                  ListTile(
                    title: Text('Opening Time'),
                    subtitle: Text(openTime != null 
                      ? _formatTime(openTime!)
                      : 'Select opening time'),
                    trailing: Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        setState(() {
                          openTime = time;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text('Closing Time'),
                    subtitle: Text(closeTime != null 
                      ? _formatTime(closeTime!)
                      : 'Select closing time'),
                    trailing: Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        setState(() {
                          closeTime = time;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Color(0xFF9E3B35))),
                ),
                ElevatedButton(
                  onPressed: openTime != null && closeTime != null
                      ? () {
                          Navigator.pop(context, {
                            'day': selectedDay,
                            'open': _formatTime(openTime!),
                            'close': _formatTime(closeTime!),
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF9E3B35),
                  ),
                  child: Text('Add', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      _updateOperatingHours(result['day'], result['open'], result['close']);
    }
  }

  void _removeOperatingHours(String day) {
    setState(() {
      _operatingHours.remove(day);
    });
  }

  String _formatDate(Timestamp timestamp) {
    DateTime date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}
