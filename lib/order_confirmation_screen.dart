// ============================================================
//  order_confirmation_screen.dart — NearBuy Redesign
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'customer_dashboard.dart';
import 'screens/my_orders_screen.dart';
import 'nearbuy_theme.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final String orderId;
  final String shopName;
  final double totalAmount;

  const OrderConfirmationScreen({
    super.key,
    required this.orderId,
    required this.shopName,
    required this.totalAmount,
  });

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortId = '#${widget.orderId.substring(0, 10).toUpperCase()}';

    return Scaffold(
      backgroundColor: NearBuyColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                // Success animation
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [NearBuyColors.orange, Color(0xFFFF8A50)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: NearBuyColors.orange.withOpacity(0.35),
                          blurRadius: 30, offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
                  ),
                ),
                const SizedBox(height: 28),
                // Brand logo
                RichText(
                  text: TextSpan(children: [
                    TextSpan(text: 'Near', style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w800, color: NearBuyColors.navy,
                    )),
                    TextSpan(text: 'Buy', style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w800, color: NearBuyColors.orange,
                    )),
                  ]),
                ),
                const SizedBox(height: 8),
                Text('Order Confirmed!', style: GoogleFonts.poppins(
                  fontSize: 26, fontWeight: FontWeight.w800, color: NearBuyColors.textPrimary,
                )),
                const SizedBox(height: 8),
                Text(
                  'Your order has been placed at ${widget.shopName}. The shop will confirm shortly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 13, color: NearBuyColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 28),
                // Order details card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: NearBuyColors.navy.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _detailRow(Icons.receipt_long_rounded, 'Order ID', shortId),
                      _divider(),
                      _detailRow(Icons.storefront_rounded, 'Shop', widget.shopName),
                      _divider(),
                      _detailRow(
                        Icons.currency_rupee_rounded, 'Total Amount',
                        'Rs. ${widget.totalAmount.toStringAsFixed(0)}',
                        valueColor: NearBuyColors.navy,
                        valueBold: true,
                      ),
                      _divider(),
                      _detailRow(Icons.payments_outlined, 'Payment', 'Cash on Delivery'),
                      _divider(),
                      _detailRow(
                        Icons.pending_actions_rounded, 'Status', 'Pending',
                        valueColor: NearBuyColors.warning,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Info box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NearBuyColors.orange.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NearBuyColors.orange.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: NearBuyColors.orange.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.info_outline_rounded, size: 18, color: NearBuyColors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Please keep cash ready for delivery. The shopkeeper will contact you for confirmation.',
                          style: GoogleFonts.poppins(fontSize: 12, color: NearBuyColors.orange, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // Action buttons
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NearBuyColors.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const CustomerDashboard()),
                      (_) => false,
                    ),
                    icon: const Icon(Icons.home_rounded, color: Colors.white, size: 18),
                    label: Text('Back to Home', style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                    )),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: NearBuyColors.navy, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                      (_) => false,
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, color: NearBuyColors.navy, size: 18),
                    label: Text('View My Orders', style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600, color: NearBuyColors.navy,
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {Color? valueColor, bool valueBold = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: NearBuyColors.navy.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: NearBuyColors.navy),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: GoogleFonts.poppins(
          fontSize: 13, color: NearBuyColors.textSecondary,
        ))),
        Text(value, style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
          color: valueColor ?? NearBuyColors.textPrimary,
        )),
      ],
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Divider(height: 1, color: NearBuyColors.divider),
  );
}