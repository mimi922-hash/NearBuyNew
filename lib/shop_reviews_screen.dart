import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ShopReviewsPage extends StatelessWidget {
  final String shopId;
  const ShopReviewsPage({super.key, required this.shopId});

  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color bgColor      = Color(0xFFF8FAFC);

  // ══════════════════════════════════════════════════════════
  // BACKWARD-COMPATIBLE FIELD HELPERS
  // Old reviews:  userId, name, rating, comment, createdAt
  // New reviews:  userId, userName, profilePic, rating, comment, timestamp
  // ══════════════════════════════════════════════════════════

  /// Name: userName -> name -> userId -> 'Anonymous'
  static String _getUserName(Map<String, dynamic> data) {
    final userName = data['userName'];
    if (userName != null && userName.toString().trim().isNotEmpty) {
      return userName.toString();
    }
    final name = data['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString();
    }
    final userId = data['userId'];
    if (userId != null && userId.toString().trim().isNotEmpty) {
      return userId.toString();
    }
    return 'Anonymous';
  }

  /// Profile pic: only 'profilePic' (new). Old reviews never had this,
  /// so a null/empty value just falls back to the initial-letter avatar.
  static String? _getProfilePic(Map<String, dynamic> data) {
    final pic = data['profilePic'];
    if (pic != null && pic.toString().trim().isNotEmpty) return pic.toString();
    return null;
  }

  /// Date: timestamp (new) -> createdAt (old) -> null if neither exists.
  static DateTime? _getReviewDate(Map<String, dynamic> data) {
    final ts = data['timestamp'];
    if (ts is Timestamp) return ts.toDate();
    final created = data['createdAt'];
    if (created is Timestamp) return created.toDate();
    return null;
  }

  /// Rating: handles int, double, numeric string, or missing -> 0.
  static double _parseRating(dynamic r) {
    if (r is int) return r.toDouble();
    if (r is double) return r;
    if (r is String) return double.tryParse(r) ?? 0;
    return 0;
  }

  /// Comment: always returns a safe string, never null.
  static String _getComment(Map<String, dynamic> data) {
    final c = data['comment'];
    return c?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryNavy, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Shop Reviews', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // NOTE: no orderBy() here on purpose --- old reviews may not have
        // a `timestamp` field, and Firestore's orderBy silently drops any
        // document missing the ordered field. Sorting is done client-side
        // below so both old and new reviews always show up, and no extra
        // Firestore index is required.
        stream: FirebaseFirestore.instance.collection('shops').doc(shopId)
            .collection('reviews').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6A1A)));
          final reviews = snapshot.data!.docs;
          if (reviews.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.rate_review_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No reviews yet.', style: TextStyle(color: Colors.grey.shade500)),
          ]));

          // ── Client-side sort: latest first. Reviews with no usable
          // date (old docs missing both timestamp & createdAt) are
          // pushed to the bottom instead of crashing/erroring out.
          final sortedReviews = List<QueryDocumentSnapshot>.from(reviews);
          sortedReviews.sort((a, b) {
            final da = _getReviewDate(a.data() as Map<String, dynamic>);
            final db = _getReviewDate(b.data() as Map<String, dynamic>);
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da);
          });

          // ── Average rating: counts old + new reviews, skips any
          // doc with a missing/invalid rating instead of treating it as 0.
          double total = 0;
          int ratedCount = 0;
          for (var doc in reviews) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['rating'] == null) continue;
            total += _parseRating(data['rating']);
            ratedCount++;
          }
          double avgRating = ratedCount > 0 ? total / ratedCount : 0;

          return Column(children: [
            // ── Average rating card ──
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [primaryNavy, Color(0xFF1A3A5C)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Average Rating', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(avgRating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                    const Text(' / 5', style: TextStyle(color: Colors.white60, fontSize: 18)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${reviews.length} Reviews', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                ]),
                const Spacer(),
                // Star display
                Column(children: List.generate(5, (i) => Icon(
                  i < avgRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: i < avgRating.round() ? accentOrange : Colors.white30, size: 22))),
              ]),
            ),

            Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              itemCount: sortedReviews.length,
              itemBuilder: (context, index) {
                final data       = sortedReviews[index].data() as Map<String, dynamic>;
                final rating     = _parseRating(data['rating']);
                final comment    = _getComment(data);
                final userName   = _getUserName(data);
                final profilePic = _getProfilePic(data);
                final reviewDate = _getReviewDate(data);
                final dateStr    = reviewDate != null
                    ? '${reviewDate.day}/${reviewDate.month}/${reviewDate.year}'
                    : 'Date not available';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                        backgroundColor: const Color(0xFF0E2A47).withOpacity(0.1),
                        child: profilePic == null ? Text(userName[0].toUpperCase(),
                            style: const TextStyle(color: primaryNavy, fontWeight: FontWeight.bold)) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(userName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryNavy)),
                        Text(dateStr, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      ])),
                      // Star rating badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFF6A1A), size: 16),
                          const SizedBox(width: 3),
                          Text(
                            rating == rating.roundToDouble() ? rating.toInt().toString() : rating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF6A1A)),
                          ),
                        ]),
                      ),
                    ]),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(comment, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5)),
                    ],
                  ]),
                );
              },
            )),
          ]);
        },
      ),
    );
  }
}