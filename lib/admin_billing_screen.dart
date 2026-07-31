import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'payment_verification_screen.dart';
import 'suspended_shops_screen.dart';
import 'billing_workflow_screen.dart';
import 'admin_dashboard.dart';

class AdminBillingScreen extends StatefulWidget {
  const AdminBillingScreen({super.key});

  @override
  State<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends State<AdminBillingScreen> {
  static const Color kOrange = Color(0xFFFF6B00);
  static const Color kNavy = Color(0xFF0D1B3E);
  static const Color kNavyCard = Color(0xFF112240);

  int _pendingCount = 0;
  int _suspendedCount = 0;
  int _activeCount = 0;
  double _totalRevenue = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _recentRequests = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final billing =
        await FirebaseFirestore.instance.collection('billing').get();
    final shops = await FirebaseFirestore.instance.collection('shops').get();

    int pending = 0;
    int suspended = 0;
    int active = 0;
    double revenue = 0;
    List<Map<String, dynamic>> recent = [];

    for (var doc in billing.docs) {
      final data = doc.data();
      final status = data['payment_status'] ?? 'pending_verification';
      if (status == 'pending_verification') pending++;
      if (status == 'paid') {
        revenue += (data['total_platform_fee'] ?? 0).toDouble();
      }
      recent.add({'id': doc.id, ...data});
    }

    for (var doc in shops.docs) {
      final st = doc.data()['status'] ?? 'verified';
      if (st == 'suspended')
        suspended++;
      else
        active++;
    }

    recent.sort((a, b) {
      final at = a['submitted_at'];
      final bt = b['submitted_at'];
      if (at == null || bt == null) return 0;
      return (bt as dynamic).compareTo(at);
    });

    setState(() {
      _pendingCount = pending;
      _suspendedCount = suspended;
      _activeCount = active;
      _totalRevenue = revenue;
      _recentRequests = recent.take(5).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        elevation: 0,
        title: const Text('Admin Billing Dashboard',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() => _loading = true);
              _loadStats();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRevenueCard(),
              const SizedBox(height: 16),
              _buildStatsGrid(),
              const SizedBox(height: 20),
              _buildQuickNav(context),
              const SizedBox(height: 20),
              _buildRecentPayments(context),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildRevenueCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.monetization_on, color: kOrange, size: 26),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Platform Revenue',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(height: 2),
                  Text('All verified payments',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'PKR ${_totalRevenue.toStringAsFixed(0)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      {
        'label': 'Pending\nReviews',
        'value': '$_pendingCount',
        'icon': Icons.pending_actions,
        'color': Colors.blue
      },
      {
        'label': 'Active Shops',
        'value': '$_activeCount',
        'icon': Icons.check_circle_outline,
        'color': Colors.green
      },
      {
        'label': 'Suspended\nShops',
        'value': _suspendedCount < 10
            ? '0$_suspendedCount'
            : '$_suspendedCount',
        'icon': Icons.block_outlined,
        'color': Colors.red
      },
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
                right: stats.indexOf(s) < stats.length - 1 ? 10 : 0),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(s['icon'] as IconData,
                    color: s['color'] as Color, size: 22),
                const SizedBox(height: 8),
                Text(s['value'] as String,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: s['color'] as Color)),
                Text(s['label'] as String,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickNav(BuildContext context) {
    final navItems = [
      {
        'label': 'Verify\nPayments',
        'icon': Icons.verified_user_outlined,
        'color': kOrange,
        'screen': const PaymentVerificationScreen()
      },
      {
        'label': 'Suspended\nShops',
        'icon': Icons.block,
        'color': Colors.red,
        'screen': const SuspendedShopsScreen()
      },
      {
        'label': 'Billing\nWorkflow',
        'icon': Icons.account_tree_outlined,
        'color': kNavy,
        'screen': const BillingWorkflowScreen()
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Management',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D1B3E))),
        const SizedBox(height: 12),
        Row(
          children: navItems.map((item) {
            return Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => item['screen'] as Widget)),
                child: Container(
                  margin: EdgeInsets.only(
                      right: navItems.indexOf(item) < navItems.length - 1
                          ? 10
                          : 0),
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  decoration: BoxDecoration(
                    color: (item['color'] as Color).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: (item['color'] as Color).withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      Icon(item['icon'] as IconData,
                          color: item['color'] as Color, size: 26),
                      const SizedBox(height: 8),
                      Text(item['label'] as String,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: item['color'] as Color),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Icon(Icons.arrow_forward,
                          size: 14, color: item['color'] as Color),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentPayments(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Payment Requests',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D1B3E))),
            TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PaymentVerificationScreen())),
              child: const Text('View All',
                  style: TextStyle(
                      color: kOrange, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._recentRequests.map((data) {
          final status = data['payment_status'] ?? 'pending_verification';
          final color = status == 'paid'
              ? Colors.green
              : status == 'rejected'
                  ? Colors.red
                  : Colors.orange;
          final statusLabel = status == 'paid'
              ? 'Approved'
              : status == 'rejected'
                  ? 'Rejected'
                  : 'Pending';

          String dateStr = '';
          final submittedAt = data['submitted_at'];
          if (submittedAt != null && submittedAt is Timestamp) {
            final dt = submittedAt.toDate();
            dateStr =
                '${dt.day} May ${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
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
                  child: const Icon(Icons.receipt_outlined,
                      color: Colors.green, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['month_label'] ?? 'Month',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0D1B3E))),
                      Text('Fee: PKR ${data['total_platform_fee'] ?? 0}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      if (data['shop_name'] != null)
                        Text('Shop: ${data['shop_name']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
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
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (dateStr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(dateStr,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
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
          // Billing tab (index 2) is active
          final active = i == 2;
          return GestureDetector(
            onTap: () {
              switch (i) {
                case 0:
                  // Go to Admin Dashboard
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminDashboard()),
                    (route) => false,
                  );
                  break;
                case 1:
                  // Go to Admin Dashboard and scroll to shops
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const AdminDashboard(scrollToShops: true)),
                    (route) => false,
                  );
                  break;
                case 2:
                  // Already on Billing — no action needed
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
                        ? const Color(0xFFFF6B00).withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    items[i]['icon'] as IconData,
                    color: active ? const Color(0xFFFF6B00) : Colors.white54,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  items[i]['label'] as String,
                  style: TextStyle(
                    color: active ? const Color(0xFFFF6B00) : Colors.white38,
                    fontSize: 10,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal,
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