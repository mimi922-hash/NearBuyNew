import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
 
class SignupScreen extends StatefulWidget {
  final String role;
  const SignupScreen({super.key, required this.role});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}
 
class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _nameController            = TextEditingController();
  final _emailController           = TextEditingController();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController(); // ✅ NEW
  bool _obscureText    = true;
  bool _obscureConfirm = true;  // ✅ NEW
  bool _isLoading      = false;
  String _passwordStrength = "";
  late AnimationController _animController;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;
 
  // ── Brand Colors ──
  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);

  // ✅ NEW — validation constants & helpers (added, nothing existing removed)
  static const int _nameMaxLength     = 50;
  static const int _emailMaxLength    = 50;
  static const int _passwordMaxLength = 30;
  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
  static final RegExp _nameRegex = RegExp(r'^[a-zA-Z\s]{3,50}$');

  bool _isValidEmail(String email) => _emailRegex.hasMatch(email);
  bool _isValidName(String name)   => _nameRegex.hasMatch(name);
 
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650),
    );
    _fadeAnim  = Tween<double>(begin: 0, end: 1).animate(_animController);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }
 
  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
 
  // ✅ Password strength — unchanged logic
  void _checkPasswordStrength(String password) {
    if (password.isEmpty) { setState(() => _passwordStrength = ""); return; }
    String message;
    if (password.length < 6)                         { message = "Too short – at least 6 characters required."; }
    else if (!RegExp(r'[A-Z]').hasMatch(password))   { message = "Add at least one UPPERCASE letter."; }
    else if (!RegExp(r'[a-z]').hasMatch(password))   { message = "Add at least one lowercase letter."; }
    else if (!RegExp(r'[0-9]').hasMatch(password))   { message = "Add at least one number."; }
    else if (!RegExp(r'[!@#\$&*~]').hasMatch(password)) { message = "Add a special character (! @ # \$ & * ~)."; }
    else                                              { message = "Strong Password 💪"; }
    setState(() => _passwordStrength = message);
  }
 
  // ✅ SIGNUP LOGIC — unchanged + confirm password check
  // ✅ Only addition: proper name-format and email-format validation before
  // the existing Firebase create-account flow runs. No existing logic altered.
  Future<void> _signup() async {
    if (widget.role.toLowerCase() == "admin") {
      _showSnack("Admin accounts cannot be created.", Colors.red); return;
    }
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack("Please fill all fields.", Colors.red); return;
    }
    // ✅ NEW — proper name validation (letters/spaces, min 3 / max 50 chars)
    if (!_isValidName(_nameController.text.trim())) {
      _showSnack("Please enter a valid name (letters only, 3-50 characters).", Colors.red);
      return;
    }
    // ✅ NEW — proper email format validation
    if (!_isValidEmail(_emailController.text.trim())) {
      _showSnack("Please enter a valid email address.", Colors.red);
      return;
    }
    // ✅ Confirm password check
    if (_passwordController.text.trim() != _confirmPasswordController.text.trim()) {
      _showSnack("Passwords do not match!", Colors.red); return;
    }
    if (_passwordStrength != "Strong Password 💪") {
      _showSnack("Please use a stronger password!", Colors.red); return;
    }
    setState(() => _isLoading = true);
    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
      final uid = userCredential.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': widget.role,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // ✅ FIX 1: proper message instead of literal "${widget.role}" text
      _showSnack("Your account is created! Please login.", Colors.green);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? "Signup failed", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }
 
  Color get _roleColor =>
      widget.role == 'Customer' ? accentOrange : primaryNavy;
  IconData get _roleIcon =>
      widget.role == 'Customer' ? Icons.person_rounded : Icons.storefront_rounded;
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // ── Header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 55, bottom: 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryNavy, const Color(0xFF1A3A5C)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(50),
                bottomRight: Radius.circular(50),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.5), width: 2),
                  ),
                  child: Icon(_roleIcon, size: 46, color: Colors.white),
                ),
                const SizedBox(height: 14),
                Text('Sign Up',
                    style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold,
                      color: Colors.white, letterSpacing: 0.5,
                    )),
                const SizedBox(height: 4),
                const Text('Create your NearBuy account',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          // ── Form ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 16, offset: const Offset(0, 4),
                          )],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildField(controller: _nameController,
                                hint: 'Full Name', icon: Icons.person_outline,
                                maxLength: _nameMaxLength), // ✅ NEW — length limit
                            const SizedBox(height: 14),
                            _buildField(controller: _emailController,
                                hint: 'Enter Email',
                                icon: Icons.person_outline,
                                keyboardType: TextInputType.emailAddress,
                                maxLength: _emailMaxLength), // ✅ NEW — length limit
                            const SizedBox(height: 14),
                            // Password
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscureText,
                              onChanged: _checkPasswordStrength,
                              maxLength: _passwordMaxLength, // ✅ NEW — length limit
                              buildCounter: (context,
                                      {required currentLength,
                                      required isFocused,
                                      maxLength}) =>
                                  null, // ✅ NEW — hides default counter text
                              decoration: _inputDec(
                                hint: 'Password', icon: Icons.lock_outline,
                                suffix: IconButton(
                                  // ✅ FIX 2: open eye = text visible, closed eye = text hidden
                                  icon: Icon(_obscureText
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                      color: Colors.grey),
                                  onPressed: () => setState(() => _obscureText = !_obscureText),
                                ),
                              ),
                            ),
                            if (_passwordStrength.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(children: [
                                Icon(
                                  _passwordStrength.contains('Strong')
                                      ? Icons.check_circle : Icons.info_outline,
                                  size: 15,
                                  color: _passwordStrength.contains('Strong')
                                      ? Colors.green : Colors.red.shade400,
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: Text(_passwordStrength,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _passwordStrength.contains('Strong')
                                          ? Colors.green : Colors.red.shade400,
                                      fontWeight: FontWeight.w500,
                                    ))),
                              ]),
                            ],
                            const SizedBox(height: 14),
                            // ✅ Confirm Password
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              onChanged: (_) => setState(() {}),
                              maxLength: _passwordMaxLength, // ✅ NEW — length limit
                              buildCounter: (context,
                                      {required currentLength,
                                      required isFocused,
                                      maxLength}) =>
                                  null, // ✅ NEW — hides default counter text
                              decoration: _inputDec(
                                hint: 'Confirm Password', icon: Icons.lock_reset_outlined,
                                suffix: IconButton(
                                  // ✅ FIX 2: open eye = text visible, closed eye = text hidden
                                  icon: Icon(_obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                      color: Colors.grey),
                                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                ),
                              ),
                            ),
                            // ✅ Live match indicator
                            if (_confirmPasswordController.text.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Builder(builder: (_) {
                                final match = _passwordController.text ==
                                    _confirmPasswordController.text;
                                return Row(children: [
                                  Icon(
                                    match ? Icons.check_circle : Icons.cancel_outlined,
                                    size: 15,
                                    color: match ? Colors.green : Colors.red.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    match ? 'Passwords match ✓' : 'Passwords do not match',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: match ? Colors.green : Colors.red.shade400,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ]);
                              }),
                            ],
                            const SizedBox(height: 22),
                            // ✅ Orange button
                            SizedBox(
                              width: double.infinity, height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentOrange,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _isLoading ? null : _signup,
                                child: _isLoading
                                    ? const SizedBox(width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2.5))
                                    : const Text('Create Account',
                                        style: TextStyle(
                                          fontSize: 17, fontWeight: FontWeight.bold,
                                        )),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account? ',
                              style: TextStyle(color: Colors.black54, fontSize: 14)),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text('Login',
                                style: TextStyle(
                                  color: Color(0xFFFF6A1A),
                                  fontWeight: FontWeight.bold, fontSize: 14,
                                )),
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
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength, // ✅ NEW — optional length limit param
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      maxLength: maxLength, // ✅ NEW
      buildCounter: (context,
              {required currentLength, required isFocused, maxLength}) =>
          null, // ✅ NEW — hides default counter text
      decoration: _inputDec(hint: hint, icon: icon),
    );
  }
 
  InputDecoration _inputDec({
    required String hint, required IconData icon, Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
      suffixIcon: suffix,
      filled: true, fillColor: const Color(0xFFF8FAFC),
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
        borderSide: const BorderSide(color: Color(0xFFFF6A1A), width: 1.5),
      ),
    );
  }
}