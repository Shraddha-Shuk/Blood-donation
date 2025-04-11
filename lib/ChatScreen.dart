import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:async';
import 'dart:convert';
import 'package:rrd/FindDonor.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rrd/donor_list.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  String _conversationHistory = '';
  
  // Predefined suggested questions
  final List<String> suggestedQuestions = [
    "Am I eligible to donate blood?",
    "What are common health tips for blood donors?",
    "How often can I donate blood?",
    "What are the blood donation requirements?",
    "Find eligible O+ blood donors near me",
    "Search for available A- blood donors",
    "Where can I find eligible AB+ donors?",
  ];

  // API Key (replace with your actual key)
  final String apiKey = 'AIzaSyBK5vEFy3AlWhraeRgY-Cz-PZ3rWLf9qKc';
  
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _addWelcomeMessage();
  }

  void _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('chat_history');
    if (history != null) {
      setState(() {
        for (int i = 0; i < history.length; i += 2) {
          _messages.add(ChatMessage(
            text: history[i],
            isUser: true,
          ));
          if (i + 1 < history.length) {
            _messages.add(ChatMessage(
              text: history[i + 1],
              isUser: false,
            ));
          }
        }
      });
    }
    
    // Rebuild conversation history string
    _rebuildConversationHistory();
  }
  
  void _rebuildConversationHistory() {
    // Create a simple conversation history to provide context
    _conversationHistory = '';
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      _conversationHistory += msg.isUser ? 'User: ' : 'Assistant: ';
      _conversationHistory += '${msg.text}\n';
    }
  }

  void _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = <String>[];
    for (final message in _messages) {
      history.add(message.text);
    }
    await prefs.setStringList('chat_history', history);
  }

  void _addWelcomeMessage() {
    if (_messages.isEmpty) {
      setState(() {
        _messages.add(const ChatMessage(
          text: "Hello! I'm your health assistant. How can I help you today with blood donation information?",
          isUser: false,
        ));
      });
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Function to get user's current location
  Future<LatLng?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled. Please enable them.')),
      );
      return null;
    }

    // Check location permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permissions are permanently denied')),
      );
      return null;
    }

    try {
      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
      return null;
    }
  }

  // Function to get address from coordinates
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

  // Function to detect blood group from text
  String? _detectBloodGroup(String text) {
    // Normalize the text for easier matching
    final normalizedText = text.toLowerCase();
    
    // Define patterns for different blood group formats
    final Map<String, String> bloodGroupPatterns = {
      r'a\s*\+': 'A+',
      r'a\s*\-': 'A-',
      r'b\s*\+': 'B+',
      r'b\s*\-': 'B-',
      r'ab\s*\+': 'AB+',
      r'ab\s*\-': 'AB-',
      r'o\s*\+': 'O+',
      r'o\s*\-': 'O-',
      r'a\s*positive': 'A+',
      r'a\s*negative': 'A-',
      r'b\s*positive': 'B+',
      r'b\s*negative': 'B-',
      r'ab\s*positive': 'AB+',
      r'ab\s*negative': 'AB-',
      r'o\s*positive': 'O+',
      r'o\s*negative': 'O-',
      r'a\s*\+ve': 'A+',
      r'a\s*\-ve': 'A-',
      r'b\s*\+ve': 'B+',
      r'b\s*\-ve': 'B-',
      r'ab\s*\+ve': 'AB+',
      r'ab\s*\-ve': 'AB-',
      r'o\s*\+ve': 'O+',
      r'o\s*\-ve': 'O-',
    };
    
    // Check for each pattern
    for (final pattern in bloodGroupPatterns.keys) {
      if (RegExp(pattern).hasMatch(normalizedText)) {
        return bloodGroupPatterns[pattern];
      }
    }
    
    return null;
  }

  // Function to navigate directly to donor results with blood group and location
  Future<void> _navigateToFindDonors(String bloodGroup) async {
    setState(() {
      _isTyping = true;
    });
    
    // Get current location
    final currentLocation = await _getCurrentLocation();
    
    if (currentLocation == null) {
      setState(() {
        _isTyping = false;
      });
      
      // If location not available, navigate to FindDonorsPage to let user select location
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FindDonorsPage(
            initialBloodType: bloodGroup,
          ),
        ),
      );
      return;
    }
    
    try {
      // Search for donors directly
      QuerySnapshot donorDocs = await FirebaseFirestore.instance
        .collection('users')
        .where('bloodType', isEqualTo: bloodGroup)
        .get();

      List<Donor> nearbyDonors = [];
      User? currentUser = FirebaseAuth.instance.currentUser;
      
      // Calculate date 3 months ago for filtering
      final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));

      for (var doc in donorDocs.docs) {
        // Skip the current user
        if (currentUser != null && doc['uid'] == currentUser.uid) {
          continue;
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
            currentLocation.latitude,
            currentLocation.longitude,
            donorLat,
            donorLon,
          ) / 1000; // Convert meters to KM

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
      
      setState(() {
        _isTyping = false;
      });
      
      // Sort donors by distance
      nearbyDonors.sort((a, b) => a.distance.compareTo(b.distance));
      
      // Navigate directly to results page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DonorList(donors: nearbyDonors),
        ),
      );
      
      // Show snackbar with results count
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Found ${nearbyDonors.length} eligible donors with $bloodGroup blood type nearby!"),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      setState(() {
        _isTyping = false;
      });
      
      print("Error searching for donors: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error searching for donors. Please try again.")),
      );
      
      // Fallback to FindDonorsPage if there's an error
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FindDonorsPage(
            initialBloodType: bloodGroup,
            initialLocation: currentLocation,
          ),
        ),
      );
    }
  }

  Future<String> _generateResponse(String prompt) async {
    try {
      // Check if the prompt is asking for blood donors
      final bloodGroup = _detectBloodGroup(prompt);
      final isSearchingDonors = prompt.toLowerCase().contains('donor') || 
                               prompt.toLowerCase().contains('blood') && 
                               (prompt.toLowerCase().contains('near me') || 
                                prompt.toLowerCase().contains('around me') ||
                                prompt.toLowerCase().contains('find') ||
                                prompt.toLowerCase().contains('search'));
      
      if (bloodGroup != null && isSearchingDonors) {
        // Navigate to donor results directly with blood group pre-selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToFindDonors(bloodGroup);
        });
        return "I'll help you find eligible $bloodGroup blood donors near you. I'm searching for donors who haven't donated in the last 3 months...";
      }

      // Prepare system instructions
      final systemInstruction = 'You are a helpful AI assistant for a health organization. '
          'Provide information about blood donation eligibility, health tips, '
          'and answer frequently asked questions. '
          'Keep responses concise, accurate, and friendly. '
          'Use markdown formatting (bold, italic, lists) to make your responses more readable. '
          'If you don\'t know something, say so rather than making up information. '
          'Focus on providing evidence-based health information.';
      
      // URL for Gemini API - using gemini-pro which is available in v1beta
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');
      
      // Build API request body
      final requestBody = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': '$systemInstruction\n\nConversation history:\n$_conversationHistory\n\nUser query: $prompt'
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'topP': 0.8,
          'topK': 40,
          'maxOutputTokens': 1000,
        }
      });
      
      // Make API call
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );
      
      // Check if successful
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // Extract text from response structure
        if (responseData['candidates'] != null && 
            responseData['candidates'].isNotEmpty && 
            responseData['candidates'][0]['content'] != null &&
            responseData['candidates'][0]['content']['parts'] != null &&
            responseData['candidates'][0]['content']['parts'].isNotEmpty) {
          return responseData['candidates'][0]['content']['parts'][0]['text'];
        } else {
          print('Invalid response structure: ${response.body}');
          return "I couldn't generate a response. Please try again.";
        }
      } else {
        print('Error status code: ${response.statusCode}');
        print('Error response: ${response.body}');
        return "Error ${response.statusCode}: ${json.decode(response.body)['error']['message'] ?? 'Unknown error'}";
      }
    } catch (e) {
      print('Exception while calling API: $e');
      return "Error connecting to AI service: $e";
    }
  }

  void _sendMessage() async {
    if (_textController.text.trim().isEmpty) return;

    final messageText = _textController.text.trim();
    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: messageText,
        isUser: true,
      ));
      _isTyping = true;
    });
    _scrollDown();
    
    // Update conversation history with the new user message
    _rebuildConversationHistory();

    // Get AI response
    final responseText = await _generateResponse(messageText);
    
    setState(() {
      _messages.add(ChatMessage(
        text: responseText,
        isUser: false,
      ));
      _isTyping = false;
      
      // Update conversation history to include AI's response
      _rebuildConversationHistory();
    });
    _scrollDown();
    _saveHistory();
  }

  void _handleSuggestedQuestion(String question) {
    _textController.text = question;
    _sendMessage();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    
      appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back,color: Colors.white,),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
        title: const Text('Health Chatbot',style: TextStyle(color: Colors.white),),
        backgroundColor: Color(0xffA5231D),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete,color: Colors.white,),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear History'),
                  content: const Text('Are you sure you want to clear the chat history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _messages.clear();
                          _addWelcomeMessage();
                          _rebuildConversationHistory();
                        });
                        _saveHistory();
                        Navigator.pop(context);
                      },
                      child: const Text('CLEAR'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _messages[index];
              },
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Typing...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: suggestedQuestions.map((question) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          label: Text(question),
                          onPressed: () => _handleSuggestedQuestion(question),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Ask a question...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          fillColor: Colors.grey[100],
                          filled: true,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      onPressed: _sendMessage,
                      child: const Icon(Icons.send),
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
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatMessage({
    super.key,
    required this.text,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: Colors.red,
              child: const Icon(Icons.health_and_safety, color: Colors.white),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Color.fromARGB(142, 211, 75, 107) : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color.fromARGB(142, 211, 75, 107)),
              ),
              child: isUser
                ? Text(text)
                : MarkdownBody(
                    data: text,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 16),
                      h1: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                      h2: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                      h3: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                      strong: const TextStyle(fontWeight: FontWeight.bold),
                      em: const TextStyle(fontStyle: FontStyle.italic),
                      listBullet: TextStyle(color: Theme.of(context).primaryColor),
                    ),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser)
            const CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, color: Colors.white),
            ),
        ],
      ),
    );
  }
}