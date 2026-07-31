import 'dart:async';
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:intl/intl.dart';

import 'upload_receipt_screen.dart';

import 'billing_history_screen.dart';

import 'suspended_shop_screen.dart';

class ShopkeeperBillingScreen extends StatefulWidget {

  final String? shopId;

  const ShopkeeperBillingScreen({super.key, this.shopId});

  @override

  State<ShopkeeperBillingScreen> createState() =>

      _ShopkeeperBillingScreenState();

}

class _ShopkeeperBillingScreenState extends State<ShopkeeperBillingScreen> {

  static const Color kOrange = Color(0xFFFF6B00);

  static const Color kNavy = Color(0xFF0D1B3E);

  final _auth = FirebaseAuth.instance;

  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _shopData;

  Map<String, dynamic>? _activeBillingData;

  String? _activeBillingDocId;

  bool _loading = true;

  // ── Countdown timer variables ──────────────────────────────────────
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;
  DateTime? _graceDueTime;

  @override

  void initState() {

    super.initState();

    _loadData();

  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startBillingCountdown(DateTime dueTime) {
    _countdownTimer?.cancel();
    _graceDueTime = dueTime;
    final remaining = dueTime.difference(DateTime.now());
    setState(() {
      _remainingTime = remaining.isNegative ? Duration.zero : remaining;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final rem = _graceDueTime!.difference(DateTime.now());
      setState(() {
        _remainingTime = rem.isNegative ? Duration.zero : rem;
      });
      if (_remainingTime == Duration.zero) {
        _countdownTimer?.cancel();
      }
    });
  }

  /// Option C Logic:

  /// Unpaid orders = billingCycleId field nahi hai YA null hai

  /// (Firestore isNull: true sirf tab kaam karta hai jab field exist kare)

  /// Isliye manually filter karte hain.

  Future<void> _loadData() async {

    setState(() => _loading = true);

    final user = _auth.currentUser;

    if (user == null) {

      setState(() => _loading = false);

      return;

    }

    // Step 1: Get shop

    final shopSnap = await _firestore

        .collection('shops')

        .where('owner_email', isEqualTo: user.email)

        .limit(1)

        .get();

    if (shopSnap.docs.isEmpty) {

      setState(() => _loading = false);

      return;

    }

    final shopDoc = shopSnap.docs.first;

    final shopId = shopDoc.id;

    // Step 2: Fetch ALL orders for this shop

    // Then filter: billingCycleId field missing OR null = unpaid orders

    final allOrdersSnap = await _firestore

        .collection('orders')

        .where('shopId', isEqualTo: shopId)

        .get();

    // Option C: sirf woh orders count karo jinka billingCycleId null hai

    // Yeh orders abhi kisi billing cycle mein nahi hain

    final unpaidDocs = allOrdersSnap.docs.where((doc) {

      final data = doc.data();

      final isDelivered = (data['status'] ?? '') == 'delivered';

      return isDelivered &&

          (!data.containsKey('billingCycleId') ||

          data['billingCycleId'] == null);

    }).toList();

    int pendingFee = 0;

    for (final doc in unpaidDocs) {

      final data = doc.data();

      final fee = ((data['platformFee'] ?? 0) as num).toInt();

      pendingFee += fee;

    }

    // Step 3: Check for active billing cycle (pending_verification or rejected)

    // Option C mein billing cycle = billing collection ka document

    final activeBillingSnap = await _firestore

        .collection('billing')

        .where('shopId', isEqualTo: shopId)

        .where('payment_status', whereIn: ['pending_verification', 'rejected'])

        .limit(1)

        .get();

    Map<String, dynamic>? activeBillingData;

    String? activeBillingDocId;

    if (activeBillingSnap.docs.isNotEmpty) {

      activeBillingDocId = activeBillingSnap.docs.first.id;

      activeBillingData = activeBillingSnap.docs.first.data();

      // Agar rejected cycle hai aur naye orders aa gaye hain

      // toh total fee update karo (rejected + new unpaid)

      // NOTE: Rejected cycle ke orders dobara billingCycleId null ho jaate hain

      // isliye unpaidDocs mein woh bhi shamil ho jaate hain

      final storedFee =

          ((activeBillingData['total_platform_fee'] ?? 0) as num).toInt();

      if (pendingFee != storedFee) {

        await activeBillingSnap.docs.first.reference

            .update({'total_platform_fee': pendingFee});

        activeBillingData = {

          ...activeBillingData,

          'total_platform_fee': pendingFee

        };

      }

      // ── AUTO SUSPEND CHECK ────────────────────────────────────────

      // Agar billing rejected hai aur 3 min grace period expire ho gayi

      if (activeBillingData['payment_status'] == 'rejected') {

        final dueTime = activeBillingData['due_time'];

        if (dueTime != null) {

          final dueDate = (dueTime as Timestamp).toDate();

          if (DateTime.now().isAfter(dueDate)) {

            // 3 min complete — shop suspend karo

            await _firestore

                .collection('shops')

                .doc(shopId)

                .update({

              'status': 'suspended',

              'warningActive': false,

            });

            // Local state update

            activeBillingData = {

              ...activeBillingData,

              'grace_period_active': false,

            };

          }

        }

      }

    }

    setState(() {

      _shopData = {

        'id': shopId,

        'pending_fee': pendingFee,

        'unpaid_order_count': unpaidDocs.length,

        ...shopDoc.data(),

      };

      _activeBillingData = activeBillingData;

      _activeBillingDocId = activeBillingDocId;

      _loading = false;

    });

    // ── Countdown start karo agar rejected + due_time maujood hai ──
    if (activeBillingData != null &&
        activeBillingData['payment_status'] == 'rejected') {
      final dueTimeRaw = activeBillingData['due_time'];
      if (dueTimeRaw != null) {
        final dueDate = (dueTimeRaw as Timestamp).toDate();
        if (DateTime.now().isBefore(dueDate)) {
          _startBillingCountdown(dueDate);
        }
      }
    } else {
      _countdownTimer?.cancel();
      if (mounted) setState(() => _remainingTime = Duration.zero);
    }

  }

  String get _billingStatus {

    if (_shopData == null) return 'Active';

    final shopStatus = (_shopData!['status'] ?? 'verified') as String;

    if (shopStatus == 'suspended') return 'Suspended';

    final pendingFee = (_shopData!['pending_fee'] ?? 0) as int;

    if (pendingFee == 0) return 'Active';

    if (_activeBillingData == null) return 'Warning';

    final ps =

        (_activeBillingData!['payment_status'] ?? 'pending_verification')

            as String;

    if (ps == 'rejected') return 'Overdue';

    if (ps == 'pending_verification') return 'Under Review';

    return 'Warning';

  }

  Color get _statusColor {

    switch (_billingStatus) {

      case 'Active':

        return Colors.green;

      case 'Warning':

        return kOrange;

      case 'Under Review':

        return Colors.blue;

      case 'Overdue':

        return Colors.red;

      case 'Suspended':

        return Colors.red.shade900;

      default:

        return Colors.green;

    }

  }

  @override

  Widget build(BuildContext context) {

    if (_loading) {

      return const Scaffold(

          body: Center(child: CircularProgressIndicator()));

    }

    final fee = ((_shopData?['pending_fee'] ?? 0) as num).toInt();

    final orderCount =

        ((_shopData?['unpaid_order_count'] ?? 0) as num).toInt();

    final payStatus =

        (_activeBillingData?['payment_status'] ?? '') as String;

    final shopStatus = ((_shopData?['status'] ?? 'verified') as String);

    final monthLabel = (_activeBillingData?['month_label'] ??

        DateFormat('MMMM yyyy').format(DateTime.now())) as String;

    return Scaffold(

      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(

        backgroundColor: kNavy,

        elevation: 0,

        title: const Text('Billing Dashboard',

            style: TextStyle(

                color: Colors.white,

                fontWeight: FontWeight.bold,

                fontSize: 18)),

        centerTitle: true,

        actions: [

          IconButton(

            icon: const Icon(Icons.refresh, color: Colors.white),

            onPressed: _loadData,

          )

        ],

      ),

      body: RefreshIndicator(

        onRefresh: _loadData,

        child: SingleChildScrollView(

          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(16),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              _buildShopHeader(),

              const SizedBox(height: 16),

              // Option C: Rejected hone par naye orders bhi include ho jaate hain

              if (fee > 0 && payStatus == 'rejected')

                _buildWarningBanner(isRejected: true),

              if (fee > 0 && payStatus == 'pending_verification')

                _buildWarningBanner(isRejected: false, isUnderReview: true),

              if (fee > 0 && payStatus.isEmpty)

                _buildWarningBanner(isRejected: false),

              if (shopStatus == 'suspended') _buildSuspensionBanner(context),

              const SizedBox(height: 8),

              _buildStatusChip(),

              const SizedBox(height: 16),

              _buildSummaryGrid(fee, orderCount, monthLabel, payStatus),

              const SizedBox(height: 20),

              _buildQuickActions(context, fee),

              const SizedBox(height: 20),

              _buildReminderSection(),

              const SizedBox(height: 80),

            ],

          ),

        ),

      ),

      bottomNavigationBar: _buildBottomNav(context),

    );

  }

  Widget _buildShopHeader() {

    return Container(

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(

        gradient: const LinearGradient(

          colors: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)],

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

        ),

        borderRadius: BorderRadius.circular(16),

        boxShadow: [

          BoxShadow(

              color: Colors.black.withOpacity(0.15),

              blurRadius: 12,

              offset: const Offset(0, 4))

        ],

      ),

      child: Row(

        children: [

          Container(

            width: 52,

            height: 52,

            decoration: BoxDecoration(

              color: kOrange.withOpacity(0.2),

              borderRadius: BorderRadius.circular(12),

            ),

            child: const Icon(Icons.store, color: kOrange, size: 28),

          ),

          const SizedBox(width: 12),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  _shopData?['shop_name'] ?? 'My Shop',

                  style: const TextStyle(

                      color: Colors.white,

                      fontWeight: FontWeight.bold,

                      fontSize: 16),

                ),

                Text(

                  _shopData?['shop_category'] ?? '',

                  style: TextStyle(

                      color: Colors.white.withOpacity(0.7), fontSize: 13),

                ),

              ],

            ),

          ),

          Text('Reg: ${_shopData?['registration_no'] ?? ''}',

              style: const TextStyle(color: Colors.white70, fontSize: 11)),

        ],

      ),

    );

  }

  Widget _buildWarningBanner(

      {required bool isRejected, bool isUnderReview = false}) {

    Color bannerColor = isRejected

        ? Colors.red.shade50

        : isUnderReview

            ? Colors.blue.shade50

            : Colors.orange.shade50;

    Color borderColor = isRejected

        ? Colors.red.shade300

        : isUnderReview

            ? Colors.blue.shade300

            : Colors.orange.shade300;

    Color iconColor = isRejected

        ? Colors.red.shade700

        : isUnderReview

            ? Colors.blue.shade700

            : Colors.orange.shade700;

    IconData bannerIcon = isRejected

        ? Icons.cancel_outlined

        : isUnderReview

            ? Icons.hourglass_top_outlined

            : Icons.timer_outlined;

    // ── Rejection ke liye countdown string ──
    final bool expired = _remainingTime == Duration.zero && isRejected;
    final mins = _remainingTime.inMinutes;
    final secs = _remainingTime.inSeconds % 60;
    final timeStr = expired
        ? 'Time expired!'
        : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    String message = isRejected

        ? (expired
            ? 'Grace period expired — shop will be suspended. Go to billing screen now.'
            : 'Receipt was rejected. Upload a valid receipt, otherwise the shop will be suspended:')

        : isUnderReview

            ? 'Receipt has been submitted. Please wait for admin verification.'

            : 'Platform fee is pending. Please upload a receipt.';

    return Container(

      margin: const EdgeInsets.only(bottom: 12),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: bannerColor,

        border: Border.all(color: borderColor, width: isRejected ? 1.5 : 1.0),

        borderRadius: BorderRadius.circular(12),

      ),

      child: Row(

        children: [

          Icon(bannerIcon, color: iconColor, size: 22),

          const SizedBox(width: 10),

          Expanded(

            child: Text(

              message,

              style: TextStyle(

                  color: isRejected

                      ? Colors.red.shade800

                      : isUnderReview

                          ? Colors.blue.shade800

                          : Colors.orange.shade800,

                  fontSize: 13,

                  fontWeight: FontWeight.w500),

            ),

          ),

          // ── Live countdown clock (sirf rejected pe) ──────────────
          if (isRejected) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: expired ? Colors.red.shade800 : Colors.red.shade600,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],

        ],

      ),

    );

  }

  Widget _buildSuspensionBanner(BuildContext context) {

    return GestureDetector(

      onTap: () => Navigator.push(

          context,

          MaterialPageRoute(

              builder: (_) =>

                  SuspendedShopScreen(shopData: _shopData!))),

      child: Container(

        margin: const EdgeInsets.only(bottom: 12),

        padding: const EdgeInsets.all(14),

        decoration: BoxDecoration(

          color: Colors.red.shade50,

          border: Border.all(color: Colors.red.shade300),

          borderRadius: BorderRadius.circular(12),

        ),

        child: Row(

          children: [

            Icon(Icons.block, color: Colors.red.shade700, size: 22),

            const SizedBox(width: 10),

            Expanded(

              child: Text(

                'Your shop is temporarily suspended. Tap to see details.',

                style: TextStyle(

                    color: Colors.red.shade800,

                    fontSize: 13,

                    fontWeight: FontWeight.w600),

              ),

            ),

            Icon(Icons.arrow_forward_ios,

                color: Colors.red.shade400, size: 14),

          ],

        ),

      ),

    );

  }

  Widget _buildStatusChip() {

    return Row(

      children: [

        const Text('Billing Status:',

            style: TextStyle(

                fontSize: 14,

                fontWeight: FontWeight.w600,

                color: Color(0xFF0D1B3E))),

        const SizedBox(width: 10),

        Container(

          padding:

              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),

          decoration: BoxDecoration(

            color: _statusColor.withOpacity(0.12),

            borderRadius: BorderRadius.circular(20),

            border: Border.all(color: _statusColor.withOpacity(0.4)),

          ),

          child: Row(

            mainAxisSize: MainAxisSize.min,

            children: [

              Container(

                  width: 7,

                  height: 7,

                  decoration: BoxDecoration(

                      color: _statusColor, shape: BoxShape.circle)),

              const SizedBox(width: 6),

              Text(_billingStatus,

                  style: TextStyle(

                      color: _statusColor,

                      fontWeight: FontWeight.bold,

                      fontSize: 13)),

            ],

          ),

        ),

      ],

    );

  }

  Widget _buildSummaryGrid(

      int fee, int orderCount, String monthLabel, String payStatus) {

    // Option C: payStatus values = pending_verification, rejected, paid

    String payStatusDisplay;

    Color payStatusColor;

    if (payStatus.isEmpty) {

      payStatusDisplay = fee == 0 ? 'CLEAR' : 'NOT SUBMITTED';

      payStatusColor = fee == 0 ? Colors.green : Colors.orange;

    } else if (payStatus == 'pending_verification') {

      payStatusDisplay = 'UNDER REVIEW';

      payStatusColor = Colors.blue;

    } else if (payStatus == 'paid') {

      payStatusDisplay = 'PAID';

      payStatusColor = Colors.green;

    } else if (payStatus == 'rejected') {

      payStatusDisplay = 'REJECTED';

      payStatusColor = Colors.red;

    } else {

      payStatusDisplay = payStatus.toUpperCase();

      payStatusColor = Colors.orange;

    }

    final cards = [

      {

        'title': 'Pending Platform Fee',

        'value': fee == 0 ? 'Rs. 0 (Clear)' : 'Rs. $fee',

        'icon': Icons.account_balance_wallet_outlined,

        'color': fee == 0 ? Colors.green : kOrange,

      },

      {

        'title': 'Unpaid Orders',

        'value': '$orderCount Orders',

        'icon': Icons.shopping_bag_outlined,

        'color': kNavy,

      },

      {

        'title': 'Cycle Status',

        'value': payStatusDisplay,

        'icon': Icons.payment_outlined,

        'color': payStatusColor,

      },

      {

        'title': 'Receipt Submitted',

        'value':

            _activeBillingData?['submitted_at'] != null ? 'Yes' : 'No',

        'icon': Icons.receipt_long_outlined,

        'color': Colors.purple,

      },

    ];

    return GridView.builder(

      shrinkWrap: true,

      physics: const NeverScrollableScrollPhysics(),

      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(

        crossAxisCount: 2,

        crossAxisSpacing: 12,

        mainAxisSpacing: 12,

        childAspectRatio: 1.5,

      ),

      itemCount: cards.length,

      itemBuilder: (_, i) {

        final c = cards[i];

        return Container(

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

            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [

              Container(

                padding: const EdgeInsets.all(7),

                decoration: BoxDecoration(

                  color: (c['color'] as Color).withOpacity(0.1),

                  borderRadius: BorderRadius.circular(8),

                ),

                child: Icon(c['icon'] as IconData,

                    color: c['color'] as Color, size: 20),

              ),

              Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(c['value'] as String,

                      style: TextStyle(

                          fontWeight: FontWeight.bold,

                          fontSize: 14,

                          color: c['color'] as Color)),

                  Text(c['title'] as String,

                      style: const TextStyle(

                          fontSize: 11, color: Colors.grey)),

                ],

              ),

            ],

          ),

        );

      },

    );

  }

  Widget _buildQuickActions(BuildContext context, int fee) {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        const Text('Quick Actions',

            style: TextStyle(

                fontSize: 16,

                fontWeight: FontWeight.bold,

                color: Color(0xFF0D1B3E))),

        const SizedBox(height: 12),

        Row(

          children: [

            Expanded(

              child: _actionBtn(

                icon: Icons.upload_file,

                label: 'Upload Receipt',

                color: kOrange,

                onTap: () {

                  final shopId = _shopData?['id'] ?? '';

                  if (shopId.isEmpty) {

                    ScaffoldMessenger.of(context).showSnackBar(

                        const SnackBar(

                      content: Text('Shop did not load. Please refresh.'),

                      backgroundColor: Colors.red,

                    ));

                    return;

                  }

                  if (fee == 0) {

                    ScaffoldMessenger.of(context).showSnackBar(

                        const SnackBar(

                      content:

                          Text('No pending fee. All clear!'),

                      backgroundColor: Colors.green,

                    ));

                    return;

                  }

                  // Option C: Under Review mein nahi ja sakte

                  final payStatus =

                      (_activeBillingData?['payment_status'] ?? '') as String;

                  if (payStatus == 'pending_verification') {

                    ScaffoldMessenger.of(context).showSnackBar(

                        const SnackBar(

                      content: Text(

                          'Receipt already submitted. Please wait for admin verification.'),

                      backgroundColor: Colors.blue,

                    ));

                    return;

                  }

                  Navigator.push(

                    context,

                    MaterialPageRoute(

                      builder: (_) => UploadReceiptScreen(

                        shopId: shopId,

                        fee: fee,

                        existingBillingCycleId: _activeBillingDocId,

                      ),

                    ),

                  ).then((_) => _loadData());

                },

              ),

            ),

            const SizedBox(width: 10),

            Expanded(

              child: _actionBtn(

                icon: Icons.history,

                label: 'Billing History',

                color: kNavy,

                onTap: () => Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) => BillingHistoryScreen(

                        shopId: _shopData?['id'] ?? ''),

                  ),

                ),

              ),

            ),

          ],

        ),

      ],

    );

  }

  Widget _actionBtn({

    required IconData icon,

    required String label,

    required Color color,

    required VoidCallback onTap,

  }) {

    return GestureDetector(

      onTap: onTap,

      child: Container(

        padding: const EdgeInsets.symmetric(vertical: 14),

        decoration: BoxDecoration(

          color: color,

          borderRadius: BorderRadius.circular(14),

          boxShadow: [

            BoxShadow(

                color: color.withOpacity(0.3),

                blurRadius: 8,

                offset: const Offset(0, 4))

          ],

        ),

        child: Column(

          children: [

            Icon(icon, color: Colors.white, size: 24),

            const SizedBox(height: 6),

            Text(label,

                style: const TextStyle(

                    color: Colors.white,

                    fontWeight: FontWeight.w600,

                    fontSize: 12)),

          ],

        ),

      ),

    );

  }

  Widget _buildReminderSection() {

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

          const Text('How Billing Works',

              style: TextStyle(

                  fontSize: 15,

                  fontWeight: FontWeight.bold,

                  color: Color(0xFF0D1B3E))),

          const SizedBox(height: 12),

          _reminderItem(Icons.shopping_bag_outlined,

              'Platform fee remains pending after each completed order'),

          _reminderItem(Icons.account_balance_wallet_outlined,

              'All unpaid orders keep accumulating'),

          _reminderItem(Icons.upload_file,

              '"Press "Pay Now" — all unpaid orders get locked in one batch'),

          _reminderItem(Icons.lock_outline,

              'Locked orders get billingCycleId set — they won\'t be counted again'),

          _reminderItem(Icons.admin_panel_settings,

              'Admin verifies the receipt'),

          _reminderItem(Icons.check_circle_outline,

              'After verification those orders become "paid" — new cycle begins'),

          _reminderItem(Icons.refresh,

              'On rejection those orders go back to "unpaid" — included in next receipt with new orders'),

        ],

      ),

    );

  }

  Widget _reminderItem(IconData icon, String text) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 10),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Icon(icon, color: kOrange, size: 18),

          const SizedBox(width: 10),

          Expanded(

              child: Text(text,

                  style: const TextStyle(

                      fontSize: 13, color: Colors.black87))),

        ],

      ),

    );

  }

  Widget _buildBottomNav(BuildContext context) {

    return Container(

      decoration: BoxDecoration(

        color: Colors.white,

        boxShadow: [

          BoxShadow(

              color: Colors.black.withOpacity(0.08),

              blurRadius: 12,

              offset: const Offset(0, -3))

        ],

      ),

      child: BottomNavigationBar(

        backgroundColor: Colors.white,

        selectedItemColor: kOrange,

        unselectedItemColor: Colors.grey,

        type: BottomNavigationBarType.fixed,

        currentIndex: 2,

        items: const [

          BottomNavigationBarItem(

              icon: Icon(Icons.home_outlined), label: 'Home'),

          BottomNavigationBarItem(

              icon: Icon(Icons.receipt_outlined), label: 'Orders'),

          BottomNavigationBarItem(

              icon: Icon(Icons.account_balance_wallet_outlined),

              label: 'Billing'),

          BottomNavigationBarItem(

              icon: Icon(Icons.person_outline), label: 'Profile'),

        ],

      ),

    );

  }

}