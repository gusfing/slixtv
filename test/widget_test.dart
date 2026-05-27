import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slix_iptv/main.dart';

void main() {
  testWidgets('App root smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: SlixTvApp()));

    // Verify splash screen or initial elements load
    expect(find.byType(SlixTvApp), findsOneWidget);
  });
}
