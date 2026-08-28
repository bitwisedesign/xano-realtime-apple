import Foundation

/// Builds an `AsyncStream` and captures its continuation on iOS 16 / macOS 13.
///
/// `AsyncStream.makeStream` is newer than the package's deployment target.
enum AsyncStreamFactory {
    /// Creates a stream and the continuation that feeds it.
    ///
    /// - Parameters:
    ///   - type: Element type, required because the buffering policy does not infer it.
    ///   - bufferingPolicy: Buffering policy for the stream.
    /// - Returns: The stream and its continuation.
    static func make<Element>(
        of type: Element.Type,
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy
    ) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
        var continuation: AsyncStream<Element>.Continuation?
        let stream = AsyncStream(bufferingPolicy: bufferingPolicy) { cont in
            continuation = cont
        }
        guard let continuation else {
            preconditionFailure("AsyncStream builder must invoke its closure synchronously")
        }
        return (stream, continuation)
    }
}
