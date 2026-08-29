// ============================================================
//  screens/map_screen.dart — NearBuy Redesign
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../services/location_service.dart';
import '../shop_products_screen.dart';
import '../nearbuy_theme.dart';

class MapScreen extends StatefulWidget {
  final double? destinationLat;
  final double? destinationLng;
  final String? destinationName;

  const MapScreen({
    super.key,
    this.destinationLat,
    this.destinationLng,
    this.destinationName,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  LatLng? _currentLatLng;
  Set<Marker> _shopMarkers = {};
  Set<Polyline> _routeLines = {};
  String? _selectedCategory;
  bool _isLoading = true;
  _ShopInfo? _selectedShop;
  bool _showRoutePanel = false;
  
  // ─── All shops data for filtering ──────────────────────────
  List<_ShopInfo> _allShops = [];
  bool _isFiltering = false;

  // ─── Complete Categories List (same as Customer Dashboard) ──
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
    _getCurrentLocation();
    _fetchVerifiedShops();
  }

  void _getCurrentLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentLatLng = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });
        mapController?.animateCamera(CameraUpdate.newLatLng(_currentLatLng!));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getCategoryColor(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('grocery') || cat.contains('general store')) return const Color(0xFF10B981);
    if (cat.contains('pharmacy') || cat.contains('health')) return const Color(0xFF3B82F6);
    if (cat.contains('electronic') || cat.contains('mobile')) return const Color(0xFFF59E0B);
    if (cat.contains('restaurant') || cat.contains('food')) return const Color(0xFFEF4444);
    if (cat.contains('clothing') || cat.contains('fashion')) return const Color(0xFFEC4899);
    if (cat.contains('beauty') || cat.contains('cosmetic')) return const Color(0xFF8B5CF6);
    if (cat.contains('bakery') || cat.contains('sweet')) return const Color(0xFFF472B6);
    if (cat.contains('furniture') || cat.contains('decor')) return const Color(0xFF8B5CF6);
    if (cat.contains('jewellery') || cat.contains('accessories')) return const Color(0xFFF59E0B);
    if (cat.contains('sports') || cat.contains('fitness')) return const Color(0xFF10B981);
    if (cat.contains('auto') || cat.contains('parts')) return const Color(0xFF6B7280);
    if (cat.contains('baby') || cat.contains('kids')) return const Color(0xFFF472B6);
    if (cat.contains('pet')) return const Color(0xFF8B5CF6);
    if (cat.contains('gift') || cat.contains('flower')) return const Color(0xFFEC4899);
    return NearBuyColors.navy;
  }

  String _getCategoryEmoji(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('grocery') || cat.contains('general store')) return '🛒';
    if (cat.contains('clothing') || cat.contains('fashion')) return '👕';
    if (cat.contains('shoe') || cat.contains('footwear')) return '👟';
    if (cat.contains('electronic') || cat.contains('mobile')) return '📱';
    if (cat.contains('pharmacy') || cat.contains('health')) return '💊';
    if (cat.contains('beauty') || cat.contains('cosmetic')) return '💄';
    if (cat.contains('bakery') || cat.contains('sweet')) return '🍰';
    if (cat.contains('restaurant') || cat.contains('food')) return '🍽';
    if (cat.contains('fruit') || cat.contains('vegetable')) return '🥦';
    if (cat.contains('meat') || cat.contains('poultry')) return '🍗';
    if (cat.contains('stationery') || cat.contains('book')) return '📚';
    if (cat.contains('hardware') || cat.contains('tool')) return '🛠';
    if (cat.contains('furniture') || cat.contains('decor')) return '🛋';
    if (cat.contains('jewellery') || cat.contains('accessories')) return '💎';
    if (cat.contains('sports') || cat.contains('fitness')) return '⚽';
    if (cat.contains('auto') || cat.contains('parts')) return '🚗';
    if (cat.contains('baby') || cat.contains('kids')) return '🧸';
    if (cat.contains('pet')) return '🐾';
    if (cat.contains('gift') || cat.contains('flower')) return '🎁';
    return '🏪';
  }

  Future<BitmapDescriptor> _createCustomMarker(String shopName, String category) async {
    const double w = 300, h = 130;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final color = _getCategoryColor(category);
    final emoji = _getCategoryEmoji(category);

    // Drop pin
    final pinPaint = Paint()..color = color;
    canvas.drawCircle(const Offset(56, 56), 34, pinPaint);
    // White inner
    canvas.drawCircle(const Offset(56, 56), 20, Paint()..color = Colors.white);
    // Store icon - emoji
    final tpEmoji = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    );
    tpEmoji.layout();
    tpEmoji.paint(canvas, Offset(56 - tpEmoji.width / 2, 56 - tpEmoji.height / 2));
    // Pin tip
    final path = Path()
      ..moveTo(56, 95)..lineTo(42, 70)..lineTo(70, 70)..close();
    canvas.drawPath(path, pinPaint);

    // White label
    final labelRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(102, 25, 178, 50), const Radius.circular(12),
    );
    canvas.drawRRect(labelRect, Paint()..color = Colors.white);
    canvas.drawRRect(labelRect, Paint()
      ..color = Colors.black12..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final tp = TextPainter(
      text: TextSpan(
        text: shopName.length > 18 ? '${shopName.substring(0, 18)}...' : shopName,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A2340)),
      ),
      textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '...',
    );
    tp.layout(maxWidth: 158);
    tp.paint(canvas, Offset(112, 38));

    final img = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _fetchVerifiedShops() {
    FirebaseFirestore.instance
        .collection('shops')
        .where('status', isEqualTo: 'verified')
        .snapshots()
        .listen((snapshot) async {
      List<_ShopInfo> shops = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lat = data['location_lat'] as double?;
        final lng = data['location_lng'] as double?;
        if (lat == null || lng == null) continue;

        final category = data['category'] ?? data['shop_category'] ?? 'Other';
        final shopName = data['shop_name'] ?? 'Shop';

        double avgRating = 0.0;
        int reviewCount = 0;
        try {
          final reviews = await FirebaseFirestore.instance
              .collection('shops').doc(doc.id).collection('reviews').get();
          reviewCount = reviews.docs.length;
          if (reviewCount > 0) {
            double total = 0;
            for (var r in reviews.docs) total += (r.data()['rating'] ?? 0).toDouble();
            avgRating = total / reviewCount;
          }
        } catch (_) {}

        shops.add(_ShopInfo(
          id: doc.id,
          name: shopName,
          category: category,
          lat: lat,
          lng: lng,
          avgRating: avgRating,
          reviewCount: reviewCount,
          address: data['shop_location'] ?? data['address'] ?? data['location'] ?? '',
          phone: data['phone'] ?? data['mobile'] ?? '',
        ));
      }

      // Store all shops for filtering
      _allShops = shops;
      
      // Apply category filter if selected
      await _applyFilter(_selectedCategory);
      
      if (mounted) setState(() => _isFiltering = false);
    });
  }

  Future<void> _applyFilter(String? category) async {
    if (_allShops.isEmpty) return;
    
    setState(() => _isFiltering = true);
    
    List<_ShopInfo> filteredShops = _allShops;
    
    // Filter by category
    if (category != null && category != 'All') {
      filteredShops = _allShops.where((shop) {
        final shopCat = shop.category.toLowerCase().trim();
        final filterCat = category.toLowerCase().trim();
        return shopCat.contains(filterCat) || filterCat.contains(shopCat);
      }).toList();
    }

    // Create markers for filtered shops
    Set<Marker> markers = {};
    for (var shop in filteredShops) {
      final icon = await _createCustomMarker(shop.name, shop.category);
      markers.add(Marker(
        markerId: MarkerId(shop.id),
        position: LatLng(shop.lat, shop.lng),
        icon: icon,
        onTap: () {
          setState(() {
            _selectedShop = shop;
            _showRoutePanel = true;
          });
        },
      ));
    }

    if (mounted) {
      setState(() {
        _shopMarkers = markers;
        _isFiltering = false;
      });
    }

    // If a shop is selected and we have filtered, keep it selected
    if (_selectedShop != null && !filteredShops.any((s) => s.id == _selectedShop!.id)) {
      setState(() {
        _selectedShop = null;
        _showRoutePanel = false;
      });
    }
  }

  Future<void> _openGoogleMapsDirections(_ShopInfo shop) async {
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${shop.lat},${shop.lng}'
      '&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _goToShop(_ShopInfo shop) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ShopProductsScreen(shopId: shop.id, shopName: shop.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NearBuyColors.navy,
      body: Stack(
        children: [
          // Map
          _isLoading || _isFiltering
              ? const Center(
                  child: CircularProgressIndicator(color: NearBuyColors.orange),
                )
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentLatLng ?? const LatLng(31.5204, 74.3587),
                    zoom: 14,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: _shopMarkers,
                  polylines: _routeLines,
                  onMapCreated: (ctrl) {
                    mapController = ctrl;
                    if (_currentLatLng != null) {
                      ctrl.animateCamera(CameraUpdate.newLatLngZoom(_currentLatLng!, 14));
                    }
                  },
                  onTap: (_) {
                    setState(() {
                      _selectedShop = null;
                      _showRoutePanel = false;
                    });
                  },
                ),

          // Top AppBar overlay
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 8),
                _buildCategoryFilter(),
              ],
            ),
          ),

          // My Location FAB
          Positioned(
            bottom: _showRoutePanel ? 300 : 100,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'location_fab',
              backgroundColor: Colors.white,
              onPressed: () {
                if (_currentLatLng != null) {
                  mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentLatLng!, 15));
                }
              },
              child: const Icon(Icons.my_location_rounded, color: NearBuyColors.navy),
            ),
          ),

          // Shop count badge
          Positioned(
            bottom: _showRoutePanel ? 370 : 170,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: NearBuyColors.navy,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8),
                ],
              ),
              child: Text(
                '${_shopMarkers.length} shops',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Bottom Sheet: Selected Shop
          if (_showRoutePanel && _selectedShop != null)
            _buildShopBottomPanel(_selectedShop!),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NearBuyColors.navy,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: 'Near', style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
              )),
              TextSpan(text: 'Buy', style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.orange,
              )),
              TextSpan(text: '  Map', style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.white60,
              )),
            ]),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: NearBuyColors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NearBuyColors.orange.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(
                  color: NearBuyColors.orange, shape: BoxShape.circle,
                )),
                const SizedBox(width: 6),
                Text('Live', style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: NearBuyColors.orange,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (ctx, i) {
          final cat = _categories[i];
          final isSelected = (_selectedCategory ?? 'All') == cat['label'];
          return GestureDetector(
            onTap: () {
              final newCategory = cat['label'] == 'All' ? null : cat['label'] as String;
              setState(() {
                _selectedCategory = newCategory;
              });
              _applyFilter(newCategory);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? NearBuyColors.orange : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat['icon'] as IconData,
                    size: 14,
                    color: isSelected ? Colors.white : NearBuyColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    cat['label'],
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : NearBuyColors.textPrimary,
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

  Widget _buildShopBottomPanel(_ShopInfo shop) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: NearBuyColors.divider, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            // Shop header
            Row(
              children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: _getCategoryColor(shop.category).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _getCategoryEmoji(shop.category),
                    style: const TextStyle(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.name, style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
                      )),
                      Text(shop.category, style: GoogleFonts.poppins(
                        fontSize: 12, color: NearBuyColors.textSecondary,
                      )),
                    ],
                  ),
                ),
                _StarRatingRowInline(rating: shop.avgRating, reviewCount: shop.reviewCount),
              ],
            ),
            if (shop.address.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.location_on_rounded, size: 14, color: NearBuyColors.orange),
                  const SizedBox(width: 6),
                  Expanded(child: Text(shop.address, style: GoogleFonts.poppins(
                    fontSize: 12, color: NearBuyColors.textSecondary,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: [
                // View Shop
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _goToShop(shop),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: NearBuyColors.navy, width: 1.5),
                    ),
                    icon: const Icon(Icons.storefront_rounded, size: 16, color: NearBuyColors.navy),
                    label: Text('View Shop', style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                    )),
                  ),
                ),
                const SizedBox(width: 12),
                // Get Directions
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _openGoogleMapsDirections(shop),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NearBuyColors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.directions_rounded, size: 18, color: Colors.white),
                    label: Text('Get Directions', style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
                    )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Route info pills
            Row(
              children: [
                _routePill(Icons.directions_car_rounded, 'Driving', NearBuyColors.navy),
                const SizedBox(width: 8),
                _routePill(Icons.directions_walk_rounded, 'Walking', NearBuyColors.textSecondary),
                const SizedBox(width: 8),
                _routePill(Icons.directions_transit_rounded, 'Transit', NearBuyColors.textSecondary),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NearBuyColors.orange.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NearBuyColors.orange.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: NearBuyColors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Tap "Get Directions" to open Google Maps with shortest route & alternate routes.',
                    style: GoogleFonts.poppins(fontSize: 11, color: NearBuyColors.orange),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routePill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color,
          )),
        ],
      ),
    );
  }
}

// ─── Star Rating Row Widget (Inline) ──────────────────────
class _StarRatingRowInline extends StatelessWidget {
  final double rating;
  final int reviewCount;

  const _StarRatingRowInline({required this.rating, required this.reviewCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(5, (i) {
          if (i < rating.floor()) {
            return const Icon(Icons.star_rounded, color: NearBuyColors.orange, size: 14);
          } else if (i < rating.ceil() && rating % 1 >= 0.25) {
            return const Icon(Icons.star_half_rounded, color: NearBuyColors.orange, size: 14);
          } else {
            return Icon(Icons.star_border_rounded, color: NearBuyColors.textHint, size: 14);
          }
        }),
        const SizedBox(width: 4),
        Text(
          '${rating.toStringAsFixed(1)} ($reviewCount)',
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: NearBuyColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── Shop Info Model ───────────────────────────────────────
class _ShopInfo {
  final String id, name, category, address, phone;
  final double lat, lng, avgRating;
  final int reviewCount;

  const _ShopInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.avgRating,
    required this.reviewCount,
    required this.address,
    required this.phone,
  });
}