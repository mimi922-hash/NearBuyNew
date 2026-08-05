// payment_verification_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'verification_details_screen.dart';
import 'admin_dashboard.dart';
import 'admin_billing_screen.dart';

class PaymentVerificationScreen extends StatelessWidget {
  const PaymentVerificationScreen({super.key});

  static const Color kOrange = Color(0xFFFF6B00);
  static const Color kNavy = Color(0xFF0D1B3E);
  static const Color kNavyCard = Color(0xFF112240);

  // ── Helper: Get month name from DateTime ──────────────────────
  String _getMonthName(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[date.month - 1];
  }

  // ── Helper: Format date with dynamic month ────────────────────
  String _formatDate(dynamic timestamp) {
    if (timestamp == null || timestamp is! Timestamp) return '';
    
    final dt = timestamp.toDate();
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final month = _getMonthName(dt);
    
    return '${dt.day} $month ${dt.year} • ${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
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
        title: const Text('Payment Verifications',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('billing')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('No data available.'));
          }

          final allDocs = snapshot.data!.docs;
          int pendingCount = 0;
          int approvedCount = 0;
          int rejectedCount = 0;

          for (final doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['payment_status'] ?? 'pending_verification';
            if (status == 'pending_verification') pendingCount++;
            if (status == 'paid') approvedCount++;
            if (status == 'rejected') rejectedCount++;
          }

