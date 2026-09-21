// lib/core/theme/ink_tokens.dart
//
// Colours, spacing and text styles of the indigo "ink" card design used by
// the profile, settings, invoice and salary screens. Screens refer to it
// through a private alias (`typedef _Tok = InkTokens;`); the few screens
// with a deliberately denser layout keep their own values.

import 'package:flutter/material.dart';

class InkTokens {
  InkTokens._();

  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);
  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );
  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );
  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );
  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    color        : inkMuted,
  );
  static const tsBody = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
  );
  static const double cRadius = 10.0;
  static const double padH    = 18.0;
  static const double padV    = 16.0;
  static const tsSmall = TextStyle(
    fontFamily : fcond,
    fontWeight : FontWeight.w500,
    fontSize   : 11,
    color      : inkMuted,
  );
  static const double radius  = 6.0;
  static const tsMono = TextStyle(
    fontFamily: 'RobotoMono', // monospace font — keep as-is or replace if you have one
    fontWeight: FontWeight.w400,
    fontSize  : 12,
    color     : ink,
  );
  static const borderFocus = Color(0xFF4338CA);
  static const badgeBg     = Color(0xFF1E1B4B);
  static const badgeFg     = Color(0xFFFFFFFF);
  static const fxcond = 'NotoSansExtraCondensed';
  static const tsBadge = TextStyle(
    fontFamily   : fxcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 11,
    letterSpacing: 2.0,
    color        : badgeFg,
  );
  static const tsHint = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w400,
    fontSize  : 11,
    color     : inkMuted,
    height    : 1.3,
  );
  static const double gutter  = 12.0;
  static const double rowGap  = 16.0;
  static const tsInputMono = TextStyle(
    fontFamily   : fbody,
    fontWeight   : FontWeight.w500,
    fontSize     : 13,
    color        : ink,
    letterSpacing: 0.3,
    height       : 1.4,
  );
}
