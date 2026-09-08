import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'preview/billing_preview_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const BillingPreviewApp());
}
