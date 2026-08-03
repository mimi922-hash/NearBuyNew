import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class ShopkeeperOrdersScreen extends StatefulWidget {
  final String shopId;
  const ShopkeeperOrdersScreen({super.key, required this.shopId});
  @override
  State<ShopkeeperOrdersScreen> createState() => _ShopkeeperOrdersScreenState();
}

class _ShopkeeperOrdersScreenState extends State<ShopkeeperOrdersScreen>
    with SingleTickerProviderStateMixin {
  // ── Brand Colors ──
  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color bgColor      = Color(0xFFF8FAFC);

  late TabController _tabController;
  final List<String> _statusTabs = ['All','Pending','Confirmed','Delivered','Cancelled'];

  @override
  void initState() { 
    super.initState(); 
    _tabController = TabController(length: _statusTabs.length, vsync: this); 
  }
  
  @override
  void dispose() { 
    _tabController.dispose(); 
    super.dispose(); 
  }

  Stream<QuerySnapshot> _ordersStream(String statusFilter) {
    if (statusFilter == 'All') {
      return FirebaseFirestore.instance
          .collection('orders')
          .where('shopId', isEqualTo: widget.shopId)
          .snapshots();
    }
    return FirebaseFirestore.instance
        .collection('orders')
        .where('shopId', isEqualTo: widget.shopId)
        .where('status', isEqualTo: statusFilter.toLowerCase())
        .snapshots();
  }

  // ── 🔥 NEW: Stock Deduction with Transaction ──
  Future<void> _deductStockForOrder(String orderId, List<dynamic> items) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    
    try {
      await firestore.runTransaction((transaction) async {
        // 1. Get the order document
        final orderRef = firestore.collection('orders').doc(orderId);
        final orderDoc = await transaction.get(orderRef);
        
        if (!orderDoc.exists) {
          throw Exception('Order not found');
        }
        
        final orderData = orderDoc.data() as Map<String, dynamic>;
        
        // 2. CRITICAL: Check if stock was already deducted
        if (orderData['stockDeducted'] == true) {
          throw Exception('Stock already deducted for this order');
        }
        
        // 3. Check if order status is already delivered
        if (orderData['status'] == 'delivered') {
          throw Exception('Order already delivered');
        }
        
        // 4. For each item, get product and update stock
        for (var item in items) {
          final productId = item['productId'];
          if (productId == null) {
            throw Exception('Product ID missing for item: ${item['name']}');
          }
          
          final orderedQty = (item['quantity'] as num).toInt();
          if (orderedQty <= 0) continue;
          
          // Get product document
          final productRef = firestore
              .collection('shops')
              .doc(widget.shopId)
              .collection('products')
              .doc(productId);
          
          final productDoc = await transaction.get(productRef);
          
          if (!productDoc.exists) {
            throw Exception('Product not found: ${item['name']}');
          }
          
          final productData = productDoc.data() as Map<String, dynamic>;
          final currentQty = (productData['quantity'] as num?)?.toInt() ?? 0;
          
          // 5. Check if sufficient stock is available
          if (currentQty < orderedQty) {
            throw Exception(
              'Insufficient stock for ${item['name']}. '
              'Available: $currentQty, Ordered: $orderedQty'
            );
          }
          
          // 6. Calculate new quantity (never negative)
          final newQty = currentQty - orderedQty;
          final outOfStock = newQty <= 0;
          
          // 7. Update product with new quantity and stock status
          transaction.update(productRef, {
            'quantity': newQty,
            'out_of_stock': outOfStock,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
        
        // 8. Mark order as stock deducted and delivered
        transaction.update(orderRef, {
          'status': 'delivered',
          'stockDeducted': true,
          'deliveredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order delivered and stock updated successfully!'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      rethrow;
    }
  }

  // ── Updated: Mark as Delivered with Stock Deduction ──
  Future<void> _markOrderDelivered(String orderId, List<dynamic> items) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: accentOrange),
      ),
    );
    
    try {
      await _deductStockForOrder(orderId, items);
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      // Error already shown in _deductStockForOrder
    }
  }

  // ── Updated: Simple status update (no stock deduction) ──
  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    // If marking as delivered, use the stock deduction method
    if (newStatus.toLowerCase() == 'delivered') {
      // Get order items first
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();
      
      if (!orderDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final orderData = orderDoc.data() as Map<String, dynamic>;
      final items = List.from(orderData['items'] ?? []);
      
      // Check if already delivered
      if (orderData['status'] == 'delivered') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order already delivered'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // Check if stock already deducted (safety check)
      if (orderData['stockDeducted'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stock already deducted for this order'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      await _markOrderDelivered(orderId, items);
      return;
    }
    
    // For other status changes (cancel, confirm) - no stock deduction
    final Map<String, dynamic> updateData = {
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .update(updateData);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order marked as $newStatus'),
          backgroundColor: _statusColor(newStatus),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':   return const Color(0xFFFF6A1A);
      case 'confirmed': return Colors.blue.shade600;
      case 'delivered': return Colors.green.shade600;
      case 'cancelled': return Colors.red.shade600;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':   return Icons.hourglass_top_rounded;
      case 'confirmed': return Icons.check_circle_outline;
      case 'delivered': return Icons.local_shipping_outlined;
      case 'cancelled': return Icons.cancel_outlined;
      default: return Icons.info_outline;
    }
  }

  void _openOrderDetails(Map<String, dynamic> data, String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          data: data,
          orderId: orderId,
          onStatusUpdate: _updateOrderStatus,
          statusColor: _statusColor,
          shopId: widget.shopId,
        ),
      ),
    );
  }

  Widget _buildOrderList(String statusFilter) {
    return StreamBuilder<QuerySnapshot>(
      stream: _ordersStream(statusFilter),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6A1A)),
          );
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag_outlined, size: 70, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'No ${statusFilter == 'All' ? '' : statusFilter.toLowerCase()} orders yet',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                ),
              ],
            ),
          );
        }
        
        final orders = snapshot.data!.docs.toList();
        orders.sort((a, b) {
          final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
          final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aTs == null || bTs == null) return 0;
          return bTs.compareTo(aTs);
        });
        
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final data    = orders[index].data() as Map<String, dynamic>;
            final orderId = orders[index].id;
            final status  = data['status'] ?? 'pending';
            final items   = List.from(data['items'] ?? []);
            final total   = (data['totalAmount'] ?? 0).toDouble();
            
            final customerLabel = (data['customerName'] != null && data['customerName'].toString().trim().isNotEmpty)
                ? data['customerName'].toString()
                : (data['customerEmail'] ?? 'Customer').toString();
            
            Timestamp? ts = data['createdAt'];
            String dateStr = '';
            if (ts != null) { 
              final d = ts.toDate(); 
              dateStr = '${d.day}/${d.month}/${d.year}  ${d.hour}:${d.minute.toString().padLeft(2,'0')}'; 
            }
            
            // ── NEW: Check if stock was deducted ──
            final bool stockDeducted = data['stockDeducted'] == true;

            return GestureDetector(
              onTap: () => _openOrderDetails(data, orderId),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(left: BorderSide(color: _statusColor(status), width: 3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_statusIcon(status), color: _statusColor(status), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              customerLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: primaryNavy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // ── NEW: Stock deducted badge ──
                          if (status.toLowerCase() == 'delivered' && stockDeducted)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '✓ Stock Updated',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 13, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            '${items.length} item${items.length == 1 ? '' : 's'}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            'Rs. ${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: primaryNavy,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(dateStr, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                          const Spacer(),
                          const Icon(Icons.money, size: 13, color: Colors.green),
                          const SizedBox(width: 4),
                          const Text('COD', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          Text('Tap for details →', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                        ],
                      ),
                      // ── Pending order actions ──
                      if (status == 'pending') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _updateOrderStatus(orderId, 'cancelled'),
                                child: const Text('Cancel', style: TextStyle(color: Colors.red, fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E2A47),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _updateOrderStatus(orderId, 'confirmed'),
                                child: const Text('Confirm', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Manage Orders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: accentOrange,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: _statusTabs.map((s) => Tab(text: s)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _statusTabs.map((s) => _buildOrderList(s)).toList(),
      ),
    );
  }
}

// ── Updated Order Detail Screen ──
class OrderDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String orderId;
  final Future<void> Function(String, String) onStatusUpdate;
  final Color Function(String) statusColor;
  final String shopId;

  const OrderDetailScreen({
    super.key,
    required this.data,
    required this.orderId,
    required this.onStatusUpdate,
    required this.statusColor,
    required this.shopId,
  });

  static const Color primaryNavy  = Color(0xFF0E2A47);
  static const Color accentOrange = Color(0xFFFF6A1A);
  static const Color bgColor      = Color(0xFFF8FAFC);

  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Future<void> _openDirections(BuildContext context, double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open maps')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open maps')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items  = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = data['status'] ?? 'pending';
    final bool stockDeducted = data['stockDeducted'] == true;

    final customerName = (data['customerName'] != null && data['customerName'].toString().trim().isNotEmpty)
        ? data['customerName'].toString()
        : null;
    final customerEmail = data['customerEmail']?.toString() ?? 'N/A';

    final String deliveryAddress = (data['deliveryAddress'] != null && data['deliveryAddress'].toString().trim().isNotEmpty)
        ? data['deliveryAddress'].toString()
        : 'Delivery address not provided';

    final deliveryLocationRaw = data['deliveryLocation'];
    double? lat;
    double? lng;
    if (deliveryLocationRaw is Map) {
      lat = _parseCoord(deliveryLocationRaw['latitude']);
      lng = _parseCoord(deliveryLocationRaw['longitude']);
    }
    final bool hasValidLocation = lat != null && lng != null;

    final double subtotal    = ((data['subtotal'] ?? 0) as num).toDouble();
    final double deliveryFee = ((data['deliveryCharge'] ?? 0) as num).toDouble();
    final double platformFee = ((data['platformFee'] ?? 0) as num).toDouble();
    final double totalAmount = ((data['totalAmount'] ?? 0) as num).toDouble();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryNavy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Order Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                border: Border(left: BorderSide(color: statusColor(status), width: 4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: primaryNavy, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Order Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryNavy)),
                  ),
                  // ── NEW: Stock deducted status ──
                  if (status.toLowerCase() == 'delivered' && stockDeducted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '✓ Stock Updated',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor(status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor(status)),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Customer info card
            _infoCard([
              _infoRow(Icons.person_outline, 'Customer', customerName ?? customerEmail),
              Divider(height: 18, color: Colors.grey.shade100),
              _infoRow(Icons.money, 'Payment', 'Cash on Delivery'),
              Divider(height: 18, color: Colors.grey.shade100),
              _infoRow(Icons.tag, 'Order ID', orderId.length > 12 ? '${orderId.substring(0, 12)}...' : orderId),
            ]),
            const SizedBox(height: 12),

            // Delivery Information card
            _infoCard([
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 18, color: primaryNavy),
                const SizedBox(width: 8),
                const Text('Delivery Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryNavy)),
              ]),
              const SizedBox(height: 10),
              _infoRow(Icons.home_outlined, 'Address', deliveryAddress),
              if (hasValidLocation) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.directions_outlined, color: accentOrange, size: 18),
                    label: const Text('View Delivery Location', style: TextStyle(color: accentOrange, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: accentOrange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _openDirections(context, lat!, lng!),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),

            // Items card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Items Ordered:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryNavy)),
                  const SizedBox(height: 12),
                  ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: (item['image_url'] != null && item['image_url'] != '')
                              ? Image.network(
                                  item['image_url'],
                                  width: 58,
                                  height: 58,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _imgPlaceholder(),
                                )
                              : _imgPlaceholder(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryNavy),
                              ),
                              const SizedBox(height: 3),
                              // ── NEW: Show productId for debugging ──
                              Text(
                                'Qty: ${item['quantity']}  ·  Rs. ${(item['price'] ?? 0).toStringAsFixed(0)} each',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Rs. ${((item['price'] ?? 0) * (item['quantity'] ?? 1)).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryNavy),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Price summary card
            _infoCard([
              _priceRow('Subtotal', 'Rs. ${subtotal.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              _priceRow('Delivery Charges', 'Rs. ${deliveryFee.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              _priceRow('Platform Fee (5%)', 'Rs. ${platformFee.toStringAsFixed(2)}', color: accentOrange),
              Divider(height: 18, color: Colors.grey.shade100),
              _priceRow('Total', 'Rs. ${totalAmount.toStringAsFixed(2)}', bold: true, color: primaryNavy),
            ]),
            const SizedBox(height: 20),

            // ── UPDATED: Action buttons ──
            if (status == 'pending') ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        await onStatusUpdate(orderId, 'cancelled');
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                      label: const Text('Confirm', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryNavy,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        await onStatusUpdate(orderId, 'confirmed');
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ] else if (status == 'confirmed') ...[
              // ── UPDATED: Mark as Delivered with stock deduction ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.local_shipping, color: Colors.white),
                  label: const Text('Mark as Delivered', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await onStatusUpdate(orderId, 'delivered');
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
            ] else if (status == 'delivered') ...[
              // ── NEW: Show stock deduction status ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: stockDeducted ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: stockDeducted ? Colors.green.shade300 : Colors.orange.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      stockDeducted ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      color: stockDeducted ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stockDeducted
                            ? '✓ Stock has been deducted for this order'
                            : '⚠️ Stock was NOT deducted for this order',
                        style: TextStyle(
                          color: stockDeducted ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
    width: 58,
    height: 58,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F4FF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.image_outlined, color: primaryNavy, size: 26),
  );

  Widget _infoCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
    ),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _infoRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 18, color: Colors.grey.shade400),
      const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryNavy),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _priceRow(String label, String value, {bool bold = false, Color? color}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: bold ? 15 : 14, color: Colors.grey.shade600)),
      Text(
        value,
        style: TextStyle(
          fontSize: bold ? 16 : 14,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: color ?? Colors.black87,
        ),
      ),
    ],
  );
}