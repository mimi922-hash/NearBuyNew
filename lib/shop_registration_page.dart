import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/cloudinary_service.dart';

class ShopRegistrationPage extends StatefulWidget {
  const ShopRegistrationPage({super.key});
  @override
  State<ShopRegistrationPage> createState() => _ShopRegistrationPageState();
}

class _ShopRegistrationPageState extends State<ShopRegistrationPage> {
  // ── Brand Colors ──
  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color lightNavy    = Color(0xFF1A3A5C);
  static const Color bgColor      = Color(0xFFF8FAFC);

  // All controllers, logic variables unchanged ──────────
  final _formKey = GlobalKey<FormState>();
  final PageController _pageController = PageController();
  final _ownerNameController    = TextEditingController();
  final _ownerEmailController   = TextEditingController();
  final _ownerContactController = TextEditingController(text: '03');
  final _shopNameController     = TextEditingController();
  final _cnicController         = TextEditingController();
  final _regNoController        = TextEditingController();
  String? _shopCategory;
  final _shopLocationController = TextEditingController();
  LatLng? _selectedLocation;
  GoogleMapController? _mapController;
  int _currentStep = 0;
  final user = FirebaseAuth.instance.currentUser;
  File? _cnicFrontImage, _cnicBackImage, _shopImage;
  String? _cnicFrontUrl, _cnicBackUrl, _shopImageUrl;

  // ✅ NEW — field length limits & name-format helper (validation additions only)
  static const int _ownerNameMaxLength = 50;
  static const int _shopNameMaxLength  = 50;
  static const int _phoneMaxLength     = 12;  // "03xx-xxxxxxx"
  static const int _cnicMaxLength      = 15;  // "XXXXX-XXXXXXX-X"
  static const int _regNoMaxLength     = 10;  // "REG-123456"
  static const int _addressMaxLength   = 150;
  static final RegExp _nameRegex = RegExp(r'^[a-zA-Z\s]{3,50}$');
  bool _isValidName(String name) => _nameRegex.hasMatch(name);

  // ✅ Replaces the old groceryCategories list — these exact 20 categories
  // must match the Customer Dashboard's category chips (NearBuyColors filter)
  // so that category-based filtering works correctly on both sides.
  final List<String> shopCategories = [
    'Grocery & General Store',
    'Clothing & Fashion',
    'Shoes & Footwear',
    'Electronics & Mobiles',
    'Pharmacy & Health',
    'Beauty & Cosmetics',
    'Bakery & Sweets',
    'Restaurants & Food',
    'Fruits & Vegetables',
    'Meat & Poultry',
    'Stationery & Books',
    'Hardware & Tools',
    'Furniture & Home Decor',
    'Jewellery & Accessories',
    'Sports & Fitness',
    'Auto Parts & Accessories',
    'Baby & Kids',
    'Pet Supplies',
    'Gifts & Flowers',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _ownerEmailController.text = user?.email ?? '';
    // ✅ "REG-" prefix is always present; user only types the 6 digits after it.
    _regNoController.text = 'REG-';
  }

