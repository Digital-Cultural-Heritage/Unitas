import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

// ─── Text Styles (migrated from typography.ts) ───────────────────────────────

TextStyle get heading => GoogleFonts.outfit(
  fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary, height: 1.2,
);

TextStyle get subTitle => GoogleFonts.outfit(
  fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary,
);

TextStyle get body => GoogleFonts.outfit(
  fontSize: 14, fontWeight: FontWeight.w400, color: dim1,
);

TextStyle get caption => GoogleFonts.outfit(
  fontSize: 12, fontWeight: FontWeight.w400, color: dim2,
);

TextStyle get label => GoogleFonts.outfit(
  fontSize: 11, fontWeight: FontWeight.w600, color: dim2,
  letterSpacing: 0.5,
);

TextStyle get statStyle => GoogleFonts.outfit(
  fontSize: 26, fontWeight: FontWeight.w700, color: textPrimary,
);

TextStyle get buttonStyle => GoogleFonts.outfit(
  fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white,
);

TextStyle get small => GoogleFonts.outfit(
  fontSize: 10, fontWeight: FontWeight.w400, color: dim2,
);
