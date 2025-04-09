import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'homePage.dart';
import '../components/utils.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);
  
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}
  
class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _usernameController   = TextEditingController();
  final TextEditingController _emailController      = TextEditingController();
  final TextEditingController _handphoneController  = TextEditingController();
  final TextEditingController _passwordController   = TextEditingController();
  bool _agreed = false;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color.fromARGB(255, 193, 52, 52),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _register() async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Terms of Service and Privacy Policy first！'),
        ),
      );
      return;
    }
    try {
      // Create user with email and password.
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      userCredential.user!.updateDisplayName(_usernameController.text);
      
      // Generate a new UUID for Firestore document key.
      String newUserDocId = userCredential.user!.uid;
      
      // Create the user document with additional fields.
      await usersCollection.doc(newUserDocId).set({
        'username': _usernameController.text.trim(),
        'handphone': _handphoneController.text.trim(),
        'email': _emailController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status':"normal",
        'helpersCount':0,
        'helpersOnTheWay':[],
        'helpingUserId':null,
        'emergencyType':'',
      });

      _navigateToHome(userCredential);
      // Optionally navigate to a home/dashboard screen.
    } on FirebaseAuthException catch (e) {
      _showSnackBar("Registration failed: ${e.message}");
    } catch (e) {
      _showSnackBar("An error occurred during registration. ${e.toString()}");
    } 
  }

    void _navigateToHome(UserCredential userCredential) {
    // Use pushReplacement to remove LoginPage from stack
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(userCredential: userCredential),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder and SingleChildScrollView to make the content scrollable when it exceeds the limit, and fill the parent height to avoid overflow when there is less content
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(_usernameController, 'Username', Icons.person),
                      const SizedBox(height: 20),
                      _buildTextField(_emailController, 'Email', Icons.email),
                      const SizedBox(height: 20),
                      _buildTextField(_handphoneController, 'Handphone (Optional)', Icons.phone),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey[50],
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Checkbox(
                            value: _agreed,
                            activeColor: const Color(0xFFE91E63),
                            onChanged: (v) => setState(() => _agreed = v!),
                          ),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'I agree to the ',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  TextSpan(
                                    text: 'Terms of Service',
                                    style: const TextStyle(
                                      color: Color(0xFF6A1B9A),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: ' and ',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: const TextStyle(
                                      color: Color(0xFF6A1B9A),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE91E63),
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                        child: const Text(
                          'CREATE ACCOUNT',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildTextField(
      TextEditingController controller, String hint, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey[50],
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}