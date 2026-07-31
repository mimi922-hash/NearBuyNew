import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'upload_receipt_screen.dart';

class SuspendedShopScreen extends StatefulWidget {
  final Map<String, dynamic> shopData;
  const SuspendedShopScreen({super.key, required this.shopData});

  @override
  State<SuspendedShopScreen> createState() => _SuspendedShopScreenState();
}

class _SuspendedShopScreenState extends State<SuspendedShopScreen> {
  String? _activeBillingCycleId;
  bool _loadingBillingId = true;

  @override
  void initState() {
    super.initState();
    _fetchActiveBillingCycleId();
  }

  /// Option C: Existing billing cycle ID fetch karo
  /// (agar rejected cycle hai toh use update karein, naya mat banao)
  Future<void> _fetchActiveBillingCycleId() async {
    final shopId = widget.shopData['id'] ?? '';
    if (shopId.isEmpty) {
      setState(() => _loadingBillingId = false);
      return;
    }

    // Option C: 'pending_verification' ya 'rejected' status
    final snap = await FirebaseFirestore.instance
        .collection('billing')
        .where('shopId', isEqualTo: shopId)
        .where('payment_status', whereIn: ['pending_verification', 'rejected'])
        .limit(1)
        .get();

    setState(() {
      _activeBillingCycleId =
          snap.docs.isNotEmpty ? snap.docs.first.id : null;
      _loadingBillingId = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int fee =
        ((widget.shopData['pending_fee'] ?? 0) as num).toInt();

    final reasons = [
      'Receipt was not uploaded within the required time',
      'Fake payment receipt detected',
      'Blurry or unreadable screenshot submitted',
      'Incomplete amount submitted (did not match the fee)',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B3E),
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Shop Suspended',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.shade200, width: 3),
              ),
              child:
                  Icon(Icons.block, color: Colors.red.shade600, size: 64),
            ),
            const SizedBox(height: 24),
            Text('Shop Temporarily Suspended',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Your shop is temporarily hidden from customers because the platform fee payment has not been verified.',
                style: TextStyle(
                    color: Colors.red.shade700, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
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
                  const Text('Shop Details',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0D1B3E))),
                  const Divider(height: 20),
                  _infoRow(Icons.store, 'Shop Name',
                      widget.shopData['shop_name'] ?? '-'),
                  _infoRow(Icons.confirmation_number, 'Registration',
                      widget.shopData['registration_no'] ?? '-'),
                  _infoRow(Icons.category_outlined, 'Category',
                      widget.shopData['shop_category'] ?? '-'),
                  _infoRow(Icons.account_balance_wallet_outlined,
                      'Pending Fee', 'Rs. $fee'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
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
                  const Text('Possible Reasons',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0D1B3E))),
                  const SizedBox(height: 12),
                  ...reasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.cancel_outlined,
                                color: Colors.red.shade400, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87)),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: (fee == 0 || _loadingBillingId)
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UploadReceiptScreen(
                              shopId: widget.shopData['id'] ?? '',
                              fee: fee,
                              // Option C: Existing billing cycle update karein
                              existingBillingCycleId: _activeBillingCycleId,
                            ),
                          ),
                        ),
                icon: _loadingBillingId
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.upload_file, color: Colors.white),
                label: Text(
                  fee > 0
                      ? 'Upload Receipt for Rs. $fee'
                      : 'No Pending Fee',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  disabledBackgroundColor: Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF6B00), size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D1B3E))),
        ],
      ),
    );
  }
}