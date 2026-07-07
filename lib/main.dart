import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rss_reader/src/app/reader_app.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/app.dart';
import 'package:rss_reader/src/rust/frb_generated.dart';

Future<void> main() async {
  final controller = await bootstrapReaderController();
  runApp(MyApp(controller: controller));
}

Future<ReaderController> bootstrapReaderController({
  ReaderRepository? repository,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // P0b: open the persisted SQLite database before any reader state is loaded.
  // Runs on the FRB worker pool; the existing snapshot-based UI is untouched
  // (P1a/P2a rewire it onto the new database APIs).
  final dir = await getApplicationDocumentsDirectory();
  await initDatabase(path: p.join(dir.path, 'rss_reader.db'));
  final resolvedRepository = repository ?? await ReaderRepository.create();
  final controller = ReaderController(repository: resolvedRepository);
  await controller.load();
  return controller;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return ReaderApp(controller: controller);
  }
}
