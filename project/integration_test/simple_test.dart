import 'package:flutter_test/flutter_test.dart';
import 'package:DawnChat/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Rust bridge initialises', (WidgetTester tester) async {
    expect(RustLib.instance, isNotNull);
  });
}
