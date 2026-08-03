// ============================================================
//  shop_products_screen.dart — NearBuy Redesign
// ============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cart_screen.dart';
import 'nearbuy_theme.dart';

// ══════════════════════════════════════════════════════════
// BACKWARD-COMPATIBLE REVIEW FIELD HELPERS (file-private)
// Old reviews:  userId, name, rating, comment, createdAt
// New reviews:  userId, userName, profilePic, rating, comment, timestamp
// Shared by _ShopProductsScreenState and _ReviewCard below.
// ══════════════════════════════════════════════════════════

/// Rating: handles int, double, numeric string, or missing -> 0.
double _parseRating(dynamic r) {
  if (r is int) return r.toDouble();
  if (r is double) return r;
  if (r is String) return double.tryParse(r) ?? 0;
  return 0;
}

/// Name: userName (new) -> name (old) -> userId -> 'Anonymous'.
String _getUserName(Map<String, dynamic> data) {
  final userName = data['userName'];
  if (userName != null && userName.toString().trim().isNotEmpty) return userName.toString();
  final name = data['name'];
  if (name != null && name.toString().trim().isNotEmpty) return name.toString();
  final userId = data['userId'];
  if (userId != null && userId.toString().trim().isNotEmpty) return userId.toString();
  return 'Anonymous';
}

/// Profile pic: 'profilePic' only --- old reviews never had this field,
/// so missing/empty just falls back to the initial-letter avatar.
String? _getProfilePic(Map<String, dynamic> data) {
  final pic = data['profilePic'];
  if (pic != null && pic.toString().trim().isNotEmpty) return pic.toString();
  return null;
}

/// Date: timestamp (new) -> createdAt (old) -> null if neither exists.
DateTime? _getReviewDate(Map<String, dynamic> data) {
  final ts = data['timestamp'];
  if (ts is Timestamp) return ts.toDate();
  final created = data['createdAt'];
  if (created is Timestamp) return created.toDate();
  return null;
}

/// Comment: always a safe string, never null.
String _getComment(Map<String, dynamic> data) {
  final c = data['comment'];
  return c?.toString() ?? '';
}

class ShopProductsScreen extends StatefulWidget {
  final String shopId;
  final String shopName;

  const ShopProductsScreen({super.key, required this.shopId, required this.shopName});

  @override
  State<ShopProductsScreen> createState() => _ShopProductsScreenState();
}

