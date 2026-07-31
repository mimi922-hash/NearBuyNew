import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ShopDetailPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final Function(String status, {String? reason}) onStatusChange;

  const ShopDetailPage({
    super.key,
    required this.shopId,
    required this.shopData,
    required this.onStatusChange,
  });

  @override
  State<ShopDetailPage> createState() => _ShopDetailPageState();
}

class _ShopDetailPageState extends State<ShopDetailPage> {
  // ── Colors ────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF0B1D35);
  static const Color _navyCard = Color(0xFF112240);
  static const Color _accent = Color(0xFFF4511E);
  static const Color _accentOrange = Color(0xFFFF9500);
  static const Color _white = Colors.white;

  final TextEditingController _rejectionController =
      TextEditingController();

  @override
  void dispose() {
    _rejectionController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────
  void _openImage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _FullScreenImage(imageUrl: url)),
    );
  }

  Future<void> _downloadImage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ── Section header ────────────────────────────────────────────
  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _accent, size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: _white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ── Detail row ────────────────────────────────────────────────
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: _white.withOpacity(0.45),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'N/A',
              style: const TextStyle(
                color: _white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Document image card ───────────────────────────────────────
  Widget _documentCard(String? url, String title) {
    if (url == null || url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: _navyCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_not_supported,
                    color: _white.withOpacity(0.3), size: 32),
                const SizedBox(height: 8),
                Text(
                  'No $title',
                  style: TextStyle(
                      color: _white.withOpacity(0.3),
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _openImage(url),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, prog) {
                      if (prog == null) return child;
                      return Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: _navyCard,
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: _accent),
                        ),
                      );
                    },
                    errorBuilder: (ctx, e, st) => Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: _navyCard,
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.broken_image,
                          color: _white.withOpacity(0.3)),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.zoom_in,
                        color: _white, size: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _downloadImage(url),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _navyCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded,
                      color: _white.withOpacity(0.7),
                      size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Download',
                    style: TextStyle(
                      color: _white.withOpacity(0.7),
                      fontSize: 12,
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

  // ── Status history ────────────────────────────────────────────
  Widget _statusHistory() {
    final status =
        (widget.shopData['status'] ?? 'pending').toLowerCase();
    final submittedAt = widget.shopData['created_at'];

    final List<Map<String, dynamic>> history = [
      if (status == 'verified' || status == 'rejected')
        {
          'label':
              status == 'verified' ? 'Verified' : 'Rejected',
          'color': status == 'verified'
              ? Colors.greenAccent
              : Colors.redAccent,
          'active': true,
        },
      {
        'label': 'Submitted',
        'color': _white.withOpacity(0.4),
        'active': false,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: history.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item['active'] as bool
                      ? item['color'] as Color
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: item['color'] as Color,
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['label'] as String,
                      style: TextStyle(
                        color: item['active'] as bool
                            ? item['color'] as Color
                            : _white.withOpacity(0.5),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      item['active'] as bool
                          ? 'Recently updated'
                          : (submittedAt?.toString() ??
                              'Unknown date'),
                      style: TextStyle(
                        color: _white.withOpacity(0.3),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _divider() => Divider(
        color: _white.withOpacity(0.07),
        height: 1,
      );

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final data = widget.shopData;
    final status = (data['status'] ?? 'pending').toLowerCase();

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

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Shop Details',
          style: TextStyle(
            color: _white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert,
                color: _white.withOpacity(0.7)),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Shop header card ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _navyCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      final url =
                          data['shop_image_url'] ?? '';
                      if (url.isNotEmpty) _openImage(url);
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.15),
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: data['shop_image_url'] != null &&
                              (data['shop_image_url']
                                      as String)
                                  .isNotEmpty
                          ? Image.network(
                              data['shop_image_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.store,
                                      color: _accent),
                            )
                          : const Icon(Icons.store,
                              color: _accent, size: 28),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                data['shop_name'] ??
                                    'Shop Name',
                                style: const TextStyle(
                                  color: _white,
                                  fontWeight:
                                      FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor
                                    .withOpacity(0.15),
                                borderRadius:
                                    BorderRadius.circular(8),
                                border: Border.all(
                                    color: statusColor
                                        .withOpacity(0.4),
                                    width: 0.5),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 13,
                                color:
                                    _white.withOpacity(0.4)),
                            const SizedBox(width: 4),
                            Text(
                              data['owner_name'] ?? 'N/A',
                              style: TextStyle(
                                color:
                                    _white.withOpacity(0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.mail_outline,
                                size: 13,
                                color:
                                    _white.withOpacity(0.4)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                data['owner_email'] ?? 'N/A',
                                style: TextStyle(
                                  color: _white
                                      .withOpacity(0.55),
                                  fontSize: 12,
                                ),
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined,
                                size: 13,
                                color:
                                    _white.withOpacity(0.4)),
                            const SizedBox(width: 4),
                            Text(
                              data['owner_contact'] ?? 'N/A',
                              style: TextStyle(
                                color:
                                    _white.withOpacity(0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Scrollable vertical content ─────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  16, 4, 16, 16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // ════════════════════════════════════════
                  // SECTION 1 — Shop Information
                  // ════════════════════════════════════════
                  _sectionHeader(
                      'Shop Information', Icons.store_rounded),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: _navyCard,
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _detailRow('Category',
                            data['shop_category'] ?? 'N/A'),
                        _divider(),
                        _detailRow('Address',
                            data['shop_location'] ?? 'N/A'),
                        _divider(),
                        _detailRow(
                          'Hours',
                          '${data['open_time'] ?? 'N/A'} – ${data['close_time'] ?? 'N/A'}',
                        ),
                        _divider(),
                        _detailRow('Description',
                            data['shop_description'] ?? 'N/A'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ════════════════════════════════════════
                  // SECTION 2 — Documents
                  // ════════════════════════════════════════
                  _sectionHeader(
                      'Documents', Icons.folder_rounded),
                  _documentCard(
                      data['cnic_front_url'], 'CNIC Front'),
                  _documentCard(
                      data['cnic_back_url'], 'CNIC Back'),

                  const SizedBox(height: 20),

                  // ════════════════════════════════════════
                  // SECTION 3 — Activity / Status History
                  // ════════════════════════════════════════
                  _sectionHeader(
                      'Status History', Icons.history_rounded),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _navyCard,
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: _statusHistory(),
                  ),

                  const SizedBox(height: 20),

                  // ════════════════════════════════════════
                  // ACTION BUTTONS
                  // ════════════════════════════════════════
                  if (status == 'pending') ...[
                    TextField(
                      controller: _rejectionController,
                      style: const TextStyle(
                          color: _white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'Reason for rejection (optional)',
                        hintStyle: TextStyle(
                            color: _white.withOpacity(0.35),
                            fontSize: 13),
                        filled: true,
                        fillColor: _navyCard,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            label: 'Reject Shop',
                            color: Colors.redAccent,
                            onTap: () {
                              widget.onStatusChange(
                                'rejected',
                                reason: _rejectionController
                                    .text,
                              );
                              Navigator.pop(context, true);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _actionButton(
                            label: 'Approve Shop',
                            color: _accentOrange,
                            onTap: () {
                              widget.onStatusChange(
                                  'verified');
                              Navigator.pop(context, true);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (status == 'verified') ...[
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            label: 'Reject Shop',
                            color: Colors.redAccent,
                            onTap: () {
                              widget
                                  .onStatusChange('rejected');
                              Navigator.pop(context, true);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _actionButton(
                            label: 'Unverify Shop',
                            color: _accentOrange,
                            onTap: () {
                              widget
                                  .onStatusChange('pending');
                              Navigator.pop(context, true);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],

                  SizedBox(
                      height:
                          MediaQuery.of(context).padding.bottom +
                              8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color.withOpacity(0.4), width: 0.5),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ── Fullscreen image viewer ────────────────────────────────────────
class _FullScreenImage extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded,
                color: Colors.white),
            onPressed: () async {
              final uri = Uri.parse(imageUrl);
              if (await canLaunchUrl(uri))
                await launchUrl(uri);
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.network(
            imageUrl,
            loadingBuilder: (ctx, child, prog) {
              if (prog == null) return child;
              return const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFF4511E)),
              );
            },
            errorBuilder: (ctx, e, st) => const Icon(
              Icons.broken_image,
              color: Colors.white38,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}