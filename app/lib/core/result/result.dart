/// A sealed Result type for operations whose failure is an expected outcome
/// (e.g. "no route found", "building not cached") rather than a programmer
/// error. Repositories return [Result] across the domain boundary; they never
/// throw. See docs/02-architecture.md §6.
sealed class Result<T, E> {
  const Result();

  const factory Result.ok(T value) = Ok<T, E>;
  const factory Result.err(E error) = Err<T, E>;

  bool get isOk => this is Ok<T, E>;

  /// Transforms the success value, propagating errors untouched.
  Result<U, E> map<U>(U Function(T value) f) => switch (this) {
        Ok(:final value) => Result.ok(f(value)),
        Err(:final error) => Result.err(error),
      };

  /// Chains an operation that itself can fail.
  Result<U, E> flatMap<U>(Result<U, E> Function(T value) f) => switch (this) {
        Ok(:final value) => f(value),
        Err(:final error) => Result.err(error),
      };

  /// Collapses both branches into a single value; forces exhaustive handling.
  U fold<U>(U Function(T value) onOk, U Function(E error) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final error) => onErr(error),
      };

  T getOrElse(T Function(E error) orElse) => fold((v) => v, orElse);
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;

  @override
  String toString() => 'Err($error)';
}
