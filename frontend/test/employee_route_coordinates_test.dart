import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/job.dart';

void main() {
  test('JobLocation.formatCoordinates renders 4-decimal lat/lon pair', () {
    expect(
      JobLocation(latitude: 30.0444, longitude: 31.2357).formatCoordinates(),
      '30.0444, 31.2357',
    );
  });

}
