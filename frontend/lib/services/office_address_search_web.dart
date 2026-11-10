import 'dart:async';
import 'dart:js_interop';

@JS('google.maps.Geocoder')
extension type _Geocoder._(JSObject _) implements JSObject {
  external factory _Geocoder();
  external void geocode(JSObject request, JSFunction callback);
}

extension type _Result._(JSObject _) implements JSObject {
  @JS('formatted_address')
  external String get formattedAddress;
  external _Geometry get geometry;
}

extension type _Geometry._(JSObject _) implements JSObject {
  external _Point get location;
}

extension type _Point._(JSObject _) implements JSObject {
  external double lat();
  external double lng();
}

Future<List<Map<String, dynamic>>> searchOfficeAddress(String address) async {
  final completer = Completer<List<Map<String, dynamic>>>();
  try {
    _Geocoder().geocode(
      {'address': address}.jsify() as JSObject,
      ((JSArray<_Result>? results, JSString status) {
        if (completer.isCompleted) return;
        final code = status.toDart;
        if (code == 'OK' || code == 'ZERO_RESULTS') {
          completer.complete([
            for (final result in results?.toDart ?? <_Result>[])
              {
                'address': result.formattedAddress,
                'latitude': result.geometry.location.lat(),
                'longitude': result.geometry.location.lng(),
              },
          ]);
        } else {
          completer.completeError(Exception(
            code == 'REQUEST_DENIED'
                ? 'Address search is not enabled for this website. Enable Google Geocoding API for the map key, or select a pin manually.'
                : 'Address search is temporarily unavailable. Try again or select a pin manually.',
          ));
        }
      }).toJS,
    );
  } catch (_) {
    throw Exception('Map search could not load. Refresh the page and try again.');
  }
  return completer.future.timeout(const Duration(seconds: 15));
}
