import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
// import 'package:rrd/FirebaseAPI.dart';
import 'package:rrd/HomePage.dart';
import 'package:rrd/Login.dart';
import 'package:rrd/Signup.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Run the app
  runApp(MaterialApp(
    home: AuthWrapper(),
  ));
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return MainScreen(); // User is logged in
        } else {
          return IntroScreen(); // User is not logged in
        }
      },
    );
  }
}

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(MediaQuery.of(context).size.width, 120),
                  painter: WavePainter(_animationController.value),
                );
              },
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Spacer(),
              Center(
                child: Image.asset(
                  'assets/logo.png', // Replace with your actual logo asset
                  height: 200,
                ),
              ),
              SizedBox(height: 40),
              SizedBox(
                width: MediaQuery.sizeOf(context).width *
                    0.5, // Makes both buttons equal in width
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => LoginPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: BorderSide(color: Colors.red),
                    ),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text("Login"),
                  ),
                ),
              ),
              SizedBox(height: 10),
              SizedBox(
                width: MediaQuery.sizeOf(context).width *
                    0.5, // Ensures equal width as the login button
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SignUpPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text("Sign Up"),
                  ),
                ),
              ),
              Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;

  WavePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint1 = Paint()..color = Colors.red.withOpacity(0.6);
    Paint paint2 = Paint()..color = Colors.red.withOpacity(0.8);

    Path path1 = Path();
    Path path2 = Path();

    double waveHeight1 = 80 * sin(animationValue * pi); // Bigger wave height
    double waveHeight2 = 90 * cos(animationValue * pi);

    double waveWidthFactor = 1.5; // Increases the width of waves

    path1.moveTo(0, size.height);
    path2.moveTo(0, size.height);

    for (double i = 0; i < size.width; i++) {
      path1.lineTo(
          i,
          size.height -
              waveHeight1 *
                  sin((i / size.width) *
                      2 *
                      pi /
                      waveWidthFactor) // Wider waves
          );

      path2.lineTo(
          i,
          size.height -
              waveHeight2 *
                  cos((i / size.width) * 2 * pi / waveWidthFactor + pi / 3));
    }

    path1.lineTo(size.width, size.height);
    path1.close();

    path2.lineTo(size.width, size.height);
    path2.close();

    canvas.drawPath(path1, paint1);
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
