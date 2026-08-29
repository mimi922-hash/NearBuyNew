import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'role_selection_screen.dart';
import 'customer_dashboard.dart';
import 'shopkeeper_dashboard.dart';
import 'admin_dashboard.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Brand Colors
  static const Color primaryNavy = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);

  // Admin credentials
  final String mainAdminUID = "sYf4uOsCnBhbZ6khzF4y21Ii0W13";
  final String mainAdminEmail = "nearbuyadmin@gmail.com";

  // Validation
  static const int _emailMaxLength = 50;
  static const int _passwordMaxLength = 30;
  static final RegExp _emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');

  bool _isValidEmail(String email) => _emailRegex.hasMatch(email);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_animController);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    // Clear any previous focus
    FocusScope.of(context).unfocus();
    
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Validation
    if (email.isEmpty) {
      _showSnack('Please enter your email address.', Colors.red);
      return;
    }
    
    if (password.isEmpty) {
      _showSnack('Please enter your password.', Colors.red);
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnack('Please enter a valid email address (e.g., name@domain.com).', Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters long.', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Show progress
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logging in...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Attempt sign in
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (!mounted) return;

      final user = userCredential.user;
      if (user == null) {
        _showSnack('Login failed. Please try again.', Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      final uid = user.uid;
      
      // Get user data from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        _showSnack('User profile not found. Please contact support.', Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      final savedRole = userDoc['role'] as String? ?? '';

      // Save FCM Token
      try {
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({'fcmToken': fcmToken});
        }
      } catch (e) {
        // Don't fail login if FCM fails
        print('FCM Token update failed: $e');
      }

      // Admin validation
      if (savedRole == 'Admin') {
        if (uid != mainAdminUID || email.toLowerCase() != mainAdminEmail.toLowerCase()) {
          _showSnack('Access Denied! Only main Admin can login.', Colors.red);
          setState(() => _isLoading = false);
          return;
        }
      }

      // Success message
      _showSnack('Welcome back! Login successful 🎉', Colors.green);
      
      // Wait a moment for the user to see the success message
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Navigate based on role
      if (savedRole == 'Customer') {
        _goTo(const CustomerDashboard());
      } else if (savedRole == 'Shopkeeper') {
        _goTo(const ShopkeeperDashboard());
      } else if (savedRole == 'Admin') {
        _goTo(const AdminDashboard());
      } else {
        _showSnack('Unknown user role. Please contact support.', Colors.red);
        setState(() => _isLoading = false);
      }
    } on FirebaseAuthException catch (e) {
      // Detailed error handling
      String errorMessage = _getFirebaseErrorMessage(e);
      _showSnack(errorMessage, Colors.red);
    } catch (e) {
      // Handle any other errors
      _showSnack('An error occurred. Please try again.', Colors.red);
      print('Login error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getFirebaseErrorMessage(FirebaseAuthException e) {
    print('Firebase Auth Error Code: ${e.code}');
    print('Firebase Auth Error Message: ${e.message}');
    
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again or reset your password.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled. Please contact support.';
      case 'requires-recent-login':
        return 'Please log in again to continue.';
      case 'invalid-credential':
        return 'Invalid credentials. Please check your email and password.';
      default:
        return e.message ?? 'Login failed. Please try again.';
    }
  }

  void _goTo(Widget screen) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 36),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryNavy, Color(0xFF1A3A5C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(50),
                bottomRight: Radius.circular(50),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: accentOrange.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo002.jpeg',
                      height: 72,
                      width: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 72,
                          width: 72,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.store, size: 40, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'Near',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: 'Buy',
                        style: TextStyle(color: accentOrange),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Discover shops nearby',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Welcome Back!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0E2A47),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Login to continue',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Email field
                      _buildField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'Enter your email',
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.emailAddress,
                        maxLength: _emailMaxLength,
                      ),
                      const SizedBox(height: 14),
                      // Password field
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscureText,
                        maxLength: _passwordMaxLength,
                        buildCounter: (context,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                            null,
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: Color(0xFF64748B),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () =>
                                setState(() => _obscureText = !_obscureText),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: accentOrange,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      // Forgot password link
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: accentOrange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isLoading ? null : _loginUser,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // Sign up link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RoleSelectionScreen(),
                              ),
                            ),
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                color: accentOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      buildCounter: (context,
              {required currentLength, required isFocused, maxLength}) =>
          null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0xFFFF6A1A),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}