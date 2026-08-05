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

  // ─── NEW: Admin Payment Details ──────────────────────────────────────
  Map<String, dynamic>? _adminPaymentDetails;
  bool _loadingPaymentDetails = true;

  // ── Countdown timer variables ──────────────────────────────────────
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;
  DateTime? _graceDueTime;
  bool _suspending = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAdminPaymentDetails();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ─── NEW: Load Admin Payment Details from Firestore ──────────────────
  Future<void> _loadAdminPaymentDetails() async {
    setState(() => _loadingPaymentDetails = true);
    try {
      final doc = await _firestore
          .collection('adminSettings')
          .doc('paymentDetails')
          .get();

      if (doc.exists) {
        setState(() {
          _adminPaymentDetails = doc.data();
        });
      } else {
        setState(() {
          _adminPaymentDetails = null;
        });
      }
    } catch (e) {
      debugPrint('Error loading admin payment details: $e');
      setState(() {
        _adminPaymentDetails = null;
      });
    } finally {
      setState(() => _loadingPaymentDetails = false);
    }
  }

  void _startBillingCountdown(DateTime dueTime) {
    _countdownTimer?.cancel();
    _graceDueTime = dueTime;
    final remaining = dueTime.difference(DateTime.now());
    setState(() {
      _remainingTime = remaining.isNegative ? Duration.zero : remaining;
    });

    if (_remainingTime == Duration.zero) {
      _suspendShopIfNeeded();
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final rem = _graceDueTime!.difference(DateTime.now());
      setState(() {
        _remainingTime = rem.isNegative ? Duration.zero : rem;
      });
      if (_remainingTime == Duration.zero) {
        _countdownTimer?.cancel();
        _suspendShopIfNeeded();
      }
    });
  }

  Future<void> _suspendShopIfNeeded() async {
    if (_suspending) return;
    final shopId = _shopData?['id'];
    if (shopId == null) return;
    if ((_shopData?['status'] ?? '') == 'suspended') return;

    _suspending = true;
    try {
      await _firestore.collection('shops').doc(shopId).update({
        'status': 'suspended',
        'warningActive': false,
      });
      if (mounted) {
        setState(() {
          _shopData = {..._shopData!, 'status': 'suspended'};
        });
      }
    } catch (e) {
      debugPrint('Auto-suspend error: $e');
    } finally {
      _suspending = false;
    }
  }

  // ─── Calculate Platform Fee = 5% of orderTotal ─────────────────────
  Future<void> _loadData() async {
    setState(() => _loading = true);

    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

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

    // Fetch all delivered orders for this shop
    final allOrdersSnap = await _firestore
        .collection('orders')
        .where('shopId', isEqualTo: shopId)
        .get();

    // Filter: delivered orders with no billingCycleId (unpaid)
    final unpaidDocs = allOrdersSnap.docs.where((doc) {
      final data = doc.data();
      final isDelivered = (data['status'] ?? '') == 'delivered';
      return isDelivered &&
          (!data.containsKey('billingCycleId') ||
          data['billingCycleId'] == null);
    }).toList();

    // ─── Calculate 5% from orderTotal ──────────────────────────────────
    int pendingFee = 0;
    for (final doc in unpaidDocs) {
      final data = doc.data();
      
      // Get order total from the order document
      num? orderTotal;
      
      // Try different possible field names
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
      
      // Platform Fee = 5% of order total
      if (orderTotal != null && orderTotal > 0) {
        final fee = (orderTotal * 0.05).toInt();
        pendingFee += fee;
      }
    }

    // Check for active billing cycle
    final activeBillingSnap = await _firestore
        .collection('billing')
        .where('shopId', isEqualTo: shopId)
        .where('payment_status', whereIn: ['pending_verification', 'rejected'])
        .limit(1)
        .get();

    Map<String, dynamic>? activeBillingData;
    String? activeBillingDocId;
    String currentShopStatus = (shopDoc.data()['status'] ?? 'verified') as String;

    if (activeBillingSnap.docs.isNotEmpty) {
      activeBillingDocId = activeBillingSnap.docs.first.id;
      activeBillingData = activeBillingSnap.docs.first.data();

      // Update stored fee if different
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

      // Auto suspend check
      if (activeBillingData['payment_status'] == 'rejected') {
        final dueTime = activeBillingData['due_time'];
        if (dueTime != null) {
          final dueDate = (dueTime as Timestamp).toDate();
          if (DateTime.now().isAfter(dueDate) && currentShopStatus != 'suspended') {
            await _firestore.collection('shops').doc(shopId).update({
              'status': 'suspended',
              'warningActive': false,
            });
            currentShopStatus = 'suspended';
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
        'status': currentShopStatus,
      };
      _activeBillingData = activeBillingData;
      _activeBillingDocId = activeBillingDocId;
      _loading = false;
    });

    if (activeBillingData != null &&
        activeBillingData['payment_status'] == 'rejected' &&
        currentShopStatus != 'suspended') {
      final dueTimeRaw = activeBillingData['due_time'];
      if (dueTimeRaw != null) {
        final dueDate = (dueTimeRaw as Timestamp).toDate();
        _startBillingCountdown(dueDate);
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
        // FIX: back arrow was rendering black — made explicit and white.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Billing Dashboard',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadData();
              _loadAdminPaymentDetails();
            },
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadData();
          await _loadAdminPaymentDetails();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShopHeader(),
              const SizedBox(height: 16),
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
              // ─── NEW: Admin Payment Details Card ────────────────────
              _buildAdminPaymentDetailsCard(),
              const SizedBox(height: 20),
              _buildQuickActions(context, fee),
              const SizedBox(height: 20),
              _buildReminderSection(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      // FIX: bottom nav bar removed per request. The rest of the screen's
      // logic (data loading, countdown, suspend flow, actions) is untouched.
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

  // ─── UPDATED: Shows "Platform Fee (5%)" ──────────────────────────
  // FIX: grid cards were overflowing (~5.7px) when a subtitle line was
  // present, because the fixed childAspectRatio didn't leave enough
  // vertical room for icon + value + title + subtitle. Lowered the
  // aspect ratio slightly (taller cells) and swapped the inner
  // spaceBetween layout for a tight, top-aligned Column so the content
  // only takes the height it actually needs — no more, no less.
  Widget _buildSummaryGrid(
      int fee, int orderCount, String monthLabel, String payStatus) {
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
        'title': 'Platform Fee (5%)',
        'value': fee == 0 ? 'Rs. 0' : 'Rs. $fee',
        'icon': Icons.account_balance_wallet_outlined,
        'color': fee == 0 ? Colors.green : kOrange,
        'subtitle': fee > 0 ? '5% of order total' : 'No pending orders',
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
        childAspectRatio: 1.25, // was 1.5 — taller cells so 3-line cards fit
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
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 8),
              Text(c['value'] as String,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: c['color'] as Color)),
              Text(c['title'] as String,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
              if (c.containsKey('subtitle') && c['subtitle'] != null)
                Text(c['subtitle'] as String,
                    style: const TextStyle(
                        fontSize: 9, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  // ─── NEW: Admin Payment Details Card ──────────────────────────────
  Widget _buildAdminPaymentDetailsCard() {
    // Show loading indicator while fetching payment details
    if (_loadingPaymentDetails) {
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
        child: const Row(
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Loading payment details...',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Check if any payment details exist
    final data = _adminPaymentDetails;
    if (data == null || data.values.every((v) => v == null || v == '')) {
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
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No payment details available. Please contact admin.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Build list of available payment details
    final List<Widget> details = [];
    
    void addDetail(String label, String? value, IconData icon) {
      if (value != null && value.isNotEmpty) {
        details.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: kOrange, size: 14),
                const SizedBox(width: 8),
                SizedBox(
                  width: 95,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D1B3E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    addDetail('Account Holder', data['accountHolderName'] as String?, Icons.person_outline);
    addDetail('Bank Name', data['bankName'] as String?, Icons.business_outlined);
    addDetail('Account Number', data['accountNumber'] as String?, Icons.numbers_outlined);
    addDetail('IBAN', data['iban'] as String?, Icons.code_outlined);
    addDetail('JazzCash', data['jazzcashNumber'] as String?, Icons.phone_android_outlined);
    addDetail('Easypaisa', data['easypaisaNumber'] as String?, Icons.phone_iphone_outlined);

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: kOrange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Admin Payment Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D1B3E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          ...details,
          // Show hint that these details are from admin
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade500, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Please send payment to the above account',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              'NearBuy earns 5% commission from each customer order'),
          _reminderItem(Icons.account_balance_wallet_outlined,
              'Platform fee accumulates from all delivered orders'),
          _reminderItem(Icons.upload_file,
              'Press "Upload Receipt" to pay all pending fees in one batch'),
          _reminderItem(Icons.lock_outline,
              'Locked orders get billingCycleId set — they won\'t be counted again'),
          _reminderItem(Icons.admin_panel_settings,
              'Admin verifies the receipt payment'),
          _reminderItem(Icons.check_circle_outline,
              'After verification, orders become "paid" — new cycle begins'),
          _reminderItem(Icons.refresh,
              'On rejection, orders go back to "unpaid" and get included again'),
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
}