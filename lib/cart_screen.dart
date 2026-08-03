// ============================================================
//  cart_screen.dart — NearBuy Redesign
//  (with Delivery Location / Address support + Distance-Based
//   Delivery Charges)
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'order_confirmation_screen.dart';
import 'delivery_location_picker_screen.dart';
import 'nearbuy_theme.dart';

class CartScreen extends StatefulWidget {
  final String shopId;
  final String shopName;
  const CartScreen({super.key, required this.shopId, required this.shopName});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final user = FirebaseAuth.instance.currentUser;
  static const double platformFeePercent = 0.05;
  bool _placingOrder = false;

  // ─── Delivery charge rate table ──────────────────────────
  // Change these anytime — nothing else needs to be touched.
  static const double deliveryRate0to2km   = 50;
  static const double deliveryRate2to5km   = 80;
  static const double deliveryRate5to10km  = 120;
  static const double deliveryRateOver10km = 150;
  // Flat fallback charge when distance can't be calculated (manual
  // address, or shop coordinates missing/invalid).
  static const double manualAddressDeliveryCharge = 100;

  // ─── Delivery location state ─────────────────────────────
  double? _latitude;
  double? _longitude;
  String _deliveryAddress = '';
  bool _gettingLocation = false;
  // Manual address entry (used when the customer wants delivery at a
  // different address than their current GPS location)
  bool _useManualAddress = false;
  bool _isManualAddress = false;
  // True while the customer is actively choosing/changing a location —
  // controls whether the 3 selection options or the confirmed summary shows
  bool _editingLocation = true;
  final TextEditingController _manualAddressController = TextEditingController();

  // ─── Shop location + delivery charge state ───────────────
  double? _shopLat;
  double? _shopLng;
  double? _deliveryDistanceKm;
  double _deliveryCharge = 0;

  @override
  void initState() {
    super.initState();
    _fetchShopLocation();
  }

  @override
  void dispose() {
    _manualAddressController.dispose();
    super.dispose();
  }

  // Fetches the shop's stored coordinates once, then recalculates the
  // delivery charge in case a delivery location was already picked.
  Future<void> _fetchShopLocation() async {
    try {
      final shopDoc = await FirebaseFirestore.instance
          .collection('shops').doc(widget.shopId).get();
      final data = shopDoc.data();
      if (data != null) {
        final lat = data['location_lat'];
        final lng = data['location_lng'];
        if (lat is num && lng is num) {
          _shopLat = lat.toDouble();
          _shopLng = lng.toDouble();
        }
      }
    } catch (e) {
      debugPrint('Shop location fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _updateDeliveryCharge());
      }
    }
  }

  Stream<QuerySnapshot> _cartStream() => FirebaseFirestore.instance
      .collection('users').doc(user!.uid).collection('cart')
      .where('shopId', isEqualTo: widget.shopId)
      .snapshots();

  double _calculateSubtotal(List<QueryDocumentSnapshot> items) {
    double total = 0;
    for (var item in items) {
      final d = item.data() as Map<String, dynamic>;
      total += (d['price'] ?? 0) * (d['quantity'] ?? 1);
    }
    return total;
  }

  // ─── Distance-based delivery charge ──────────────────────
  double _calculateDeliveryCharge(double distanceKm) {
    if (distanceKm <= 2) return deliveryRate0to2km;
    if (distanceKm <= 5) return deliveryRate2to5km;
    if (distanceKm <= 10) return deliveryRate5to10km;
    return deliveryRateOver10km;
  }

