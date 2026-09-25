import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'watch/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const WatchApp());
}
