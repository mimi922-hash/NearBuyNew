import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top;
      case 'confirmed':
        return Icons.thumb_up_alt_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        // ── Light navy background
        backgroundColor: const Color(0xFF2D3F6B),
        // ── White back arrow
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        // ── White "My Orders" title
        title: const Text(
          "My Orders",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('customerId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!.docs;
          orders.sort((a, b) {
            final aTime = (a.data() as Map)['createdAt'];
            final bTime = (b.data() as Map)['createdAt'];
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    "No orders yet",
                    style: TextStyle(
                        fontSize: 18, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final data = orders[index].data() as Map<String, dynamic>;
              final orderId = orders[index].id;
              return _OrderCard(
                data: data,
                orderId: orderId,
                statusColor: _statusColor,
                statusIcon: _statusIcon,
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _OrderCard — same card content/layout as before, unchanged.
// Only addition: a collapsible "Before you pay / receive" banner
// shown for orders that are still 'pending' or 'confirmed' (i.e.
// not yet completed/cancelled — the order hasn't reached the
// customer yet, so the receiving checklist is still relevant).
// Kept as its own StatefulWidget just so each card can expand /
// collapse independently without touching the parent's logic.
// ─────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String orderId;
  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;

  const _OrderCard({
    required this.data,
    required this.orderId,
    required this.statusColor,
    required this.statusIcon,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _instructionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final orderId = widget.orderId;
    final status = data['status'] ?? 'pending';
    final shopName = data['shopName'] ?? 'Shop';
    final totalAmount = data['totalAmount'] ?? 0;
    final items = data['items'] as List<dynamic>? ?? [];

    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as dynamic).toDate()
        : null;

    // Instructions are only relevant while the order hasn't reached the
    // customer yet — i.e. still pending or confirmed. Once completed or
    // cancelled, the receiving checklist no longer applies.
    final showInstructions = status == 'pending' || status == 'confirmed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: shop name + status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    shopName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.statusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: widget.statusColor(status), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.statusIcon(status),
                          size: 14,
                          color: widget.statusColor(status)),
                      const SizedBox(width: 4),
                      Text(
                        status[0].toUpperCase() +
                            status.substring(1),
                        style: TextStyle(
                            fontSize: 12,
                            color: widget.statusColor(status),
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Order ID
            Text(
              "Order #${orderId.substring(0, 8).toUpperCase()}",
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600),
            ),

            // Date
            if (createdAt != null)
              Text(
                "${createdAt.day}/${createdAt.month}/${createdAt.year}  ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}",
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),

            const Divider(height: 16),

            // Items list
            ...items.map((item) {
              final itemData = item as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "${itemData['quantity']}x ${itemData['name']}",
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      "Rs. ${((itemData['price'] ?? 0) * (itemData['quantity'] ?? 1)).toStringAsFixed(0)}",
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }),

            const Divider(height: 16),

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text(
                  "Rs. ${totalAmount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ],
            ),

            // Payment method
            const SizedBox(height: 4),
            Text(
              "Payment: ${data['paymentMethod'] ?? 'Cash on Delivery'}",
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600),
            ),

            // ── Order Receiving Instructions (collapsible) ──
            // Only shown for orders that haven't reached the customer yet.
            if (showInstructions) ...[
              const SizedBox(height: 10),
              _buildInstructionsBanner(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsBanner() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _instructionsExpanded = !_instructionsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "⚠️ Before you pay — tap to view receiving instructions",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                  Icon(
                    _instructionsExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Colors.deepOrange,
                  ),
                ],
              ),
            ),
          ),
          if (_instructionsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Divider(height: 1),
                  SizedBox(height: 10),
                  Text(
                    "📦 Order Receiving Instructions",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Please check your order carefully before making payment.",
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                  SizedBox(height: 8),
                  _InstructionLine("🛍️", "Check all products and make sure nothing is missing."),
                  _InstructionLine("🍔", "Food items: Check expiry date, freshness, packaging, leakage, and damage."),
                  _InstructionLine("📦", "Packaging: Make sure the package is properly sealed and not damaged or leaking."),
                  _InstructionLine("💻", "Electronic items: Carefully check the product, model, condition, and visible damage before payment."),
                  _InstructionLine("🔢", "Quantity: Make sure you received the correct quantity of every product."),
                  _InstructionLine("🚚", "Delivery Time: Your order will typically be delivered within 1–2 days."),
                  _InstructionLine("💰", "Payment: Pay only after you are fully satisfied that your order is correct and complete."),
                  _InstructionLine("📞", "If something is missing or incorrect, contact the shopkeeper using the provided contact number."),
                  SizedBox(height: 10),
                  Text(
                    "⚠️ Important Note",
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Once payment is made and the order is accepted, it may be difficult to resolve issues. "
                    "Therefore, please check your parcel carefully before paying.",
                    style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Small helper widget for one instruction line (emoji + text), used only
// inside the expanded instructions panel above.
class _InstructionLine extends StatelessWidget {
  final String emoji;
  final String text;
  const _InstructionLine(this.emoji, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}