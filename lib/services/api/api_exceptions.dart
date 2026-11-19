/// Network-level failure (offline, DNS, timeout, connection reset).
class ApiNetworkException implements Exception {
  final String message;

  ApiNetworkException([this.message = 'No internet connection.']);

  @override
  String toString() => message;
}

/// Server explicitly rejected the event (e.g. attendance already exists).
class ApiConflictException implements Exception {
  final String message;

  ApiConflictException([this.message = 'The server reported a conflict.']);

  @override
  String toString() => message;
}

/// Server-side validation error (HTTP 422), returned to the form UI.
class ApiValidationException implements Exception {
  final String message;

  ApiValidationException([this.message = 'The server rejected this request.']);

  @override
  String toString() => message;
}

/// Unexpected server error (HTTP 5xx).
class ApiServerException implements Exception {
  final String message;

  ApiServerException([this.message = 'Server error. Please try again.']);

  @override
  String toString() => message;
}

/// Any other non-success response.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
