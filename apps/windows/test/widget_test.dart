import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('app name is stable', () {
    expect(AppConstants.productName, 'Send to PC');
  });
}