          // Filter only pending for the list
          final pendingDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['payment_status'] ?? 'pending_verification') ==
                'pending_verification';
          }).toList();

          // Sort by submitted_at descending
          pendingDocs.sort((a, b) {
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

          // Also get recently verified
          final recentlyVerified = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['payment_status'] ?? '') == 'paid';
          }).toList();

          recentlyVerified.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['verified_at'] ?? aData['submitted_at'];
            final bTs = bData['verified_at'] ?? bData['submitted_at'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            final aDt = (aTs as dynamic).toDate() as DateTime;
            final bDt = (bTs as dynamic).toDate() as DateTime;
            return bDt.compareTo(aDt);
          });

          return SingleChildScrollView(
            child: Column(
              children: [
                // Stats header row
                _buildStatsHeader(pendingCount, approvedCount, rejectedCount),

                // Pending Verifications section
                if (pendingDocs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pending Verifications',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D1B3E))),
                        TextButton(
                          onPressed: () {},
                          child: const Text('View All',
                              style: TextStyle(
                                  color: kOrange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  ...pendingDocs.take(5).map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;
                    final shopId = data['shopId'] ?? '';
                    return _buildPendingCard(context, docId, data, shopId);
                  }),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 64, color: Colors.green.shade300),
                        const SizedBox(height: 16),
                        const Text('No pending verifications!',
                            style:
                                TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],

                // Recently Verified section
                if (recentlyVerified.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recently Verified',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D1B3E))),
                        TextButton(
                          onPressed: () {},
                          child: const Text('View All',
                              style: TextStyle(
                                  color: kOrange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  ...recentlyVerified.take(3).map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final shopId = data['shopId'] ?? '';
                    return _buildVerifiedCard(context, data, shopId);
                  }),
                ],

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildStatsHeader(int pending, int approved, int rejected) {
    return Container(
      margin: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          _statBox(
            icon: Icons.pending_actions_outlined,
            iconColor: Colors.blue,
            count: pending,
            label: 'Pending\nVerifications',
            bgColor: Colors.blue.shade50,
          ),
          _statDivider(),
          _statBox(
            icon: Icons.check_circle_outline,
            iconColor: Colors.green,
            count: approved,
            label: 'Approved',
            bgColor: Colors.green.shade50,
          ),
          _statDivider(),
          _statBox(
            icon: Icons.cancel_outlined,
            iconColor: Colors.red,
            count: rejected,
            label: 'Rejected',
            bgColor: Colors.red.shade50,
          ),
        ],
      ),
    );
  }

  Widget _statBox({
    required IconData icon,
    required Color iconColor,
    required int count,
    required String label,
    required Color bgColor,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            count < 10 ? '0$count' : '$count',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: iconColor),
          ),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      height: 60,
      width: 1,
      color: Colors.grey.shade200,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildPendingCard(BuildContext context, String docId,
      Map<String, dynamic> data, String shopId) {
    final fee = data['total_platform_fee'] ?? 0;
    final monthLabel = data['month_label'] ?? '-';
    final submittedAt = data['submitted_at'];
    final orderCount = ((data['order_count'] ?? 0) as num).toInt();

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('shops').doc(shopId).get(),
      builder: (context, shopSnap) {
        final shopName = shopSnap.hasData && shopSnap.data!.exists
            ? (shopSnap.data!.data() as Map<String, dynamic>)['shop_name'] ??
                'Unknown Shop'
            : 'Loading...';

        // ── Use helper function for date formatting ──
        final dateStr = _formatDate(submittedAt);
        
        String orderIdStr = data['order_id'] ?? '#ORD${docId.substring(0, 5).toUpperCase()}';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
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
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: kOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shopName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF0D1B3E))),
                    Text('PKR ${fee.toString()}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF0D1B3E))),
                    Text('Order ID: $orderIdStr',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (dateStr.isNotEmpty)
                      Text(dateStr,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Pending',
                        style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VerificationDetailsScreen(
                          billingId: docId,
                          billingData: data,
                          shopId: shopId,
                          shopName: shopName,
                        ),
                      ),
                    ),
                    child: const Icon(Icons.chevron_right,
                        color: Colors.grey, size: 22),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerifiedCard(BuildContext context, Map<String, dynamic> data,
      String shopId) {
    final fee = data['total_platform_fee'] ?? 0;
    final docId = data['id'] ?? '';

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('shops').doc(shopId).get(),
      builder: (context, shopSnap) {
        final shopName = shopSnap.hasData && shopSnap.data!.exists
            ? (shopSnap.data!.data() as Map<String, dynamic>)['shop_name'] ??
                'Unknown Shop'
            : 'Loading...';

        final verifiedAt = data['verified_at'] ?? data['submitted_at'];
        
        // ── Use helper function for date formatting ──
        final dateStr = _formatDate(verifiedAt);
        
        String orderIdStr = data['order_id'] ??
            '#ORD${shopId.substring(0, Math.min(5, shopId.length)).toUpperCase()}';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
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
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: Colors.green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shopName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF0D1B3E))),
                    Text('PKR ${fee.toString()}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF0D1B3E))),
                    Text('Order ID: $orderIdStr',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (dateStr.isNotEmpty)
                      Text(dateStr,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Approved',
                        style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right,
                      color: Colors.grey, size: 22),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
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

  String _fmtTs(dynamic ts) {
    if (ts == null) return '-';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '-';
  }

  Widget _buildBottomNav(BuildContext context) {
    final items = [
      {'icon': Icons.dashboard_rounded, 'label': 'Dashboard'},
      {'icon': Icons.store_rounded, 'label': 'Shops'},
      {'icon': Icons.account_balance_wallet_rounded, 'label': 'Billing'},
      {'icon': Icons.bar_chart_rounded, 'label': 'Reports'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: kNavyCard,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          // Billing (index 2) is active
          final active = i == 2;
          return GestureDetector(
            onTap: () {
              switch (i) {
                case 0:
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminDashboard()),
                    (route) => false,
                  );
                  break;
                case 1:
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const AdminDashboard(scrollToShops: true)),
                    (route) => false,
                  );
                  break;
                case 2:
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminBillingScreen()),
                  );
                  break;
                case 3:
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Reports coming soon!'),
                      backgroundColor: kNavyCard,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                  break;
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: active
                        ? kOrange.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    items[i]['icon'] as IconData,
                    color: active ? kOrange : Colors.white54,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  items[i]['label'] as String,
                  style: TextStyle(
                    color: active ? kOrange : Colors.white38,
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// Helper to avoid dart:math import issues
class Math {
  static int min(int a, int b) => a < b ? a : b;
}