import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rrd/Signup.dart';
import 'package:rrd/HomePage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:rrd/forgot_password.dart';
import 'package:rrd/utils/custom_loader.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool obscureText = true;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String selectedEntity = 'user'; // Default to user

  Future<void> loginUser() async {
    try {
      FocusScope.of(context).unfocus();
      AppLoader.show(context);
      // First authenticate with Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;

      await firebaseMessaging.requestPermission();
      String? fcmToken = await firebaseMessaging.getToken();

      DocumentReference userDocRef = FirebaseFirestore.instance
          .collection('${selectedEntity}s') // users, hospitals, or bloodbanks
          .doc(userCredential.user!.uid);

      DocumentSnapshot userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await _auth.signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Account not found. Please sign up first.")),
        );
        AppLoader.hide(context);
        return;
      }

      if (fcmToken != null) {
        await userDocRef.update({'fcmToken': fcmToken});
      }

      AppLoader.hide(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Successful!")),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainScreen()),
      );
    } catch (e) {
      if (kDebugMode) {
        AppLoader.hide(context);
        print("Login error: $e");
      }
      
      // Provide a more user-friendly error message based on error type
      String errorMessage = "Login failed. Please check your credentials and try again.";
      
      // Handle common Firebase auth errors with more specific messages
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
          case 'wrong-password':
            errorMessage = "Incorrect email or password. Please try again.";
            break;
          case 'invalid-email':
            errorMessage = "Please enter a valid email address.";
            break;
          case 'user-disabled':
            errorMessage = "This account has been disabled. Please contact support.";
            break;
          case 'too-many-requests':
            errorMessage = "Too many unsuccessful login attempts. Please try again later.";
            break;
          case 'network-request-failed':
            errorMessage = "Network error. Please check your internet connection.";
            break;
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red[700],
        ),
      );
      AppLoader.hide(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                Text(
                  "Welcome Back!",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 20),
      
                // Entity Selection
                Text("Select Account Type",style: TextStyle(fontSize: 14, color: Colors.black54)),
                SizedBox(height: 10,),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedEntity,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(value: 'hospital', child: Text('Hospital')),
                        DropdownMenuItem(value: 'bloodbank', child: Text('Blood Bank')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedEntity = value!;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 16),
      
                /// Email
                Text("E-mail",style: TextStyle(fontSize: 14, color: Colors.black54)),
                TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  hintText: "Enter email",
                  fillColor: Colors.grey.shade200,
                  enabled: true,
                  filled: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none
                  ),
                ),
              ),
                SizedBox(height: 16),
      
                /// Password
                Text("Password",style: TextStyle(fontSize: 14, color: Colors.black54)),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscureText,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    hintText: "Enter password",
                    fillColor: Colors.grey.shade200,
                    enabled: true,
                    filled: true,
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          obscureText = !obscureText;
                        });
                      },
                      icon: obscureText ? Icon(Icons.visibility) : Icon(Icons.visibility_off),
                      color: Colors.grey,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) {
                        return ForgotPassword();
                      },));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text("Forgot password?",
                          style: TextStyle(color: Colors.red, fontSize: 14,fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: loginUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding:EdgeInsets.symmetric(horizontal: 100, vertical: 14),
                    ),
                    child: Text("Login",style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade400)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text("OR", style: TextStyle(color: Colors.grey)),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade400)),
                  ],
                ),
                SizedBox(height: 20),
                // Center(
                //   child: ElevatedButton(
                //     onPressed: () {}, // Implement Google Sign-In later
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: Colors.white,
                //       elevation: 2,
                //       shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(8),
                //         side: BorderSide(color: Colors.grey.shade300),
                //       ),
                //     ),
                //     child: Padding(
                //       padding: const EdgeInsets.symmetric(
                //           vertical: 10, horizontal: 20),
                //       child: Row(
                //         mainAxisSize: MainAxisSize.min,
                //         children: [
                //           Image.network(
                //             'https://banner2.cleanpng.com/20181108/vqy/kisspng-youtube-google-logo-google-images-google-account-consulting-crm-the-1-recommended-crm-for-g-suite-1713925083723.webp',
                //             height: 24,
                //           ),
                //           SizedBox(width: 10),
                //           Text("Sign in with Google",
                //               style: TextStyle(color: Colors.black54)),
                //         ],
                //       ),
                //     ),
                //   ),
                // ),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: Colors.black54,fontSize: 14),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => SignUpPage()),
                              );
                            },
                            child: Text(
                              "Sign Up",
                              style: TextStyle(
                                  color: Colors.red, fontWeight: FontWeight.bold,fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