  // Recomputes _deliveryDistanceKm and _deliveryCharge from current state.
  // Called after: shop location loads, current-location fetch, map picker
  // selection, and manual address save. Safe to call any time — never
  // throws, even with missing/null/invalid coordinates.
  void _updateDeliveryCharge() {
    if (_isManualAddress) {
      // Manual address: no coordinates, so distance can't be calculated.
      _deliveryDistanceKm = null;
      _deliveryCharge = manualAddressDeliveryCharge;
      return;
    }
    if (_latitude == null || _longitude == null) {
      // No delivery location picked yet.
      _deliveryDistanceKm = null;
      _deliveryCharge = 0;
      return;
    }
    if (_shopLat == null || _shopLng == null) {
      // Shop coordinates missing/invalid/not loaded yet — fall back to
      // the flat rate instead of crashing or charging Rs. 0.
      _deliveryDistanceKm = null;
      _deliveryCharge = manualAddressDeliveryCharge;
      return;
    }
    final distanceMeters = Geolocator.distanceBetween(
      _shopLat!, _shopLng!, _latitude!, _longitude!,
    );
    final distanceKm = distanceMeters / 1000;
    _deliveryDistanceKm = double.parse(distanceKm.toStringAsFixed(1));
    _deliveryCharge = _calculateDeliveryCharge(distanceKm);
  }

