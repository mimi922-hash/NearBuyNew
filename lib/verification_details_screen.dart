// verification_details_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VerificationDetailsScreen extends StatefulWidget {
  final String billingId;
  final Map<String, dynamic> billingData;
  final String shopId;
  final String shopName;

  const VerificationDetailsScreen({
    super.key,
    required this.billingId,
    required this.billingData,
    required this.shopId,
    required this.shopName,
  });

  @override
  State<VerificationDetailsScreen> createState() =>
      _VerificationDetailsScreenState();
}

class _VerificationDetailsScreenState
    extends State<VerificationDetailsScreen> {
  static const Color kOrange = Color(0xFFFF6B00);
  static const Color kNavy = Color(0xFF0D1B3E);

  bool _processing = false;
  String? _selectedRejectionReason;
  
  // ─── For displaying fee breakdown ──────────────────────────────
  double _totalOrderAmount = 0;
  double _calculatedFee = 0;
  List<Map<String, dynamic>> _orderDetails = [];

  final _rejectionReasons = [
    'Fake Receipt Uploaded',
    'Blurry Screenshot',
    'Incomplete Payment',
    'Invalid Transaction ID',
  ];

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  // ─── FIXED: Load order details using stored platformFee ──────────
  Future<void> _loadOrderDetails() async {
    final orderIds = (widget.billingData['orderIds'] as List<dynamic>?)
            ?.cast<String>() ??
        [];

    if (orderIds.isEmpty) {
      setState(() {
        _totalOrderAmount = 0;
        _calculatedFee = 0;
        _orderDetails = [];
      });
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      double totalAmount = 0;
      double totalPlatformFee = 0;
      List<Map<String, dynamic>> details = [];

      for (String orderId in orderIds) {
        final doc = await firestore.collection('orders').doc(orderId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;

          // ─── READ STORED platformFee ──────────────────────────────
          final platformFee = (data['platformFee'] as num?)?.toDouble() ?? 0;
          
          // ─── READ order total for display purposes ────────────────
          num? orderTotal;
          if (data.containsKey('orderTotal')) {
            orderTotal = (data['orderTotal'] as num?)?.toDouble();
          } else if (data.containsKey('totalAmount')) {
            orderTotal = (data['totalAmount'] as num?)?.toDouble();
          } else if (data.containsKey('grandTotal')) {
            orderTotal = (data['grandTotal'] as num?)?.toDouble();
          } else if (data.containsKey('amount')) {
            orderTotal = (data['amount'] as num?)?.toDouble();
          } else if (data.containsKey('total_amount')) {
            orderTotal = (data['total_amount'] as num?)?.toDouble();
          } else if (data.containsKey('order_amount')) {
            orderTotal = (data['order_amount'] as num?)?.toDouble();
          }

          if (orderTotal != null && orderTotal > 0) {
            totalAmount += orderTotal.toDouble();
          }
          
          // ─── USE STORED platformFee ──────────────────────────────
          totalPlatformFee += platformFee;
          
          details.add({
            'orderId': orderId,
            'orderTotal': orderTotal?.toDouble() ?? 0,
            'platformFee': platformFee, // ✅ Using stored value
          });
        }
      }

      setState(() {
        _totalOrderAmount = totalAmount;
        _calculatedFee = totalPlatformFee; // ✅ Using stored sum
        _orderDetails = details;
      });

      // Update stored fee if mismatch (safety check)
      double storedFee = (widget.billingData['total_platform_fee'] ?? 0).toDouble();
      if ((totalPlatformFee - storedFee).abs() > 0.01) {
        await firestore
            .collection('billing')
            .doc(widget.billingId)
            .update({
          'total_platform_fee': totalPlatformFee.round(),
        });
        widget.billingData['total_platform_fee'] = totalPlatformFee.round();
      }
    } catch (e) {
      debugPrint('Error loading order details: $e');
    }
  }

  // ─── OPTION C: APPROVE ──────────────────────────────────────────────
  Future<void> _approvePayment() async {
    setState(() => _processing = true);
    try {
      final firestore = FirebaseFirestore.instance;

      await firestore
          .collection('billing')
          .doc(widget.billingId)
          .update({
        'payment_status': 'paid',
        'verified_at': FieldValue.serverTimestamp(),
      });

      await firestore
          .collection('shops')
          .doc(widget.shopId)
          .update({'status': 'verified'});

      final ordersSnap = await firestore
          .collection('orders')
          .where('shopId', isEqualTo: widget.shopId)
          .where('billingCycleId', isEqualTo: widget.billingId)
          .get();

      if (ordersSnap.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final orderDoc in ordersSnap.docs) {
          batch.update(orderDoc.reference, {
            'billingStatus': 'paid',
          });
        }
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment approved! Shop has been reactivated.'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ─── OPTION C: REJECT ───────────────────────────────────────────────
  Future<void> _rejectPayment() async {
    if (_selectedRejectionReason == null) {
      _showRejectionDialog();
      return;
    }

    setState(() => _processing = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final dueTime = DateTime.now().add(const Duration(minutes: 3));

      await firestore
          .collection('billing')
          .doc(widget.billingId)
          .update({
        'payment_status': 'rejected',
        'rejection_reason': _selectedRejectionReason,
        'rejected_at': FieldValue.serverTimestamp(),
        'grace_period_active': true,
        'due_time': Timestamp.fromDate(dueTime),
      });

      final ordersSnap = await firestore
          .collection('orders')
          .where('shopId', isEqualTo: widget.shopId)
          .where('billingCycleId', isEqualTo: widget.billingId)
          .get();

      if (ordersSnap.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final orderDoc in ordersSnap.docs) {
          batch.update(orderDoc.reference, {
            'billingStatus': 'unpaid',
            'billingCycleId': null,
          });
        }
        await batch.commit();
      }

      await firestore
          .collection('shops')
          .doc(widget.shopId)
          .update({
        'warningActive': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Receipt rejected. Shopkeeper has been given 3 minutes.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _processing = false);
    }
  }

  Future<void> _suspendShop() async {
    setState(() => _processing = true);
    try {
      final firestore = FirebaseFirestore.instance;

      await firestore
          .collection('shops')
          .doc(widget.shopId)
          .update({'status': 'suspended'});

      await firestore
          .collection('billing')
          .doc(widget.billingId)
          .update({'payment_status': 'rejected'});

      final ordersSnap = await firestore
          .collection('orders')
          .where('shopId', isEqualTo: widget.shopId)
          .where('billingCycleId', isEqualTo: widget.billingId)
          .get();

      if (ordersSnap.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final orderDoc in ordersSnap.docs) {
          batch.update(orderDoc.reference, {
            'billingStatus': 'unpaid',
            'billingCycleId': null,
          });
        }
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Shop successfully suspended.'),
          backgroundColor: Colors.red,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _processing = false);
    }
  }

  void _showRejectionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Select Rejection Reason',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _rejectionReasons
              .map((r) => ListTile(
                    title: Text(r, style: const TextStyle(fontSize: 14)),
                    leading: Radio<String>(
                      value: r,
                      groupValue: _selectedRejectionReason,
                      activeColor: Colors.red,
                      onChanged: (v) {
                        setState(() => _selectedRejectionReason = v);
                        Navigator.pop(context);
                        _rejectPayment();
                      },
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ─── Helper: Format time in 12-hour format ──────────────────────
  String _formatTime12Hour(dynamic timestamp) {
    if (timestamp == null || timestamp is! Timestamp) return '-';
    
    final dt = timestamp.toDate();
    int hour = dt.hour;
    final minute = dt.minute;
    final amPm = hour >= 12 ? 'PM' : 'AM';
    
    // Convert to 12-hour format
    if (hour > 12) hour = hour - 12;
    if (hour == 0) hour = 12;
    
    return '${dt.day}/${dt.month}/${dt.year} ${hour}:${minute.toString().padLeft(2, '0')} $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.billingData;
    final receiptUrl = data['receipt_url'];
    final fee = data['total_platform_fee'] ?? 0;
    final monthLabel = data['month_label'] ?? '-';
    final method = data['payment_method'] ?? '-';
    final txnId = data['transaction_id'] ?? '-';
    final note = data['note'];
    final orderCount = ((data['order_count'] ?? 0) as num).toInt();
    final orderIds = (data['orderIds'] as List<dynamic>?)?.cast<String>() ?? [];

    // ─── Show fee breakdown ──────────────────────────────────────
    final showFeeBreakdown = _orderDetails.isNotEmpty && _totalOrderAmount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Verification Details',
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
            _buildCard(
              title: 'Shop Details',
              icon: Icons.store,
              children: [
                _infoRow('Shop Name', widget.shopName),
                _infoRow('Shop ID', widget.shopId),
              ],
            ),
            const SizedBox(height: 14),

            _buildCard(
              title: 'Billing Cycle Summary',
              icon: Icons.receipt_long,
              children: [
                _infoRow('Billing Month', monthLabel),
                
                // ─── FIXED: Platform Fee with breakdown ──────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Platform Fee (5% Commission)', 'Rs. $fee'),
                    if (showFeeBreakdown) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kOrange.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: kOrange.withOpacity(0.15),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Calculated from ${_orderDetails.length} order(s):',
                              style: TextStyle(
                                fontSize: 11,
                                color: kNavy.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ..._orderDetails.map((order) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Order ${order['orderId'].substring(0, 8)}...',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: kNavy.withOpacity(0.5),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${order['orderTotal'].toStringAsFixed(0)} × 5% = Rs. ${order['platformFee'].toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: kNavy.withOpacity(0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                            const Divider(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Order Amount:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kNavy,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Rs. ${_totalOrderAmount.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kNavy,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Platform Fee (5%):',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kOrange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Rs. ${_calculatedFee.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kOrange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            // ─── NEW: Show source of truth ──────────
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '✓ Fee sourced from orders (5% of subtotal)',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                
                _infoRow('Orders in Batch', '$orderCount orders'),
                _infoRow('Payment Method', method),
                _infoRow('Transaction ID', txnId),
                if (note != null && note.isNotEmpty)
                  _infoRow('Note', note),
                if (data['submitted_at'] != null)
                  _infoRow('Submitted At', _formatTime12Hour(data['submitted_at'])), // ✅ 12-hour format
              ],
            ),

            if (orderIds.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildCard(
                title: 'Orders in This Batch',
                icon: Icons.list_alt_outlined,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'These $orderCount orders are included in this receipt:',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ...orderIds.take(10).map((id) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.circle,
                                      size: 6,
                                      color: Colors.blue.shade400),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(id,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace')),
                                  ),
                                ],
                              ),
                            )),
                        if (orderIds.length > 10)
                          Text(
                            '...and ${orderIds.length - 10} more orders',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade600,
                                fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
            if (receiptUrl != null)
              _buildCard(
                title: 'Uploaded Receipt',
                icon: Icons.image_outlined,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      receiptUrl,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.amber.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'On approval, $orderCount orders will be marked "paid" and the shop will become active. On rejection, all orders will go back to "unpaid".',
                      style:
                          TextStyle(fontSize: 12, color: Colors.amber.shade800),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            if (!_processing) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _approvePayment,
                  icon: const Icon(Icons.check_circle_outline,
                      color: Colors.white),
                  label: const Text('Approve Payment',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rejectPayment,
                      icon: Icon(Icons.cancel_outlined,
                          color: Colors.red.shade600, size: 18),
                      label: Text('Reject',
                          style: TextStyle(
                              color: Colors.red.shade600,
                              fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _suspendShop,
                      icon:
                          const Icon(Icons.block, color: Colors.red, size: 18),
                      label: const Text('Suspend Shop',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
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
          Row(
            children: [
              Icon(icon, color: kOrange, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF0D1B3E))),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D1B3E)),
                  textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}