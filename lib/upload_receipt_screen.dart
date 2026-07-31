import 'dart:io';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:image_picker/image_picker.dart';

import 'package:intl/intl.dart';

import 'package:http/http.dart' as http;

class UploadReceiptScreen extends StatefulWidget {

  final String shopId;

  final int fee;

  /// Option C: Agar pehle se ek billing cycle exist kare (rejected)

  /// toh us cycle ko update karte hain, naya nahi banate

  final String? existingBillingCycleId;

  const UploadReceiptScreen({

    super.key,

    required this.shopId,

    required this.fee,

    this.existingBillingCycleId,

  });

  @override

  State<UploadReceiptScreen> createState() => _UploadReceiptScreenState();

}

class _UploadReceiptScreenState extends State<UploadReceiptScreen> {

  static const Color kOrange = Color(0xFFFF6B00);

  static const Color kNavy = Color(0xFF0D1B3E);

  // ═══════════════════════════════════════════════════════════════

  //  🔧 CLOUDINARY CONFIG — SIRF YEH 2 VALUES APNI FILL KAREIN

  //

  //  Kahan milega?

  //  1. cloudinary.com pe login karein

  //  2. Dashboard > Settings > Upload > Upload Presets

  //  3. Ek "unsigned" preset banayein (ya existing use karein)

  //  4. Cloud name dashboard ke upar left corner mein hota hai

  // ═══════════════════════════════════════════════════════════════

  static const String _cloudinaryCloudName = 'dxzaqavfj';     // <-- Yahan apna cloud name

  static const String _cloudinaryUploadPreset = 'nearbuy_preset'; // <-- Yahan apna unsigned preset

  // ═══════════════════════════════════════════════════════════════

  final _txnCtrl = TextEditingController();

  final _noteCtrl = TextEditingController();

  String _selectedMethod = 'JazzCash';

  File? _receiptImage;

  bool _uploading = false;

  String? _validationMsg;

  double _uploadProgress = 0;

  final _methods = ['JazzCash', 'Easypaisa', 'Bank Transfer'];

  // ─── IMAGE PICKER ──────────────────────────────────────────────

  Future<void> _pickImage() async {

    final picked = await ImagePicker()

        .pickImage(source: ImageSource.gallery, imageQuality: 85);

    if (picked != null) {

      setState(() {

        _receiptImage = File(picked.path);

        _validationMsg = null;

      });

    }

  }

  Future<void> _pickFromCamera() async {

    final picked = await ImagePicker()

        .pickImage(source: ImageSource.camera, imageQuality: 85);

    if (picked != null) {

      setState(() {

        _receiptImage = File(picked.path);

        _validationMsg = null;

      });

    }

  }

  // ─── CLOUDINARY UPLOAD ─────────────────────────────────────────

  // Firebase Storage bilkul use nahi hota yahan

  // Sirf Cloudinary REST API se image upload hoti hai

  // Returns: secure_url string ya null on failure

