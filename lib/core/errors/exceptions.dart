/// Low-level exceptions thrown by data sources. These never escape the data
/// layer — repositories catch them and convert to `Failure`.
class ServerException implements Exception {
  ServerException(this.statusCode, [this.message]);
  final int statusCode;
  final String? message;
}

class NetworkException implements Exception {
  NetworkException([this.message]);
  final String? message;
}

class CacheException implements Exception {
  CacheException([this.message]);
  final String? message;
}

class UnauthorizedException implements Exception {
  UnauthorizedException([this.message]);
  final String? message;
}
