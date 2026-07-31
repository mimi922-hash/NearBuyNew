import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BillingHistoryScreen extends StatelessWidget {
  final String shopId;
  const BillingHistoryScreen({super.key, required this.shopId});

  static const Color kOrange = Color(0xFFFF6B00);
  static const Color kNavy = Color(0xFF0D1B3E);

  // Option C: Updated status colors
  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending_verification':
        return Colors.blue;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Option C: Updated status labels (Urdu/English)
  String _statusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'Approved ✓';
      case 'pending_verification':
        return 'Under Review';
      case 'rejected':
        return 'Rejected';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Billing History',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('billing')
            .where('shopId', isEqualTo: shopId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 64, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text('Billing history could not be loaded.',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 16)),
                ],
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No billing record found',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                      'Upload your first receipt to start billing history.',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 13)),
                ],
              ),
            );
          }

          // Sort: latest submitted_at pehle
          final docs = snapshot.data!.docs.toList();
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['submitted_at'];
            final bTs = bData['submitted_at'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            final aDt = (aTs as dynamic).toDate() as DateTime;
            final bDt = (bTs as dynamic).toDate() as DateTime;
            return bDt.compareTo(aDt);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final status =
                  (data['payment_status'] ?? 'pending_verification') as String;
              final color = _statusColor(status);
              final label = _statusLabel(status);
              final fee =
                  ((data['total_platform_fee'] ?? 0) as num).toInt();
              final monthLabel =
                  (data['month_label'] ?? 'N/A') as String;
              final receiptUrl = data['receipt_url'] as String?;
              final rejectionReason =
                  data['rejection_reason'] as String?;
              final orderCount =
                  ((data['order_count'] ?? 0) as num).toInt();
              // Option C: orderIds list
              final orderIds =
                  (data['orderIds'] as List<dynamic>?)?.cast<String>() ?? [];

              return Container(
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(monthLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF0D1B3E))),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: color.withOpacity(0.4)),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      _infoRow('Platform Fee', 'Rs. $fee'),
                      if (orderCount > 0)
                        _infoRow('Orders in Batch', '$orderCount orders'),
                      _infoRow('Payment Method',
                          (data['payment_method'] ?? '-') as String),
                      if (data['transaction_id'] != null)
                        _infoRow('Transaction ID',
                            data['transaction_id'] as String),
                      if (data['submitted_at'] != null)
                        _infoRow(
                            'Submitted', _formatTs(data['submitted_at'])),
                      if (data['verified_at'] != null)
                        _infoRow(
                            'Verified', _formatTs(data['verified_at'])),

                      // Option C: orderIds preview
                      if (orderIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
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
                                'Batch Orders (${orderIds.length}):',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                orderIds.take(3).join(', ') +
                                    (orderIds.length > 3
                                        ? ' ...+${orderIds.length - 3} more'
                                        : ''),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue.shade600,
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Rejection reason
                      if (status == 'rejected' && rejectionReason != null)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red.shade600, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Rejection Reason: $rejectionReason',
                                  style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // View Receipt
                      if (receiptUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _showReceiptDialog(context, receiptUrl),
                              icon: const Icon(Icons.image_outlined,
                                  size: 16),
                              label: const Text('View Receipt'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kOrange,
                                side: const BorderSide(color: kOrange),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
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

  String _formatTs(dynamic ts) {
    if (ts == null) return '-';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '-';
  }

  void _showReceiptDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              height: 200,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image_outlined,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Receipt image could not be loaded.',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}