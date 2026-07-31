// ============================================================
//  nearbuy_theme.dart — NearBuy Brand Design System
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NearBuyColors {
  // Brand palette
  static const Color navy      = Color(0xFF1A2340);   // dark navy (logo text)
  static const Color orange    = Color(0xFFE8420A);   // brand orange (logo Buy)
  static const Color orangeLight = Color(0xFFFF6B35); // lighter orange accent
  static const Color cream     = Color(0xFFFAF8F5);   // off-white background
  static const Color cardBg    = Color(0xFFFFFFFF);
  static const Color divider   = Color(0xFFEEEBE6);
  static const Color textPrimary   = Color(0xFF1A2340);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint      = Color(0xFFADB5BD);
  static const Color success   = Color(0xFF10B981);
  static const Color warning   = Color(0xFFF59E0B);
  static const Color error     = Color(0xFFEF4444);
  static const Color starYellow = Color(0xFFFBBF24);
  static const Color verified  = Color(0xFF059669);
}

class NearBuyTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: NearBuyColors.navy,
      secondary: NearBuyColors.orange,
      surface: NearBuyColors.cream,
    ),
    scaffoldBackgroundColor: NearBuyColors.cream,
    textTheme: GoogleFonts.poppinsTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: NearBuyColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: NearBuyColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    cardTheme: CardThemeData(
      color: NearBuyColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: NearBuyColors.divider, width: 1),
      ),
    ),
  );
}

// ─── Shared widget: NearBuy App Bar ───────────────────────
class NearBuyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  const NearBuyAppBar({super.key, required this.title, this.actions, this.showBack = true});

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: NearBuyColors.navy,
      elevation: 0,
      automaticallyImplyLeading: showBack,
      leading: showBack
          ? IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'Near',
              style: GoogleFonts.poppins(
                fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
              ),
            ),
            TextSpan(
              text: 'Buy',
              style: GoogleFonts.poppins(
                fontSize: 20, fontWeight: FontWeight.w700, color: NearBuyColors.orange,
              ),
            ),
            TextSpan(
              text: '  $title',
              style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w400, color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      actions: actions,
    );
  }
}

// ─── Shared widget: Status Badge ──────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  Color get _color {
    switch (status.toLowerCase()) {
      case 'pending':   return NearBuyColors.warning;
      case 'confirmed': return Colors.blue;
      case 'completed': return NearBuyColors.success;
      case 'cancelled': return NearBuyColors.error;
      default:          return NearBuyColors.textSecondary;
    }
  }

  IconData get _icon {
    switch (status.toLowerCase()) {
      case 'pending':   return Icons.hourglass_top_rounded;
      case 'confirmed': return Icons.thumb_up_alt_rounded;
      case 'completed': return Icons.check_circle_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default:          return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: _color),
          const SizedBox(width: 5),
          Text(
            status[0].toUpperCase() + status.substring(1),
            style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared widget: Star Rating Row ───────────────────────
class StarRatingRow extends StatelessWidget {
  final double rating;
  final int reviewCount;
  final double starSize;
  const StarRatingRow({super.key, required this.rating, this.reviewCount = 0, this.starSize = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          if (i < rating.floor()) {
            return Icon(Icons.star_rounded, size: starSize, color: NearBuyColors.starYellow);
          } else if (i < rating) {
            return Icon(Icons.star_half_rounded, size: starSize, color: NearBuyColors.starYellow);
          } else {
            return Icon(Icons.star_outline_rounded, size: starSize, color: NearBuyColors.textHint);
          }
        }),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: GoogleFonts.poppins(
            fontSize: starSize - 1, fontWeight: FontWeight.w600, color: NearBuyColors.textPrimary,
          ),
        ),
        if (reviewCount > 0) ...[
          const SizedBox(width: 3),
          Text(
            '($reviewCount)',
            style: GoogleFonts.poppins(fontSize: starSize - 2, color: NearBuyColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

// ─── Shared widget: NearBuy Logo Mark (small) ─────────────
class NearBuyLogo extends StatelessWidget {
  final double size;
  const NearBuyLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: NearBuyColors.orange,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(Icons.storefront_rounded, color: Colors.white, size: size * 0.6),
    );
  }
}