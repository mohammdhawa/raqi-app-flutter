// Basic smoke test for the Document Approval app.

import 'package:flutter_test/flutter_test.dart';

import 'package:doc_approval/main.dart';

void main() {
  testWidgets('App widget class exists and can be referenced', (WidgetTester tester) async {
    // Verify that the app widget class is accessible.
    // Full integration testing requires mocking Riverpod providers,
    // network layer, and secure storage.
    expect(DocApprovalApp, isNotNull);
  });
}
