import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BloodRequestsList extends StatelessWidget {
  const BloodRequestsList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bloodRequests')
            .orderBy('date', descending: true)
            .limit(10)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
      
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
      
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No blood requests available'));
          }
      
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              
              return BloodRequestCard(
                bloodGroup: data['bloodGroup'] ?? 'Unknown',
                hospital: data['hospital'] ?? 'Unknown',
                date: data['date'] ?? '',
                time: data['time'] ?? '',
                units: data['units']?.toString() ?? '0',
                status: data['status'] ?? 'Unknown',
                phone: data['phone'] ?? '',
              );
            },
          );
        },
      ),
    );
  }
}

class BloodRequestCard extends StatelessWidget {
  final String bloodGroup;
  final String hospital;
  final String date;
  final String time;
  final String units;
  final String status;
  final String phone;

  const BloodRequestCard({
    Key? key,
    required this.bloodGroup,
    required this.hospital,
    required this.date,
    required this.time,
    required this.units,
    required this.status,
    required this.phone,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Blood Group Circle
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.shade800, width: 2),
              ),
              child: Center(
                child: Text(
                  bloodGroup,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hospital,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Date: $date'),
                  Text('Time: $time'),
                  Text('Units needed: $units'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: status.toLowerCase() == 'active' 
                              ? Colors.green.shade100 
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: status.toLowerCase() == 'active' 
                                ? Colors.green.shade800 
                                : Colors.grey.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Contact Button
            ElevatedButton(
              onPressed: () {
                // Navigate to contact or phone call functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Contacting: $phone'))
                );
                // You can implement phone call functionality here
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Contact'),
            ),
          ],
        ),
      ),
    );
  }
}