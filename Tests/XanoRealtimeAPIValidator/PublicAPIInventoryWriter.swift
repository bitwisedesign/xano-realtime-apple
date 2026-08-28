import Foundation

/// Rewrites ``PublicAPIInventory`` from a scanned public-API key set.
enum PublicAPIInventoryWriter {
    // MARK: - Properties

    /// Environment variable that asks the completeness test to regenerate the inventory.
    static let environmentVariable = "REGENERATE_PUBLIC_API_INVENTORY"

    /// Whether the current process requested regeneration.
    static var isRequested: Bool {
        guard let value = ProcessInfo.processInfo.environment[environmentVariable] else {
            return false
        }
        return value != "0" && value != "false" && !value.isEmpty
    }

    // MARK: - Public API

    /// Writes a sorted inventory file next to this source file.
    ///
    /// - Parameters:
    ///   - symbols: Keys produced by the public-API source scan.
    ///   - filePath: Path of this writer file; used to locate `PublicAPIInventory.swift`.
    /// - Throws: An error if the inventory file cannot be written.
    static func write(_ symbols: Set<String>, filePath: String = #filePath) throws {
        let inventoryURL = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("PublicAPIInventory.swift")
        try rendered(symbols).write(to: inventoryURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Private Helpers

    /// Swift source for ``PublicAPIInventory`` with `symbols` in sorted order.
    private static func rendered(_ symbols: Set<String>) -> String {
        let lines = symbols.sorted().map { key in
            "        \(swiftStringLiteral(key))"
        }
        let body = lines.joined(separator: ",\n")
        return """
        /// Approved public API surface for `XanoRealtime`.
        ///
        /// Completeness tests compare a source scan against ``symbols``. Do not edit
        /// this set by hand. When an API change is approved, regenerate with
        /// `REGENERATE_PUBLIC_API_INVENTORY=1 swift test --filter scannedPublicAPIMatchesApprovedInventory`.
        enum PublicAPIInventory {
            // MARK: - Properties

            /// Approved public type, member, and enum-case keys.
            ///
            /// Types are bare names. Members use `Type.name` for properties and cases.
            /// Functions, initializers, and subscripts use Swift selector form
            /// (`Type.name(_:)`, `Type.init(label:)`, `Type.subscript(key:)`).
            static let symbols: Set<String> = [
        \(body)
            ]
        }

        """
    }

    /// A Swift string literal for `value`.
    private static func swiftStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
