import '../errors/failure.dart';

/// A lightweight Result type. Repositories return `Result<T>` so the
/// presentation layer never has to handle raw exceptions.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    final self = this;
    return switch (self) {
      Success<T>() => success(self.value),
      ResultFailure<T>() => failure(self.failure),
    };
  }

  bool get isSuccess => this is Success<T>;
}

class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.failure);
  final Failure failure;
}
