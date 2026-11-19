import 'package:teqbae/models/geo_point.dart';
import 'package:teqbae/services/location/location_service.dart';

class FakeLocationService implements LocationService {
  GeoPoint point;
  LocationException? error;
  bool serviceEnabled;

  FakeLocationService({required this.point, this.error, this.serviceEnabled = true});

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<GeoPoint> getCurrentPosition() async {
    if (error != null) throw error!;
    return point;
  }
}
