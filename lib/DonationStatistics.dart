import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class DonationStatistics extends StatefulWidget {
  @override
  _DonationStatisticsState createState() => _DonationStatisticsState();
}

class _DonationStatisticsState extends State<DonationStatistics> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  int _totalDonations = 0;
  DateTime? _firstDonation;
  DateTime? _lastDonation;
  double _averageDonationsPerYear = 0;
  int _potentialLivesSaved = 0;
  Map<int, int> _donationsByYear = {};
  List<Map<String, dynamic>> _donationLocations = [];
  
  @override
  void initState() {
    super.initState();
    _fetchDonationStatistics();
  }
  
  // Fetch donation statistics from Firestore
  Future<void> _fetchDonationStatistics() async {
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
              .orderBy('date')
              .get();
              
          if (donationQuery.docs.isNotEmpty) {
            // Calculate statistics
            _totalDonations = donationQuery.docs.length;
            _potentialLivesSaved = _totalDonations * 3; // Each donation can save up to 3 lives
            
            // First and last donation dates
            _firstDonation = (donationQuery.docs.first['date'] as Timestamp).toDate();
            _lastDonation = (donationQuery.docs.last['date'] as Timestamp).toDate();
            
            // Calculate average donations per year
            if (_firstDonation != null && _lastDonation != null) {
              final years = _lastDonation!.difference(_firstDonation!).inDays / 365;
              if (years > 0) {
                _averageDonationsPerYear = _totalDonations / years;
              } else {
                _averageDonationsPerYear = _totalDonations.toDouble();
              }
            }
            
            // Group donations by year
            Map<int, int> donationsByYear = {};
            Map<String, int> locationCounts = {};
            
            for (var doc in donationQuery.docs) {
              final date = (doc['date'] as Timestamp).toDate();
              final year = date.year;
              final location = doc['location'] as String;
              
              // Count by year
              donationsByYear[year] = (donationsByYear[year] ?? 0) + 1;
              
              // Count by location
              locationCounts[location] = (locationCounts[location] ?? 0) + 1;
            }
            
            _donationsByYear = donationsByYear;
            
            // Convert location counts to sorted list
            List<Map<String, dynamic>> locations = [];
            locationCounts.forEach((location, count) {
              locations.add({
                'location': location,
                'count': count,
              });
            });
            
            // Sort by count (descending)
            locations.sort((a, b) => b['count'].compareTo(a['count']));
            _donationLocations = locations;
          }
          
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching donation statistics: $e");
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading donation statistics"))
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Donation Statistics"),
        backgroundColor: Color(0xffA5231D),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xffA5231D)))
          : _totalDonations == 0
              ? _buildEmptyState()
              : _buildStatisticsView(),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart,
            size: 80,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            "No donation records yet",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Add donations to see your statistics",
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(Icons.add),
            label: Text("Add Your First Donation"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xffA5231D),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatisticsView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          _buildSummaryCards(),
          SizedBox(height: 24),
          
          // Donations by year chart
          if (_donationsByYear.isNotEmpty) ...[
            Text(
              "Donations by Year",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Container(
              height: 250,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: _buildYearlyChart(),
            ),
            SizedBox(height: 24),
          ],
          
          // Donation locations
          if (_donationLocations.isNotEmpty) ...[
            Text(
              "Favorite Donation Locations",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            ..._donationLocations.take(5).map((location) => _buildLocationItem(location)),
          ],
          
          SizedBox(height: 24),
          
          // Impact section
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xffA5231D).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Your Impact",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xffA5231D),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.favorite, color: Color(0xffA5231D)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You've potentially saved $_potentialLivesSaved lives through your donations!",
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.water_drop, color: Color(0xffA5231D)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You've donated approximately ${_totalDonations * 450}ml of blood in total.",
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCards() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard(
          title: "Total Donations",
          value: _totalDonations.toString(),
          icon: Icons.bloodtype,
          color: Color(0xffA5231D),
        ),
        _buildStatCard(
          title: "First Donation",
          value: _firstDonation != null 
              ? DateFormat('MMM yyyy').format(_firstDonation!)
              : "N/A",
          icon: Icons.calendar_today,
          color: Colors.blue,
        ),
        _buildStatCard(
          title: "Yearly Average",
          value: _averageDonationsPerYear.toStringAsFixed(1),
          icon: Icons.show_chart,
          color: Colors.green,
        ),
        _buildStatCard(
          title: "Lives Saved",
          value: _potentialLivesSaved.toString(),
          icon: Icons.favorite,
          color: Colors.purple,
        ),
      ],
    );
  }
  
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildYearlyChart() {
    // Sort years
    List<int> years = _donationsByYear.keys.toList()..sort();
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (_donationsByYear.values.reduce((a, b) => a > b ? a : b) * 1.2).toDouble(),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.blueGrey,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${years[groupIndex]}: ${rod.toY.round()} donations',
                TextStyle(color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value < 0 || value >= years.length) return Text('');
                return Text(
                  years[value.toInt()].toString(),
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
              reservedSize: 28,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value == 0) return Text('');
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
              reservedSize: 28,
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(
          years.length,
          (index) => BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: _donationsByYear[years[index]]!.toDouble(),
                color: Color(0xffA5231D),
                width: 22,
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLocationItem(Map<String, dynamic> location) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0xffA5231D).withOpacity(0.1),
            child: Text(
              location['count'].toString(),
              style: TextStyle(
                color: Color(0xffA5231D),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              location['location'],
              style: TextStyle(
                fontSize: 16,
              ),
            ),
          ),
          Text(
            "${(location['count'] / _totalDonations * 100).round()}%",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
} 