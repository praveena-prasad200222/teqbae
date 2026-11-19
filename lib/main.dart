import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'di.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final AppDependencies dependencies = await AppDependencies.create();
  runApp(RebsApp(dependencies: dependencies));
}
