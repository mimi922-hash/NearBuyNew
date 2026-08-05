import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'role_selection_screen.dart';
import 'shop_detail_page.dart';
import 'admin_billing_screen.dart';
import 'admin_payment_details_screen.dart';

class AdminDashboard extends StatefulWidget {
  final bool scrollToShops;
  const AdminDashboard({super.key, this.scrollToShops = false});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final user = FirebaseAuth.instance.currentUser;

  // ── Brand colors ──────────────────────────────────────────────
  static const Color _navy = Color(0xFF0B1D35);
  static const Color _navyLight = Color(0xFF0F2545);
  static const Color _navyCard = Color(0xFF112240);
  static const Color _accent = Color(0xFFF4511E);
  static const Color _accentOrange = Color(0xFFFF9500);
  static const Color _white = Colors.white;

  int selectedIndex = 0;
  int _bottomNavIndex = 0;

  // ── Scroll + highlight for Total Shops card ───────────────────
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _totalShopsKey = GlobalKey();
  bool _shopsHighlighted = false;

  // ── Auth ───────────────────────────────────────────────────────
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.scrollToShops) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToShopsCard();
      });
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  // ── Scroll to & highlight Total Shops card ────────────────────
  void _scrollToShopsCard() {
    final ctx = _totalShopsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
    setState(() => _shopsHighlighted = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _shopsHighlighted = false);
    });
  }

  // ── NEW: Navigate to Payment Account Details ──────────────────
  void _openPaymentDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentDetailsScreen(),
      ),
    );
  }

  Future<void> _updateShopStatus(
    String shopId,
    String status, {
    String? reason,
  }) async {
    await FirebaseFirestore.instance.collection('shops').doc(shopId).update({
      'status': status,
      'rejection_reason': status == "rejected" ? reason ?? "" : "",
    });
  }

  Stream<int> _count(String collection, {String? status}) {
    Query ref = FirebaseFirestore.instance.collection(collection);
    if (status != null) ref = ref.where('status', isEqualTo: status);
    return ref.snapshots().map((s) => s.docs.length);
  }

  Stream<int> _pendingBillingCount() {
    return FirebaseFirestore.instance
        .collection('billing')
        .where('payment_status', isEqualTo: 'pending_verification')
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ── Dynamic trend calculation ─────────────────────────────────
  Stream<Map<String, dynamic>> _trendStream(
    String collection, {
    String? status,
  }) {
    Query ref = FirebaseFirestore.instance.collection(collection);
    if (status != null) ref = ref.where('status', isEqualTo: status);

    return ref.snapshots().map((snap) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));

      int todayCount = 0;
      int yesterdayCount = 0;

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final raw = data['created_at'];
        DateTime? createdAt;
        if (raw is Timestamp) {
          createdAt = raw.toDate();
        } else if (raw is String) {
          createdAt = DateTime.tryParse(raw);
        }

        if (createdAt != null) {
          if (createdAt.isAfter(todayStart)) {
            todayCount++;
          } else if (createdAt.isAfter(yesterdayStart) &&
              createdAt.isBefore(todayStart)) {
            yesterdayCount++;
          }
        }
      }

      double changePercent = 0;
      bool isUp = true;
      if (yesterdayCount > 0) {
        changePercent =
            ((todayCount - yesterdayCount) / yesterdayCount) * 100;
        isUp = changePercent >= 0;
      } else if (todayCount > 0) {
        changePercent = 100;
        isUp = true;
      }

      return {
        'total': snap.docs.length,
        'percent': changePercent.abs(),
        'isUp': isUp,
        'todayCount': todayCount,
        'yesterdayCount': yesterdayCount,
      };
    });
  }

  // ── Animated counter ──────────────────────────────────────────
  Widget _animatedCount(int value, {Color color = _white}) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      builder: (context, val, _) => Text(
        val.toString(),
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ── Stat card with dynamic trend ──────────────────────────────
  Widget _statCard(
    String title,
    IconData icon,
    Color iconBg,
    String collection, {
    String? status,
  }) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _trendStream(collection, status: status),
      builder: (context, snap) {
        final total = snap.data?['total'] as int? ?? 0;
        final percent = snap.data?['percent'] as double? ?? 0;
        final isUp = snap.data?['isUp'] as bool? ?? true;
        final todayCount = snap.data?['todayCount'] as int? ?? 0;
        final yesterdayCount = snap.data?['yesterdayCount'] as int? ?? 0;

        String trendLabel;
        Color trendColor;

        if (!snap.hasData) {
          trendLabel = 'Loading...';
          trendColor = _white.withOpacity(0.4);
        } else if (yesterdayCount == 0 && todayCount == 0) {
          trendLabel = 'No data today';
          trendColor = _white.withOpacity(0.4);
        } else if (yesterdayCount == 0 && todayCount > 0) {
          trendLabel = '+$todayCount new today';
          trendColor = Colors.greenAccent;
        } else {
          trendLabel =
              '${percent.toStringAsFixed(1)}% vs yesterday';
          trendColor =
              isUp ? Colors.greenAccent : Colors.redAccent;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _navyCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconBg, size: 22),
              ),
              const SizedBox(height: 12),
              _animatedCount(total),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: _white.withOpacity(0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (snap.hasData &&
                      !(yesterdayCount == 0 && todayCount == 0))
                    Icon(
                      isUp
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 11,
                      color: trendColor,
                    ),
                  if (snap.hasData &&
                      !(yesterdayCount == 0 && todayCount == 0))
                    const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      trendLabel,
                      style:
                          TextStyle(color: trendColor, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Billing banner ────────────────────────────────────────────
  // ── FIXED: Changed "Total Balance PKR 0" to "Billings" ──────
  Widget _billingBanner() {
    return StreamBuilder<int>(
      stream: _pendingBillingCount(),
      builder: (context, snap) {
        final pending = snap.data ?? 0;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AdminBillingScreen()),
          ),
          child: Container(
            margin:
                const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _navyCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: _accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Platform Billing',
                        style: TextStyle(
                          color: _white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // ── FIXED: Changed to "Billings" ──
                      const Text(
                        'Billings',
                        style: TextStyle(
                          color: _white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (pending > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        margin:
                            const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color:
                              _accentOrange.withOpacity(0.2),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$pending pending',
                          style: const TextStyle(
                            color: _accentOrange,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'View Payments ›',
                        style: TextStyle(
                          color: _white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────
  String _currentStatus() {
    if (selectedIndex == 0) return "pending";
    if (selectedIndex == 1) return "verified";
    return "rejected";
  }

  Widget _tabBar() {
    final tabs = ['Pending', 'Verified', 'Rejected'];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        final pendingCount = snap.data?.docs.length ?? 0;

        return Container(
          margin:
              const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _navyCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final active = selectedIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () =>
                      setState(() => selectedIndex = i),
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        vertical: 9),
                    decoration: BoxDecoration(
                      color: active
                          ? _accent
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(
                          tabs[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active
                                ? _white
                                : _white.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (i == 0 &&
                            pendingCount > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1),
                            decoration: BoxDecoration(
                              color: active
                                  ? _white.withOpacity(0.25)
                                  : _accent.withOpacity(0.25),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$pendingCount',
                              style: TextStyle(
                                color: active
                                    ? _white
                                    : _accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ── Shop list ─────────────────────────────────────────────────
  Widget _shopList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .where('status', isEqualTo: _currentStatus())
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child:
                  CircularProgressIndicator(color: _accent),
            ),
          );
        }

        final shops = snap.data!.docs;
        if (shops.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                "No ${_currentStatus()} shops",
                style: TextStyle(
                    color: _white.withOpacity(0.4)),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: shops.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding:
              const EdgeInsets.symmetric(horizontal: 16),
          itemBuilder: (context, i) {
            final shop = shops[i];
            final data =
                shop.data() as Map<String, dynamic>;
            final billingStatus =
                data['billing_status'] ?? 'active';
            final status = data['status'] ?? 'pending';

            Color statusColor;
            switch (status) {
              case 'verified':
                statusColor = Colors.greenAccent;
                break;
              case 'rejected':
                statusColor = Colors.redAccent;
                break;
              default:
                statusColor = _accentOrange;
            }

            return GestureDetector(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopDetailPage(
                      shopId: shop.id,
                      shopData: data,
                      onStatusChange: (String st,
                              {String? reason}) async {
                        await _updateShopStatus(
                            shop.id, st,
                            reason: reason);
                      },
                    ),
                  ),
                );
                if (result == true) setState(() {});
              },
              child: Container(
                margin:
                    const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _navyCard,
                  borderRadius:
                      BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.15),
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.store,
                          color: _accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['shop_name'] ??
                                      'Unnamed Shop',
                                  style: const TextStyle(
                                    color: _white,
                                    fontWeight:
                                        FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (billingStatus ==
                                  'suspended')
                                Container(
                                  padding: const EdgeInsets
                                      .symmetric(
                                      horizontal: 7,
                                      vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red
                                        .withOpacity(0.2),
                                    borderRadius:
                                        BorderRadius
                                            .circular(6),
                                  ),
                                  child: const Text(
                                    'SUSPENDED',
                                    style: TextStyle(
                                      color:
                                          Colors.redAccent,
                                      fontSize: 9,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            data['shop_category'] ?? '',
                            style: TextStyle(
                              color:
                                  _white.withOpacity(0.45),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            data['shop_location'] ?? '',
                            style: TextStyle(
                              color:
                                  _white.withOpacity(0.35),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor
                                .withOpacity(0.15),
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Icon(
                          Icons.chevron_right,
                          color: _white.withOpacity(0.3),
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Bottom nav (4 items) ──────────────────────────────────────
  Widget _bottomNav() {
    final items = [
      {
        'icon': Icons.dashboard_rounded,
        'label': 'Dashboard',
      },
      {
        'icon': Icons.store_rounded,
        'label': 'Shops',
      },
      {
        'icon': Icons.account_balance_wallet_rounded,
        'label': 'Billing',
      },
      {
        'icon': Icons.bar_chart_rounded,
        'label': 'Reports',
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: _navyCard,
        border: Border(
            top: BorderSide(
                color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final active = _bottomNavIndex == i;
          return GestureDetector(
            onTap: () {
              setState(() => _bottomNavIndex = i);
              switch (i) {
                case 0:
                  // Already on dashboard — no navigation needed
                  break;
                case 1:
                  // Scroll to and highlight the Total Shops card
                  _scrollToShopsCard();
                  break;
                case 2:
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const AdminBillingScreen()),
                  ).then((_) =>
                      setState(() => _bottomNavIndex = 0));
                  break;
                case 3:
                  // Reports page — to be built later
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                          'Reports coming soon!'),
                      backgroundColor: _navyCard,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10)),
                    ),
                  );
                  Future.delayed(
                      const Duration(milliseconds: 300),
                      () =>
                          setState(() => _bottomNavIndex = 0));
                  break;
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  items[i]['icon'] as IconData,
                  color: active
                      ? _accent
                      : _white.withOpacity(0.4),
                  size: 22,
                ),
                const SizedBox(height: 3),
                Text(
                  items[i]['label'] as String,
                  style: TextStyle(
                    color: active
                        ? _accent
                        : _white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: active
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting = 'Good morning';
    if (hour >= 12 && hour < 17) greeting = 'Good afternoon';
    if (hour >= 17) greeting = 'Good evening';

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu,
                color: _white.withOpacity(0.8)),
            onPressed: () =>
                Scaffold.of(ctx).openDrawer(),
          ),
        ),
        // ── UPDATED: 3-dot menu with Payment Account Details ──
        actions: [
          // ── NEW: 3-dot menu with Payment Account Details ──
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: _white.withOpacity(0.8)),
            color: _navyCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'profile') {
                // Profile/Edit Profile - you can add this later
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Profile editing coming soon!'),
                    backgroundColor: _navyCard,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              } else if (value == 'payment_details') {
                _openPaymentDetails();
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        color: _white.withOpacity(0.7), size: 20),
                    const SizedBox(width: 12),
                    Text('Profile / Edit Profile',
                        style: TextStyle(
                            color: _white.withOpacity(0.9),
                            fontSize: 14)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'payment_details',
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        color: _accentOrange, size: 20),
                    const SizedBox(width: 12),
                    Text('Payment Account Details',
                        style: TextStyle(
                            color: _white.withOpacity(0.9),
                            fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout,
                        color: Colors.redAccent, size: 20),
                    const SizedBox(width: 12),
                    Text('Logout',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          // ── Notification icon ──────────────────────────────
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: Icon(
                    Icons.notifications_none_rounded,
                    color: _white.withOpacity(0.8)),
                onPressed: () {},
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: _navyCard,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration:
                  const BoxDecoration(color: _navy),
              currentAccountPicture: Container(
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: _accent, width: 2),
                ),
                child: const Icon(Icons.person,
                    color: _white, size: 28),
              ),
              accountName: Text(
                user?.displayName ?? "Admin",
                style: const TextStyle(
                    color: _white,
                    fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(
                user?.email ?? "",
                style: TextStyle(
                    color: _white.withOpacity(0.6)),
              ),
            ),
            ListTile(
              leading: const Icon(
                  Icons.account_balance_wallet,
                  color: _accentOrange),
              title: const Text('Platform Billing',
                  style: TextStyle(color: _white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const AdminBillingScreen()),
                );
              },
            ),
            // ── NEW: Payment Account Details in drawer ──
            ListTile(
              leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: _accentOrange),
              title: const Text('Payment Account Details',
                  style: TextStyle(color: _white)),
              onTap: () {
                Navigator.pop(context);
                _openPaymentDetails();
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout,
                  color: Colors.redAccent),
              title: const Text("Logout",
                  style:
                      TextStyle(color: Colors.redAccent)),
              onTap: _logout,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // ── Greeting ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          20, 4, 20, 0),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting,',
                            style: TextStyle(
                              color:
                                  _white.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              // "Near" in white, "Buy" in orange
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Near',
                                      style: TextStyle(
                                        color: _white,
                                        fontSize: 24,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Buy',
                                      style: TextStyle(
                                        color:
                                            _accent,
                                        fontSize: 24,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('👋',
                                  style: TextStyle(
                                      fontSize: 22)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5),
                            decoration: BoxDecoration(
                              color: _navyCard,
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: _white
                                        .withOpacity(0.5)),
                                const SizedBox(width: 5),
                                Text(
                                  '${now.day} ${_monthName(now.month)} ${now.year}  ▾',
                                  style: TextStyle(
                                    color: _white
                                        .withOpacity(0.65),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Overview title ────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overview',
                            style: TextStyle(
                              color: _white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'View Reports ›',
                            style: TextStyle(
                              color: _accent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Stat grid ─────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      child: Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _statCard(
                                    'Total Users',
                                    Icons.people_alt_rounded,
                                    Colors.blueAccent,
                                    'users',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AnimatedContainer(
                                    key: _totalShopsKey,
                                    duration: const Duration(milliseconds: 400),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _shopsHighlighted
                                            ? _accentOrange
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: _statCard(
                                      'Total Shops',
                                      Icons.store_rounded,
                                      _accent,
                                      'shops',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _statCard(
                                    'Verified Shops',
                                    Icons.verified_rounded,
                                    Colors.greenAccent,
                                    'shops',
                                    status: 'verified',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _statCard(
                                    'Pending Shops',
                                    Icons
                                        .hourglass_top_rounded,
                                    _accentOrange,
                                    'shops',
                                    status: 'pending',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Billing Banner ────────────────────
                    _billingBanner(),

                    const SizedBox(height: 20),

                    // ── Shop Verification header ──────────
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20),
                      child: Text(
                        'Shop Verification',
                        style: TextStyle(
                          color: _white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Tab bar ───────────────────────────
                    _tabBar(),

                    const SizedBox(height: 12),

                    // ── Shop list ─────────────────────────
                    _shopList(),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Bottom nav ────────────────────────────────
            _bottomNav(),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[m];
  }
}