  void _nextStep() {
    if (_formKey.currentState!.validate()) {
      if (_currentStep < 2) {
        setState(() => _currentStep++);
        _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      } else { _submitForm(); }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ UPDATED — pickImage() now lets the user choose between
  // Camera and Gallery via a bottom sheet, instead of always
  // going straight to the gallery. Return type / callers unchanged
  // (still returns File? and is awaited the same way everywhere).
  // ─────────────────────────────────────────────────────────
  Future<File?> pickImage() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.camera_alt_outlined, color: accentOrange),
                  ),
                  title: const Text('Take a Photo', style: TextStyle(color: primaryNavy, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: accentOrange),
                  ),
                  title: const Text('Choose from Gallery', style: TextStyle(color: primaryNavy, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return null;

    final XFile? image = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (image != null) return File(image.path);
    return null;
  }

  Future<void> _submitForm() async {
    // ✅ Location is mandatory — this is a second safety net in addition to
    // the field validator, since Step 3's validator only runs when the
    // user is currently on that page's Form context.
    if (_selectedLocation == null || _shopLocationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid shop location before submitting.')),
      );
      return;
    }

    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF6A1A))));
    try {
      if (_shopImage != null) _shopImageUrl = await CloudinaryService.uploadImage(_shopImage!, 'nearbuy_preset');
      if (_cnicFrontImage != null) _cnicFrontUrl = await CloudinaryService.uploadImage(_cnicFrontImage!, 'nearbuy_preset');
      if (_cnicBackImage != null) _cnicBackUrl = await CloudinaryService.uploadImage(_cnicBackImage!, 'nearbuy_preset');
      await FirebaseFirestore.instance.collection('shops').add({
        'ownerUid': FirebaseAuth.instance.currentUser!.uid,
        'owner_name': _ownerNameController.text,
        'owner_email': _ownerEmailController.text,
        'owner_contact': _ownerContactController.text,
        'shop_name': _shopNameController.text,
        'shop_category': _shopCategory,
        'cnic_number': _cnicController.text,
        'registration_no': _regNoController.text,
        'shop_location': _shopLocationController.text,
        'location_lat': _selectedLocation?.latitude ?? 0.0,
        'location_lng': _selectedLocation?.longitude ?? 0.0,
        'location_geo': _selectedLocation != null
            ? GeoPoint(_selectedLocation!.latitude, _selectedLocation!.longitude) : GeoPoint(0, 0),
        'cnic_front_url': _cnicFrontUrl ?? '',
        'cnic_back_url': _cnicBackUrl ?? '',
        'shop_image_url': _shopImageUrl ?? '',
        'status': 'pending',
        'created_at': Timestamp.now(),
      });
      Navigator.pop(context); Navigator.pop(context);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit')));
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ NEW — Flexible Shop Location system
  // Replaces the old single "_pickLocation()" (current-GPS-only) flow with
  // three explicit options, since the shopkeeper may be registering a shop
  // they are not physically standing at. Firestore fields untouched:
  // still writes location_lat / location_lng / location_geo exactly as before.
  // ─────────────────────────────────────────────────────────

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationMessage('Please enable location services to use current location.');
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showLocationMessage('Location permission denied.');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showLocationMessage('Location permission permanently denied. Please enable it from app settings.');
      return false;
    }
    return true;
  }

  Future<String?> _reverseGeocode(LatLng latLng) async {
    try {
      final placemarks = await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = [p.street, p.locality, p.administrativeArea]
          .where((e) => e != null && e.trim().isNotEmpty)
          .toList();
      return parts.isNotEmpty ? parts.join(', ') : null;
    } catch (_) {
      return null;
    }
  }

  // ── Option 1: Use Current Location ──
  Future<void> _useCurrentLocation() async {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: accentOrange)));
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final latLng = LatLng(pos.latitude, pos.longitude);
      final address = await _reverseGeocode(latLng);
      if (!mounted) return;
      Navigator.pop(context); // close loader
      setState(() {
        _selectedLocation = latLng;
        _shopLocationController.text =
            address ?? '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
      });
      if (address == null) {
        _showLocationMessage('Location saved, but a readable address could not be found for this point.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showLocationMessage('Failed to fetch current location.');
    }
  }

  // ✅ NEW — Search a typed place name / address and jump the dialog map to
  // it. Used only inside the "Select Location on Map" dialog's search bar.
  // Does not touch _selectedLocation directly — only updates the temporary
  // pin (tempLocation) via setDialogState, exactly like tap/drag already do,
  // so the user still has to press "Confirm Location" to save it.
  Future<void> _searchOnMapDialog(
      String query, void Function(LatLng) onFound, StateSetter setDialogState) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      final locations = await locationFromAddress(trimmed);
      if (locations.isEmpty) {
        _showLocationMessage('No results found for "$trimmed".');
        return;
      }
      final found = LatLng(locations.first.latitude, locations.first.longitude);
      onFound(found);
      await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(found, 16));
    } catch (e) {
      _showLocationMessage('Could not search for "$trimmed". Please try a different search term.');
    }
  }

  // ── Option 2: Select Location on Map (tap, drag, or search — not restricted to current position) ──
  Future<void> _selectOnMap() async {
    LatLng initial = _selectedLocation ?? const LatLng(31.5204, 74.3587); // Lahore fallback

    if (_selectedLocation == null) {
      // Best-effort: center on current location only if permission is
      // already granted — never force a permission prompt just to open the map.
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition();
          initial = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {}
    }

    LatLng tempLocation = initial;
    // ✅ NEW — search bar controller for this dialog instance only
    final TextEditingController searchController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          title: const Text('Select Shop Location',
              style: TextStyle(color: primaryNavy, fontWeight: FontWeight.bold, fontSize: 16)),
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          content: SizedBox(
            height: 480, // ✅ increased slightly to fit the new search bar
            width: double.maxFinite,
            child: Column(
              children: [
                // ✅ NEW — search bar to find a location by name/address
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) => _searchOnMapDialog(
                        v, (found) => setDialogState(() => tempLocation = found), setDialogState),
                    decoration: InputDecoration(
                      hintText: 'Search for a location...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search, color: accentOrange, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded, color: accentOrange),
                        onPressed: () => _searchOnMapDialog(searchController.text,
                            (found) => setDialogState(() => tempLocation = found), setDialogState),
                      ),
                      isDense: true,
                      filled: true, fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accentOrange, width: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(target: tempLocation, zoom: 15),
                      onMapCreated: (c) => _mapController = c,
                      onTap: (latLng) => setDialogState(() => tempLocation = latLng),
                      markers: {
                        Marker(
                          markerId: const MarkerId('shop'),
                          position: tempLocation,
                          draggable: true,
                          onDragEnd: (newPos) => setDialogState(() => tempLocation = newPos),
                        ),
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Search, tap anywhere, or drag the pin to set the exact shop location',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: accentOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Confirm Location', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                final confirmed = tempLocation;
                Navigator.pop(dialogCtx);
                showDialog(context: context, barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator(color: accentOrange)));
                final address = await _reverseGeocode(confirmed);
                if (!mounted) return;
                Navigator.pop(context); // close loader
                setState(() {
                  _selectedLocation = confirmed;
                  _shopLocationController.text = address ??
                      '${confirmed.latitude.toStringAsFixed(5)}, ${confirmed.longitude.toStringAsFixed(5)}';
                });
                if (address == null) {
                  _showLocationMessage('Location pin saved, but a readable address could not be found for this point.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Option 3: Enter Address Manually ──
  Future<void> _enterAddressManually() async {
    final addressController = TextEditingController(text: _shopLocationController.text);

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Enter Shop Address',
            style: TextStyle(color: primaryNavy, fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: addressController,
          maxLines: 3,
          maxLength: _addressMaxLength, // ✅ NEW — length limit on manual address
          decoration: InputDecoration(
            hintText: 'e.g. Shop 12, Main Boulevard, Gulberg, Lahore',
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: accentOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              final address = addressController.text.trim();
              if (address.isEmpty) return;
              // ✅ NEW — minimum meaningful length guard for manual address
              if (address.length < 6) {
                _showLocationMessage('Please enter a more complete address.');
                return;
              }
              Navigator.pop(dialogCtx);

              showDialog(context: context, barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator(color: accentOrange)));
              try {
                final locations = await locationFromAddress(address);
                if (!mounted) return;
                Navigator.pop(context); // close loader
                if (locations.isEmpty) {
                  // ✅ Geocoding failed — do NOT save invalid/empty coordinates.
                  _showLocationMessage(
                      'Could not find this address. Please refine it or use "Select Location on Map" instead.');
                  return;
                }
                final loc = locations.first;
                setState(() {
                  _selectedLocation = LatLng(loc.latitude, loc.longitude);
                  _shopLocationController.text = address;
                });
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(context);
                _showLocationMessage(
                    'Could not find this address. Please refine it or use "Select Location on Map" instead.');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _locationOptionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: accentOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: accentOrange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: primaryNavy, fontWeight: FontWeight.w600, fontSize: 14))),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  // ── UI Helpers ──
  Widget _field({
    required TextEditingController controller, required String label,
    required IconData icon, String? Function(String?)? validator,
    bool readOnly = false, TextInputType? keyboard, List<TextInputFormatter>? inputFormatters,
    int? maxLength, // ✅ NEW — optional length limit param
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller, readOnly: readOnly,
        keyboardType: keyboard, inputFormatters: inputFormatters,
        validator: validator,
        maxLength: maxLength, // ✅ NEW
        buildCounter: (context,
                {required currentLength, required isFocused, maxLength}) =>
            null, // ✅ NEW — hides default counter text
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: accentOrange),
          labelText: label,
          floatingLabelStyle: const TextStyle(color: primaryNavy),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: accentOrange, width: 1.5)),
        ),
      ),
    );
  }

  // ✅ Updated step wizard
  Widget _stepWizard() {
    final steps = ['Owner', 'Shop', 'Location'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        children: List.generate(3, (i) {
          final isActive = _currentStep == i;
          final isDone   = _currentStep > i;
          return Expanded(
            child: Row(
              children: [
                Column(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isActive ? accentOrange : isDone ? primaryNavy : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: isActive || isDone ? Colors.transparent : Colors.grey.shade300, width: 1.5),
                      boxShadow: isActive ? [BoxShadow(color: accentOrange.withOpacity(0.3), blurRadius: 10)] : [],
                    ),
                    child: Center(child: isDone
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text('${i+1}', style: TextStyle(
                            color: isActive || isDone ? Colors.white : Colors.grey, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(height: 4),
                  Text(steps[i], style: TextStyle(
                      fontSize: 11, color: isActive ? accentOrange : Colors.grey.shade500,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                ]),
                if (i < 2) Expanded(child: Container(height: 2, margin: const EdgeInsets.only(bottom: 22),
                    color: isDone ? primaryNavy : Colors.grey.shade200)),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ✅ Updated image upload box
  Widget _imageUploadBox(String title, IconData icon, File? imageFile, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: imageFile != null ? accentOrange : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: accentOrange),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: primaryNavy))),
          imageFile != null
              ? ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Image.file(imageFile, width: 50, height: 50, fit: BoxFit.cover))
              : Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: accentOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.upload_outlined, color: accentOrange, size: 18)),
        ]),
      ),
    );
  }

  Widget _bottomButton(String text, VoidCallback onTap, {Color? bg}) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: bg ?? primaryNavy, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      onPressed: onTap,
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
    ),
  );

  Widget _backNextButtons(String nextText) => Row(children: [
    Expanded(child: OutlinedButton(
      style: OutlinedButton.styleFrom(
          side: BorderSide(color: _currentStep == 0 ? Colors.grey.shade300 : accentOrange),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          foregroundColor: _currentStep == 0 ? Colors.grey : accentOrange),
      onPressed: _previousStep,
      child: const Text('Back'),
    )),
    const SizedBox(width: 12),
    Expanded(child: _bottomButton(nextText, _nextStep, bg: accentOrange)),
  ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
        title: const Text('Shop Registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _stepWizard(),
            Divider(height: 1, color: Colors.grey.shade100),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // ── STEP 1: Owner Details ──
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      _sectionTitle('Owner Details', Icons.person_outline),
                      _field(controller: _ownerNameController, label: 'Owner Name', icon: Icons.person,
                          maxLength: _ownerNameMaxLength, // ✅ NEW — length limit
                          // ✅ NEW — stricter validation: required, letters only, 3-50 chars
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return 'Owner name is required';
                            if (!_isValidName(val)) return 'Enter a valid name (letters only, 3-50 characters)';
                            return null;
                          }),
                      _field(controller: _ownerEmailController, label: 'Email', icon: Icons.email, readOnly: true),
                      _field(controller: _ownerContactController, label: 'Phone Number', icon: Icons.phone,
                          keyboard: TextInputType.number, inputFormatters: phoneFormatter,
                          maxLength: _phoneMaxLength, // ✅ NEW — length limit
                          validator: (v) => RegExp(r'^03\d{2}-\d{7}$').hasMatch(v!) ? null : 'Format: 03xx-xxxxxxx'),
                      const SizedBox(height: 14),
                      _imageUploadBox('Upload CNIC Front', Icons.badge, _cnicFrontImage,
                          () async { File? img = await pickImage(); if (img != null) setState(() => _cnicFrontImage = img); }),
                      const SizedBox(height: 12),
                      _imageUploadBox('Upload CNIC Back', Icons.badge, _cnicBackImage,
                          () async { File? img = await pickImage(); if (img != null) setState(() => _cnicBackImage = img); }),
                      const SizedBox(height: 24),
                      _bottomButton('Next →', _nextStep, bg: accentOrange),
                    ]),
                  ),

                  // ── STEP 2: Shop Details ──
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      _sectionTitle('Shop Details', Icons.store_outlined),
                      _field(controller: _shopNameController, label: 'Shop Name', icon: Icons.store,
                          maxLength: _shopNameMaxLength, // ✅ NEW — length limit
                          // ✅ NEW — stricter validation: required, min 3 characters
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return 'Shop name required';
                            if (val.length < 3) return 'Shop name must be at least 3 characters';
                            return null;
                          }),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: DropdownButtonFormField(
                          value: _shopCategory,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.category, color: Color(0xFFFF6A1A)),
                            labelText: 'Shop Category',
                            floatingLabelStyle: const TextStyle(color: primaryNavy),
                            filled: true, fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: accentOrange, width: 1.5)),
                          ),
                          // ✅ Uses the new 20-category list — names match the
                          // Customer Dashboard's category chips exactly.
                          items: shopCategories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setState(() => _shopCategory = v),
                          validator: (v) => v == null ? 'Please select category' : null,
                        ),
                      ),
                      _field(controller: _cnicController, label: 'CNIC Number', icon: Icons.badge,
                          keyboard: TextInputType.number, inputFormatters: cnicFormatter,
                          maxLength: _cnicMaxLength, // ✅ NEW — length limit
                          validator: (v) => RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(v!) ? null : 'Format: XXXXX-XXXXXXX-X'),
                      const SizedBox(height: 4),
                      _imageUploadBox('Upload Shop Image', Icons.store, _shopImage,
                          () async { File? img = await pickImage(); if (img != null) setState(() => _shopImage = img); }),
                      const SizedBox(height: 12),
                      // ✅ Registration Number — fixed "REG-XXXXXX" format, same
                      // pattern-formatter style as Phone/CNIC above.
                      _field(controller: _regNoController, label: 'Registration Number', icon: Icons.assignment,
                          keyboard: TextInputType.number, inputFormatters: regNoFormatter,
                          maxLength: _regNoMaxLength, // ✅ NEW — length limit
                          validator: (v) => RegExp(r'^REG-\d{6}$').hasMatch(v!) ? null : 'Format: REG-123456'),
                      const SizedBox(height: 16),
                      _backNextButtons('Next →'),
                    ]),
                  ),

                  // ── STEP 3: Location (✅ new flexible 3-option system) ──
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      _sectionTitle('Shop Location', Icons.location_on_outlined),
                      _locationOptionButton(
                        icon: Icons.my_location_rounded,
                        label: 'Use Current Location',
                        onTap: _useCurrentLocation,
                      ),
                      _locationOptionButton(
                        icon: Icons.map_rounded,
                        label: 'Select Location on Map',
                        onTap: _selectOnMap,
                      ),
                      _locationOptionButton(
                        icon: Icons.edit_location_alt_rounded,
                        label: 'Enter Address Manually',
                        onTap: _enterAddressManually,
                      ),
                      const SizedBox(height: 10),
                      _field(controller: _shopLocationController, label: 'Selected Shop Location', icon: Icons.location_on,
                          readOnly: true,
                          maxLength: _addressMaxLength, // ✅ NEW — length limit
                          validator: (v) => v!.isEmpty ? 'Please select a location using one of the options above' : null),
                      if (_selectedLocation != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Icon(Icons.gps_fixed_rounded, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ]),
                        ),
                      const SizedBox(height: 18),
                      _backNextButtons('Submit ✓'),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: accentOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: accentOrange, size: 22)),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryNavy)),
    ]),
  );

  final phoneFormatter = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11), _PhoneNumberTextInputFormatter()];
  final cnicFormatter  = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13), _CnicTextInputFormatter()];
  // ✅ New formatter for Registration Number — keeps "REG-" fixed and only
  // lets the user type up to 6 digits after it.
  final regNoFormatter = [FilteringTextInputFormatter.digitsOnly, _RegNoTextInputFormatter()];
}

// ── formatters unchanged ──
class _PhoneNumberTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    String formatted = '';
    for (int i = 0; i < digits.length; i++) { if (i == 4) formatted += '-'; formatted += digits[i]; }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}
class _CnicTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 13) digits = digits.substring(0, 13);
    String formatted = '';
    for (int i = 0; i < digits.length; i++) { if (i == 5 || i == 12) formatted += '-'; formatted += digits[i]; }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

// ✅ New — Registration Number formatter: always "REG-" + up to 6 digits.
class _RegNoTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 6) digits = digits.substring(0, 6);
    final formatted = 'REG-$digits';
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}