import 'package:flutter_test/flutter_test.dart';
import 'package:rss_reader/main.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';

void main() {
  testWidgets('shows empty state before any feeds are added', (tester) async {
    final controller = ReaderController(repository: ReaderRepository.memory());

    await tester.pumpWidget(MyApp(controller: controller));
    await tester.pump();

    expect(find.text('Rust RSS Reader'), findsOneWidget);
    expect(find.text('No feeds yet'), findsOneWidget);
    expect(
      find.text(
        'Add an RSS or Atom feed URL to start building your reading list.',
      ),
      findsOneWidget,
    );
  });
}
