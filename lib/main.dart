import 'package:flutter/material.dart';

import 'app.dart';
import 'utils/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.I.init();
  runApp(const QuarkLiteApp());
}