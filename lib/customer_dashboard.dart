// ============================================================
//  customer_dashboard.dart — NearBuy Redesign
// ============================================================

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

  final List<Map<String, dynamic>> _categories = [
    {'label': 'All',         'icon': Icons.apps_rounded},
    {'label': 'Grocery',     'icon': Icons.local_grocery_store_rounded},
    {'label': 'Pharmacy',    'icon': Icons.local_pharmacy_rounded},
    {'label': 'Electronics', 'icon': Icons.devices_rounded},
    {'label': 'Restaurant',  'icon': Icons.restaurant_rounded},
    {'label': 'Clothing',    'icon': Icons.checkroom_rounded},
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
                  label: 'My Orders',
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
          final name = (data['shop_name'] ?? '').toString().toLowerCase();
          if (_searchText.isNotEmpty && !name.contains(_searchText)) return false;
          if (_selectedCategory != 'All') {
            final cat = (data['shop_category'] ?? '').toString();
            if (cat != _selectedCategory) return false;
          }
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
    switch ((data['shop_category'] ?? '').toString().toLowerCase()) {
      case 'grocery':     return '🛒';
      case 'pharmacy':    return '💊';
      case 'electronics': return '📱';
      case 'restaurant':  return '🍽';
      case 'clothing':    return '👕';
      default:            return '🏪';
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
                      '$_categoryEmoji  ${data['shop_category'] ?? 'Shop'}',
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
                  final category = shopData?['shop_category'] ?? '';
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
      case 'grocery':     emoji = '🛒'; break;
      case 'pharmacy':    emoji = '💊'; break;
      case 'electronics': emoji = '📱'; break;
      case 'restaurant':  emoji = '🍽'; break;
      case 'clothing':    emoji = '👕'; break;
    }
    return Container(
      width: 90, height: 90,
      color: NearBuyColors.navy.withOpacity(0.05),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 36))),
    );
  }
}