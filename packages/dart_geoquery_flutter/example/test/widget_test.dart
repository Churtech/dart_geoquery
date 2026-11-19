import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App initializes correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const DartGeoQueryDemoApp());
    expect(find.byType(DartGeoQueryDemoApp), findsOneWidget);
  });
}
