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
  /// If set, this destination will be highlighted and a route drawn immediately.
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

  final List<String> _categories = ['All', 'Grocery', 'Pharmacy', 'Electronics', 'Restaurant', 'Clothing'];

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
    switch (category.toLowerCase()) {
      case 'grocery':     return const Color(0xFF10B981);
      case 'pharmacy':    return const Color(0xFF3B82F6);
      case 'electronics': return const Color(0xFFF59E0B);
      case 'restaurant':  return const Color(0xFFEF4444);
      case 'clothing':    return const Color(0xFFEC4899);
      default:            return NearBuyColors.navy;
    }
  }

  Future<BitmapDescriptor> _createCustomMarker(String shopName, Color color) async {
    const double w = 300, h = 130;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Drop pin
    final pinPaint = Paint()..color = color;
    canvas.drawCircle(const Offset(56, 56), 34, pinPaint);
    // White inner
    canvas.drawCircle(const Offset(56, 56), 20, Paint()..color = Colors.white);
    // Store icon - simplified circle
    canvas.drawCircle(const Offset(56, 56), 10, Paint()..color = color);
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
      Set<Marker> markers = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lat  = data['location_lat'] as double?;
        final lng  = data['location_lng'] as double?;
        if (lat == null || lng == null) continue;

        final category = data['shop_category'] ?? 'Other';
        final shopName = data['shop_name']     ?? 'Shop';
        final color = _getCategoryColor(category);

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

        final icon = await _createCustomMarker(shopName, color);
        final shopInfo = _ShopInfo(
          id: doc.id, name: shopName, category: category,
          lat: lat, lng: lng, avgRating: avgRating, reviewCount: reviewCount,
          address: data['address'] ?? '', phone: data['phone'] ?? '',
        );

        markers.add(Marker(
          markerId: MarkerId(doc.id),
          position: LatLng(lat, lng),
          icon: icon,
          onTap: () {
            setState(() {
              _selectedShop = shopInfo;
              _showRoutePanel = true;
            });
          },
        ));
      }
      if (mounted) setState(() => _shopMarkers = markers);
    });
  }

  // ─── Open Google Maps with Directions ─────────────────
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

  // ─── Navigate to shop page ─────────────────────────────
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
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: NearBuyColors.orange))
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
          final isSelected = (_selectedCategory ?? 'All') == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat == 'All' ? null : cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? NearBuyColors.orange : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)],
              ),
              child: Text(cat, style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : NearBuyColors.textPrimary,
              )),
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
                  child: Icon(Icons.storefront_rounded,
                      color: _getCategoryColor(shop.category), size: 26),
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
                StarRatingRow(rating: shop.avgRating, reviewCount: shop.reviewCount),
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

// ─── Shop Info Model ───────────────────────────────────────
class _ShopInfo {
  final String id, name, category, address, phone;
  final double lat, lng, avgRating;
  final int reviewCount;

  const _ShopInfo({
    required this.id, required this.name, required this.category,
    required this.lat, required this.lng, required this.avgRating,
    required this.reviewCount, required this.address, required this.phone,
  });
}