  Future<void> _updateQuantity(String docId, int newQty) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('cart').doc(docId);
    if (newQty <= 0) {
      await ref.delete();
    } else {
      await ref.update({'quantity': newQty});
    }
  }

  Future<void> _removeItem(String docId) async {
    await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('cart').doc(docId).delete();
  }

  // ─── Delivery location: fetch current location ───────────
  Future<void> _getCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      // 1. Check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationMessage(
          'Location services are disabled. Please enable location/GPS and try again.',
        );
        return;
      }

      // 2. Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationMessage(
            'Location permission denied. We need it to set your delivery address.',
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationMessage(
          'Location permission is permanently denied. Please enable it from app settings.',
          actionLabel: 'Open Settings',
          onAction: Geolocator.openAppSettings,
        );
        return;
      }

      // 3. Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 4. Convert to readable address
      String readableAddress = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          readableAddress = [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
      }

      if (readableAddress.trim().isEmpty) {
        // Fallback if reverse-geocoding fails but we still have coordinates
        readableAddress =
            'Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}';
      }

      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _deliveryAddress = readableAddress;
        _isManualAddress = false;
        _useManualAddress = false;
        _editingLocation = false;
        _updateDeliveryCharge();
      });
    } catch (e) {
      debugPrint('Location error: $e');
      _showLocationMessage('Could not get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  // ─── Delivery location: choose any point on the map ───────
  // Unlike current-location, this does NOT require the picked point to be
  // where the customer is standing — they can pick home, office, a
  // relative's house, or any other delivery point.
  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );
    if (result == null || !mounted) return; // customer backed out without confirming
    setState(() {
      _latitude = result['latitude'] as double?;
      _longitude = result['longitude'] as double?;
      _deliveryAddress = (result['address'] as String?) ?? '';
      _isManualAddress = false;
      _useManualAddress = false;
      _editingLocation = false;
      _updateDeliveryCharge();
    });
  }

  // Saves an address the customer typed in manually. No GPS coordinates
  // are attached for a manual address — only the text is stored, so the
  // customer can request delivery to any address, not just where they
  // are standing right now.
  void _saveManualAddress() {
    final text = _manualAddressController.text.trim();
    if (text.isEmpty) {
      _showLocationMessage('Please type a delivery address first.');
      return;
    }
    setState(() {
      _deliveryAddress = text;
      _latitude = null;
      _longitude = null;
      _isManualAddress = true;
      _useManualAddress = false;
      _editingLocation = false;
      _updateDeliveryCharge();
    });
  }

  void _showLocationMessage(String message, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: NearBuyColors.error,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, textColor: Colors.white, onPressed: onAction)
            : null,
      ),
    );
  }

  Future<void> _placeOrder(List<QueryDocumentSnapshot> cartItems, double subtotal) async {
    // Validate delivery location before creating the order.
    // A delivery address is mandatory either way; GPS coordinates are only
    // required when the address came from "Use Current Location" — a
    // manually typed address is valid without them.
    if (_deliveryAddress.trim().isEmpty) {
      _showLocationMessage('Please select your delivery location first.');
      return;
    }
    if (!_isManualAddress && (_latitude == null || _longitude == null)) {
      _showLocationMessage('Please select your delivery location first.');
      return;
    }

    setState(() => _placingOrder = true);
    try {
      final platformFee = subtotal * platformFeePercent;
      final totalAmount = subtotal + platformFee + _deliveryCharge;
      final List<Map<String, dynamic>> orderItems = cartItems.map((item) {
        final d = item.data() as Map<String, dynamic>;
        return {
          'productId': d['productId'], 'name': d['name'],
          'price': d['price'], 'quantity': d['quantity'], 'image_url': d['image_url'] ?? '',
        };
      }).toList();
      final orderRef = await FirebaseFirestore.instance.collection('orders').add({
        'customerId': user!.uid, 'customerEmail': user!.email,
        'shopId': widget.shopId, 'shopName': widget.shopName,
        'items': orderItems, 'subtotal': subtotal,
        'platformFee': platformFee,
        'deliveryCharge': _deliveryCharge,
        'deliveryDistanceKm': _deliveryDistanceKm,
        'totalAmount': totalAmount,
        'paymentMethod': 'Cash on Delivery', 'status': 'pending',
        'deliveryAddress': _deliveryAddress,
        'deliveryLocation': (_latitude != null && _longitude != null)
            ? {'latitude': _latitude, 'longitude': _longitude}
            : null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Clear cart
      final cartDocs = await FirebaseFirestore.instance
          .collection('users').doc(user!.uid).collection('cart')
          .where('shopId', isEqualTo: widget.shopId).get();
      for (var doc in cartDocs.docs) await doc.reference.delete();

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => OrderConfirmationScreen(
            orderId: orderRef.id,
            shopName: widget.shopName,
            totalAmount: totalAmount,
            deliveryAddress: _deliveryAddress,
            deliveryCharge: _deliveryCharge,
            deliveryDistanceKm: _deliveryDistanceKm,
          ),
        ));
      }
    } catch (e) {
      debugPrint('Order error: $e');
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NearBuyColors.cream,
      appBar: AppBar(
        backgroundColor: NearBuyColors.navy,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(text: TextSpan(children: [
              TextSpan(text: 'Near', style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
              )),
              TextSpan(text: 'Buy', style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.orange,
              )),
            ])),
            Text('My Cart', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white60)),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _cartStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: NearBuyColors.navy));
          }
          final cartItems = snapshot.data!.docs;
          if (cartItems.isEmpty) {
            return _buildEmptyCart();
          }
          final subtotal     = _calculateSubtotal(cartItems);
          final platformFee  = subtotal * platformFeePercent;
          final totalAmount  = subtotal + platformFee + _deliveryCharge;

          return Column(
            children: [
              // Shop name header strip
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: NearBuyColors.navy.withOpacity(0.04),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: NearBuyColors.navy.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.storefront_rounded, size: 16, color: NearBuyColors.navy),
                    ),
                    const SizedBox(width: 10),
                    Text(widget.shopName, style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
                    )),
                    const Spacer(),
                    Text('${cartItems.length} item${cartItems.length > 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(fontSize: 12, color: NearBuyColors.textSecondary)),
                  ],
                ),
              ),
              // Scrollable area: cart items + delivery location section.
              // Wrapping both together (instead of only the cart list) means
              // that when the delivery card grows taller — e.g. the manual
              // address field opens up — the extra content scrolls instead
              // of overflowing past the fixed Order Summary below.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      ListView.builder(
                        padding: const EdgeInsets.all(16),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cartItems.length,
                        itemBuilder: (ctx, i) => _CartItemTile(
                          doc: cartItems[i],
                          onUpdateQty: _updateQuantity,
                          onRemove: _removeItem,
                        ),
                      ),
                      // Delivery Location section
                      _buildDeliveryLocationSection(),
                    ],
                  ),
                ),
              ),
              // Order Summary
              _buildOrderSummary(subtotal, platformFee, totalAmount, cartItems),
            ],
          );
        },
      ),
    );
  }

  // ─── Delivery Location UI ─────────────────────────────────
  Widget _buildDeliveryLocationSection() {
    final hasAddress = _deliveryAddress.isNotEmpty;
    final showOptions = _editingLocation || !hasAddress;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: NearBuyColors.navy.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 16, color: NearBuyColors.navy),
              const SizedBox(width: 6),
              Text('Delivery Location', style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
              )),
            ],
          ),
          const SizedBox(height: 12),

          // ── Confirmed summary: shown once an address is picked and the
          // customer isn't actively changing it ──
          if (hasAddress && !showOptions) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isManualAddress ? Icons.edit_location_alt_rounded : Icons.location_on_rounded,
                  size: 15, color: NearBuyColors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _deliveryAddress,
                    style: GoogleFonts.poppins(
                      fontSize: 13, color: NearBuyColors.textPrimary, fontWeight: FontWeight.w600, height: 1.4,
                    ),
                  ),
                ),
                if (_isManualAddress) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: NearBuyColors.navy.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Manual', style: GoogleFonts.poppins(
                      fontSize: 9, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                    )),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _editingLocation = true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: NearBuyColors.navy.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(Icons.sync_alt_rounded, size: 14, color: NearBuyColors.navy),
                label: Text('Change Location', style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                )),
              ),
            ),
          ],

          // ── Selection options: current location / map / manual ──
          if (showOptions) ...[
            if (!hasAddress)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Please select your delivery location',
                  style: GoogleFonts.poppins(fontSize: 12, color: NearBuyColors.textHint),
                ),
              ),
            _locationOptionTile(
              icon: Icons.my_location_rounded,
              iconColor: NearBuyColors.navy,
              title: 'Use Current Location',
              subtitle: 'Use my current location',
              trailing: _gettingLocation
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: NearBuyColors.navy),
                    )
                  : null,
              onTap: _gettingLocation ? null : _getCurrentLocation,
            ),
            const SizedBox(height: 8),
            _locationOptionTile(
              icon: Icons.map_rounded,
              iconColor: NearBuyColors.orange,
              title: 'Choose on Map',
              subtitle: 'Select any delivery location on map',
              onTap: _gettingLocation ? null : _openMapPicker,
            ),
            const SizedBox(height: 8),
            _locationOptionTile(
              icon: Icons.edit_location_alt_rounded,
              iconColor: NearBuyColors.navy,
              title: 'Enter Address',
              subtitle: 'Enter delivery address manually',
              selected: _useManualAddress,
              onTap: _gettingLocation
                  ? null
                  : () => setState(() => _useManualAddress = !_useManualAddress),
            ),

            // Inline manual-address input, shown only when "Enter Address" is toggled on
            if (_useManualAddress) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _manualAddressController,
                maxLines: 2,
                minLines: 1,
                style: GoogleFonts.poppins(fontSize: 13, color: NearBuyColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. House 25, Street 4, Model Town, Lahore',
                  hintStyle: GoogleFonts.poppins(fontSize: 12, color: NearBuyColors.textHint),
                  filled: true,
                  fillColor: NearBuyColors.cream,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: _saveManualAddress,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NearBuyColors.navy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save Address', style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
                  )),
                ),
              ),
            ],

            // Cancel row — only useful once an address already exists,
            // so the customer can back out of "Change Location" mode
            if (hasAddress) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _editingLocation = false;
                    _useManualAddress = false;
                  }),
                  child: Text('Cancel', style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600, color: NearBuyColors.textSecondary,
                  )),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // Single tappable row used for each of the 3 delivery-location options
  Widget _locationOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
    bool selected = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? NearBuyColors.orange.withOpacity(0.06) : NearBuyColors.cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? NearBuyColors.orange.withOpacity(0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.poppins(
                    fontSize: 11, color: NearBuyColors.textSecondary,
                  )),
                ],
              ),
            ),
            if (trailing != null) trailing
            else Icon(Icons.chevron_right_rounded, size: 18, color: NearBuyColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: NearBuyColors.navy.withOpacity(0.04), shape: BoxShape.circle,
            ),
            child: Icon(Icons.shopping_cart_outlined, size: 64, color: NearBuyColors.textHint),
          ),
          const SizedBox(height: 20),
          Text('Your cart is empty', style: GoogleFonts.poppins(
            fontSize: 18, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
          )),
          const SizedBox(height: 8),
          Text('Add items from the shop to get started', style: GoogleFonts.poppins(
            fontSize: 13, color: NearBuyColors.textSecondary,
          )),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white),
            label: const Text('Browse Shop'),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(
      double subtotal, double platformFee, double totalAmount, List<QueryDocumentSnapshot> items) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: NearBuyColors.navy.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: NearBuyColors.divider, borderRadius: BorderRadius.circular(2),
          )),
          const SizedBox(height: 16),
          Text('Order Summary', style: GoogleFonts.poppins(
            fontSize: 15, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
          )),
          const SizedBox(height: 14),
          _summaryRow('Subtotal', 'Rs. ${subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _summaryRow('Platform Fee (5%)', 'Rs. ${platformFee.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _summaryRow('Delivery Charges', 'Rs. ${_deliveryCharge.toStringAsFixed(0)}'),
          if (_deliveryDistanceKm != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                Text(
                  'Delivery Distance: ${_deliveryDistanceKm!.toStringAsFixed(1)} km',
                  style: GoogleFonts.poppins(fontSize: 11, color: NearBuyColors.textHint),
                ),
              ],
            ),
          ] else if (_isManualAddress) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                Text(
                  'Fixed rate (manual address)',
                  style: GoogleFonts.poppins(fontSize: 11, color: NearBuyColors.textHint),
                ),
              ],
            ),
          ],
          const Divider(height: 20),
          Row(
            children: [
              Text('Total', style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
              )),
              const Spacer(),
              Text('Rs. ${totalAmount.toStringAsFixed(0)}', style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w800, color: NearBuyColors.navy,
              )),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 14, color: NearBuyColors.textSecondary),
              const SizedBox(width: 6),
              Text('Cash on Delivery', style: GoogleFonts.poppins(
                fontSize: 12, color: NearBuyColors.textSecondary,
              )),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _placingOrder ? null : () => _placeOrder(items, subtotal),
              style: ElevatedButton.styleFrom(
                backgroundColor: NearBuyColors.orange,
                disabledBackgroundColor: NearBuyColors.orange.withOpacity(0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _placingOrder
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text('Place Order  •  Rs. ${totalAmount.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                      )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: NearBuyColors.textSecondary)),
        const Spacer(),
        Text(value, style: GoogleFonts.poppins(
          fontSize: 13, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
        )),
      ],
    );
  }
}

