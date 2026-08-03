// ============================================================
//  customer_dashboard.dart — NearBuy Redesign (+ Advanced Filters)
// ============================================================
//
// NOTE ON ASSUMPTIONS (please read before wiring into your project):
//
// 1) PRICE FILTER
//    Your `shops` collection (as shown to me) does NOT contain min/max
//    price fields, and I don't have visibility into your actual
//    products collection/schema. So this filter is implemented
//    defensively in two layers so it can NEVER crash and NEVER
//    silently guess a wrong field:
//      a) If the shop document itself has `min_price` / `max_price`
//         (num), those are used directly — cheapest, no extra reads.
//      b) Otherwise, it lazily queries a TOP-LEVEL `products`
//         collection filtered by `shopId == <shop doc id>` and reads
//         a `price` (num) field to compute min/max for that shop.
//         This result is cached in-memory so each shop is only
//         queried once per session.
//    -> If your products actually live somewhere else (e.g.
//       `shops/{shopId}/products` subcollection, or a different field
//       name), tell me the exact collection path + field name and
//       I'll swap ONE function (`_fetchShopPriceRange`) — nothing
//       else needs to change.
//
// 2) RATING FILTER
//    Your shop documents don't appear to store a rating field —
//    ratings are computed live from the `shops/{shopId}/reviews`
//    subcollection (see `_FirestoreShopRating` below, unchanged).
//    So the filter first checks for a stored field in this order:
//    `averageRating` -> `rating_average` -> `rating`. If none exist,
//    it falls back to lazily computing the average from the reviews
//    subcollection (same source your star-rating widget already
//    uses), caches it per shop, and re-filters once it arrives.
//
// 3) OPEN / CLOSED FILTER
//    Reuses your existing `open_time` / `close_time` fields (12-hour
//    "h:mm AM/PM" format, matching your shopkeeper timing picker).
//    Handles overnight ranges (e.g. 8:00 PM – 2:00 AM) correctly.
//    If a shop has no timing fields, it's treated as "unknown" and
//    is excluded only when the Open/Closed filter is active (never
//    crashes, never shown as a false positive).
//
// 4) BILLING-SUSPENSION GATE (added — see notes inline below)
//    This is NOT one of the toggleable advanced filters above. It is
//    a mandatory gate applied unconditionally to every shop in the
//    list, independent of _activeAdvancedFilterCount. It exists to
//    close a gap: the shopkeeper-side auto-suspend write (in
//    ShopkeeperBillingScreen) only used to fire when the shopkeeper's
//    billing screen was open/refreshed. This gate reads the shop's
//    active `rejected` billing cycle directly from Firestore and,
//    once `due_time` has passed, treats the shop as suspended on the
//    customer side too — even if `shops.status` hasn't been written
//    to `'suspended'` yet. `shops.status` remains authoritative the
//    moment it *does* update (this is only a bridge for the gap
//    before that write lands). A per-shop one-shot Timer is scheduled
//    so the list refreshes itself exactly at `due_time`, without the
//    customer needing to manually reload.
//
// No new packages are required — RangeSlider/ChoiceChip/RadioListTile
// are all built into the Flutter SDK you already use.
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'role_selection_screen.dart';
import 'shop_products_screen.dart';
import 'services/location_service.dart';
import 'screens/map_screen.dart';
import 'screens/my_orders_screen.dart';
import 'nearbuy_theme.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard>
    with SingleTickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  String _searchText = "";
  Position? _currentPosition;
  String? _profileImageUrl;
  String? _displayName;
  bool _isUploading = false;
  String _selectedCategory = "All";
  int _currentNavIndex = 0; // 0 = Shops, 1 = My Orders, 2 = Favorites

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ─────────────────────────────────────────────────────────
  // ADVANCED FILTERS — new state
  // ─────────────────────────────────────────────────────────
  static const double _priceRangeMin = 0;
  static const double _priceRangeMax = 10000;

  double? _distanceFilterKm; // null = All
  RangeValues _priceFilter = const RangeValues(_priceRangeMin, _priceRangeMax);
  bool _priceFilterActive = false; // becomes true only after user applies a non-default range
  double _ratingFilterMin = 0; // 0 = All, 4.0, 4.5
  String _availabilityFilter = 'All'; // 'All' | 'Open' | 'Closed'

  // Lazy caches so we never re-fetch price/rating for the same shop twice.
  final Map<String, RangeValues?> _shopPriceCache = {}; // null => known "no price data"
  final Set<String> _shopPriceFetching = {};
  final Map<String, double?> _shopRatingCache = {}; // null => known "no rating data"
  final Set<String> _shopRatingFetching = {};

  // ── FIX: mandatory suspension-by-grace-period check (NOT a toggleable
  // filter — always applied, doesn't count toward _activeAdvancedFilterCount).
  // true  = shop has a rejected billing cycle whose due_time has passed,
  //         so treat as suspended even if shops.status hasn't caught up yet.
  final Map<String, bool> _shopBillingSuspendedCache = {};
  final Set<String> _shopBillingFetching = {};
  final Map<String, Timer?> _shopSuspensionTimers = {};

  int get _activeAdvancedFilterCount {
    int count = 0;
    if (_distanceFilterKm != null) count++;
    if (_priceFilterActive) count++;
    if (_ratingFilterMin > 0) count++;
    if (_availabilityFilter != 'All') count++;
    return count;
  }

  final List<Map<String, dynamic>> _categories = [
    {'label': 'All', 'icon': Icons.apps_rounded},
    {'label': 'Grocery & General Store', 'icon': Icons.local_grocery_store_rounded},
    {'label': 'Clothing & Fashion', 'icon': Icons.checkroom_rounded},
    {'label': 'Shoes & Footwear', 'icon': Icons.shopping_bag_rounded},
    {'label': 'Electronics & Mobiles', 'icon': Icons.devices_rounded},
    {'label': 'Pharmacy & Health', 'icon': Icons.local_pharmacy_rounded},
    {'label': 'Beauty & Cosmetics', 'icon': Icons.face_retouching_natural_rounded},
    {'label': 'Bakery & Sweets', 'icon': Icons.bakery_dining_rounded},
    {'label': 'Restaurants & Food', 'icon': Icons.restaurant_rounded},
    {'label': 'Fruits & Vegetables', 'icon': Icons.eco_rounded},
    {'label': 'Meat & Poultry', 'icon': Icons.set_meal_rounded},
    {'label': 'Stationery & Books', 'icon': Icons.menu_book_rounded},
    {'label': 'Hardware & Tools', 'icon': Icons.handyman_rounded},
    {'label': 'Furniture & Home Decor', 'icon': Icons.chair_rounded},
    {'label': 'Jewellery & Accessories', 'icon': Icons.diamond_rounded},
    {'label': 'Sports & Fitness', 'icon': Icons.sports_soccer_rounded},
    {'label': 'Auto Parts & Accessories', 'icon': Icons.car_repair_rounded},
    {'label': 'Baby & Kids', 'icon': Icons.child_friendly_rounded},
    {'label': 'Pet Supplies', 'icon': Icons.pets_rounded},
    {'label': 'Gifts & Flowers', 'icon': Icons.card_giftcard_rounded},
    {'label': 'Other', 'icon': Icons.more_horiz_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _displayName = user?.displayName ?? "Customer";
    _fetchCurrentLocation();
    _loadProfileData();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    // FIX: cancel any pending per-shop grace-period timers so we never
    // call setState() after this widget is disposed.
    for (final t in _shopSuspensionTimers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  void _loadProfileData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user?.uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _profileImageUrl = doc.data()?['profile_image'];
        if (doc.data()?['name'] != null) _displayName = doc.data()?['name'];
      });
    }
  }

  Future<void> _updateName(String newName) async {
    try {
      await user?.updateDisplayName(newName);
      await FirebaseFirestore.instance.collection('users').doc(user?.uid).set(
        {'name': newName}, SetOptions(merge: true),
      );
      setState(() => _displayName = newName);
    } catch (e) { debugPrint("Update Name Error: $e"); }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _isUploading = true);
      try {
        String cloudName = "your_cloud_name";
        String uploadPreset = "your_preset";
        var request = http.MultipartRequest(
          'POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
        );
        request.fields['upload_preset'] = uploadPreset;
        request.files.add(await http.MultipartFile.fromPath('file', pickedFile.path));
        var response = await request.send();
        if (response.statusCode == 200) {
          var responseData = await response.stream.toBytes();
          var jsonRes = jsonDecode(String.fromCharCodes(responseData));
          String url = jsonRes['secure_url'];
          await FirebaseFirestore.instance.collection('users').doc(user?.uid)
              .set({'profile_image': url}, SetOptions(merge: true));
          setState(() => _profileImageUrl = url);
        }
      } catch (e) { debugPrint("Upload Error: $e"); }
      finally { setState(() => _isUploading = false); }
    }
  }

  void _showProfileDialog() {
    TextEditingController nameController = TextEditingController(text: _displayName);
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
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: NearBuyColors.divider, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickAndUploadImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: NearBuyColors.navy.withOpacity(0.08),
                    backgroundImage: _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null,
                    child: _profileImageUrl == null
                        ? Icon(Icons.person_rounded, size: 48, color: NearBuyColors.navy)
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: NearBuyColors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                  if (_isUploading)
                    const Positioned.fill(child: CircularProgressIndicator()),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              style: GoogleFonts.poppins(fontSize: 15, color: NearBuyColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Full Name',
                labelStyle: GoogleFonts.poppins(color: NearBuyColors.textSecondary),
                prefixIcon: Icon(Icons.person_outline, color: NearBuyColors.navy),
                filled: true,
                fillColor: NearBuyColors.cream,
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: NearBuyColors.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NearBuyColors.divider),
              ),
              child: Row(
                children: [
                  Icon(Icons.email_outlined, color: NearBuyColors.textSecondary, size: 18),
                  const SizedBox(width: 10),
                  Text(user?.email ?? '', style: GoogleFonts.poppins(
                    fontSize: 14, color: NearBuyColors.textSecondary,
                  )),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: NearBuyColors.divider),
                    ),
                    child: Text('Cancel', style: GoogleFonts.poppins(color: NearBuyColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _updateName(nameController.text);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Profile updated!', style: GoogleFonts.poppins()),
                          backgroundColor: NearBuyColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    },
                    child: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) setState(() => _currentPosition = position);
    } catch (_) {}
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (_) => false,
      );
    }
  }

  Stream<QuerySnapshot> _getVerifiedShops() {
    return FirebaseFirestore.instance
        .collection('shops')
        .where('status', isEqualTo: 'verified')
        .snapshots();
  }

  bool _isBillingAllowed(Map<String, dynamic> data) {
    final billing = data['billing_status'];
    return billing == null || billing == 'active';
  }

  double _distance(Map<String, dynamic> data) {
    if (_currentPosition == null) return 0;
    final lat = data['location_lat'];
    final lng = data['location_lng'];
    if (lat == null || lng == null) return 0;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude, _currentPosition!.longitude, lat, lng,
    ) / 1000;
  }

  // ─────────────────────────────────────────────────────────
  // ADVANCED FILTERS — helper logic
  // ─────────────────────────────────────────────────────────

  /// Distance filter — reuses existing `_currentPosition` / `_distance()`.
  /// If location isn't available and a distance filter is selected, the
  /// filter is simply not applied (nothing crashes); the filter sheet
  /// itself shows a message asking the user to enable location.
  bool _matchesDistanceFilter(Map<String, dynamic> data) {
    if (_distanceFilterKm == null) return true;
    if (_currentPosition == null) return true; // graceful no-op, see note above
    final dist = _distance(data);
    if (dist <= 0) return true; // shop has no lat/lng — don't hide it, just can't rank it
    return dist <= _distanceFilterKm!;
  }

  /// Rating filter — checks common stored field names first; falls back to
  /// a lazily-cached average computed from the reviews subcollection
  /// (same source as `_FirestoreShopRating`). Never crashes if missing.
  bool _matchesRatingFilter(String shopId, Map<String, dynamic> data) {
    if (_ratingFilterMin <= 0) return true;

    final storedRating = data['averageRating'] ?? data['rating_average'] ?? data['rating'];
    if (storedRating is num) {
      return storedRating.toDouble() >= _ratingFilterMin;
    }

    if (_shopRatingCache.containsKey(shopId)) {
      final cached = _shopRatingCache[shopId];
      if (cached == null) return false; // known: no reviews / no rating yet
      return cached >= _ratingFilterMin;
    }

    _fetchShopRatingIfNeeded(shopId);
    return false; // exclude until cached value arrives, then list re-filters automatically
  }

  void _fetchShopRatingIfNeeded(String shopId) {
    if (_shopRatingFetching.contains(shopId)) return;
    _shopRatingFetching.add(shopId);
    FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('reviews')
        .get()
        .then((snap) {
      double? avg;
      if (snap.docs.isNotEmpty) {
        double total = 0;
        for (var d in snap.docs) {
          total += ((d.data())['rating'] ?? 0).toDouble();
        }
        avg = total / snap.docs.length;
      }
      _shopRatingCache[shopId] = avg;
      if (mounted) setState(() {});
    }).catchError((_) {
      _shopRatingCache[shopId] = null;
    });
  }

  /// Price filter — see the note block at the top of this file for the
  /// exact assumptions. Cheap path uses shop-level min/max fields if
  /// present; otherwise lazily queries a top-level `products` collection.
  bool _matchesPriceFilter(String shopId, Map<String, dynamic> data) {
    if (!_priceFilterActive) return true;

    final minPriceField = data['min_price'];
    final maxPriceField = data['max_price'];
    if (minPriceField is num && maxPriceField is num) {
      return _rangesOverlap(
        minPriceField.toDouble(), maxPriceField.toDouble(),
        _priceFilter.start, _priceFilter.end,
      );
    }

    if (_shopPriceCache.containsKey(shopId)) {
      final cached = _shopPriceCache[shopId];
      if (cached == null) return false; // known: no product price data available
      return _rangesOverlap(cached.start, cached.end, _priceFilter.start, _priceFilter.end);
    }

    _fetchShopPriceRange(shopId);
    return false; // exclude until cached value arrives, then list re-filters automatically
  }

  bool _rangesOverlap(double aStart, double aEnd, double bStart, double bEnd) {
    return aStart <= bEnd && aEnd >= bStart;
  }

  void _fetchShopPriceRange(String shopId) {
    if (_shopPriceFetching.contains(shopId)) return;
    _shopPriceFetching.add(shopId);
    // ASSUMPTION: top-level `products` collection with a `shopId` field
    // and a numeric `price` field. Swap this query if your real schema
    // differs (see note block at the top of this file).
    FirebaseFirestore.instance
        .collection('products')
        .where('shopId', isEqualTo: shopId)
        .get()
        .then((snap) {
      RangeValues? range;
      if (snap.docs.isNotEmpty) {
        double? minP, maxP;
        for (var d in snap.docs) {
          final p = d.data()['price'];
          if (p is num) {
            final pd = p.toDouble();
            if (minP == null || pd < minP) minP = pd;
            if (maxP == null || pd > maxP) maxP = pd;
          }
        }
        if (minP != null && maxP != null) range = RangeValues(minP, maxP);
      }
      _shopPriceCache[shopId] = range;
      if (mounted) setState(() {});
    }).catchError((_) {
      _shopPriceCache[shopId] = null;
    });
  }

  /// Open/Closed filter — reuses existing `open_time` / `close_time`
  /// string fields ("h:mm AM/PM"). Handles overnight ranges. If a shop
  /// has no timing data, it's excluded only while this filter is active.
  bool _matchesAvailabilityFilter(Map<String, dynamic> data) {
    if (_availabilityFilter == 'All') return true;
    final openTime = data['open_time'];
    final closeTime = data['close_time'];
    if (openTime == null || closeTime == null ||
        openTime.toString().isEmpty || closeTime.toString().isEmpty) {
      return false; // unknown timing — can't confirm, so exclude rather than guess
    }
    final isOpen = _isShopOpenNow(openTime.toString(), closeTime.toString());
    if (isOpen == null) return false; // unparseable time string
    return _availabilityFilter == 'Open' ? isOpen : !isOpen;
  }

  /// Parses "h:mm AM/PM" into minutes-since-midnight. Returns null if the
  /// string can't be parsed, so callers can fail gracefully.
  int? _parseTimeToMinutes(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(raw.trim());
    if (match == null) return null;
    int hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!.toUpperCase();
    if (hour == 12) hour = 0;
    if (period == 'PM') hour += 12;
    return hour * 60 + minute;
  }

  /// Returns true if open, false if closed, null if times couldn't be parsed.
  /// Correctly handles shops whose hours cross midnight (e.g. 8 PM – 2 AM).
  bool? _isShopOpenNow(String openTimeStr, String closeTimeStr) {
    final openMin = _parseTimeToMinutes(openTimeStr);
    final closeMin = _parseTimeToMinutes(closeTimeStr);
    if (openMin == null || closeMin == null) return null;

    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;

    if (openMin == closeMin) return true; // 24-hour shop
    if (closeMin > openMin) {
      // Same-day range, e.g. 9:00 AM - 9:00 PM
      return nowMin >= openMin && nowMin < closeMin;
    } else {
      // Crosses midnight, e.g. 8:00 PM - 2:00 AM
      return nowMin >= openMin || nowMin < closeMin;
    }
  }

  // ─────────────────────────────────────────────────────────
  // GRACE-PERIOD SUSPENSION CHECK (mandatory, not a toggleable filter)
  // ─────────────────────────────────────────────────────────
  // See the note block at the top of this file for why this exists.
  bool _isShopSuspendedByGracePeriod(String shopId) {
    if (_shopBillingSuspendedCache.containsKey(shopId)) {
      return _shopBillingSuspendedCache[shopId] ?? false;
    }
    _fetchShopBillingSuspensionIfNeeded(shopId);
    return false; // don't hide before we actually know
  }

  void _fetchShopBillingSuspensionIfNeeded(String shopId) {
    if (_shopBillingFetching.contains(shopId)) return;
    _shopBillingFetching.add(shopId);
    FirebaseFirestore.instance
        .collection('billing')
        .where('shopId', isEqualTo: shopId)
        .where('payment_status', isEqualTo: 'rejected')
        .limit(1)
        .get()
        .then((snap) {
      bool suspended = false;
      if (snap.docs.isNotEmpty) {
        final dueTimeRaw = snap.docs.first.data()['due_time'];
        if (dueTimeRaw is Timestamp) {
          final dueDate = dueTimeRaw.toDate();
          if (DateTime.now().isAfter(dueDate)) {
            suspended = true;
          } else {
            // Not expired yet — schedule a one-shot timer so the list
            // refreshes itself exactly at due_time, without the customer
            // needing to manually reload.
            _scheduleSuspensionTimer(shopId, dueDate);
          }
        }
      }
      _shopBillingSuspendedCache[shopId] = suspended;
      if (mounted) setState(() {});
    }).catchError((_) {
      _shopBillingSuspendedCache[shopId] = false;
    });
  }

  void _scheduleSuspensionTimer(String shopId, DateTime dueDate) {
    _shopSuspensionTimers[shopId]?.cancel();
    final delay = dueDate.difference(DateTime.now());
    if (delay.isNegative) {
      _shopBillingSuspendedCache[shopId] = true;
      if (mounted) setState(() {});
      return;
    }
    _shopSuspensionTimers[shopId] = Timer(delay, () {
      _shopBillingSuspendedCache[shopId] = true;
      if (mounted) setState(() {});
    });
  }

  void _resetFilters() {
    setState(() {
      _distanceFilterKm = null;
      _priceFilter = const RangeValues(_priceRangeMin, _priceRangeMax);
      _priceFilterActive = false;
      _ratingFilterMin = 0;
      _availabilityFilter = 'All';
      // Category is intentionally left untouched — it's a separate
      // selection (category chips), not part of the advanced filters.
    });
  }

  // ─── Bottom Nav tap handler ──────────────────────────────
  void _onNavTap(int index) {
    if (index == 1) {
      // My Orders — navigate to screen
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
      return;
    }
    if (index == 2) {
      // Favorites — navigate to wishlist
      Navigator.push(context, MaterialPageRoute(builder: (_) => const _WishlistScreen()));
      return;
    }
    // index == 0 => Shops (stay on this page)
    setState(() => _currentNavIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NearBuyColors.cream,
      drawer: _buildDrawer(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildCategoryChips()),
            SliverToBoxAdapter(child: _buildSectionHeader()),
            _buildShopList(),
          ],
        ),
      ),
      // ─── Bottom Navigation Bar ───────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: NearBuyColors.navy.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.store_rounded,
                  label: 'Shops',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.receipt_long_rounded,
                  label: 'Order History',
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.favorite_rounded,
                  label: 'Favorites',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Bottom Nav Item ─────────────────────────────────────
  Widget _buildNavItem({required int index, required IconData icon, required String label}) {
    final isSelected = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => _onNavTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? NearBuyColors.navy.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? NearBuyColors.navy : NearBuyColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? NearBuyColors.navy : NearBuyColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 130,
      backgroundColor: NearBuyColors.navy,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
          ),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map_outlined, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const MapScreen()),
          ),
        ),
        GestureDetector(
          onTap: _showProfileDialog,
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: NearBuyColors.orange,
              backgroundImage: _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null,
              child: _profileImageUrl == null
                  ? Text(
                      (_displayName ?? 'C')[0].toUpperCase(),
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2340), Color(0xFF243057)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: 'Near',
                      style: GoogleFonts.poppins(
                        fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text: 'Buy',
                      style: GoogleFonts.poppins(
                        fontSize: 26, fontWeight: FontWeight.w800, color: NearBuyColors.orange,
                      ),
                    ),
                  ]),
                ),
                Text(
                  'Shops near you',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: NearBuyColors.navy.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchText = v.toLowerCase()),
                style: GoogleFonts.poppins(fontSize: 14, color: NearBuyColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search shops near you...',
                  hintStyle: GoogleFonts.poppins(fontSize: 14, color: NearBuyColors.textHint),
                  prefixIcon: Icon(Icons.search_rounded, color: NearBuyColors.navy, size: 22),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildFilterButton(),
        ],
      ),
    );
  }

  // ─── Filter button (with active-count badge) ────────────
  Widget _buildFilterButton() {
    final count = _activeAdvancedFilterCount;
    return GestureDetector(
      onTap: _showFilterSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: count > 0 ? NearBuyColors.navy : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: NearBuyColors.navy.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(
              Icons.tune_rounded,
              color: count > 0 ? Colors.white : NearBuyColors.navy,
              size: 22,
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: const BoxDecoration(
                  color: NearBuyColors.orange,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Filter bottom sheet ─────────────────────────────────
  void _showFilterSheet() {
    // Local temp state so Reset/Cancel don't affect the list until Apply.
    double? tempDistance = _distanceFilterKm;
    RangeValues tempPrice = _priceFilter;
    bool tempPriceActive = _priceFilterActive;
    double tempRating = _ratingFilterMin;
    String tempAvailability = _availabilityFilter;

    final distanceOptions = <Map<String, dynamic>>[
      {'label': 'All', 'value': null},
      {'label': 'Within 1 km', 'value': 1.0},
      {'label': 'Within 3 km', 'value': 3.0},
      {'label': 'Within 5 km', 'value': 5.0},
      {'label': 'Within 10 km', 'value': 10.0},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(width: 40, height: 4, decoration: BoxDecoration(
                        color: NearBuyColors.divider, borderRadius: BorderRadius.circular(2),
                      )),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Filter Shops', style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
                        )),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: NearBuyColors.textSecondary),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ── Distance
                    _filterSectionLabel('📍 Distance'),
                    if (_currentPosition == null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: NearBuyColors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_off_rounded, size: 16, color: NearBuyColors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Location not available. Please enable location to use distance filter.',
                                style: GoogleFonts.poppins(fontSize: 11, color: NearBuyColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: distanceOptions.map((opt) {
                        final selected = tempDistance == opt['value'];
                        return ChoiceChip(
                          label: Text(opt['label'], style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: selected ? Colors.white : NearBuyColors.textSecondary,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          )),
                          selected: selected,
                          onSelected: _currentPosition == null && opt['value'] != null
                              ? null
                              : (_) => setSheetState(() => tempDistance = opt['value']),
                          selectedColor: NearBuyColors.navy,
                          backgroundColor: NearBuyColors.cream,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: selected ? NearBuyColors.navy : NearBuyColors.divider),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── Price
                    _filterSectionLabel('💰 Price Range'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rs. ${tempPrice.start.round()}', style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                        )),
                        Text('Rs. ${tempPrice.end.round()}', style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                        )),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(ctx).copyWith(
                        activeTrackColor: NearBuyColors.orange,
                        inactiveTrackColor: NearBuyColors.divider,
                        thumbColor: NearBuyColors.navy,
                        overlayColor: NearBuyColors.navy.withOpacity(0.1),
                        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 9),
                      ),
                      child: RangeSlider(
                        min: _priceRangeMin,
                        max: _priceRangeMax,
                        divisions: 20,
                        values: tempPrice,
                        labels: RangeLabels(
                          'Rs. ${tempPrice.start.round()}',
                          'Rs. ${tempPrice.end.round()}',
                        ),
                        onChanged: (v) => setSheetState(() {
                          tempPrice = v;
                          tempPriceActive = !(v.start == _priceRangeMin && v.end == _priceRangeMax);
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Rating
                    _filterSectionLabel('⭐ Rating'),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        {'label': 'All Ratings', 'value': 0.0},
                        {'label': '4.0+ ⭐', 'value': 4.0},
                        {'label': '4.5+ ⭐', 'value': 4.5},
                      ].map((opt) {
                        final selected = tempRating == opt['value'];
                        return ChoiceChip(
                          label: Text(opt['label'] as String, style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: selected ? Colors.white : NearBuyColors.textSecondary,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          )),
                          selected: selected,
                          onSelected: (_) => setSheetState(() => tempRating = opt['value'] as double),
                          selectedColor: NearBuyColors.navy,
                          backgroundColor: NearBuyColors.cream,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: selected ? NearBuyColors.navy : NearBuyColors.divider),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── Availability
                    _filterSectionLabel('🟢 Availability'),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: ['All', 'Open Now', 'Closed'].map((label) {
                        final value = label == 'Open Now' ? 'Open' : label;
                        final selected = tempAvailability == value;
                        return ChoiceChip(
                          label: Text(label, style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: selected ? Colors.white : NearBuyColors.textSecondary,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          )),
                          selected: selected,
                          onSelected: (_) => setSheetState(() => tempAvailability = value),
                          selectedColor: NearBuyColors.navy,
                          backgroundColor: NearBuyColors.cream,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: selected ? NearBuyColors.navy : NearBuyColors.divider),
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // ── Reset / Apply
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setSheetState(() {
                              tempDistance = null;
                              tempPrice = const RangeValues(_priceRangeMin, _priceRangeMax);
                              tempPriceActive = false;
                              tempRating = 0;
                              tempAvailability = 'All';
                            }),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(color: NearBuyColors.divider),
                            ),
                            child: Text('Reset', style: GoogleFonts.poppins(
                              color: NearBuyColors.textSecondary, fontWeight: FontWeight.w600,
                            )),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: NearBuyColors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              setState(() {
                                _distanceFilterKm = tempDistance;
                                _priceFilter = tempPrice;
                                _priceFilterActive = tempPriceActive;
                                _ratingFilterMin = tempRating;
                                _availabilityFilter = tempAvailability;
                              });
                              Navigator.pop(ctx);
                            },
                            child: Text('Apply Filters', style: GoogleFonts.poppins(
                              color: Colors.white, fontWeight: FontWeight.w700,
                            )),
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
      },
    );
  }

  Widget _filterSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: GoogleFonts.poppins(
        fontSize: 13, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
      )),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (ctx, i) {
          final cat = _categories[i];
          final isSelected = _selectedCategory == cat['label'];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat['label']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? NearBuyColors.navy : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? NearBuyColors.navy : NearBuyColors.divider,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(color: NearBuyColors.navy.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3)),
                ] : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat['icon'] as IconData,
                    size: 15,
                    color: isSelected ? NearBuyColors.orange : NearBuyColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat['label'],
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : NearBuyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            'Shops Near You',
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const MapScreen()),
            ),
            child: Row(
              children: [
                Text('View Map', style: GoogleFonts.poppins(
                  fontSize: 12, color: NearBuyColors.orange, fontWeight: FontWeight.w600,
                )),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded, size: 10, color: NearBuyColors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getVerifiedShops(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: NearBuyColors.navy)),
          );
        }

        var docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (!_isBillingAllowed(data)) return false;
          // FIX: mandatory grace-period suspension gate — independent of
          // whether the shopkeeper's app is open/refreshed. See note block
          // at the top of this file.
          if (_isShopSuspendedByGracePeriod(doc.id)) return false;
          final name = (data['shop_name'] ?? '').toString().toLowerCase();
          if (_searchText.isNotEmpty && !name.contains(_searchText)) return false;
          if (_selectedCategory != 'All') {
            // Firestore shop doc stores the category under 'category',
            // but some older docs may still use 'shop_category' — check both
            // so filtering keeps working regardless of which field is set.
            final cat = (data['category'] ?? data['shop_category'] ?? '').toString();
            if (cat != _selectedCategory) return false;
          }
          // ── Advanced filters (distance / price / rating / open-closed) ──
          if (!_matchesDistanceFilter(data)) return false;
          if (!_matchesPriceFilter(doc.id, data)) return false;
          if (!_matchesRatingFilter(doc.id, data)) return false;
          if (!_matchesAvailabilityFilter(data)) return false;
          return true;
        }).toList();

        docs.sort((a, b) {
          final da = _distance(a.data() as Map<String, dynamic>);
          final db = _distance(b.data() as Map<String, dynamic>);
          return da.compareTo(db);
        });

        if (docs.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.store_mall_directory_outlined, size: 64, color: NearBuyColors.textHint),
                  const SizedBox(height: 12),
                  Text('No shops found', style: GoogleFonts.poppins(
                    fontSize: 16, color: NearBuyColors.textSecondary,
                  )),
                  if (_activeAdvancedFilterCount > 0) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _resetFilters,
                      child: Text('Clear filters', style: GoogleFonts.poppins(
                        fontSize: 13, color: NearBuyColors.orange, fontWeight: FontWeight.w600,
                      )),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              return _ShopCard(
                shopId: doc.id,
                data: data,
                distance: _distance(data),
                currentPosition: _currentPosition,
              );
            },
            childCount: docs.length,
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [NearBuyColors.navy, Color(0xFF243057)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: NearBuyColors.orange.withOpacity(0.2),
                          backgroundImage: _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null,
                          child: _profileImageUrl == null
                              ? Text(
                                  (_displayName ?? 'C')[0].toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: NearBuyColors.orange, shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _displayName ?? 'Customer',
                    style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
                    ),
                  ),
                  Text(
                    user?.email ?? '',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _drawerItem(Icons.person_outline_rounded, 'View Profile', () {
              Navigator.pop(context);
              _showProfileDialog();
            }),
            _drawerItem(Icons.receipt_long_rounded, 'My Orders', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
            }),
            _drawerItem(Icons.favorite_border_rounded, 'Favorites', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const _WishlistScreen()));
            }),
            _drawerItem(Icons.map_outlined, 'Explore Map', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen()));
            }),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Divider(),
            ),
            _drawerItem(Icons.logout_rounded, 'Logout', _logout, isDestructive: true),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive
              ? NearBuyColors.error.withOpacity(0.08)
              : NearBuyColors.navy.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18,
            color: isDestructive ? NearBuyColors.error : NearBuyColors.navy),
      ),
      title: Text(label, style: GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w500,
        color: isDestructive ? NearBuyColors.error : NearBuyColors.textPrimary,
      )),
      trailing: isDestructive ? null : Icon(
        Icons.arrow_forward_ios_rounded, size: 13, color: NearBuyColors.textHint,
      ),
      onTap: onTap,
    );
  }
}

