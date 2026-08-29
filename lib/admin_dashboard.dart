import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

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

  // ── Profile image ─────────────────────────────────────────────
  String? _profileImageUrl;
  bool _isUploading = false;

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
    _loadProfileData();
    if (widget.scrollToShops) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToShopsCard();
      });
    }
  }

  void _loadProfileData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .get();
      
      if (mounted && doc.exists) {
        final data = doc.data();
        setState(() {
          _profileImageUrl = data?['profile_image'];
        });
      }
    } catch (e) {
      debugPrint("Error loading profile data: $e");
    }
  }

  // ─── Profile Image Upload with Cloudinary ──────────────────
  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (pickedFile == null) return;

      final File imageFile = File(pickedFile.path);
      final int fileSize = await imageFile.length();
      if (fileSize > 5 * 1024 * 1024) {
        if (mounted) {
          _showSnackBar('Image size should be less than 5MB', Colors.red);
        }
        return;
      }

      if (!mounted) return;
      setState(() => _isUploading = true);

      // ─── Cloudinary Upload ──────────────────────────────────
      String cloudName = "dxzaqavfj";
      String uploadPreset = "nearbuy_preset";
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
      );
      
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', pickedFile.path));
      
      var response = await request.send();
      
      if (!mounted) {
        setState(() => _isUploading = false);
        return;
      }

      if (response.statusCode == 200) {
        var responseData = await response.stream.toBytes();
        var responseString = String.fromCharCodes(responseData);
        var jsonRes = jsonDecode(responseString);
        String url = jsonRes['secure_url'];
        
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .set(
              {'profile_image': url},
              SetOptions(merge: true),
            );

        if (mounted) {
          setState(() {
            _profileImageUrl = url;
            _isUploading = false;
          });
          _showSnackBar('Profile photo updated!', Colors.green);
        }
      } else {
        setState(() => _isUploading = false);
        _showSnackBar('Failed to upload image. Please try again.', Colors.red);
      }
    } catch (e) {
      debugPrint("Upload Error: $e");
      if (mounted) {
        setState(() => _isUploading = false);
        _showSnackBar('Error uploading image: ${e.toString()}', Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
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

  // ── Navigate to Payment Account Details ──────────────────
  void _openPaymentDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentDetailsScreen(),
      ),
    );
  }

  // ⭐ FIXED: _updateShopStatus with auto-tab switch
  Future<void> _updateShopStatus(
    String shopId,
    String status, {
    String? reason,
  }) async {
    await FirebaseFirestore.instance.collection('shops').doc(shopId).update({
      'status': status,
      'rejection_reason': status == "rejected" ? reason ?? "" : "",
    });

    // ⭐ Auto-switch to appropriate tab after status update
    if (mounted) {
      if (status == 'verified') {
        setState(() {
          selectedIndex = 1; // Switch to Verified tab
        });
        _showSnackBar('Shop approved successfully!', Colors.green);
      } else if (status == 'rejected') {
        setState(() {
          selectedIndex = 2; // Switch to Rejected tab
        });
        _showSnackBar('Shop rejected!', Colors.red);
      } else {
        setState(() {
          selectedIndex = 0; // Switch to Pending tab
        });
        _showSnackBar('Shop status updated to Pending', Colors.orange);
      }
    }
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

  // ─── Dynamic trend calculation ─────────────────────────────────
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
      int totalCount = snap.docs.length;

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final raw = data['created_at'];
        DateTime? createdAt;
        
        if (raw is Timestamp) {
          createdAt = raw.toDate();
        } else if (raw is DateTime) {
          createdAt = raw;
        } else if (raw is String) {
          createdAt = DateTime.tryParse(raw);
        }

        if (createdAt == null) {
          continue;
        }

        if (createdAt != null) {
          if (createdAt.isAfter(todayStart)) {
            todayCount++;
          } else if (createdAt.isAfter(yesterdayStart) && createdAt.isBefore(todayStart)) {
            yesterdayCount++;
          }
        }
      }

      double changePercent = 0;
      bool isUp = true;
      
      if (yesterdayCount > 0) {
        changePercent = ((todayCount - yesterdayCount) / yesterdayCount) * 100;
        isUp = changePercent >= 0;
      } else if (todayCount > 0) {
        changePercent = 100;
        isUp = true;
      }

      return {
        'total': totalCount,
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
    bool hideTrend = false,
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
        } else if (todayCount == 0 && yesterdayCount == 0) {
          trendLabel = 'No new entries today';
          trendColor = _white.withOpacity(0.4);
        } else if (yesterdayCount == 0 && todayCount > 0) {
          trendLabel = '+$todayCount new today';
          trendColor = Colors.greenAccent;
        } else if (todayCount == 0 && yesterdayCount > 0) {
          trendLabel = 'No new today ($yesterdayCount yesterday)';
          trendColor = Colors.redAccent;
        } else if (percent == 0) {
          trendLabel = 'Same as yesterday';
          trendColor = _white.withOpacity(0.5);
        } else {
          trendLabel = '${percent.toStringAsFixed(1)}% change vs yesterday';
          trendColor = isUp ? Colors.greenAccent : Colors.redAccent;
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
              if (!hideTrend)
                Row(
                  children: [
                    if (snap.hasData && (todayCount > 0 || yesterdayCount > 0))
                      Icon(
                        isUp && todayCount >= yesterdayCount
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 11,
                        color: trendColor,
                      ),
                    if (snap.hasData && (todayCount > 0 || yesterdayCount > 0))
                      const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        trendLabel,
                        style: TextStyle(color: trendColor, fontSize: 11),
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
            margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Platform Billing',
                        style: TextStyle(
                          color: _white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
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
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: _accentOrange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
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
                        borderRadius: BorderRadius.circular(20),
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
          margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  onTap: () => setState(() => selectedIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: active ? _accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tabs[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active ? _white : _white.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (i == 0 && pendingCount > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: active
                                  ? _white.withOpacity(0.25)
                                  : _accent.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$pendingCount',
                              style: TextStyle(
                                color: active ? _white : _accent,
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
              child: CircularProgressIndicator(color: _accent),
            ),
          );
        }

        if (snap.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                "No ${_currentStatus()} shops",
                style: TextStyle(color: _white.withOpacity(0.4)),
              ),
            ),
          );
        }

        final shops = snap.data!.docs.toList();
        
        shops.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          
          DateTime? aDate;
          DateTime? bDate;
          
          final aTimestamp = aData['created_at'];
          final bTimestamp = bData['created_at'];
          
          if (aTimestamp is Timestamp) {
            aDate = aTimestamp.toDate();
          } else if (aTimestamp is DateTime) {
            aDate = aTimestamp;
          }
          
          if (bTimestamp is Timestamp) {
            bDate = bTimestamp.toDate();
          } else if (bTimestamp is DateTime) {
            bDate = bTimestamp;
          }
          
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          
          return bDate.compareTo(aDate);
        });

        return ListView.builder(
          itemCount: shops.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemBuilder: (context, i) {
            final shop = shops[i];
            final data = shop.data() as Map<String, dynamic>;
            final billingStatus = data['billing_status'] ?? 'active';
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
                      onStatusChange: (String st, {String? reason}) async {
                        await _updateShopStatus(shop.id, st, reason: reason);
                      },
                    ),
                  ),
                );
                if (result == true) setState(() {});
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _navyCard,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.store, color: _accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['shop_name'] ?? 'Unnamed Shop',
                                  style: const TextStyle(
                                    color: _white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (billingStatus == 'suspended')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'SUSPENDED',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            data['shop_category'] ?? '',
                            style: TextStyle(
                              color: _white.withOpacity(0.45),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            data['shop_location'] ?? '',
                            style: TextStyle(
                              color: _white.withOpacity(0.35),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
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
      {'icon': Icons.dashboard_rounded, 'label': 'Dashboard'},
      {'icon': Icons.store_rounded, 'label': 'Shops'},
      {'icon': Icons.account_balance_wallet_rounded, 'label': 'Billing'},
      {'icon': Icons.bar_chart_rounded, 'label': 'Reports'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: _navyCard,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
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
                  break;
                case 1:
                  _scrollToShopsCard();
                  break;
                case 2:
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminBillingScreen()),
                  ).then((_) => setState(() => _bottomNavIndex = 0));
                  break;
                case 3:
                  _showReportsDialog();
                  Future.delayed(
                      const Duration(milliseconds: 300),
                      () => setState(() => _bottomNavIndex = 0));
                  break;
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  items[i]['icon'] as IconData,
                  color: active ? _accent : _white.withOpacity(0.4),
                  size: 22,
                ),
                const SizedBox(height: 3),
                Text(
                  items[i]['label'] as String,
                  style: TextStyle(
                    color: active ? _accent : _white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─── Reports Dialog ──────────────────────────────────────────
  void _showReportsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _navyCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Reports',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              color: _accent.withOpacity(0.5),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Reports coming soon!\n\nWe\'re working on bringing you detailed analytics and insights.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Notifications Dialog ────────────────────────────────────
  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _navyCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              color: _white.withOpacity(0.3),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'No notifications yet',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'We\'ll notify you about important updates',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Profile Dialog with Image Upload ────────────────────────
  void _showProfileDialog() {
    final nameController = TextEditingController(text: user?.displayName ?? '');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _navyCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Admin Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // ─── Profile Image with Upload ──────────────
                    GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: _accent.withOpacity(0.2),
                            backgroundImage: _profileImageUrl != null 
                                ? NetworkImage(_profileImageUrl!) 
                                : null,
                            child: _profileImageUrl == null
                                ? Text(
                                    (user?.displayName ?? 'A')[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: _accent,
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          if (_isUploading)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                ),
                              ),
                            ),
                          if (!_isUploading)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.displayName ?? 'Admin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_rounded,
                      color: _accent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Administrator',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  labelStyle: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                  ),
                  filled: true,
                  fillColor: _navy,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _accent, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                try {
                  await user?.updateDisplayName(newName);
                  Navigator.pop(context);
                  if (mounted) {
                    _showSnackBar('Profile updated successfully!', Colors.green);
                    setState(() {});
                  }
                } catch (e) {
                  _showSnackBar('Error: ${e.toString()}', Colors.red);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
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

    final dateDisplay = '${now.day} ${_monthName(now.month)} ${now.year}';

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: _white.withOpacity(0.8)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: _white.withOpacity(0.8)),
            color: _navyCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'profile') {
                _showProfileDialog();
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
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_none_rounded,
                    color: _white.withOpacity(0.8)),
                onPressed: _showNotificationsDialog,
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
              decoration: const BoxDecoration(color: _navy),
              currentAccountPicture: GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: _accent.withOpacity(0.2),
                      backgroundImage: _profileImageUrl != null 
                          ? NetworkImage(_profileImageUrl!) 
                          : null,
                      child: _profileImageUrl == null
                          ? Icon(Icons.person, color: _white, size: 30)
                          : null,
                    ),
                    if (_isUploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
              leading: const Icon(Icons.account_balance_wallet,
                  color: _accentOrange),
              title: const Text('Platform Billing',
                  style: TextStyle(color: _white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminBillingScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined,
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
                  style: TextStyle(color: Colors.redAccent)),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Greeting ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting,',
                            style: TextStyle(
                              color: _white.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Near',
                                      style: TextStyle(
                                        color: _white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Buy',
                                      style: TextStyle(
                                        color: _accent,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('👋',
                                  style: TextStyle(fontSize: 22)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _navyCard,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 12,
                                    color: _white.withOpacity(0.5)),
                                const SizedBox(width: 5),
                                Text(
                                  dateDisplay,
                                  style: TextStyle(
                                    color: _white.withOpacity(0.65),
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
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overview',
                            style: TextStyle(
                              color: _white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          GestureDetector(
                            onTap: _showReportsDialog,
                            child: Text(
                              'View Reports ›',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Stat grid ─────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _statCard(
                                    'Total Users',
                                    Icons.people_alt_rounded,
                                    Colors.blueAccent,
                                    'users',
                                    hideTrend: true,
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    Icons.hourglass_top_rounded,
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
                      padding: EdgeInsets.symmetric(horizontal: 20),
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
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m];
  }
}