import Foundation

/// Database identity Xano attaches to an authenticated realtime peer.
public struct RealtimePermissions: Codable, Sendable, Equatable {
    /// Xano table identifier (`dbo_id` on the wire).
    public let dboID: Int
    /// Xano row identifier (`row_id` on the wire).
    public let rowID: Int

    /// Creates permissions from table and row identifiers.
    ///
    /// Explicit so the memberwise initializer is not public.
    ///
    /// - Parameters:
    ///   - dboID: Table identifier.
    ///   - rowID: Row identifier.
    init(dboID: Int, rowID: Int) { // swiftlint:disable:this unneeded_synthesized_initializer
        self.dboID = dboID
        self.rowID = rowID
    }

    enum CodingKeys: String, CodingKey {
        case dboID = "dbo_id"
        case rowID = "row_id"
    }
}
