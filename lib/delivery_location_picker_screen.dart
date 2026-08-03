// ============================================================
//  delivery_location_picker_screen.dart — NearBuy
//  Lets the customer pick ANY delivery point on a map — their
//  home, office, a relative's place, etc. — not just wherever
//  their device currently is.
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'nearbuy_theme.dart';

class DeliveryLocationPickerScreen extends StatefulWidget {
  /// Optional starting point — pass the customer's last-picked
  /// coordinates (if any) so the map opens centered there instead
  /// of a hardcoded default.
  final double? initialLatitude;
  final double? initialLongitude;

  const DeliveryLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<DeliveryLocationPickerScreen> createState() => _DeliveryLocationPickerScreenState();
}

class _DeliveryLocationPickerScreenState extends State<DeliveryLocationPickerScreen> {
  // Fallback center if the customer has no previous location on file.
  static const LatLng _fallbackCenter = LatLng(31.5204, 74.3587); // Lahore

  GoogleMapController? _mapController;
  late LatLng _pickedLatLng;
  String _previewAddress = 'Move the map to select your delivery point';
  bool _resolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _pickedLatLng = (widget.initialLatitude != null && widget.initialLongitude != null)
        ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
        : _fallbackCenter;
  }

  Future<void> _resolveAddress(LatLng position) async {
    setState(() => _resolvingAddress = true);
    String resolved;
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.street, p.subLocality, p.locality, p.administrativeArea]
            .where((part) => part != null && part.trim().isNotEmpty)
            .toList();
        resolved = parts.join(', ');
      } else {
        resolved = '';
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      resolved = '';
    }

    if (resolved.trim().isEmpty) {
      resolved = 'Lat: ${position.latitude.toStringAsFixed(5)}, '
          'Lng: ${position.longitude.toStringAsFixed(5)}';
    }

    if (!mounted) return;
    setState(() {
      _previewAddress = resolved;
      _resolvingAddress = false;
    });
  }

  void _confirmLocation() {
    Navigator.pop<Map<String, dynamic>>(context, {
      'latitude': _pickedLatLng.latitude,
      'longitude': _pickedLatLng.longitude,
      'address': _previewAddress,
    });
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
        title: Text('Choose Delivery Location', style: GoogleFonts.poppins(
          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
        )),
      ),
      body: Stack(
        children: [
          // Map — the pin stays fixed in the center of the screen; the
          // customer drags/pans the MAP underneath it instead of dragging
          // a marker. This is the standard, reliable "center-pin" pattern.
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _pickedLatLng, zoom: 15),
            onMapCreated: (controller) {
              _mapController = controller;
              _resolveAddress(_pickedLatLng);
            },
            onCameraMove: (position) => _pickedLatLng = position.target,
            onCameraIdle: () => _resolveAddress(_pickedLatLng),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
          ),

          // Fixed center pin
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(Icons.location_on_rounded, size: 46, color: NearBuyColors.orange),
              ),
            ),
          ),

          // Bottom sheet: address preview + confirm button
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: NearBuyColors.navy.withOpacity(0.18), blurRadius: 18, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_rounded, size: 16, color: NearBuyColors.navy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _resolvingAddress ? 'Locating address...' : _previewAddress,
                          style: GoogleFonts.poppins(
                            fontSize: 12, color: NearBuyColors.textSecondary, height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _resolvingAddress ? null : _confirmLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NearBuyColors.orange,
                        disabledBackgroundColor: NearBuyColors.orange.withOpacity(0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Confirm Location', style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white,
                      )),
                    ),
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