  Future<String?> _uploadToCloudinary(File imageFile) async {

    try {

      // Validation: config values check karo

      if (_cloudinaryCloudName == 'YOUR_CLOUD_NAME' ||

          _cloudinaryUploadPreset == 'YOUR_UPLOAD_PRESET') {

        debugPrint(

            '❌ Cloudinary config missing! _cloudinaryCloudName aur _cloudinaryUploadPreset set karein.');

        return null;

      }

      final uri = Uri.parse(

        'https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/image/upload',

      );

      final request = http.MultipartRequest('POST', uri)

        ..fields['upload_preset'] = _cloudinaryUploadPreset

        ..fields['folder'] = 'nearshop_receipts'

        ..files.add(

          await http.MultipartFile.fromPath('file', imageFile.path),

        );

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final url = data['secure_url'] as String?;

        debugPrint('✅ Cloudinary upload success: $url');

        return url;

      } else {

        final error = jsonDecode(response.body);

        debugPrint('❌ Cloudinary error (${response.statusCode}): $error');

        return null;

      }

    } catch (e) {

      debugPrint('❌ Cloudinary upload exception: $e');

      return null;

    }

  }

  // ─── SUBMIT ────────────────────────────────────────────────────

  Future<void> _submit() async {

    // --- Validation ---

    if (_txnCtrl.text.trim().isEmpty) {

      setState(() => _validationMsg = 'Please enter Transaction ID');

      return;

    }

    if (_receiptImage == null) {

      setState(() => _validationMsg = 'Please upload receipt image');

      return;

    }

    if (widget.shopId.isEmpty) {

      setState(() =>

          _validationMsg = 'Shop ID missing. Please go back and try again.');

      return;

    }

    if (widget.fee == 0) {

      setState(() => _validationMsg = 'No pending fee.');

      return;

    }

    setState(() {

      _uploading = true;

      _uploadProgress = 0;

      _validationMsg = null;

    });

    try {

      final now = DateTime.now();

      final firestore = FirebaseFirestore.instance;

      // ── STEP 1: Saare unpaid orders fetch karo ─────────────────

      setState(() => _uploadProgress = 0.1);

      final allOrdersSnap = await firestore

          .collection('orders')

          .where('shopId', isEqualTo: widget.shopId)

          .get();

      final unpaidOrders = allOrdersSnap.docs.where((doc) {

        final data = doc.data();

        final isDelivered = (data['status'] ?? '') == 'delivered';

        return isDelivered &&

            (!data.containsKey('billingCycleId') ||

            data['billingCycleId'] == null);

      }).toList();

      if (unpaidOrders.isEmpty) {

        setState(() {

          _validationMsg =

              'No unpaid orders found. Nothing to submit.';

          _uploading = false;

          _uploadProgress = 0;

        });

        return;

      }

      final orderIds = unpaidOrders.map((doc) => doc.id).toList();

      // ── STEP 2: Cloudinary pe image upload ─────────────────────

      setState(() => _uploadProgress = 0.3);

      final receiptUrl = await _uploadToCloudinary(_receiptImage!);

      if (receiptUrl == null) {

        setState(() {

          _validationMsg =

              'Image upload failed.\n\nPlease check:\n• Is your internet connection working?\n• Is Cloudinary config set correctly?\n(Cloud name and upload preset)';

          _uploading = false;

          _uploadProgress = 0;

        });

        return;

      }

      setState(() => _uploadProgress = 0.6);

      // ── STEP 3: Billing Cycle document banao / update karo ──────

      String billingCycleId;

      if (widget.existingBillingCycleId != null) {

        // Rejected cycle ko update karo

        billingCycleId = widget.existingBillingCycleId!;

        await firestore

            .collection('billing')

            .doc(billingCycleId)

            .update({

          'receipt_url': receiptUrl,

          'payment_status': 'pending_verification',

          'submitted_at': FieldValue.serverTimestamp(),

          'transaction_id': _txnCtrl.text.trim(),

          'payment_method': _selectedMethod,

          'note': _noteCtrl.text.trim(),

          'total_platform_fee': widget.fee,

          'month_label': DateFormat('MMMM yyyy').format(now),

          'month': now.month,

          'year': now.year,

          'order_count': unpaidOrders.length,

          'orderIds': orderIds,

          'rejection_reason': FieldValue.delete(),

          // NEW: Grace period cancel karo — reupload ho gayi

          'grace_period_active': false,

          'due_time': null,

        });

        // Shop warning bhi clear karo

        await firestore

            .collection('shops')

            .doc(widget.shopId)

            .update({

          'warningActive': false,

        });

      } else {

        // Naya billing cycle banao

        final newDoc = await firestore.collection('billing').add({

          'shopId': widget.shopId,

          'month': now.month,

          'year': now.year,

          'month_label': DateFormat('MMMM yyyy').format(now),

          'total_platform_fee': widget.fee,

          'receipt_url': receiptUrl,

          'payment_status': 'pending_verification',

          'submitted_at': FieldValue.serverTimestamp(),

          'transaction_id': _txnCtrl.text.trim(),

          'payment_method': _selectedMethod,

          'note': _noteCtrl.text.trim(),

          'order_count': unpaidOrders.length,

          'orderIds': orderIds,

        });

        billingCycleId = newDoc.id;

      }

      setState(() => _uploadProgress = 0.8);

      // ── STEP 4: Orders lock karo (batch update) ─────────────────

      final batch = firestore.batch();

      for (final orderDoc in unpaidOrders) {

        batch.update(orderDoc.reference, {

          'billingCycleId': billingCycleId,

          'billingStatus': 'pending_verification',

        });

      }

      await batch.commit();

      // ── STEP 5: Admin notification ──────────────────────────────

      await firestore.collection('admin_notifications').add({

        'shopId': widget.shopId,

        'billingCycleId': billingCycleId,

        'type': 'billing_receipt',

        'message':

            'New $_selectedMethod receipt submitted. Fee: Rs. ${widget.fee} — batch of ${unpaidOrders.length} orders.',

        'fee': widget.fee,

        'order_count': unpaidOrders.length,

        'orderIds': orderIds,

        'month_label': DateFormat('MMMM yyyy').format(now),

        'read': false,

        'createdAt': FieldValue.serverTimestamp(),

      });

      setState(() => _uploadProgress = 1.0);

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(

          content: Text('Receipt submitted successfully!'),

          backgroundColor: Colors.green,

        ));

        Navigator.pop(context);

      }

    } catch (e) {

      setState(() {

        _validationMsg = 'Error: ${e.toString()}';

        _uploading = false;

        _uploadProgress = 0;

      });

    }

  }

  // ─── BUILD ─────────────────────────────────────────────────────

  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(

        backgroundColor: kNavy,

        elevation: 0,

        leading: IconButton(

            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),

            onPressed: _uploading ? null : () => Navigator.pop(context)),

        title: const Text('Upload Receipt',

            style: TextStyle(

                color: Colors.white,

                fontWeight: FontWeight.bold,

                fontSize: 18)),

        centerTitle: true,

      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(16),

        child: Column(

          children: [

            _buildAmountCard(),

            const SizedBox(height: 16),

            _buildInfoBox(),

            const SizedBox(height: 16),

            _buildFormCard(),

            const SizedBox(height: 16),

            _buildReceiptUpload(),

            const SizedBox(height: 16),

            // ── Upload progress bar ──

            if (_uploading) ...[

              ClipRRect(

                borderRadius: BorderRadius.circular(8),

                child: LinearProgressIndicator(

                  value: _uploadProgress > 0 ? _uploadProgress : null,

                  backgroundColor: Colors.orange.shade100,

                  valueColor: const AlwaysStoppedAnimation<Color>(kOrange),

                  minHeight: 6,

                ),

              ),

              const SizedBox(height: 8),

              Text(

                _uploadProgress < 0.3

                    ? 'Checking orders...'

                    : _uploadProgress < 0.6

                        ? 'Uploading receipt to Cloudinary...'

                        : _uploadProgress < 0.9

                            ? 'Saving billing cycle...'

                            : 'Almost done...',

                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),

                textAlign: TextAlign.center,

              ),

              const SizedBox(height: 12),

            ],

            // ── Error / validation message ──

            if (_validationMsg != null)

              Container(

                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(

                  color: Colors.red.shade50,

                  borderRadius: BorderRadius.circular(10),

                  border: Border.all(color: Colors.red.shade200),

                ),

                child: Row(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Icon(Icons.error_outline,

                        color: Colors.red.shade600, size: 18),

                    const SizedBox(width: 8),

                    Expanded(

                        child: Text(_validationMsg!,

                            style: TextStyle(

                                color: Colors.red.shade700, fontSize: 13))),

                  ],

                ),

              ),

            const SizedBox(height: 20),

            // ── Submit button ──

            SizedBox(

              width: double.infinity,

              height: 54,

              child: ElevatedButton(

                onPressed: _uploading ? null : _submit,

                style: ElevatedButton.styleFrom(

                  backgroundColor: kOrange,

                  disabledBackgroundColor: Colors.orange.shade200,

                  shape: RoundedRectangleBorder(

                      borderRadius: BorderRadius.circular(14)),

                  elevation: 4,

                ),

                child: _uploading

                    ? const Row(

                        mainAxisAlignment: MainAxisAlignment.center,

                        children: [

                          SizedBox(

                            width: 20,

                            height: 20,

                            child: CircularProgressIndicator(

                                color: Colors.white, strokeWidth: 2),

                          ),

                          SizedBox(width: 12),

                          Text('Uploading...',

                              style: TextStyle(

                                  color: Colors.white,

                                  fontSize: 15,

                                  fontWeight: FontWeight.bold)),

                        ],

                      )

                    : const Text('Submit for Verification',

                        style: TextStyle(

                            color: Colors.white,

                            fontSize: 16,

                            fontWeight: FontWeight.bold)),

              ),

            ),

            const SizedBox(height: 30),

          ],

        ),

      ),

    );

  }

  // ─── WIDGETS ───────────────────────────────────────────────────

  Widget _buildAmountCard() {

    return Container(

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(

        gradient: const LinearGradient(

          colors: [Color(0xFFFF6B00), Color(0xFFFF8C42)],

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

        ),

        borderRadius: BorderRadius.circular(16),

        boxShadow: [

          BoxShadow(

              color: kOrange.withOpacity(0.3),

              blurRadius: 12,

              offset: const Offset(0, 4))

        ],

      ),

      child: Row(

        children: [

          const Icon(Icons.account_balance_wallet,

              color: Colors.white, size: 36),

          const SizedBox(width: 16),

          Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Text('Total Payable Amount',

                  style: TextStyle(color: Colors.white70, fontSize: 13)),

              Text('Rs. ${widget.fee}',

                  style: const TextStyle(

                      color: Colors.white,

                      fontSize: 28,

                      fontWeight: FontWeight.bold)),

              const Text('All unpaid orders will be covered',

                  style: TextStyle(color: Colors.white70, fontSize: 11)),

            ],

          ),

        ],

      ),

    );

  }

  Widget _buildInfoBox() {

    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: Colors.blue.shade50,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: Colors.blue.shade200),

      ),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),

          const SizedBox(width: 10),

          Expanded(

            child: Text(

              'Pay exactly Rs. ${widget.fee}. The receipt must be clear and readable. The amount must match exactly.',

              style: TextStyle(color: Colors.blue.shade800, fontSize: 13),

            ),

          ),

        ],

      ),

    );

  }

  Widget _buildFormCard() {

    return Container(

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        boxShadow: [

          BoxShadow(

              color: Colors.black.withOpacity(0.06),

              blurRadius: 10,

              offset: const Offset(0, 3))

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          const Text('Payment Details',

              style: TextStyle(

                  fontSize: 15,

                  fontWeight: FontWeight.bold,

                  color: Color(0xFF0D1B3E))),

          const SizedBox(height: 16),

          _buildTextField(

            controller: _txnCtrl,

            label: 'Transaction ID',

            hint: 'Enter Transaction ID',

            icon: Icons.confirmation_number_outlined,

          ),

          const SizedBox(height: 14),

          DropdownButtonFormField<String>(

            value: _selectedMethod,

            decoration: InputDecoration(

              labelText: 'Payment Method',

              prefixIcon: const Icon(Icons.payment, color: kOrange),

              border: OutlineInputBorder(

                  borderRadius: BorderRadius.circular(12),

                  borderSide: BorderSide(color: Colors.grey.shade300)),

              enabledBorder: OutlineInputBorder(

                  borderRadius: BorderRadius.circular(12),

                  borderSide: BorderSide(color: Colors.grey.shade300)),

              focusedBorder: OutlineInputBorder(

                  borderRadius: BorderRadius.circular(12),

                  borderSide:

                      const BorderSide(color: kOrange, width: 1.5)),

              filled: true,

              fillColor: const Color(0xFFF8F9FA),

            ),

            items:

                _methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),

            onChanged: (v) => setState(() => _selectedMethod = v!),

          ),

          const SizedBox(height: 14),

          _buildTextField(

            controller: _noteCtrl,

            label: 'Note (Optional)',

            hint: 'Any additional info...',

            icon: Icons.note_outlined,

            maxLines: 2,

          ),

        ],

      ),

    );

  }

  Widget _buildTextField({

    required TextEditingController controller,

    required String label,

    required String hint,

    required IconData icon,

    int maxLines = 1,

  }) {

    return TextField(

      controller: controller,

      maxLines: maxLines,

      decoration: InputDecoration(

        labelText: label,

        hintText: hint,

        prefixIcon: Icon(icon, color: kOrange),

        border: OutlineInputBorder(

            borderRadius: BorderRadius.circular(12),

            borderSide: BorderSide(color: Colors.grey.shade300)),

        enabledBorder: OutlineInputBorder(

            borderRadius: BorderRadius.circular(12),

            borderSide: BorderSide(color: Colors.grey.shade300)),

        focusedBorder: OutlineInputBorder(

            borderRadius: BorderRadius.circular(12),

            borderSide: const BorderSide(color: kOrange, width: 1.5)),

        filled: true,

        fillColor: const Color(0xFFF8F9FA),

      ),

    );

  }

  Widget _buildReceiptUpload() {

    return Container(

      width: double.infinity,

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        boxShadow: [

          BoxShadow(

              color: Colors.black.withOpacity(0.06),

              blurRadius: 10,

              offset: const Offset(0, 3))

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          // Header

          Padding(

            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),

            child: Row(

              children: [

                const Icon(Icons.receipt_long, color: kOrange, size: 20),

                const SizedBox(width: 8),

                const Text('Payment Receipt',

                    style: TextStyle(

                        fontSize: 15,

                        fontWeight: FontWeight.bold,

                        color: Color(0xFF0D1B3E))),

                const Spacer(),

                if (_receiptImage != null)

                  GestureDetector(

                    onTap: () => setState(() => _receiptImage = null),

                    child: Container(

                      padding: const EdgeInsets.symmetric(

                          horizontal: 10, vertical: 4),

                      decoration: BoxDecoration(

                        color: Colors.red.shade50,

                        borderRadius: BorderRadius.circular(8),

                        border: Border.all(color: Colors.red.shade200),

                      ),

                      child: Text('Remove',

                          style: TextStyle(

                              color: Colors.red.shade600,

                              fontSize: 12,

                              fontWeight: FontWeight.w600)),

                    ),

                  ),

              ],

            ),

          ),

          // Image preview ya pick buttons

          if (_receiptImage != null)

            Padding(

              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

              child: ClipRRect(

                borderRadius: BorderRadius.circular(12),

                child: Stack(

                  children: [

                    Image.file(

                      _receiptImage!,

                      width: double.infinity,

                      height: 220,

                      fit: BoxFit.cover,

                    ),

                    Positioned(

                      bottom: 0,

                      left: 0,

                      right: 0,

                      child: Container(

                        padding: const EdgeInsets.symmetric(

                            vertical: 8, horizontal: 12),

                        decoration: BoxDecoration(

                          gradient: LinearGradient(

                            colors: [

                              Colors.black.withOpacity(0.7),

                              Colors.transparent

                            ],

                            begin: Alignment.bottomCenter,

                            end: Alignment.topCenter,

                          ),

                        ),

                        child: Row(

                          children: [

                            const Icon(Icons.check_circle,

                                color: Colors.green, size: 16),

                            const SizedBox(width: 6),

                            const Text('Receipt selected',

                                style: TextStyle(

                                    color: Colors.white,

                                    fontSize: 12,

                                    fontWeight: FontWeight.w600)),

                            const Spacer(),

                            GestureDetector(

                              onTap: _pickImage,

                              child: Container(

                                padding: const EdgeInsets.symmetric(

                                    horizontal: 8, vertical: 4),

                                decoration: BoxDecoration(

                                  color: kOrange,

                                  borderRadius: BorderRadius.circular(6),

                                ),

                                child: const Text('Change',

                                    style: TextStyle(

                                        color: Colors.white,

                                        fontSize: 11,

                                        fontWeight: FontWeight.w600)),

                              ),

                            ),

                          ],

                        ),

                      ),

                    ),

                  ],

                ),

              ),

            )

          else

            Padding(

              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

              child: Row(

                children: [

                  // Gallery

                  Expanded(

                    child: GestureDetector(

                      onTap: _pickImage,

                      child: Container(

                        height: 100,

                        decoration: BoxDecoration(

                          color: kOrange.withOpacity(0.05),

                          borderRadius: BorderRadius.circular(12),

                          border: Border.all(

                              color: kOrange.withOpacity(0.3), width: 1.5),

                        ),

                        child: Column(

                          mainAxisAlignment: MainAxisAlignment.center,

                          children: [

                            Icon(Icons.photo_library_outlined,

                                color: kOrange, size: 28),

                            const SizedBox(height: 8),

                            const Text('Gallery',

                                style: TextStyle(

                                    fontSize: 13,

                                    fontWeight: FontWeight.w600,

                                    color: kOrange)),

                          ],

                        ),

                      ),

                    ),

                  ),

                  const SizedBox(width: 12),

                  // Camera

                  Expanded(

                    child: GestureDetector(

                      onTap: _pickFromCamera,

                      child: Container(

                        height: 100,

                        decoration: BoxDecoration(

                          color: kNavy.withOpacity(0.05),

                          borderRadius: BorderRadius.circular(12),

                          border: Border.all(

                              color: kNavy.withOpacity(0.3), width: 1.5),

                        ),

                        child: Column(

                          mainAxisAlignment: MainAxisAlignment.center,

                          children: [

                            Icon(Icons.camera_alt_outlined,

                                color: kNavy, size: 28),

                            const SizedBox(height: 8),

                            const Text('Camera',

                                style: TextStyle(

                                    fontSize: 13,

                                    fontWeight: FontWeight.w600,

                                    color: kNavy)),

                          ],

                        ),

                      ),

                    ),

                  ),

                ],

              ),

            ),

        ],

      ),

    );

  }

  @override

  void dispose() {

    _txnCtrl.dispose();

    _noteCtrl.dispose();

    super.dispose();

  }

}