// ─── Shop Card ─────────────────────────────────────────────
class _ShopCard extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic> data;
  final double distance;
  final Position? currentPosition;

  const _ShopCard({
    required this.shopId,
    required this.data,
    required this.distance,
    required this.currentPosition,
  });

  String get _categoryEmoji {
    switch ((data['category'] ?? data['shop_category'] ?? '').toString().toLowerCase()) {
      case 'grocery & general store': return '🛒';
      case 'clothing & fashion':      return '👕';
      case 'shoes & footwear':        return '👟';
      case 'electronics & mobiles':   return '📱';
      case 'pharmacy & health':       return '💊';
      case 'beauty & cosmetics':      return '💄';
      case 'bakery & sweets':         return '🍰';
      case 'restaurants & food':      return '🍽';
      case 'fruits & vegetables':     return '🥦';
      case 'meat & poultry':          return '🍗';
      case 'stationery & books':      return '📚';
      case 'hardware & tools':        return '🛠';
      case 'furniture & home decor':  return '🛋';
      case 'jewellery & accessories': return '💎';
      case 'sports & fitness':        return '⚽';
      case 'auto parts & accessories':return '🚗';
      case 'baby & kids':             return '🧸';
      case 'pet supplies':            return '🐾';
      case 'gifts & flowers':         return '🎁';
      default:                        return '🏪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopName = data['shop_name'] ?? 'Unknown Shop';

    // ── Address: Firestore mein 'shop_location' field hai
    final address = data['shop_location']
        ?? data['address']
        ?? data['location']
        ?? 'Address not available';

    final openTime  = data['open_time']  ?? '';
    final closeTime = data['close_time'] ?? '';

    // ── Shop image from Firestore
    final imageUrl = data['shop_image'] as String?
        ?? data['shop_image_url'] as String?;

    // ── Reviews: fetched live from Firestore sub-collection
    final distText = distance > 0 ? '${distance.toStringAsFixed(1)} km' : '';

    // ── Category: Firestore shop doc uses 'category', with 'shop_category'
    // kept as a fallback for older documents.
    final categoryLabel = data['category'] ?? data['shop_category'] ?? 'Shop';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShopProductsScreen(shopId: shopId, shopName: shopName),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: NearBuyColors.navy.withOpacity(0.06),
              blurRadius: 16, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image area (Firestore se fetch hoti hai)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderImage(),
                        )
                      : _placeholderImage(),
                ),
                // Distance badge
                if (distText.isNotEmpty)
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: NearBuyColors.navy,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.near_me_rounded, size: 11, color: NearBuyColors.orange),
                          const SizedBox(width: 4),
                          Text(distText, style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
                          )),
                        ],
                      ),
                    ),
                  ),
                // Category chip
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6)],
                    ),
                    child: Text(
                      '$_categoryEmoji  $categoryLabel',
                      style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Info area
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(shopName, style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
                        )),
                      ),
                      // Verified badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: NearBuyColors.verified.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_rounded, size: 12, color: NearBuyColors.verified),
                            const SizedBox(width: 3),
                            Text('Verified', style: GoogleFonts.poppins(
                              fontSize: 10, fontWeight: FontWeight.w600, color: NearBuyColors.verified,
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // ── Address from Firestore
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 13, color: NearBuyColors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(address, style: GoogleFonts.poppins(
                          fontSize: 12, color: NearBuyColors.textSecondary,
                        ), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ── Reviews from Firestore (StreamBuilder)
                  Row(
                    children: [
                      _FirestoreShopRating(shopId: shopId),
                      const Spacer(),
                      if (openTime.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 12, color: NearBuyColors.textSecondary),
                            const SizedBox(width: 4),
                            Text('$openTime – $closeTime', style: GoogleFonts.poppins(
                              fontSize: 11, color: NearBuyColors.textSecondary,
                            )),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderImage() {
    return Container(
      height: 120,
      color: NearBuyColors.navy.withOpacity(0.05),
      child: Center(
        child: Text(_categoryEmoji, style: const TextStyle(fontSize: 48)),
      ),
    );
  }
}

// ─── Firestore Shop Rating Widget (reviews subcollection se) ───
class _FirestoreShopRating extends StatelessWidget {
  final String shopId;
  const _FirestoreShopRating({required this.shopId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('reviews')
          .snapshots(),
      builder: (ctx, snapshot) {
        double avgRating = 0;
        int reviewCount = 0;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs;
          reviewCount = docs.length;
          double total = 0;
          for (var d in docs) {
            total += ((d.data() as Map<String, dynamic>)['rating'] ?? 0).toDouble();
          }
          avgRating = total / reviewCount;
        }
        return StarRatingRow(rating: avgRating, reviewCount: reviewCount);
      },
    );
  }
}

// ─── Wishlist / Favorites Screen (inline) ──────────────────
class _WishlistScreen extends StatelessWidget {
  const _WishlistScreen();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: NearBuyColors.cream,
      appBar: AppBar(
        backgroundColor: NearBuyColors.navy,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: RichText(
          text: TextSpan(children: [
            TextSpan(
              text: 'Near',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            TextSpan(
              text: 'Buy',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.orange),
            ),
            TextSpan(
              text: '  Favorites',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white60),
            ),
          ]),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .collection('favorites')
            .orderBy('savedAt', descending: true)
            .snapshots(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: NearBuyColors.navy));
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: NearBuyColors.navy.withOpacity(0.04),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.favorite_border_rounded, size: 64, color: NearBuyColors.textHint),
                  ),
                  const SizedBox(height: 20),
                  Text('No favorites yet', style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
                  )),
                  const SizedBox(height: 8),
                  Text('Save shops you love to find them quickly', style: GoogleFonts.poppins(
                    fontSize: 13, color: NearBuyColors.textSecondary,
                  )),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final shopId   = data['shopId']   ?? docs[i].id;
              final shopName = data['shopName'] ?? 'Unknown Shop';
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('shops').doc(shopId).get(),
                builder: (ctx, shopSnap) {
                  final shopData = shopSnap.data?.data() as Map<String, dynamic>?;
                  final imageUrl = shopData?['shop_image'] as String? ?? shopData?['shop_image_url'] as String?;
                  final address  = shopData?['address'] ?? shopData?['location'] ?? '';
                  final category = shopData?['category'] ?? shopData?['shop_category'] ?? '';
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ShopProductsScreen(shopId: shopId, shopName: shopName)),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: NearBuyColors.navy.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? Image.network(imageUrl, width: 90, height: 90, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholder(category))
                                : _placeholder(category),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(shopName, style: GoogleFonts.poppins(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
                                  )),
                                  if (category.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(category, style: GoogleFonts.poppins(
                                      fontSize: 12, color: NearBuyColors.orange, fontWeight: FontWeight.w500,
                                    )),
                                  ],
                                  if (address.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Icon(Icons.location_on_rounded, size: 12, color: NearBuyColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(address, style: GoogleFonts.poppins(
                                        fontSize: 11, color: NearBuyColors.textSecondary,
                                      ), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    ]),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Icon(Icons.favorite_rounded, color: Colors.red.shade400, size: 22),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _placeholder(String category) {
    String emoji = '🏪';
    switch (category.toLowerCase()) {
      case 'grocery & general store': emoji = '🛒'; break;
      case 'clothing & fashion':      emoji = '👕'; break;
      case 'shoes & footwear':        emoji = '👟'; break;
      case 'electronics & mobiles':   emoji = '📱'; break;
      case 'pharmacy & health':       emoji = '💊'; break;
      case 'beauty & cosmetics':      emoji = '💄'; break;
      case 'bakery & sweets':         emoji = '🍰'; break;
      case 'restaurants & food':      emoji = '🍽'; break;
      case 'fruits & vegetables':     emoji = '🥦'; break;
      case 'meat & poultry':          emoji = '🍗'; break;
      case 'stationery & books':      emoji = '📚'; break;
      case 'hardware & tools':        emoji = '🛠'; break;
      case 'furniture & home decor':  emoji = '🛋'; break;
      case 'jewellery & accessories': emoji = '💎'; break;
      case 'sports & fitness':        emoji = '⚽'; break;
      case 'auto parts & accessories':emoji = '🚗'; break;
      case 'baby & kids':             emoji = '🧸'; break;
      case 'pet supplies':            emoji = '🐾'; break;
      case 'gifts & flowers':         emoji = '🎁'; break;
    }
    return Container(
      width: 90, height: 90,
      color: NearBuyColors.navy.withOpacity(0.05),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 36))),
    );
  }
}