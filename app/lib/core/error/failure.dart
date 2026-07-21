/// Typed failures crossing the domain boundary. Sealed so presentation is
/// forced to handle every category exhaustively (docs/02-architecture.md §6).
sealed class Failure {
  const Failure(this.message);

  /// Developer-facing description. User-facing copy is mapped centrally in
  /// the presentation layer, never here.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// Data existed but could not be parsed/validated (corrupt bundle, unknown
/// schema version, dangling references).
final class DataFormatFailure extends Failure {
  const DataFormatFailure(super.message);
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

/// Routing-specific expected outcomes.
final class RoutingFailure extends Failure {
  const RoutingFailure(super.message, this.reason);
  final RoutingFailureReason reason;
}

enum RoutingFailureReason {
  /// Graph is connected in general but no path satisfies the constraints
  /// (e.g. accessible mode with no lift). Distinct from [disconnected] so the
  /// UI can say "no step-free route exists" instead of a generic error.
  noPathForConstraints,

  /// Start and destination are in different graph components.
  disconnected,

  /// A referenced node id does not exist in the graph.
  nodeMissing,
}