class _ShopProductsScreenState extends State<ShopProductsScreen>
    with SingleTickerProviderStateMixin {
  String _searchText = "";
  double _userRating = 0;
  final TextEditingController _commentController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;
  double _avgRating = 0;
  bool isFavorite = false;
  int _cartCount = 0;
  Map<String, dynamic>? _shopData;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _calculateAverageRating();
    checkIfFavorite();
    _listenCartCount();
    _loadShopData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _loadShopData() {
    FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        setState(() => _shopData = doc.data() as Map<String, dynamic>?);
      }
    });
  }

  void _listenCartCount() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('cart')
        .where('shopId', isEqualTo: widget.shopId)
        .snapshots()
        .listen((snapshot) {
      int total = 0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['quantity'] ?? 1) as int;
      }
      if (mounted) setState(() => _cartCount = total);
    });
  }

  Future<void> _addToCart(Map<String, dynamic> productData, String productId) async {
    // ── FIX: Shop-suspended guard ──────────────────────────
    // Blocks ordering the moment shops.status becomes 'suspended' —
    // _shopData is already kept live via the snapshots() listener in
    // _loadShopData(), so this reflects the shopkeeper-side auto-suspend
    // (and the admin dashboard's manual suspend) the instant it lands in
    // Firestore, with no extra query needed here.
    if (_isShopSuspended) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This shop is currently suspended', style: GoogleFonts.poppins()),
          backgroundColor: NearBuyColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // ── Shop-closed guard ──────────────────────────────────
    // Extra safety net: even though the Add button is already disabled
    // in the UI when the shop is closed, this blocks the actual write
    // too (e.g. if triggered programmatically), without touching any
    // other existing behaviour of this function.
    if (!_isShopOpenNow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This shop is currently closed', style: GoogleFonts.poppins()),
          backgroundColor: NearBuyColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final cartRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('cart')
        .doc('${widget.shopId}_$productId');

    final existing = await cartRef.get();
    if (existing.exists) {
      await cartRef.update({'quantity': (existing.data()!['quantity'] ?? 1) + 1});
    } else {
      await cartRef.set({
        'shopId': widget.shopId,
        'shopName': widget.shopName,
        'productId': productId,
        'name': productData['name'],
        'price': productData['price'],
        'image_url': productData['image_url'] ?? '',
        'quantity': 1,
        'addedAt': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${productData['name']} added to cart', style: GoogleFonts.poppins()),
        backgroundColor: NearBuyColors.navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'View Cart',
          textColor: NearBuyColors.orange,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CartScreen(shopId: widget.shopId, shopName: widget.shopName),
            ),
          ),
        ),
      ),
    );
  }

  void checkIfFavorite() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('favorites')
        .doc(widget.shopId)
        .get();
    if (mounted) setState(() => isFavorite = doc.exists);
  }

  void _toggleFavorite() async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('favorites')
        .doc(widget.shopId);
    if (isFavorite) {
      await ref.delete();
    } else {
      await ref.set({
        'shopId': widget.shopId,
        'shopName': widget.shopName,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
    if (mounted) setState(() => isFavorite = !isFavorite);
  }

  void _calculateAverageRating() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .collection('reviews')
        .get();
    if (snapshot.docs.isEmpty) return;
    double total = 0;
    int ratedCount = 0;
    for (var d in snapshot.docs) {
      final rating = d.data()['rating'];
      if (rating == null) continue; // old/new review missing rating --- skip, don't count as 0
      total += _parseRating(rating);
      ratedCount++;
    }
    if (mounted) setState(() => _avgRating = ratedCount > 0 ? total / ratedCount : 0);
  }

  // ── Resolves the reviewer's display name + profile pic before submitting.
  // Name priority: Firestore users/{uid}.name -> FirebaseAuth displayName -> 'Anonymous'
  // Profile pic: Firestore users/{uid}.profile_image (same field customer_dashboard.dart uses)
  Future<Map<String, String?>> _fetchReviewerProfile() async {
    String name = user?.displayName ?? 'Anonymous';
    String? profilePic;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data();
        final firestoreName = data?['name'];
        if (firestoreName != null && firestoreName.toString().trim().isNotEmpty) {
          name = firestoreName.toString();
        }
        final pic = data?['profile_image'];
        if (pic != null && pic.toString().trim().isNotEmpty) {
          profilePic = pic.toString();
        }
      }
    } catch (_) {
      // Firestore lookup failed --- fall back to Auth displayName / Anonymous,
      // never block review submission because of this.
    }
    return {'name': name, 'profilePic': profilePic};
  }

  Future<void> _getDirections() async {
    final lat = _shopData?['location_lat'];
    final lng = _shopData?['location_lng'];
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location not available for this shop', style: GoogleFonts.poppins()),
          backgroundColor: NearBuyColors.error,
        ),
      );
      return;
    }
    final shopName = Uri.encodeComponent(widget.shopName);
    final Uri googleMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$shopName&travelmode=driving',
    );
    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
    } else {
      final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($shopName)');
      await launchUrl(geoUri);
    }
  }

  Future<void> _callOwner() async {
    final phone = _shopData?['phone'] ??
        _shopData?['contact'] ??
        _shopData?['owner_contact'] ??
        _shopData?['owner_phone'] ??
        _shopData?['phone_number'] ?? '';
    if (phone.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Phone number not available', style: GoogleFonts.poppins()),
          backgroundColor: NearBuyColors.error,
        ),
      );
      return;
    }
    final Uri telUri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
    }
  }

  void _showReviewBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: NearBuyColors.divider, borderRadius: BorderRadius.circular(2),
              )),
            ),
            const SizedBox(height: 20),
            Text('Rate This Shop', style: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
            )),
            const SizedBox(height: 16),
            Center(
              child: RatingBar.builder(
                initialRating: _userRating,
                minRating: 1,
                allowHalfRating: true,
                itemCount: 5,
                itemSize: 40,
                unratedColor: NearBuyColors.divider,
                itemBuilder: (_, __) => const Icon(Icons.star_rounded, color: NearBuyColors.starYellow),
                onRatingUpdate: (r) => _userRating = r,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 3,
              style: GoogleFonts.poppins(fontSize: 14, color: NearBuyColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                hintStyle: GoogleFonts.poppins(color: NearBuyColors.textHint),
                filled: true, fillColor: NearBuyColors.cream,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: NearBuyColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: NearBuyColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: NearBuyColors.orange, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (_userRating == 0) return;

                  final profile = await _fetchReviewerProfile();
                  final commentText = _commentController.text.trim();

                  try {
                    // widget.shopId is the exact same id passed in from
                    // CustomerDashboard -> ShopProductsScreen, so this
                    // always lands under the correct shop's document.
                    await FirebaseFirestore.instance
                        .collection('shops')
                        .doc(widget.shopId)
                        .collection('reviews')
                        .add({
                          'userId': user!.uid,
                          'userName': profile['name'],
                          'profilePic': profile['profilePic'],
                          'rating': _userRating,
                          'comment': commentText,
                          'timestamp': FieldValue.serverTimestamp(),
                        });

                    _commentController.clear();
                    if (mounted) setState(() => _userRating = 0);
                    _calculateAverageRating();

                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Review submitted!', style: GoogleFonts.poppins()),
                        backgroundColor: NearBuyColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not submit review. Please try again.', style: GoogleFonts.poppins()),
                        backgroundColor: NearBuyColors.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                },
                child: const Text('Submit Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // TEMPORARY CLOSURE CHECK
  // Firestore mein temporary_closures array check karo —
  // agar aaj ki date match hoti hai to shop temporarily closed hai
  // ══════════════════════════════════════════════════════════
  Map<String, dynamic>? _getTodayTemporaryClosure(Map<String, dynamic>? shopData) {
    if (shopData == null) return null;
    final closures = shopData['temporary_closures'];
    if (closures == null || closures is! List) return null;

    final now = DateTime.now();
    // Aaj ki date string — Firestore mein "YYYY-MM-DD" format mein store hai
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (final item in closures) {
      if (item is Map<String, dynamic>) {
        final closureDate = item['date']?.toString() ?? '';
        // Date string match karo (e.g. "2026-06-01")
        if (closureDate == todayStr) {
          return item; // { date: "2026-06-01", reason: "Death" }
        }
      }
    }
    return null; // Aaj koi closure nahi
  }

  // ══════════════════════════════════════════════════════════
  // SHOP SUSPENDED CHECK — used to gate "Add to Cart"
  // ══════════════════════════════════════════════════════════
  //
  // FIX (new): _shopData is already kept live via the snapshots()
  // listener in _loadShopData(), so this reflects `shops.status`
  // ('suspended' vs anything else) the instant it changes — including
  // the auto-suspend write from ShopkeeperBillingScreen's grace-period
  // timer, and the manual suspend/reactivate actions on the admin side.
  // Defensive by design, same as _isShopOpenNow below: if shop data
  // hasn't loaded yet, we default to "not suspended" so we never wrongly
  // block a purchase just because of a brief loading gap.
  bool get _isShopSuspended {
    if (_shopData == null) return false; // not loaded yet — don't block
    return _shopData?['status'] == 'suspended';
  }

  // ══════════════════════════════════════════════════════════
  // SHOP OPEN/CLOSED STATUS — used to gate "Add to Cart"
  // ══════════════════════════════════════════════════════════
  //
  // Reuses the exact same signals that _buildShopInfoCard() already shows
  // to the user as the "Open" / "Closed" / "Closed Today" badge, so the
  // Add-to-Cart button always matches what's on screen. Nothing in
  // _buildShopInfoCard() itself is touched — this just re-derives the
  // same status from `_shopData` (already kept in state via _loadShopData)
  // so it can also be used inside the Products tab / product cards.
  //
  // Defensive by design: if shop data hasn't loaded yet, or the shop_hours
  // structure is missing/incomplete for today, we default to "open" so we
  // never wrongly block a purchase just because of missing data — exactly
  // like the other defensive filters already in this codebase.
  bool get _isShopOpenNow {
    if (_shopData == null) return true; // not loaded yet — don't block

    // Temporary closure always wins, same as the banner logic.
    if (_getTodayTemporaryClosure(_shopData) != null) return false;

    final shopHours = _shopData?['shop_hours'] as Map<String, dynamic>?;
    if (shopHours == null) return true; // no structured hours — can't confirm closed

    final todayHours = shopHours[_todayKey()] as Map<String, dynamic>?;
    if (todayHours == null) return true; // no entry for today — can't confirm closed

    final isOpenFlag = todayHours['is_open'];
    if (isOpenFlag == null) return true; // flag missing — can't confirm closed

    return isOpenFlag == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NearBuyColors.cream,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildShopInfoCard()),
          SliverToBoxAdapter(child: _buildGetDirectionsButton()),
          SliverToBoxAdapter(child: _buildTabBar()),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [_buildProductsTab(), _buildReviewsTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final imageUrl = _shopData?['shop_image'] as String?
        ?? _shopData?['shop_image_url'] as String?
        ?? _shopData?['image'] as String?;

    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: NearBuyColors.navy,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(isFavorite),
              color: isFavorite ? Colors.red : Colors.white,
            ),
          ),
          onPressed: _toggleFavorite,
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CartScreen(shopId: widget.shopId, shopName: widget.shopName),
                ),
              ),
            ),
            if (_cartCount > 0)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: NearBuyColors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$_cartCount',
                    style: GoogleFonts.poppins(
                      fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _shopPlaceholder(),
              )
            else
              _shopPlaceholder(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, NearBuyColors.navy.withOpacity(0.85)],
                ),
              ),
            ),
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Text(
                widget.shopName,
                style: GoogleFonts.poppins(
                  fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NearBuyColors.navy, Color(0xFF2D3F6B)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront_rounded, size: 80, color: Colors.white24),
      ),
    );
  }

  String _todayKey() {
    const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return days[DateTime.now().weekday - 1];
  }

  Widget _buildShopInfoCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .snapshots(),
      builder: (ctx, snapshot) {
        final shopData = snapshot.data?.data() as Map<String, dynamic>?;
        final address  = shopData?['shop_location'] ?? shopData?['address'] ?? shopData?['location'] ?? 'Address not available';
        final phone    = shopData?['phone']
            ?? shopData?['contact']
            ?? shopData?['owner_contact']
            ?? shopData?['owner_phone']
            ?? shopData?['phone_number']
            ?? '';

        // ── Shop hours (regular schedule)
        final shopHours  = shopData?['shop_hours'] as Map<String, dynamic>?;
        final todayKey   = _todayKey();
        final todayHours = shopHours?[todayKey] as Map<String, dynamic>?;
        final bool isOpenToday = todayHours?['is_open'] == true;
        final String openTime  = todayHours?['open_time']  ?? '';
        final String closeTime = todayHours?['close_time'] ?? '';
        final fallbackOpen     = shopData?['open_time']  ?? '';
        final fallbackClose    = shopData?['close_time'] ?? '';
        final String displayOpen  = openTime.isNotEmpty  ? openTime  : fallbackOpen.toString();
        final String displayClose = closeTime.isNotEmpty ? closeTime : fallbackClose.toString();
        final bool showHours      = displayOpen.isNotEmpty;

        // ══════════════════════════════════════════════════
        // TEMPORARY CLOSURE CHECK
        // Firestore ke temporary_closures array se aaj ka
        // closure fetch karo — agar match ho to banner dikhao
        // ══════════════════════════════════════════════════
        final todayClosure = _getTodayTemporaryClosure(shopData);
        final bool isTemporarilyClosed = todayClosure != null;
        final String closureReason = todayClosure?['reason']?.toString() ?? 'Temporarily Closed';

        return Column(
          children: [
            // ── TEMPORARILY CLOSED BANNER ──────────────────
            // Sirf tab dikhega jab aaj temporary_closures mein entry ho
            if (isTemporarilyClosed)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECEC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NearBuyColors.error.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NearBuyColors.error.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.store_mall_directory_outlined,
                        color: NearBuyColors.error,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shop Temporarily Closed',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: NearBuyColors.error,
                            ),
                          ),

                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: NearBuyColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Closed Today',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── SHOP INFO CARD ─────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: NearBuyColors.navy.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StarRatingRow(rating: _avgRating, reviewCount: 0, starSize: 16),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: NearBuyColors.verified.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_rounded, size: 13, color: NearBuyColors.verified),
                            const SizedBox(width: 4),
                            Text('Verified', style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w600, color: NearBuyColors.verified,
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _infoRow(Icons.location_on_rounded, address, NearBuyColors.orange),
                  if (phone.toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _callOwner,
                      child: Row(
                        children: [
                          Icon(Icons.phone_rounded, size: 15, color: NearBuyColors.navy),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              phone.toString(),
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: NearBuyColors.navy,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: NearBuyColors.navy.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Call', style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                            )),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    _infoRow(Icons.phone_rounded, 'Contact not available', NearBuyColors.textSecondary),
                  ],

                  // ── Open/Close hours row
                  // Agar aaj temporarily closed hai to "Closed Today" show karo
                  // warna normal shop_hours dikhao
                  if (showHours) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 15,
                          color: isTemporarilyClosed
                              ? NearBuyColors.error
                              : isOpenToday
                                  ? NearBuyColors.success
                                  : NearBuyColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isTemporarilyClosed
                                ? '$displayOpen – $displayClose'
                                : '$displayOpen – $displayClose',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: NearBuyColors.textSecondary,
                            ),
                          ),
                        ),
                        // Badge — temporarily closed override karta hai normal status ko
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isTemporarilyClosed
                                ? NearBuyColors.error.withOpacity(0.1)
                                : isOpenToday
                                    ? NearBuyColors.success.withOpacity(0.1)
                                    : NearBuyColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isTemporarilyClosed
                                ? 'Closed Today'
                                : isOpenToday
                                    ? 'Open'
                                    : 'Closed',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isTemporarilyClosed
                                  ? NearBuyColors.error
                                  : isOpenToday
                                      ? NearBuyColors.success
                                      : NearBuyColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String text, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.poppins(
          fontSize: 13, color: NearBuyColors.textSecondary,
        ))),
      ],
    );
  }

  Widget _buildGetDirectionsButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _getDirections,
          style: ElevatedButton.styleFrom(
            backgroundColor: NearBuyColors.orange,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          icon: const Icon(Icons.directions_rounded, color: Colors.white, size: 20),
          label: Text('Get Directions', style: GoogleFonts.poppins(
            fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
          )),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: NearBuyColors.navy.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: NearBuyColors.navy,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: NearBuyColors.textSecondary,
        labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Products'),
          Tab(text: 'Reviews'),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    return Column(
      children: [
        // ── FIX: Shop-suspended notice strip ───────────────
        // Takes priority over the "closed" strip below — if the shop is
        // suspended, that's the more specific/severe reason and should be
        // the only banner shown.
        if (_isShopSuspended)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: NearBuyColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NearBuyColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.block_rounded, size: 16, color: NearBuyColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This shop is currently suspended and is not accepting orders.',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: NearBuyColors.error, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          )
        // ── Shop-closed notice strip ──────────────────────
        // Sirf Products tab ke oopar dikhta hai jab shop abhi closed ho.
        // Products tab / list ko yahan touch nahi kiya — sirf ek info
        // strip add ki hai, taake user samajh sake products dekh sakta
        // hai lekin order abhi nahi kar sakta.
        else if (!_isShopOpenNow)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: NearBuyColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NearBuyColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: NearBuyColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This shop is currently closed. You can browse products, but ordering is disabled until it reopens.',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: NearBuyColors.error, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: NearBuyColors.divider),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchText = v.toLowerCase()),
                    style: GoogleFonts.poppins(fontSize: 13, color: NearBuyColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: GoogleFonts.poppins(fontSize: 13, color: NearBuyColors.textHint),
                      prefixIcon: Icon(Icons.search_rounded, color: NearBuyColors.navy, size: 18),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shops')
                .doc(widget.shopId)
                .collection('products')
                .snapshots(),
            builder: (ctx, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: NearBuyColors.navy));
              }
              var docs = snapshot.data!.docs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                if (_searchText.isEmpty) return true;
                return (d['name'] ?? '').toString().toLowerCase().contains(_searchText);
              }).toList();

              if (docs.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 56, color: NearBuyColors.textHint),
                    const SizedBox(height: 12),
                    Text('No products found', style: GoogleFonts.poppins(
                      fontSize: 14, color: NearBuyColors.textSecondary,
                    )),
                  ],
                ));
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: docs.length,
                itemBuilder: (ctx, i) => _ProductCard(
                  doc: docs[i],
                  onAddToCart: _addToCart,
                  // FIX: shop-open flag now also folds in the suspension
                  // check, so the Add button is disabled and shows the
                  // same "unavailable" treatment for a suspended shop as
                  // it already does for a closed one.
                  isShopOpen: _isShopOpenNow && !_isShopSuspended,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_avgRating.toStringAsFixed(1), style: GoogleFonts.poppins(
                    fontSize: 40, fontWeight: FontWeight.w800, color: NearBuyColors.textPrimary,
                  )),
                  StarRatingRow(rating: _avgRating, starSize: 18),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showReviewBottomSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NearBuyColors.navy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.rate_review_rounded, size: 16, color: Colors.white),
                label: Text('Write Review', style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white,
                )),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // NOTE: no orderBy() here on purpose --- old reviews may be
            // missing `createdAt` (and new ones don't have it at all,
            // they use `timestamp`), so ordering by either field server-side
            // would silently drop documents missing that field. Sorting is
            // done client-side below instead, so old + new reviews always
            // show up and no extra Firestore index is required.
            stream: FirebaseFirestore.instance
                .collection('shops')
                .doc(widget.shopId)
                .collection('reviews')
                .snapshots(),
            builder: (ctx, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: NearBuyColors.navy));
              }
              final reviews = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
              // Latest first; reviews with no usable date (old docs missing
              // both timestamp & createdAt) are pushed to the bottom.
              reviews.sort((a, b) {
                final da = _getReviewDate(a.data() as Map<String, dynamic>);
                final db = _getReviewDate(b.data() as Map<String, dynamic>);
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return db.compareTo(da);
              });
              if (reviews.isNotEmpty) {
                double total = 0;
                int ratedCount = 0;
                for (var d in reviews) {
                  final rating = (d.data() as Map<String, dynamic>)['rating'];
                  if (rating == null) continue;
                  total += _parseRating(rating);
                  ratedCount++;
                }
                final newAvg = ratedCount > 0 ? total / ratedCount : 0.0;
                if (newAvg != _avgRating) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _avgRating = newAvg);
                  });
                }
              }
              if (reviews.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 56, color: NearBuyColors.textHint),
                    const SizedBox(height: 12),
                    Text('No reviews yet', style: GoogleFonts.poppins(
                      fontSize: 14, color: NearBuyColors.textSecondary,
                    )),
                  ],
                ));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: reviews.length,
                itemBuilder: (ctx, i) => _ReviewCard(doc: reviews[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Product Card ──────────────────────────────────────────
class _ProductCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Future<void> Function(Map<String, dynamic>, String) onAddToCart;
  // NEW: shop-level open/closed flag, passed down from
  // _ShopProductsScreenState._isShopOpenNow. When false, the Add button
  // becomes disabled (same visual treatment as out-of-stock), but the
  // product itself stays fully visible/browsable.
  final bool isShopOpen;

  const _ProductCard({
    required this.doc,
    required this.onAddToCart,
    this.isShopOpen = true,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final data        = widget.doc.data() as Map<String, dynamic>;
    final name        = data['name'] ?? 'Product';
    final price       = data['price']?.toString() ?? '0';
    final imageUrl    = data['image_url'] as String?;
    final description = data['description'] as String?;
    final bool isOutOfStock = data['out_of_stock'] == true;
    // Button is disabled if the product is out of stock OR the shop is
    // currently closed/suspended. Out-of-stock keeps priority in the
    // label below since that's the more specific reason.
    final bool isShopClosed = !widget.isShopOpen;
    final bool isAddDisabled = isOutOfStock || isShopClosed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: NearBuyColors.navy.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 90, height: 90, fit: BoxFit.cover,
                        color: isOutOfStock ? Colors.black.withOpacity(0.35) : null,
                        colorBlendMode: isOutOfStock ? BlendMode.darken : null,
                      )
                    : Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          color: NearBuyColors.navy.withOpacity(0.05),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, color: NearBuyColors.textHint),
                      ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isOutOfStock ? NearBuyColors.textHint : NearBuyColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOutOfStock
                              ? NearBuyColors.error.withOpacity(0.1)
                              : NearBuyColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isOutOfStock ? 'Out of Stock' : 'In Stock',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isOutOfStock ? NearBuyColors.error : NearBuyColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: GoogleFonts.poppins(fontSize: 11, color: NearBuyColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Rs. $price',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isOutOfStock ? NearBuyColors.textHint : NearBuyColors.navy,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: (isAddDisabled || _adding)
                            ? null
                            : () async {
                                setState(() => _adding = true);
                                await widget.onAddToCart(data, widget.doc.id);
                                if (mounted) setState(() => _adding = false);
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isAddDisabled
                                ? NearBuyColors.textHint.withOpacity(0.3)
                                : (_adding
                                    ? NearBuyColors.navy.withOpacity(0.7)
                                    : NearBuyColors.navy),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: isOutOfStock
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.remove_shopping_cart_rounded,
                                        size: 13, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text('Unavailable',
                                        style: GoogleFonts.poppins(
                                            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
                                  ],
                                )
                              : (isShopClosed
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.storefront_outlined,
                                            size: 13, color: Colors.white70),
                                        const SizedBox(width: 4),
                                        Text('Shop Closed',
                                            style: GoogleFonts.poppins(
                                                fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
                                      ],
                                    )
                                  : (_adding
                                      ? const SizedBox(
                                          width: 14, height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.add_shopping_cart_rounded,
                                                size: 13, color: Colors.white),
                                            const SizedBox(width: 4),
                                            Text('Add',
                                                style: GoogleFonts.poppins(
                                                    fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                          ],
                                        ))),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Review Card ───────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _ReviewCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data       = doc.data() as Map<String, dynamic>;
    final name       = _getUserName(data);
    final rating     = _parseRating(data['rating']);
    final comment    = _getComment(data);
    final profilePic = _getProfilePic(data);
    final date       = _getReviewDate(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NearBuyColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: NearBuyColors.navy.withOpacity(0.08),
                backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                child: profilePic == null
                    ? Text(name[0].toUpperCase(), style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, color: NearBuyColors.navy, fontSize: 14,
                      ))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
                    )),
                    if (date != null)
                      Text(
                        '${date.day}/${date.month}/${date.year}',
                        style: GoogleFonts.poppins(fontSize: 10, color: NearBuyColors.textHint),
                      ),
                  ],
                ),
              ),
              StarRatingRow(rating: rating),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment, style: GoogleFonts.poppins(
              fontSize: 13, color: NearBuyColors.textSecondary, height: 1.5,
            )),
          ],
        ],
      ),
    );
  }
}