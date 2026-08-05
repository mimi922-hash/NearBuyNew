import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminPaymentDetailsScreen extends StatefulWidget {
  const AdminPaymentDetailsScreen({super.key});

  @override
  State<AdminPaymentDetailsScreen> createState() =>
      _AdminPaymentDetailsScreenState();
}

class _AdminPaymentDetailsScreenState
    extends State<AdminPaymentDetailsScreen> {
  static const Color _navy = Color(0xFF0B1D35);
  static const Color _navyCard = Color(0xFF112240);
  static const Color _accent = Color(0xFFF4511E);
  static const Color _accentOrange = Color(0xFFFF9500);
  static const Color _white = Colors.white;

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Controllers ─────────────────────────────────────────────────
  final _accountHolderController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ibanController = TextEditingController();
  final _jazzcashController = TextEditingController();
  final _easypaisaController = TextEditingController();

  // ── Focus nodes for validation ────────────────────────────────
  final _accountHolderFocus = FocusNode();
  final _bankNameFocus = FocusNode();
  final _accountNumberFocus = FocusNode();
  final _ibanFocus = FocusNode();
  final _jazzcashFocus = FocusNode();
  final _easypaisaFocus = FocusNode();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadPaymentDetails();
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _ibanController.dispose();
    _jazzcashController.dispose();
    _easypaisaController.dispose();
    _accountHolderFocus.dispose();
    _bankNameFocus.dispose();
    _accountNumberFocus.dispose();
    _ibanFocus.dispose();
    _jazzcashFocus.dispose();
    _easypaisaFocus.dispose();
    super.dispose();
  }

  // ── Load existing payment details from Firestore ──────────────
  Future<void> _loadPaymentDetails() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore
          .collection('adminSettings')
          .doc('paymentDetails')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _accountHolderController.text = data['accountHolderName'] ?? '';
          _bankNameController.text = data['bankName'] ?? '';
          _accountNumberController.text = data['accountNumber'] ?? '';
          _ibanController.text = data['iban'] ?? '';
          _jazzcashController.text = data['jazzcashNumber'] ?? '';
          _easypaisaController.text = data['easypaisaNumber'] ?? '';
        });
      }
    } catch (e) {
      _showSnackBar('Error loading payment details: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Save payment details to Firestore ──────────────────────────
  Future<void> _savePaymentDetails() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if at least one payment method is provided
    final hasBankDetails = _accountHolderController.text.trim().isNotEmpty &&
        _bankNameController.text.trim().isNotEmpty &&
        _accountNumberController.text.trim().isNotEmpty;

    final hasJazzcash = _jazzcashController.text.trim().isNotEmpty;
    final hasEasypaisa = _easypaisaController.text.trim().isNotEmpty;

    if (!hasBankDetails && !hasJazzcash && !hasEasypaisa) {
      _showSnackBar(
        'Please provide at least one payment method: Bank Account, JazzCash, or Easypaisa.',
        Colors.orange,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data = {
        'accountHolderName': _accountHolderController.text.trim(),
        'bankName': _bankNameController.text.trim(),
        'accountNumber': _accountNumberController.text.trim(),
        'iban': _ibanController.text.trim().toUpperCase(),
        'jazzcashNumber': _jazzcashController.text.trim(),
        'easypaisaNumber': _easypaisaController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid ?? 'unknown',
      };

      await _firestore
          .collection('adminSettings')
          .doc('paymentDetails')
          .set(data, SetOptions(merge: true));

      _showSnackBar('Payment details saved successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Error saving payment details: $e', Colors.red);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ── Validators ──────────────────────────────────────────────────
  String? _validateAccountHolder(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Account holder name is required';
    }
    if (value.trim().length > 50) {
      return 'Maximum 50 characters allowed';
    }
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value.trim())) {
      return 'Only letters and spaces allowed';
    }
    return null;
  }

  String? _validateBankName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Bank name is required';
    }
    if (value.trim().length > 40) {
      return 'Maximum 40 characters allowed';
    }
    return null;
  }

  String? _validateAccountNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Account number is required';
    }
    if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
      return 'Only digits allowed';
    }
    if (value.trim().length > 24) {
      return 'Maximum 24 digits allowed';
    }
    return null;
  }

  // ── Improved IBAN Validator for Pakistan ──────────────────────
  String? _validateIBAN(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional field
    }
    
    // Remove spaces and convert to uppercase
    String iban = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    
    // Check length (Pakistan IBAN is 24 characters)
    if (iban.length != 24) {
      return 'Pakistan IBAN must be exactly 24 characters';
    }
    
    // Check if starts with 'PK'
    if (!iban.startsWith('PK')) {
      return 'Pakistan IBAN must start with "PK"';
    }
    
    // Check next 2 characters are digits
    String countryCode = iban.substring(0, 2); // PK
    String checkDigits = iban.substring(2, 4); // 2 digits
    if (!RegExp(r'^[0-9]{2}$').hasMatch(checkDigits)) {
      return 'Characters 3-4 must be digits (check digits)';
    }
    
    // Check bank code (4 letters)
    String bankCode = iban.substring(4, 8);
    if (!RegExp(r'^[A-Z]{4}$').hasMatch(bankCode)) {
      return 'Characters 5-8 must be 4 letters (bank code)';
    }
    
    // Check remaining characters (16 alphanumeric)
    String remaining = iban.substring(8);
    if (!RegExp(r'^[A-Z0-9]{16}$').hasMatch(remaining)) {
      return 'Remaining 16 characters must be letters or numbers';
    }
    
    return null;
  }

  // ── Mobile number validator with formatted input support ──────
  String? _validateMobileNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional field
    }
    
    // Remove spaces, dashes, and special characters
    String number = value.trim().replaceAll(RegExp(r'[\s\-]'), '');
    
    // Check if only digits
    if (!RegExp(r'^\d+$').hasMatch(number)) {
      return 'Only digits, spaces, and dashes allowed';
    }
    
    // Must be 11 digits
    if (number.length != 11) {
      return 'Must be exactly 11 digits (e.g., 03XX-XXXXXXX)';
    }
    
    // Must start with '03'
    if (!number.startsWith('03')) {
      return 'Must start with 03';
    }
    
    return null;
  }

  // ── Formatted display for mobile numbers ──────────────────────
  String _formatMobileNumber(String number) {
    if (number.length == 11) {
      return '${number.substring(0, 4)}-${number.substring(4)}';
    }
    return number;
  }

  // ── UI Helpers ──────────────────────────────────────────────────
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: _white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    int maxLength = 50,
    bool isRequired = true,
    bool autoCapitalize = false,
    bool formatMobile = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(color: _white, fontSize: 14),
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        maxLength: maxLength,
        textCapitalization: autoCapitalize
            ? TextCapitalization.words
            : TextCapitalization.none,
        onFieldSubmitted: (_) {
          if (textInputAction == TextInputAction.next) {
            FocusScope.of(context).nextFocus();
          }
        },
        onChanged: (value) {
          // Format mobile numbers as user types
          if (formatMobile && value.isNotEmpty) {
            String cleaned = value.replaceAll(RegExp(r'[\s\-]'), '');
            if (cleaned.length >= 4) {
              String formatted = '${cleaned.substring(0, 4)}-${cleaned.substring(4)}';
              if (controller.text != formatted) {
                controller.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
            }
          }
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: _white.withOpacity(0.6),
            fontSize: 13,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: _white.withOpacity(0.3),
            fontSize: 13,
          ),
          prefixIcon: Icon(icon, color: _accent, size: 20),
          filled: true,
          fillColor: _navyCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _white.withOpacity(0.1),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: _accent,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.redAccent,
              width: 2,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.redAccent,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          counterStyle: TextStyle(
            color: _white.withOpacity(0.3),
            fontSize: 11,
          ),
          errorStyle: const TextStyle(
            color: Colors.redAccent,
            fontSize: 12,
          ),
        ),
        validator: validator,
      ),
    );
  }

  // ── Build IBAN format helper text ─────────────────────────────
  Widget _buildIbanHelper() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _navyCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _accent.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: _accentOrange,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Pakistan IBAN Format (24 characters)',
                style: TextStyle(
                  color: _white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'PK 12 HABB 1234567890123456',
            style: TextStyle(
              color: _white.withOpacity(0.7),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• Starts with PK\n• 2 check digits\n• 4 letter bank code\n• 16 alphanumeric characters',
            style: TextStyle(
              color: _white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Payment Account Details',
          style: TextStyle(
            color: _white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2.5,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 3,
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Info banner ────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _navyCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _accentOrange.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: _accentOrange,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'These payment details will be shown to shopkeepers when they need to pay the platform fee.',
                                style: TextStyle(
                                  color: _white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Bank Account Section ────────────────────
                      _buildSectionHeader(
                          'Bank Account Details', Icons.account_balance),

                      _buildTextField(
                        controller: _accountHolderController,
                        focusNode: _accountHolderFocus,
                        label: 'Account Holder Name',
                        hint: 'e.g., Muhammad Ali',
                        icon: Icons.person_outline,
                        validator: _validateAccountHolder,
                        autoCapitalize: true,
                      ),

                      _buildTextField(
                        controller: _bankNameController,
                        focusNode: _bankNameFocus,
                        label: 'Bank Name',
                        hint: 'e.g., HBL, UBL, MCB',
                        icon: Icons.business_outlined,
                        validator: _validateBankName,
                      ),

                      _buildTextField(
                        controller: _accountNumberController,
                        focusNode: _accountNumberFocus,
                        label: 'Account Number',
                        hint: 'e.g., 1234567890123456',
                        icon: Icons.numbers_outlined,
                        validator: _validateAccountNumber,
                        keyboardType: TextInputType.number,
                        maxLength: 24,
                      ),

                      // ── IBAN Field with format helper ──────────
                      _buildTextField(
                        controller: _ibanController,
                        focusNode: _ibanFocus,
                        label: 'IBAN (Optional)',
                        hint: 'e.g., PK12HABB1234567890123456',
                        icon: Icons.code_outlined,
                        validator: _validateIBAN,
                        keyboardType: TextInputType.text,
                        maxLength: 24,
                      ),
                      
                      _buildIbanHelper(),

                      const SizedBox(height: 20),

                      // ── Mobile Money Section ─────────────────────
                      _buildSectionHeader(
                          'Mobile Money Details', Icons.phone_android),

                      _buildTextField(
                        controller: _jazzcashController,
                        focusNode: _jazzcashFocus,
                        label: 'JazzCash Number (Optional)',
                        hint: 'e.g., 0312-3456789',
                        icon: Icons.phone_android_outlined,
                        validator: _validateMobileNumber,
                        keyboardType: TextInputType.phone,
                        maxLength: 12, // 11 digits + 1 dash
                        formatMobile: true,
                      ),

                      _buildTextField(
                        controller: _easypaisaController,
                        focusNode: _easypaisaFocus,
                        label: 'Easypaisa Number (Optional)',
                        hint: 'e.g., 0312-3456789',
                        icon: Icons.phone_iphone_outlined,
                        validator: _validateMobileNumber,
                        keyboardType: TextInputType.phone,
                        maxLength: 12, // 11 digits + 1 dash
                        formatMobile: true,
                      ),

                      const SizedBox(height: 24),

                      // ── Save Button ─────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _savePaymentDetails,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Save Payment Details',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Clear All Button ─────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      backgroundColor: _navyCard,
                                      title: const Text(
                                        'Clear All Details?',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: const Text(
                                        'This will remove all payment details. Shopkeepers will not see any payment method.',
                                        style: TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text(
                                            'Cancel',
                                            style:
                                                TextStyle(color: Colors.grey),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            setState(() {
                                              _accountHolderController
                                                  .clear();
                                              _bankNameController.clear();
                                              _accountNumberController
                                                  .clear();
                                              _ibanController.clear();
                                              _jazzcashController.clear();
                                              _easypaisaController.clear();
                                            });
                                            // Also clear from Firestore
                                            try {
                                              await _firestore
                                                  .collection('adminSettings')
                                                  .doc('paymentDetails')
                                                  .update({
                                                'accountHolderName': '',
                                                'bankName': '',
                                                'accountNumber': '',
                                                'iban': '',
                                                'jazzcashNumber': '',
                                                'easypaisaNumber': '',
                                                'updatedAt':
                                                    FieldValue.serverTimestamp(),
                                              });
                                              _showSnackBar(
                                                'All payment details cleared!',
                                                Colors.orange,
                                              );
                                            } catch (e) {
                                              _showSnackBar(
                                                'Error clearing details: $e',
                                                Colors.red,
                                              );
                                            }
                                          },
                                          child: const Text(
                                            'Clear All',
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.redAccent.withOpacity(0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Clear All Details',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Last Updated Info ────────────────────────
                      StreamBuilder<DocumentSnapshot>(
                        stream: _firestore
                            .collection('adminSettings')
                            .doc('paymentDetails')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return const SizedBox.shrink();
                          }
                          final data = snapshot.data!.data()
                              as Map<String, dynamic>?;
                          if (data == null) return const SizedBox.shrink();

                          final updatedAt = data['updatedAt'];
                          if (updatedAt == null) return const SizedBox.shrink();

                          final date = (updatedAt as Timestamp).toDate();
                          final timeStr =
                              '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _navyCard,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.update_outlined,
                                  color: _white.withOpacity(0.4),
                                  size: 14,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Last updated: $timeStr',
                                  style: TextStyle(
                                    color: _white.withOpacity(0.4),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}