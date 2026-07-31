// ============================================================
//  cart_screen.dart — NearBuy Redesign
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_confirmation_screen.dart';
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

  Future<void> _placeOrder(List<QueryDocumentSnapshot> cartItems, double subtotal) async {
    setState(() => _placingOrder = true);
    try {
      final platformFee = subtotal * platformFeePercent;
      final totalAmount = subtotal + platformFee;
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
        'platformFee': platformFee, 'totalAmount': totalAmount,
        'paymentMethod': 'Cash on Delivery', 'status': 'pending',
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
            orderId: orderRef.id, shopName: widget.shopName, totalAmount: totalAmount,
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
          final totalAmount  = subtotal + platformFee;

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
              // Cart items list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: cartItems.length,
                  itemBuilder: (ctx, i) => _CartItemTile(
                    doc: cartItems[i],
                    onUpdateQty: _updateQuantity,
                    onRemove: _removeItem,
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