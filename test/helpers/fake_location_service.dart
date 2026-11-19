import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/services/location/location_service.dart';

class FakeLocationService implements LocationService {
  GeoPoint point;
  LocationException? error;

  FakeLocationService({required this.point, this.error});

  @override
  Future<GeoPoint> getCurrentPosition() async {
    if (error != null) throw error!;
    return point;
  }
}