// ─── Cart Item Tile ────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Future<void> Function(String, int) onUpdateQty;
  final Future<void> Function(String) onRemove;

  const _CartItemTile({required this.doc, required this.onUpdateQty, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final data     = doc.data() as Map<String, dynamic>;
    final name     = data['name'] ?? 'Product';
    final price    = (data['price'] ?? 0).toDouble();
    final qty      = data['quantity'] as int? ?? 1;
    final imageUrl = data['image_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: NearBuyColors.navy.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(imageUrl, width: 64, height: 64, fit: BoxFit.cover)
                : Container(
                    width: 64, height: 64,
                    color: NearBuyColors.cream,
                    child: const Icon(Icons.shopping_bag_outlined, color: NearBuyColors.textHint),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
                )),
                const SizedBox(height: 4),
                Text('Rs. ${price.toStringAsFixed(0)} each', style: GoogleFonts.poppins(
                  fontSize: 11, color: NearBuyColors.textSecondary,
                )),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Rs. ${(price * qty).toStringAsFixed(0)}', style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w800, color: NearBuyColors.navy,
              )),
              const SizedBox(height: 6),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => onUpdateQty(doc.id, qty - 1),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: qty == 1 ? NearBuyColors.error.withOpacity(0.08) : NearBuyColors.navy.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                        size: 15,
                        color: qty == 1 ? NearBuyColors.error : NearBuyColors.navy,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('$qty', style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700, color: NearBuyColors.textPrimary,
                    )),
                  ),
                  GestureDetector(
                    onTap: () => onUpdateQty(doc.id, qty + 1),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: NearBuyColors.navy.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_rounded, size: 15, color: NearBuyColors.navy),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}