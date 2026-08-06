/// Domain-level failure type. The data layer catches exceptions and returns
/// a [Failure]; the presentation layer maps it to friendly, localized copy.
///
/// Sealed so exhaustive `switch` handling is enforced by the compiler.
sealed class Failure {
  const Failure(this.message);
  final String message;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection.']);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Something went wrong on our end.'])
      : statusCode = null;
  const ServerFailure.withCode(this.statusCode, String message) : super(message);
  final int? statusCode;
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Your session has expired.']);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Could not read local data.']);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unexpected error occurred.']);
}
