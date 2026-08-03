import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'role_selection_screen.dart';
import 'shop_registration_page.dart';
import 'add_product_page.dart';
import 'shop_reviews_screen.dart';
import 'shopkeeper_orders_screen.dart';
import 'shopkeeper_billing_screen.dart';

class ShopkeeperDashboard extends StatefulWidget {
  const ShopkeeperDashboard({super.key});

  @override
  State<ShopkeeperDashboard> createState() => _ShopkeeperDashboardState();
}

class _ShopkeeperDashboardState extends State<ShopkeeperDashboard>
    with SingleTickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  bool _loading = true;
  bool _isUploading = false;
  Map<String, dynamic>? _shopData;
  String? _shopId;
  String? _profileImageUrl;
  String? _shopkeeperName;
  String? _ownerContact;
  int _pendingOrdersCount = 0;
  StreamSubscription<QuerySnapshot>? _ordersSubscription;

  // ── Billing state ─────────────────────────────────────────────────
  String _billingStatus = 'active';
  String _billingPaymentStatus = 'unpaid';
  DateTime? _graceDueTime;
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;

  // ── Revenue state ─────────────────────────────────────────────────
  double _totalRevenue = 0.0;

  StreamSubscription<DocumentSnapshot>? _billingSubscription;
  StreamSubscription<DocumentSnapshot>? _shopLiveSubscription;
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  final GlobalKey _productListKey = GlobalKey();

  // ── Brand Colors ──────────────────────────────────────────────────
  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color lightNavy    = Color(0xFF1A3A5C);
  static const Color bgColor      = Color(0xFFF0F3F8);
  static const Color cardWhite    = Color(0xFFFFFFFF);
  static const Color dividerColor = Color(0xFFEAEEF4);
  static const Color orangeLight  = Color(0xFFFFF0E8);
  static const Color navyLight    = Color(0xFFE8EEF5);
  static const Color greenLight   = Color(0xFFE8F5EE);
  static const Color yellowLight  = Color(0xFFFFFBE8);
  static const Color redLight     = Color(0xFFFFECEC);
  static const Color accentGreen  = Color(0xFF2E9E6B);
  static const Color accentYellow = Color(0xFFF5A623);
  static const Color accentRed    = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _subscribeToUserDoc();
    _checkShop();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _billingSubscription?.cancel();
    _shopLiveSubscription?.cancel();
    _userDocSubscription?.cancel();
    _countdownTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _subscribeToUserDoc() {
    if (user == null) return;
    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _profileImageUrl = data['profile_image'];
          _ownerContact    = data['phone'];
          _shopkeeperName  = data['display_name'] ??
              user!.displayName ??
              (user!.email?.split('@').first ?? 'Shopkeeper');
        });
      } else {
        setState(() {
          _shopkeeperName =
              user!.displayName ?? user!.email?.split('@').first ?? 'Shopkeeper';
        });
      }
    });
  }

  void _subscribeToShopLive(String shopId) {
    _shopLiveSubscription?.cancel();
    _shopLiveSubscription = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .snapshots()
        .listen((snap) {
      if (mounted && snap.exists) {
        final d = snap.data() as Map<String, dynamic>;
        setState(() {
          _shopData = d;
          final shopStatus = d['status'] ?? 'verified';
          _billingStatus = shopStatus == 'suspended' ? 'suspended' : 'active';
        });
      }
    });
  }

  void _subscribeToPendingOrders(String shopId) {
    _ordersSubscription?.cancel();
    _ordersSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('shopId', isEqualTo: shopId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (mounted)
        setState(() => _pendingOrdersCount = snapshot.docs.length);
    });
  }

  void _subscribeToBillingStatus(String shopId) {
    final now = DateTime.now();
    final docId = '${shopId}_${now.year}_${now.month}';
    _billingSubscription?.cancel();
    _billingSubscription = FirebaseFirestore.instance
        .collection('billing')
        .doc(docId)
        .snapshots()
        .listen((snap) {
      if (mounted && snap.exists) {
        final d = snap.data() as Map<String, dynamic>;
        final status = d['payment_status'] ?? 'unpaid';
        final dueTimeRaw = d['due_time'];
        setState(() {
          _billingPaymentStatus = status;
          if (status == 'rejected' && dueTimeRaw != null) {
            _graceDueTime = (dueTimeRaw as Timestamp).toDate();
            _remainingTime = _graceDueTime!.difference(DateTime.now());
            if (_remainingTime.isNegative) _remainingTime = Duration.zero;
            _startCountdown();
          } else {
            _graceDueTime = null;
            _remainingTime = Duration.zero;
            _countdownTimer?.cancel();
          }
        });
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _graceDueTime!.difference(DateTime.now());
      setState(() {
        _remainingTime = remaining.isNegative ? Duration.zero : remaining;
      });
      if (_remainingTime == Duration.zero) {
        _countdownTimer?.cancel();
      }
    });
  }

  // ── Fetch total revenue from delivered orders ─────────────────────
  Future<void> _fetchTotalRevenue(String shopId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: 'delivered')
          .get();
      double total = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        total += ((data['totalAmount'] ?? data['total_amount'] ?? 0) as num)
            .toDouble();
      }
      if (mounted) setState(() => _totalRevenue = total);
    } catch (_) {}
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _isUploading = true);
      try {
        var request = http.MultipartRequest('POST',
            Uri.parse('https://api.cloudinary.com/v1_1/dxzaqavfj/image/upload'));
        request.fields['upload_preset'] = 'nearbuy_preset';
        request.files
            .add(await http.MultipartFile.fromPath('file', pickedFile.path));
        var response = await request.send();
        if (response.statusCode == 200) {
          var jsonRes = jsonDecode(
              String.fromCharCodes(await response.stream.toBytes()));
          String url = jsonRes['secure_url'];
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user?.uid)
              .set({'profile_image': url}, SetOptions(merge: true));
          if (mounted) {
            _showSnack('Profile photo updated!', accentGreen);
          }
        }
      } catch (e) {
        debugPrint('Upload Error: $e');
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  void _checkShop() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('shops')
        .where('owner_email', isEqualTo: user?.email)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      _shopData = snapshot.docs.first.data();
      _shopId = snapshot.docs.first.id;
      final initialShopStatus = _shopData!['status'] ?? 'verified';
      _billingStatus = initialShopStatus == 'suspended' ? 'suspended' : 'active';
      _subscribeToShopLive(_shopId!);
      if (_shopData!['status'] == 'verified') {
        _subscribeToPendingOrders(_shopId!);
        _subscribeToBillingStatus(_shopId!);
        _fetchTotalRevenue(_shopId!);
      }
    }
    setState(() => _loading = false);
  }

  void _clearNotification() {
    if (_shopId != null) {
      FirebaseFirestore.instance
          .collection('shops')
          .doc(_shopId)
          .update({'notification': ''});
      setState(() => _shopData!['notification'] = '');
    }
  }

  void _logout() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out',
            style: TextStyle(
                color: primaryNavy,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: accentOrange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RoleSelectionScreen()),
                    (r) => false);
              }
            },
            child: const Text('Sign Out',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _openProfilePage() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _ProfilePage(
                  user: user,
                  profileImageUrl: _profileImageUrl,
                  shopkeeperName: _shopkeeperName,
                  ownerContact: _ownerContact,
                  shopData: _shopData,
                  shopId: _shopId,
                  onImageUpdated: (url) =>
                      setState(() => _profileImageUrl = url),
                )));
  }

  void _openShopTimingPage() {
    if (_shopId == null) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ShopTimingPage(shopId: _shopId!)));
  }

  // ══════════════════════════════════════════════════════════════════
  //  UI WIDGETS
  // ══════════════════════════════════════════════════════════════════

  Widget _sectionLabel(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: orangeLight,
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: accentOrange, size: 15),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: primaryNavy,
                letterSpacing: 0.2)),
      ]),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: primaryNavy.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }

  // ── FIXED: GREETING HEADER with overflow protection ──────────────
  Widget _greetingHeader() {
    final shopStatus = _shopData?['status'] ?? '';
    final isVerified = shopStatus == 'verified';

    final shopHours = _shopData?['shop_hours'] as Map<String, dynamic>?;
    final todayKey = _weekdayKey(DateTime.now().weekday);
    final dayData = shopHours?[todayKey] as Map<String, dynamic>?;
    final bool isOpen = dayData?['is_open'] == true;
    final String openTime = dayData?['open_time'] ?? '';
    final String closeTime = dayData?['close_time'] ?? '';
    final todayName = [
      '', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday', 'Sunday'
    ][DateTime.now().weekday];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1F3C), Color(0xFF1A3A6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: primaryNavy.withOpacity(0.22),
              blurRadius: 18,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row: avatar + name + verified badge ──────────────
          Row(
            children: [
              GestureDetector(
                onTap: _openProfilePage,
                child: Stack(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                          colors: [accentOrange, accentYellow]),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _profileImageUrl != null
                          ? Image.network(_profileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person, color: accentOrange, size: 24))
                          : Container(
                              color: accentOrange.withOpacity(0.2),
                              child: const Icon(Icons.person,
                                  color: accentOrange, size: 24)),
                    ),
                  ),
                  if (_isUploading)
                    const Positioned.fill(
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: accentOrange.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.store_outlined,
                                color: accentOrange, size: 10),
                            SizedBox(width: 3),
                            Text('Shopkeeper',
                                style: TextStyle(
                                    color: accentOrange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Hello, ${_shopkeeperName ?? 'Shopkeeper'} 👋',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EC878).withOpacity(0.18),
                              border: Border.all(
                                  color: const Color(0xFF2EC878)
                                      .withOpacity(0.4)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                    width: 4,
                                    height: 4,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFF2EC878),
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 3),
                                const Text('Verified',
                                    style: TextStyle(
                                        color: Color(0xFF2EC878),
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_shopData?['shop_name'] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _shopData!['shop_name'],
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Divider(color: Colors.white.withOpacity(0.12), height: 1),
          const SizedBox(height: 10),

          // ── Detail rows with smaller text ───────────────────
          Row(
            children: [
              Expanded(
                child: _heroDetailRow(
                  Icons.location_on_outlined,
                  _shopData?['shop_location'] ?? 'No address',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _heroDetailRow(
                  Icons.phone_outlined,
                  _ownerContact ??
                      _shopData?['owner_contact'] ??
                      'No contact',
                  highlight: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _heroDetailRow(
                  Icons.category_outlined,
                  _shopData?['shop_category'] ?? '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _heroDetailRow(
              Icons.badge_outlined,
              'Reg: ${_shopData?['registration_no'] ?? '—'}'),

          // ── Today timing row ──────────────────────────────────
          if (shopHours != null && dayData != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isOpen
                    ? const Color(0xFF2EC878).withOpacity(0.12)
                    : Colors.white.withOpacity(0.07),
                border: Border.all(
                  color: isOpen
                      ? const Color(0xFF2EC878).withOpacity(0.35)
                      : Colors.white.withOpacity(0.15),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isOpen
                        ? Icons.access_time_outlined
                        : Icons.store_mall_directory_outlined,
                    color: isOpen
                        ? const Color(0xFF2EC878)
                        : Colors.white54,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isOpen
                          ? '$todayName: Open $openTime – $closeTime'
                          : '$todayName: Closed Today',
                      style: TextStyle(
                          color: isOpen
                              ? const Color(0xFF2EC878)
                              : Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  GestureDetector(
                    onTap: _openShopTimingPage,
                    child: Icon(Icons.edit_outlined,
                        color: Colors.white.withOpacity(0.4), size: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroDetailRow(IconData icon, String text,
      {bool highlight = false}) {
    return Row(
      children: [
        Icon(icon,
            color: highlight
                ? accentOrange
                : Colors.white.withOpacity(0.45),
            size: 11),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                color: highlight
                    ? accentOrange
                    : Colors.white.withOpacity(0.65),
                fontSize: 10,
                fontWeight:
                    highlight ? FontWeight.w600 : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  // ── FIXED: STATS ROW with responsive chips ──────────────────────
  Widget _statsRow() {
    if (_shopId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(_shopId)
          .collection('products')
          .snapshots(),
      builder: (context, snapshot) {
        final int totalProducts = snapshot.data?.docs.length ?? 0;
        final int outOfStock = snapshot.hasData
            ? snapshot.data!.docs
                .where((d) =>
                    (d.data() as Map<String, dynamic>)['out_of_stock'] ==
                    true)
                .length
            : 0;
        
        // ── Calculate low stock (quantity > 0 and <= 5) ──
        final int lowStockCount = snapshot.hasData
            ? snapshot.data!.docs
                .where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final int quantity = data['quantity'] ?? 0;
                  return quantity > 0 && quantity <= 5 && data['out_of_stock'] != true;
                })
                .length
            : 0;

        return Column(
          children: [
            // ── FIXED: Responsive chips with smaller padding ──
            Row(children: [
              Expanded(
                child: _statChip(
                  icon: Icons.pending_actions_outlined,
                  value: '$_pendingOrdersCount',
                  label: 'Pending',
                  color: accentOrange,
                  bg: orangeLight,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ShopkeeperOrdersScreen(shopId: _shopId!))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statChip(
                  icon: Icons.inventory_2_outlined,
                  value: '$totalProducts',
                  label: 'Total',
                  color: primaryNavy,
                  bg: navyLight,
                  onTap: () {
                    if (_productListKey.currentContext != null) {
                      Scrollable.ensureVisible(
                          _productListKey.currentContext!,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statChip(
                  icon: Icons.warning_amber_rounded,
                  value: '$lowStockCount',
                  label: 'Low Stock',
                  color: accentYellow,
                  bg: yellowLight,
                  onTap: () {
                    if (_productListKey.currentContext != null) {
                      Scrollable.ensureVisible(
                          _productListKey.currentContext!,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut);
                    }
                  },
                ),
              ),
            ]),

            const SizedBox(height: 10),

            // ── Total Revenue box ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cardWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: accentGreen.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: accentGreen.withOpacity(0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: greenLight,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.trending_up_rounded,
                        color: accentGreen, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rs. ${_totalRevenue.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: accentGreen,
                              fontWeight: FontWeight.w800,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text('Total Revenue',
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: greenLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: accentGreen.withOpacity(0.3)),
                    ),
                    child: const Text('EARNED',
                        style: TextStyle(
                            color: accentGreen,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3)),
                  ),
                ],
              ),
            ),

            // ── Pending fee box ───────────────────────────────
            if ((_shopData?['pending_fee'] ?? 0) > 0) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ShopkeeperBillingScreen(shopId: _shopId!))),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cardWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: accentOrange.withOpacity(0.35),
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: accentOrange.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                            color: orangeLight,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: accentOrange,
                            size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rs. ${_shopData!['pending_fee']} Pending',
                              style: const TextStyle(
                                  color: accentOrange,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_shopData!['unpaid_order_count'] ?? 0} unpaid orders',
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      _payStatusBadge(),
                    ],
                  ),
                ),
              ),
            ],

            // ── Out of stock box ──────────────────────────────
            if (outOfStock > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: redLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: accentRed.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(
                          Icons.remove_shopping_cart_outlined,
                          color: accentRed,
                          size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$outOfStock Out of Stock',
                            style: const TextStyle(
                                color: accentRed,
                                fontWeight: FontWeight.w700,
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$outOfStock of $totalProducts unavailable',
                            style: TextStyle(
                                color: Colors.red.shade400,
                                fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: accentRed.withOpacity(0.35)),
                      ),
                      child: Text('$outOfStock',
                          style: TextStyle(
                              color: accentRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Payment status badge helper ───────────────────────────────────
  Widget _payStatusBadge() {
    final ps = (_billingPaymentStatus) as String;
    Color color;
    String label;
    if (ps == 'rejected') {
      color = accentRed;
      label = 'REJECTED';
    } else if (ps == 'pending_verification') {
      color = accentYellow;
      label = 'IN REVIEW';
    } else {
      color = accentOrange;
      label = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3)),
    );
  }

  // ── FIXED: Stat chip with responsive sizing ──────────────────────
  Widget _statChip({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color bg,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: color),
                      overflow: TextOverflow.ellipsis),
                  Text(label,
                      style: TextStyle(
                          fontSize: 9,
                          color: color.withOpacity(0.75),
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationBanner() {
    final notif = _shopData?['notification'] ?? '';
    if (notif.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: yellowLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentYellow.withOpacity(0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.notifications_active_outlined,
            color: accentYellow, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(notif,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF7A5700)),
                overflow: TextOverflow.ellipsis,
                maxLines: 2)),
        GestureDetector(
          onTap: _clearNotification,
          child: const Icon(Icons.close, size: 16, color: Colors.grey),
        )
      ]),
    );
  }

  // ── Grace period countdown banner ─────────────────────────────────
  Widget _gracePeriodBanner() {
    if (_billingPaymentStatus != 'rejected') return const SizedBox.shrink();
    if (_remainingTime == Duration.zero && _graceDueTime == null) {
      return const SizedBox.shrink();
    }
    final mins = _remainingTime.inMinutes;
    final secs = _remainingTime.inSeconds % 60;
    final expired = _remainingTime == Duration.zero;
    final timeStr = expired
        ? 'Expired!'
        : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6F00), width: 1.2),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: const BoxDecoration(
              color: Color(0xFFFF6F00), shape: BoxShape.circle),
          child: const Icon(Icons.timer_outlined,
              color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Receipt rejected — upload again',
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                expired
                    ? 'Shop will be suspended. Go to billing.'
                    : 'Shop suspended in:',
                style: const TextStyle(
                    color: Color(0xFFBF360C), fontSize: 10),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: expired
                ? const Color(0xFFB71C1C)
                : const Color(0xFFFF6F00),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            timeStr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _suspendedBanner() {
    if (_billingStatus != 'suspended') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: redLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF5350)),
      ),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
                color: accentRed, shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 14)),
        const SizedBox(width: 10),
        const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Shop Suspended',
                  style: TextStyle(
                      color: accentRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              Text(
                  'Upload correct receipt to reactivate.',
                  style: TextStyle(
                      color: Color(0xFFB71C1C), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
            ])),
      ]),
    );
  }

  // ── QUICK ACTIONS ────────────────────────────────────────────────────
  Widget _quickActions() {
    final qs = _shopData?['status'] ?? '';
    if (qs != 'verified' && qs != 'suspended') return const SizedBox.shrink();
    final isSuspended = _billingStatus == 'suspended';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('Quick Actions', Icons.bolt_outlined),
      _actionCard(
        icon: Icons.shopping_bag_outlined,
        title: 'Manage Orders',
        subtitle: _pendingOrdersCount > 0
            ? '$_pendingOrdersCount orders need attention'
            : 'No pending orders',
        color: accentOrange,
        bg: orangeLight,
        badge: _pendingOrdersCount,
        onTap: isSuspended
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        ShopkeeperOrdersScreen(shopId: _shopId!))),
        isDisabled: isSuspended,
      ),
      const SizedBox(height: 10),
      _actionCard(
        icon: Icons.rate_review_outlined,
        title: 'Customer Reviews',
        subtitle: 'See what customers are saying',
        color: primaryNavy,
        bg: navyLight,
        onTap: isSuspended
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ShopReviewsPage(shopId: _shopId!))),
        isDisabled: isSuspended,
      ),
      const SizedBox(height: 10),
      _actionCard(
        icon: Icons.schedule_outlined,
        title: 'Shop Timings',
        subtitle: 'Set weekly hours',
        color: const Color(0xFF7B5EA7),
        bg: const Color(0xFFF3EEF9),
        onTap: isSuspended ? null : _openShopTimingPage,
        isDisabled: isSuspended,
      ),
      const SizedBox(height: 10),
      _billingActionCard(),
      const SizedBox(height: 14),
    ]);
  }

  Widget _billingActionCard() {
    final Color color = _billingPaymentStatus == 'paid'
        ? accentGreen
        : _billingPaymentStatus == 'pending_verification'
            ? accentYellow
            : accentRed;
    final Color bg = _billingPaymentStatus == 'paid'
        ? greenLight
        : _billingPaymentStatus == 'pending_verification'
            ? yellowLight
            : redLight;

    String subtitle;
    if (_billingPaymentStatus == 'rejected') {
      if (_remainingTime > Duration.zero) {
        final m = _remainingTime.inMinutes.toString().padLeft(2, '0');
        final s =
            (_remainingTime.inSeconds % 60).toString().padLeft(2, '0');
        subtitle = 'Receipt rejected — $m:$s left ⚠️';
      } else {
        subtitle = 'Grace period expired!';
      }
    } else if (_billingPaymentStatus == 'pending_verification') {
      subtitle = 'Receipt submitted — awaiting verification';
    } else if (_billingPaymentStatus == 'paid') {
      subtitle = 'Payment confirmed ✓';
    } else {
      subtitle = 'Monthly fee due — tap to pay';
    }

    final IconData icon = _billingPaymentStatus == 'paid'
        ? Icons.verified_outlined
        : _billingPaymentStatus == 'pending_verification'
            ? Icons.hourglass_top_outlined
            : Icons.account_balance_wallet_outlined;

    return _actionCard(
      icon: icon,
      title: 'Monthly Billing',
      subtitle: subtitle,
      color: color,
      bg: bg,
      badgeDot: _billingPaymentStatus != 'paid' &&
          _billingPaymentStatus != 'pending_verification',
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ShopkeeperBillingScreen(shopId: _shopId!))),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bg,
    VoidCallback? onTap,
    int badge = 0,
    bool badgeDot = false,
    bool isDisabled = false,
  }) {
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.07),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(11)),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(icon, color: color, size: 18),
              if (badgeDot)
                Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: accentRed,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white, width: 1.5)))),
              if (badge > 0)
                Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                            color: accentOrange,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white, width: 1.5)),
                        child: Text('$badge',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold)))),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: primaryNavy),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ])),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 12, color: color.withOpacity(0.5)),
        ]),
      ),
    );

    if (isDisabled) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            card,
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x73000000),
                child: const Center(
                  child: Text(
                    'Unavailable',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return card;
  }

  Widget _addProductButton() {
    if (_shopId == null || _shopData?['status'] != 'verified')
      return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AddProductPage(shopId: _shopId!))),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [accentOrange, Color(0xFFFF8C42)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: accentOrange.withOpacity(0.28),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: const Row(children: [
          Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
          SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Add New Product',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                Text('List a product in your shop',
                    style: TextStyle(color: Colors.white70, fontSize: 10)),
              ])),
          Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white54, size: 12),
        ]),
      ),
    );
  }

  // ── FIXED: Product list with proper overflow handling ────────────
  Widget _productList() {
    if (_shopId == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(_shopId)
          .collection('products')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(
                color: accentOrange, strokeWidth: 2.5),
          ));
        }
        final products = snapshot.data!.docs;
        if (products.isEmpty) {
          return _card(
            padding:
                const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                    color: orangeLight, shape: BoxShape.circle),
                child: const Icon(Icons.inventory_2_outlined,
                    size: 30, color: accentOrange),
              ),
              const SizedBox(height: 10),
              const Text('No products yet',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: primaryNavy)),
              const SizedBox(height: 4),
              Text('Add your first product.',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ]),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('My Products', Icons.inventory_2_outlined),
            ...products.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final bool isOutOfStock = data['out_of_stock'] == true;
              final int quantity = data['quantity'] ?? 0;
              final bool isLowStock = quantity > 0 && quantity <= 5 && !isOutOfStock;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: cardWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isOutOfStock
                        ? accentRed.withOpacity(0.25)
                        : isLowStock
                            ? accentYellow.withOpacity(0.4)
                            : dividerColor,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: primaryNavy.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: data['image_url'] != null
                            ? Image.network(data['image_url'],
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _productPlaceholder())
                            : _productPlaceholder(),
                      ),
                      if (isOutOfStock)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              color: Colors.black.withOpacity(0.45),
                              alignment: Alignment.center,
                              child: const Text('OUT',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      if (isLowStock && !isOutOfStock)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: accentYellow,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('LOW',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 6,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(data['name'] ?? '',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfStock
                                        ? Colors.grey.shade500
                                        : primaryNavy),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOutOfStock
                                        ? Colors.grey.shade100
                                        : orangeLight,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Rs. ${data['price']}',
                                      style: TextStyle(
                                          color: isOutOfStock
                                              ? Colors.grey.shade400
                                              : accentOrange,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11)),
                                ),
                                if (quantity > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isLowStock
                                          ? yellowLight
                                          : greenLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('Qty: $quantity',
                                        style: TextStyle(
                                            color: isLowStock
                                                ? accentYellow
                                                : accentGreen,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 10)),
                                  ),
                              ],
                            ),
                          ]),
                    ),
                    // ── Edit button ──
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddProductPage(
                              shopId: _shopId!,
                              editProductId: doc.id,
                              editData: data,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOutOfStock 
                              ? redLight 
                              : isLowStock
                                  ? yellowLight
                                  : greenLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: isOutOfStock
                                  ? accentRed.withOpacity(0.3)
                                  : isLowStock
                                      ? accentYellow.withOpacity(0.3)
                                      : accentGreen.withOpacity(0.3)),
                        ),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOutOfStock
                                    ? Icons.inventory_2_outlined
                                    : isLowStock
                                        ? Icons.warning_amber_rounded
                                        : Icons.check_circle_outline,
                                size: 14,
                                color: isOutOfStock 
                                    ? accentRed 
                                    : isLowStock
                                        ? accentYellow
                                        : accentGreen,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isOutOfStock 
                                    ? 'Edit' 
                                    : isLowStock
                                        ? 'Low'
                                        : 'In',
                                style: TextStyle(
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfStock 
                                        ? accentRed 
                                        : isLowStock
                                            ? accentYellow
                                            : accentGreen),
                              ),
                            ]),
                      ),
                    ),
                  ]),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _productPlaceholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
            color: orangeLight, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.image_outlined, color: accentOrange, size: 22),
      );

  Widget _shopStatusSection() {
    if (_shopData == null) {
      return _card(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
                color: orangeLight, shape: BoxShape.circle),
            child: const Icon(Icons.storefront_outlined,
                color: accentOrange, size: 30),
          ),
          const SizedBox(height: 10),
          const Text('No Shop Registered',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: primaryNavy)),
          const SizedBox(height: 4),
          Text('Register your shop to start selling.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: accentOrange,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0),
              icon: const Icon(Icons.add_business_outlined,
                  color: Colors.white, size: 18),
              label: const Text('Register Shop',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ShopRegistrationPage())),
            ),
          ),
        ]),
      );
    }

    final status = _shopData!['status'] ?? 'pending';
    Color statusColor;
    IconData statusIcon;
    String statusText;
    Color statusBg;

    if (status == 'verified') {
      statusColor = accentGreen;
      statusIcon = Icons.verified_rounded;
      statusText = 'Verified';
      statusBg = greenLight;
    } else if (status == 'pending') {
      statusColor = accentYellow;
      statusIcon = Icons.hourglass_top_rounded;
      statusText = 'Pending';
      statusBg = yellowLight;
    } else {
      statusColor = accentRed;
      statusIcon = Icons.cancel_outlined;
      statusText = 'Rejected';
      statusBg = redLight;
    }

    return _card(
      padding: const EdgeInsets.all(0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: primaryNavy,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.store_mall_directory_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_shopData!['shop_name'] ?? 'My Shop',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                      Text(_shopData!['shop_category'] ?? '',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                    ])),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, color: statusColor, size: 10),
                    const SizedBox(width: 3),
                    Text(statusText,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _shopInfoItem(
                      Icons.location_on_outlined,
                      _shopData!['shop_location'] ?? 'No address',
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.phone_outlined,
                        size: 12, color: accentOrange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Contact: ${_ownerContact ?? _shopData!['owner_contact'] ?? 'Not provided'}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ]),
    );
  }

  Widget _shopInfoItem(IconData icon, String text) => Expanded(
        child: Row(children: [
          Icon(icon, size: 12, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1)),
        ]),
      );

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: (color ?? primaryNavy).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color ?? primaryNavy, size: 16),
      ),
      title: Text(label,
          style: TextStyle(
              color: color ?? primaryNavy,
              fontWeight: FontWeight.w600,
              fontSize: 13)),
      trailing: Icon(Icons.arrow_forward_ios,
          size: 11, color: Colors.grey.shade400),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      drawer: Drawer(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24))),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [primaryNavy, lightNavy],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius:
                  BorderRadius.only(bottomRight: Radius.circular(24)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    GestureDetector(
                      onTap: _openProfilePage,
                      child: Stack(children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                  colors: [accentOrange, accentYellow])),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.white,
                            backgroundImage: _profileImageUrl != null
                                ? NetworkImage(_profileImageUrl!)
                                : null,
                            child: _profileImageUrl == null
                                ? const Icon(Icons.person,
                                    color: primaryNavy, size: 28)
                                : null,
                          ),
                        ),
                        if (_isUploading)
                          const Positioned.fill(
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickAndUploadImage,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: accentOrange,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 9),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_shopkeeperName ?? 'Shopkeeper',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                            const SizedBox(height: 2),
                            Text(user?.email ?? '',
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                            if (_ownerContact != null &&
                                _ownerContact!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(_ownerContact!,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1),
                            ],
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: accentOrange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: accentOrange.withOpacity(0.4))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.store_outlined,
                          color: accentOrange, size: 11),
                      SizedBox(width: 4),
                      Text('Shopkeeper',
                          style: TextStyle(
                              color: accentOrange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                _drawerItem(
                    Icons.person_outline, 'My Profile', _openProfilePage),
                if (_shopData?['status'] == 'verified') ...[
                  _drawerItem(Icons.shopping_bag_outlined, 'Orders', () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ShopkeeperOrdersScreen(
                                shopId: _shopId!)));
                  }),
                  _drawerItem(Icons.rate_review_outlined, 'Reviews', () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                ShopReviewsPage(shopId: _shopId!)));
                  }),
                  _drawerItem(Icons.schedule_outlined, 'Shop Timings',
                      _openShopTimingPage),
                  _drawerItem(
                      Icons.account_balance_wallet_outlined, 'Billing',
                      () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ShopkeeperBillingScreen(
                                shopId: _shopId!)));
                  }),
                ],
                const Divider(color: dividerColor, height: 16),
                _drawerItem(
                    Icons.logout_rounded, 'Sign Out', _logout,
                    color: accentRed),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('NearBuy v1.0',
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 9)),
          ),
        ]),
      ),
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded,
                color: Colors.white, size: 24),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: RichText(
          text: const TextSpan(children: [
            TextSpan(
                text: 'Near',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            TextSpan(
                text: 'Buy',
                style: TextStyle(
                    color: accentOrange,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        actions: [
          IconButton(
            icon: Stack(children: [
              const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 22),
              if ((_shopData?['notification'] ?? '').isNotEmpty)
                Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: accentOrange,
                            shape: BoxShape.circle))),
            ]),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _openProfilePage,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: accentOrange.withOpacity(0.2),
                backgroundImage: _profileImageUrl != null
                    ? NetworkImage(_profileImageUrl!)
                    : null,
                child: _profileImageUrl == null
                    ? const Icon(Icons.person,
                        color: accentOrange, size: 16)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: accentOrange, strokeWidth: 3))
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                color: accentOrange,
                onRefresh: () async {
                  _checkShop();
                  if (_shopId != null) _fetchTotalRevenue(_shopId!);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _greetingHeader(),
                        const SizedBox(height: 12),
                        _suspendedBanner(),
                        _gracePeriodBanner(),
                        _notificationBanner(),
                        if (_shopData?['status'] == 'verified') ...[
                          _statsRow(),
                          const SizedBox(height: 12),
                        ],
                        _sectionLabel(
                            'My Shop', Icons.storefront_outlined),
                        _shopStatusSection(),
                        const SizedBox(height: 6),
                        _quickActions(),
                        if (_shopId != null &&
                            _shopData?['status'] == 'verified') ...[
                          _addProductButton(),
                          const SizedBox(height: 12),
                          SizedBox(
                              key: _productListKey,
                              child: _productList()),
                        ],
                      ]),
                ),
              ),
            ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────
  static String _weekdayKey(int weekday) {
    const keys = ['', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return keys[weekday];
  }

  static String _formatDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ══════════════════════════════════════════════════════════════════════════
//  SHOP TIMING PAGE
// ══════════════════════════════════════════════════════════════════════════

class ShopTimingPage extends StatefulWidget {
  final String shopId;
  const ShopTimingPage({super.key, required this.shopId});
  @override
  State<ShopTimingPage> createState() => _ShopTimingPageState();
}

class _ShopTimingPageState extends State<ShopTimingPage> {
  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color lightNavy    = Color(0xFF1A3A5C);
  static const Color bgColor      = Color(0xFFF0F3F8);
  static const Color cardWhite    = Color(0xFFFFFFFF);
  static const Color accentGreen  = Color(0xFF2E9E6B);
  static const Color accentRed    = Color(0xFFE53935);
  static const Color greenLight   = Color(0xFFE8F5EE);
  static const Color redLight     = Color(0xFFFFECEC);
  static const Color orangeLight  = Color(0xFFFFF0E8);

  final List<Map<String, String>> _days = [
    {'key': 'mon', 'label': 'Monday'},
    {'key': 'tue', 'label': 'Tuesday'},
    {'key': 'wed', 'label': 'Wednesday'},
    {'key': 'thu', 'label': 'Thursday'},
    {'key': 'fri', 'label': 'Friday'},
    {'key': 'sat', 'label': 'Saturday'},
    {'key': 'sun', 'label': 'Sunday'},
  ];

  Map<String, Map<String, dynamic>> _hours = {};
  List<Map<String, dynamic>> _closures = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final snap = await FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .get();
    if (snap.exists) {
      final data = snap.data()!;
      final rawHours = data['shop_hours'] as Map<String, dynamic>?;
      final rawClosures = data['temporary_closures'] as List<dynamic>?;
      final Map<String, Map<String, dynamic>> hours = {};
      for (final d in _days) {
        final k = d['key']!;
        if (rawHours != null && rawHours.containsKey(k)) {
          hours[k] = Map<String, dynamic>.from(rawHours[k]);
        } else {
          hours[k] = {
            'is_open': false,
            'open_time': '9:00 AM',
            'close_time': '9:00 PM'
          };
        }
      }
      setState(() {
        _hours = hours;
        _closures = rawClosures != null
            ? rawClosures.map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
        _loading = false;
      });
    } else {
      final Map<String, Map<String, dynamic>> hours = {};
      for (final d in _days) {
        hours[d['key']!] = {
          'is_open': false,
          'open_time': '9:00 AM',
          'close_time': '9:00 PM'
        };
      }
      setState(() {
        _hours = hours;
        _loading = false;
      });
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .update({
        'shop_hours': _hours,
        'temporary_closures': _closures,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Shop timings saved!',
              style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: accentGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('Save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(String dayKey, String field) async {
    final timeStr = _hours[dayKey]![field] as String;
    final isPm = timeStr.toUpperCase().contains('PM');
    final parts =
        timeStr.replaceAll(RegExp(r'[APap][Mm]'), '').trim().split(':');
    int hour = int.parse(parts[0]);
    final minute = parts.length > 1 ? int.parse(parts[1].trim()) : 0;
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    final initial = TimeOfDay(hour: hour, minute: minute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
                primary: accentOrange, onSurface: primaryNavy),
          ),
          child: child!,
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _hours[dayKey]![field] = picked.format(context);
      });
    }
  }

  Future<void> _addTemporaryClosure() async {
    DateTime? selectedDate;
    final TextEditingController reasonCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Temporary Closure',
              style: TextStyle(
                  color: primaryNavy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate:
                      DateTime.now().add(const Duration(days: 365)),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                          primary: accentOrange, onSurface: primaryNavy),
                    ),
                    child: child!,
                  ),
                );
                if (d != null) setD(() => selectedDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: orangeLight,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: accentOrange.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: accentOrange, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    selectedDate == null
                        ? 'Select Date'
                        : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                    style: TextStyle(
                        color: selectedDate == null
                            ? Colors.grey.shade500
                            : primaryNavy,
                        fontWeight: FontWeight.w500,
                        fontSize: 14),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(fontSize: 14, color: primaryNavy),
              decoration: InputDecoration(
                labelText: 'Reason (e.g. Eid, illness)',
                labelStyle: TextStyle(
                    color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.info_outline,
                    color: accentOrange, size: 18),
                filled: true,
                fillColor: orangeLight,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: accentOrange, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: accentOrange,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0),
              onPressed: () {
                if (selectedDate == null) return;
                final dateKey =
                    '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';
                final exists =
                    _closures.any((c) => c['date'] == dateKey);
                if (!exists) {
                  setState(() {
                    _closures.add({
                      'date': dateKey,
                      'reason': reasonCtrl.text.trim(),
                    });
                    _closures.sort((a, b) =>
                        (a['date'] as String)
                            .compareTo(b['date'] as String));
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Shop Timings',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)))
              : TextButton.icon(
                  onPressed: _saveAll,
                  icon: const Icon(Icons.save_outlined,
                      color: accentOrange, size: 18),
                  label: const Text('Save',
                      style: TextStyle(
                          color: accentOrange,
                          fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: accentOrange))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                        'Weekly Hours', Icons.calendar_month_outlined),
                    const SizedBox(height: 12),
                    ..._days.map((d) => _dayRow(d['key']!, d['label']!)),
                    const SizedBox(height: 24),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _sectionHeader('Temporary Closures',
                              Icons.event_busy_outlined),
                          GestureDetector(
                            onTap: _addTemporaryClosure,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                  color: orangeLight,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: accentOrange.withOpacity(0.3))),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add,
                                        color: accentOrange, size: 15),
                                    SizedBox(width: 4),
                                    Text('Add',
                                        style: TextStyle(
                                            color: accentOrange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                            ),
                          ),
                        ]),
                    const SizedBox(height: 12),
                    if (_closures.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardWhite,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          const Icon(Icons.event_available_outlined,
                              color: accentGreen, size: 20),
                          const SizedBox(width: 10),
                          Text('No temporary closures added.',
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13)),
                        ]),
                      )
                    else
                      ..._closures.asMap().entries.map((entry) {
                        final i = entry.key;
                        final c = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: cardWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: accentRed.withOpacity(0.2)),
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: redLight,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.event_busy_outlined,
                                  color: accentRed, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatDateDisplay(c['date']),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: primaryNavy),
                                    ),
                                    if ((c['reason'] ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(c['reason'],
                                          style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  Colors.grey.shade500)),
                                    ],
                                  ]),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() => _closures.removeAt(i));
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    color: redLight,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.delete_outline,
                                    color: accentRed, size: 16),
                              ),
                            ),
                          ]),
                        );
                      }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: accentOrange,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16))),
                        onPressed: _saving ? null : _saveAll,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined,
                                color: Colors.white),
                        label: Text(
                            _saving ? 'Saving...' : 'Save Timings',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                  ]),
            ),
    );
  }

  Widget _dayRow(String key, String label) {
    final data = _hours[key]!;
    final bool isOpen = data['is_open'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isOpen
                ? accentGreen.withOpacity(0.2)
                : Colors.grey.withOpacity(0.15)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: primaryNavy)),
          ),
          Row(children: [
            Text(isOpen ? 'Open' : 'Closed',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isOpen ? accentGreen : Colors.grey.shade400)),
            const SizedBox(width: 8),
            Switch(
              value: isOpen,
              onChanged: (v) =>
                  setState(() => _hours[key]!['is_open'] = v),
              activeColor: accentGreen,
              activeTrackColor: accentGreen.withOpacity(0.3),
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.grey.shade200,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
        ]),
        if (isOpen) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _timeTile('Open', data['open_time'],
                    Icons.wb_sunny_outlined, accentOrange,
                    () => _pickTime(key, 'open_time'))),
            const SizedBox(width: 10),
            Expanded(
                child: _timeTile('Close', data['close_time'],
                    Icons.nights_stay_outlined, primaryNavy,
                    () => _pickTime(key, 'close_time'))),
          ]),
        ],
      ]),
    );
  }

  Widget _timeTile(String label, String time, IconData icon, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color.withOpacity(0.7),
                    fontWeight: FontWeight.w500)),
            Text(time,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ]),
          const Spacer(),
          Icon(Icons.edit_outlined, size: 13, color: color.withOpacity(0.5)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) => Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: orangeLight, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: accentOrange, size: 15),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: primaryNavy,
                letterSpacing: 0.2)),
      ]);

  String _formatDateDisplay(String dateKey) {
    try {
      final d = DateTime.parse(dateKey);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[d.weekday]}, ${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return dateKey;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  PROFILE PAGE
// ══════════════════════════════════════════════════════════════════════════

class _ProfilePage extends StatefulWidget {
  final dynamic user;
  final String? profileImageUrl;
  final String? shopkeeperName;
  final String? ownerContact;
  final Map<String, dynamic>? shopData;
  final String? shopId;
  final ValueChanged<String> onImageUpdated;

  const _ProfilePage({
    required this.user,
    required this.profileImageUrl,
    required this.shopkeeperName,
    required this.ownerContact,
    required this.shopData,
    required this.shopId,
    required this.onImageUpdated,
  });

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color lightNavy    = Color(0xFF1A3A5C);
  static const Color accentGreen  = Color(0xFF2E9E6B);
  static const Color greenLight   = Color(0xFFE8F5EE);
  static const Color orangeLight  = Color(0xFFFFF0E8);
  static const Color bgColor      = Color(0xFFF0F3F8);
  static const Color accentRed    = Color(0xFFE53935);

  String? _localImageUrl;
  bool _isUploading = false;
  bool _editing = false;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _localImageUrl = widget.profileImageUrl;
    _phoneCtrl = TextEditingController(text: widget.ownerContact ?? '');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _isUploading = true);
      try {
        var request = http.MultipartRequest(
            'POST',
            Uri.parse(
                'https://api.cloudinary.com/v1_1/dxzaqavfj/image/upload'));
        request.fields['upload_preset'] = 'nearbuy_preset';
        request.files.add(
            await http.MultipartFile.fromPath('file', pickedFile.path));
        var response = await request.send();
        if (response.statusCode == 200) {
          var jsonRes = jsonDecode(
              String.fromCharCodes(await response.stream.toBytes()));
          String url = jsonRes['secure_url'];
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user?.uid)
              .set({'profile_image': url}, SetOptions(merge: true));
          setState(() => _localImageUrl = url);
          widget.onImageUpdated(url);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Profile photo updated!'),
              backgroundColor: accentGreen,
              behavior: SnackBarBehavior.floating,
            ));
          }
        }
      } catch (e) {
        debugPrint('Upload Error: $e');
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user?.uid)
          .set({
        'phone': _phoneCtrl.text.trim(),
      }, SetOptions(merge: true));
      if (widget.shopId != null && _phoneCtrl.text.trim().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.shopId)
            .update({'owner_contact': _phoneCtrl.text.trim()});
      }
      setState(() => _editing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Contact updated successfully!'),
          backgroundColor: accentGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 270,
            pinned: true,
            backgroundColor: primaryNavy,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _editing
                    ? _saveProfile()
                    : setState(() => _editing = true),
                icon: Icon(
                    _editing ? Icons.check_rounded : Icons.edit_outlined,
                    color: accentOrange,
                    size: 18),
                label: Text(_editing ? 'Save' : 'Edit',
                    style: const TextStyle(
                        color: accentOrange, fontWeight: FontWeight.bold)),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [primaryNavy, lightNavy],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter)),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      GestureDetector(
                        onTap: _pickAndUploadImage,
                        child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(colors: [
                                      accentOrange,
                                      Color(0xFFF5A623)
                                    ])),
                                child: CircleAvatar(
                                  radius: 52,
                                  backgroundColor: Colors.white,
                                  backgroundImage: _localImageUrl != null
                                      ? NetworkImage(_localImageUrl!)
                                      : null,
                                  child: _localImageUrl == null
                                      ? const Icon(Icons.person,
                                          color: primaryNavy, size: 50)
                                      : null,
                                ),
                              ),
                              if (_isUploading)
                                const Positioned.fill(
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 3)),
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: const BoxDecoration(
                                    color: accentOrange,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 14),
                              ),
                            ]),
                      ),
                      const SizedBox(height: 12),
                      Text(
                          widget.shopkeeperName ??
                              widget.user?.displayName ??
                              'Shopkeeper',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(widget.user?.email ?? '',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13)),
                    ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _pill(Icons.store_outlined, 'Shopkeeper',
                          accentOrange, orangeLight),
                      const SizedBox(width: 8),
                      if (widget.shopData?['status'] == 'verified')
                        _pill(Icons.verified_outlined, 'Verified',
                            accentGreen, greenLight),
                    ]),
                    const SizedBox(height: 20),
                    _sectionHeader('My Profile', Icons.person_outline),
                    _infoCard(children: [
                      _infoRow(
                        Icons.person_outline,
                        'Full Name',
                        widget.shopkeeperName ??
                            widget.user?.displayName ??
                            '—',
                      ),
                      _divider(),
                      _infoRow(
                        Icons.email_outlined,
                        'Email',
                        widget.user?.email ?? '—',
                      ),
                      _divider(),
                      _infoRow(
                        Icons.phone_outlined,
                        'Owner Contact',
                        widget.ownerContact?.isNotEmpty == true
                            ? widget.ownerContact!
                            : '—',
                      ),
                    ]),
                    const SizedBox(height: 20),
                    if (widget.shopId != null &&
                        widget.shopData?['status'] == 'verified') ...[
                      _sectionHeader('Quick Links', Icons.link_outlined),
                      _quickLinkTile(
                        icon: Icons.shopping_bag_outlined,
                        label: 'My Orders',
                        color: accentOrange,
                        bg: orangeLight,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ShopkeeperOrdersScreen(
                                      shopId: widget.shopId!)));
                        },
                      ),
                      const SizedBox(height: 8),
                      _quickLinkTile(
                        icon: Icons.rate_review_outlined,
                        label: 'Customer Reviews',
                        color: primaryNavy,
                        bg: const Color(0xFFE8EEF5),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ShopReviewsPage(
                                      shopId: widget.shopId!)));
                        },
                      ),
                      const SizedBox(height: 8),
                      _quickLinkTile(
                        icon: Icons.schedule_outlined,
                        label: 'Shop Timings',
                        color: const Color(0xFF7B5EA7),
                        bg: const Color(0xFFF3EEF9),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ShopTimingPage(
                                      shopId: widget.shopId!)));
                        },
                      ),
                      const SizedBox(height: 8),
                      _quickLinkTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Monthly Billing',
                        color: accentGreen,
                        bg: greenLight,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ShopkeeperBillingScreen(
                                      shopId: widget.shopId!)));
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                    _sectionHeader('Edit Contact', Icons.edit_outlined),
                    _editCard(children: [
                      _editField(
                        controller: TextEditingController(
                            text: widget.shopkeeperName ??
                                widget.user?.displayName ??
                                ''),
                        label: 'Full Name (read-only)',
                        icon: Icons.person_outline,
                        enabled: false,
                      ),
                      const SizedBox(height: 14),
                      _editField(
                        controller: TextEditingController(
                            text: widget.user?.email ?? ''),
                        label: 'Email (read-only)',
                        icon: Icons.email_outlined,
                        enabled: false,
                      ),
                      const SizedBox(height: 14),
                      _editField(
                          controller: _phoneCtrl,
                          label: 'Owner Contact',
                          icon: Icons.phone_outlined,
                          enabled: _editing,
                          keyboardType: TextInputType.phone),
                      if (_editing) ...[
                        const SizedBox(height: 18),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _editing = false),
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Colors.grey),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13)),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saveProfile,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: accentGreen,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13)),
                              child: const Text('Save Changes',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ]),
                      ],
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.dashboard_outlined,
                            size: 18, color: primaryNavy),
                        label: const Text('Back to Dashboard',
                            style: TextStyle(
                                color: primaryNavy,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: primaryNavy, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickLinkTile({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: primaryNavy))),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: color.withOpacity(0.5)),
        ]),
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color, Color bg) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _sectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: accentOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: accentOrange, size: 15),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: primaryNavy)),
        ]),
      );

  Widget _infoCard({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(children: children)),
      );

  Widget _editCard({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(children: children),
      );

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: primaryNavy.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: primaryNavy, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: valueColor ?? primaryNavy)),
              ])),
        ]),
      );

  Widget _divider() => Divider(
      height: 1,
      color: Colors.grey.shade100,
      indent: 14,
      endIndent: 14);

  Widget _editField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) =>
      TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, color: primaryNavy),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: Icon(icon,
              color: enabled ? accentOrange : Colors.grey.shade400,
              size: 18),
          filled: true,
          fillColor: enabled
              ? accentOrange.withOpacity(0.04)
              : Colors.grey.shade50,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: accentOrange, width: 1.5)),
          disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
        ),
      );
}