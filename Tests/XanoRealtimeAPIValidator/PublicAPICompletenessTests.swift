import Foundation
import Testing

/// Walks `Sources/XanoRealtime` and records public type, member, and enum-case keys.
private enum PublicAPIScanner {
    // MARK: - Nested Types

    /// A type, enum, or extension currently open in the source walk.
    private struct TypeFrame {
        /// Type or extension name used for member keys.
        var name: String
        /// Whether enum cases at this frame's body depth are public API.
        var recordsCases: Bool
        /// Whether unmarked members inherit public access from this declaration.
        var inheritsPublicAccess: Bool
        /// Brace depth of the type or extension body.
        var bodyDepth: Int
    }

    /// A parsed `actor` / `class` / `struct` / `enum` / `protocol` / `typealias` line.
    private struct TypeDeclaration {
        /// Declared type name.
        var name: String
        /// Swift keyword for the declaration.
        var kind: String
        /// Whether the declaration is marked `public` or `open`.
        var isPublic: Bool
    }

    /// A parsed `public` member whose parameter list may continue on later lines.
    private struct PendingSignature {
        /// Type the member belongs to.
        var typeName: String
        /// `func`, `init`, or `subscript`.
        var kind: String
        /// Member name (`init` / `subscript` for those kinds).
        var name: String
        /// Accumulated text starting at the opening `(`.
        var buffer: String
    }

    /// A parsed `extension TypeName` line.
    private struct ExtensionDeclaration {
        /// Extended type name used for member keys.
        var name: String
        /// Whether the extension is marked `public`.
        var isPublic: Bool
    }

    /// A parsed `public` member on one line.
    private struct MemberDeclaration {
        /// `func`, `var`, `let`, `subscript`, or `init`.
        var kind: String
        /// Member name (`init` / `subscript` for those kinds).
        var name: String
        /// Remainder of the line after the name (generics, parameters, accessors).
        var remainder: String
    }

    // MARK: - Properties

    /// Access-control and declaration modifiers consumed before a type or member kind.
    private static let declarationModifiers: Set<String> = [
        "public", "open", "package", "internal", "fileprivate", "private",
        "final", "static", "class", "indirect",
        "mutating", "nonmutating", "nonisolated",
        "convenience", "required", "override",
        "lazy", "unowned", "weak", "optional", "dynamic"
    ]

    /// Type-declaration keywords that end the modifier prefix.
    private static let typeKinds = ["actor", "class", "struct", "enum", "protocol", "typealias"]

    /// Member-declaration keywords that end the modifier prefix.
    private static let memberKinds = ["func", "var", "let", "subscript", "init"]

    // MARK: - Public API

    /// Extracts public API keys from every Swift file under `Sources/XanoRealtime`.
    ///
    /// - Parameter filePath: Path of this test file; used to locate the repo root.
    /// - Returns: The scanned public symbol keys.
    /// - Throws: An error when the sources directory cannot be read.
    static func scanSources(filePath: String = #filePath) throws -> Set<String> {
        let repoRoot = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = repoRoot.appendingPathComponent("Sources/XanoRealtime")
        var collected: Set<String> = []
        try walk(directory: sources, into: &collected)
        return collected
    }

    // MARK: - Private Helpers

    /// Recursively scans Swift files under `directory`.
    private static func walk(directory: URL, into collected: inout Set<String>) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            let isDirectory = try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            if isDirectory {
                try walk(directory: entry, into: &collected)
            } else if entry.pathExtension == "swift" {
                let source = try String(contentsOf: entry, encoding: .utf8)
                collected.formUnion(scan(source: source))
            }
        }
    }

    /// Extracts public API keys from one Swift source file.
    fileprivate static func scan(source: String) -> Set<String> {
        var symbols: Set<String> = []
        var stack: [TypeFrame] = []
        var pending: PendingSignature?
        var depth = 0
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = stripLineComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
                continue
            }
            parseDeclarations(
                in: trimmed,
                depth: depth,
                stack: &stack,
                pending: &pending,
                symbols: &symbols
            )
            depth += braceDelta(in: trimmed)
            while let frame = stack.last, depth < frame.bodyDepth {
                stack.removeLast()
            }
        }
        return symbols
    }

    /// Records types, members, and cases on `trimmed` at the current brace `depth`.
    private static func parseDeclarations(
        in trimmed: String,
        depth: Int,
        stack: inout [TypeFrame],
        pending: inout PendingSignature?,
        symbols: inout Set<String>
    ) {
        if var openSignature = pending {
            openSignature.buffer += " \(trimmed)"
            if let key = signatureKey(openSignature) {
                symbols.insert(key)
                pending = nil
            } else {
                pending = openSignature
            }
            return
        }
        if let typeDecl = parseTypeDeclaration(trimmed) {
            if typeDecl.isPublic {
                symbols.insert(typeDecl.name)
            }
            if typeDecl.kind != "typealias" {
                pushFrameIfBodyOpens(
                    name: typeDecl.name,
                    recordsCases: typeDecl.isPublic && typeDecl.kind == "enum",
                    inheritsPublicAccess: typeDecl.isPublic && typeDecl.kind == "protocol",
                    in: trimmed,
                    depth: depth,
                    stack: &stack,
                    pending: &pending,
                    symbols: &symbols
                )
            }
            return
        }
        if let extensionDecl = parseExtensionDeclaration(trimmed) {
            pushFrameIfBodyOpens(
                name: extensionDecl.name,
                recordsCases: false,
                inheritsPublicAccess: extensionDecl.isPublic,
                in: trimmed,
                depth: depth,
                stack: &stack,
                pending: &pending,
                symbols: &symbols
            )
            return
        }
        guard let current = stack.last, depth == current.bodyDepth else {
            return
        }
        if current.recordsCases {
            let caseNames = parseEnumCaseNames(trimmed)
            if !caseNames.isEmpty {
                for caseName in caseNames {
                    symbols.insert("\(current.name).\(caseName)")
                }
                return
            }
        }
        if let member = parsePublicMember(trimmed, inheritsPublicAccess: current.inheritsPublicAccess) {
            recordMember(member, on: current.name, pending: &pending, symbols: &symbols)
        }
    }

    /// Parses `actor|class|struct|enum|protocol|typealias Name` after any modifier prefix.
    private static func parseTypeDeclaration(_ trimmed: String) -> TypeDeclaration? {
        var rest = trimmed[...]
        skipAttributes(from: &rest)
        let isPublic = consumePublicAPIModifiers(from: &rest, stoppingBefore: typeKinds)
        guard let kind = consumeOne(of: typeKinds, from: &rest) else {
            return nil
        }
        skipWhitespace(&rest)
        guard let name = takeIdentifier(from: &rest) else {
            return nil
        }
        return TypeDeclaration(name: name, kind: kind, isPublic: isPublic)
    }

    /// Parses `extension TypeName` after any modifier prefix.
    private static func parseExtensionDeclaration(_ trimmed: String) -> ExtensionDeclaration? {
        var rest = trimmed[...]
        skipAttributes(from: &rest)
        let isPublic = consumePublicAPIModifiers(from: &rest, stoppingBefore: ["extension"])
        guard consumeKeyword("extension", from: &rest) else {
            return nil
        }
        skipWhitespace(&rest)
        guard let name = takeIdentifier(from: &rest) else {
            return nil
        }
        return ExtensionDeclaration(name: name, isPublic: isPublic)
    }

    /// Pushes a type frame when `trimmed` opens a body, then scans any same-line members or cases.
    private static func pushFrameIfBodyOpens(
        name: String,
        recordsCases: Bool,
        inheritsPublicAccess: Bool,
        in trimmed: String,
        depth: Int,
        stack: inout [TypeFrame],
        pending: inout PendingSignature?,
        symbols: inout Set<String>
    ) {
        guard let open = trimmed.firstIndex(of: "{") else {
            return
        }
        stack.append(
            TypeFrame(
                name: name,
                recordsCases: recordsCases,
                inheritsPublicAccess: inheritsPublicAccess,
                bodyDepth: depth + 1
            )
        )
        let body = String(trimmed[trimmed.index(after: open)...])
            .trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else {
            return
        }
        parseDeclarations(
            in: body,
            depth: depth + 1,
            stack: &stack,
            pending: &pending,
            symbols: &symbols
        )
    }

    /// Parses public enum `case` names, including comma-separated lists (not switch `case .name`).
    private static func parseEnumCaseNames(_ trimmed: String) -> [String] {
        var rest = trimmed[...]
        guard consumeKeyword("case", from: &rest) else {
            return []
        }
        skipWhitespace(&rest)
        if rest.first == "." {
            return []
        }
        return splitParameters(String(rest)).compactMap { parameter in
            var item = parameter[...]
            return takeIdentifier(from: &item)
        }
    }

    /// Parses `func|var|let|subscript|init` when the member is public API.
    ///
    /// A member is public when the modifier prefix includes `public` or `open`,
    /// or when `inheritsPublicAccess` is true and no narrower access is spelled.
    private static func parsePublicMember(
        _ trimmed: String,
        inheritsPublicAccess: Bool
    ) -> MemberDeclaration? {
        var rest = trimmed[...]
        skipAttributes(from: &rest)
        guard consumePublicAPIModifiers(
            from: &rest,
            stoppingBefore: memberKinds,
            inheritsPublicAccess: inheritsPublicAccess
        ) else {
            return nil
        }
        guard let kind = consumeOne(of: memberKinds, from: &rest) else {
            return nil
        }
        if kind == "init" || kind == "subscript" {
            return MemberDeclaration(kind: kind, name: kind, remainder: String(rest))
        }
        skipWhitespace(&rest)
        guard let name = takeIdentifier(from: &rest) else {
            return nil
        }
        return MemberDeclaration(kind: kind, name: name, remainder: String(rest))
    }

    /// Records a property immediately, or a function/init/subscript selector once its `(` list is complete.
    private static func recordMember(
        _ member: MemberDeclaration,
        on typeName: String,
        pending: inout PendingSignature?,
        symbols: inout Set<String>
    ) {
        guard member.kind == "func" || member.kind == "init" || member.kind == "subscript" else {
            symbols.insert("\(typeName).\(member.name)")
            return
        }
        var remainder = member.remainder[...]
        skipWhitespace(&remainder)
        if remainder.first == "<" {
            skipBalancedAngles(from: &remainder)
            skipWhitespace(&remainder)
        }
        guard remainder.first == "(" else {
            symbols.insert("\(typeName).\(member.name)()")
            return
        }
        let open = PendingSignature(
            typeName: typeName,
            kind: member.kind,
            name: member.name,
            buffer: String(remainder)
        )
        if let key = signatureKey(open) {
            symbols.insert(key)
        } else {
            pending = open
        }
    }

    /// Builds `Type.name(labels:)` when `pending.buffer` contains a balanced parameter list.
    private static func signatureKey(_ pending: PendingSignature) -> String? {
        guard let selector = selectorIfComplete(pending.buffer) else {
            return nil
        }
        switch pending.kind {
        case "init":
            return "\(pending.typeName).init\(selector)"
        case "subscript":
            return "\(pending.typeName).subscript\(selector)"
        default:
            return "\(pending.typeName).\(pending.name)\(selector)"
        }
    }

    /// Returns a Swift-selector `(_:label:)` when the first `(...)` in `text` is complete.
    private static func selectorIfComplete(_ text: String) -> String? {
        guard let inner = completeParameterInner(text) else {
            return nil
        }
        return formatSelector(inner)
    }

    /// Inner text of the first balanced `(...)`, or `nil` if the close paren has not appeared yet.
    private static func completeParameterInner(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "(") else {
            return nil
        }
        var depth = 0
        var inString = false
        var escape = false
        var index = open
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    let innerStart = text.index(after: open)
                    return String(text[innerStart..<index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Formats parameter inner text as `()` or `(label:label:)`.
    private static func formatSelector(_ inner: String) -> String {
        let parameters = splitParameters(inner)
        if parameters.isEmpty {
            return "()"
        }
        let labels = parameters.map { parameterLabel($0) + ":" }
        return "(\(labels.joined()))"
    }

    /// Splits a parameter list on commas that are not inside `()`, `<>`, or `[]`.
    private static func splitParameters(_ inner: String) -> [String] {
        var parameters: [String] = []
        var current = ""
        var parenDepth = 0
        var angleDepth = 0
        var bracketDepth = 0
        var inString = false
        var escape = false
        for character in inner {
            if inString {
                current.append(character)
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
                current.append(character)
            } else if character == "(" {
                parenDepth += 1
                current.append(character)
            } else if character == ")" {
                parenDepth -= 1
                current.append(character)
            } else if character == "<" {
                angleDepth += 1
                current.append(character)
            } else if character == ">" {
                angleDepth -= 1
                current.append(character)
            } else if character == "[" {
                bracketDepth += 1
                current.append(character)
            } else if character == "]" {
                bracketDepth -= 1
                current.append(character)
            } else if character == ",", parenDepth == 0, angleDepth == 0, bracketDepth == 0 {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parameters.append(trimmed)
                }
                current = ""
            } else {
                current.append(character)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parameters.append(trimmed)
        }
        return parameters
    }

    /// External argument label of one parameter (`_` or the first identifier).
    private static func parameterLabel(_ parameter: String) -> String {
        var rest = parameter[...]
        skipAttributes(from: &rest)
        skipWhitespace(&rest)
        if rest.first == "_" {
            let after = rest.index(after: rest.startIndex)
            if after == rest.endIndex || rest[after].isWhitespace {
                return "_"
            }
        }
        return takeIdentifier(from: &rest) ?? "_"
    }

    /// Consumes a matching `<...>` generic clause.
    private static func skipBalancedAngles(from rest: inout Substring) {
        guard rest.first == "<" else {
            return
        }
        var depth = 0
        while let character = rest.first {
            rest.removeFirst()
            if character == "<" {
                depth += 1
            } else if character == ">" {
                depth -= 1
                if depth == 0 {
                    return
                }
            }
        }
    }

    /// Removes a `//` comment that is not part of a string or URL scheme.
    private static func stripLineComment(_ line: String) -> String {
        var inString = false
        var escape = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inString {
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "/", line[index...].hasPrefix("//") {
                return String(line[..<index])
            }
            index = line.index(after: index)
        }
        return line
    }

    /// Net `{` minus `}` on `line`, ignoring braces inside string literals.
    private static func braceDelta(in line: String) -> Int {
        var delta = 0
        var inString = false
        var escape = false
        for character in line {
            if inString {
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" {
                delta += 1
            } else if character == "}" {
                delta -= 1
            }
        }
        return delta
    }

    /// Skips `@Attribute` and `@Attribute(...)` prefixes.
    private static func skipAttributes(from rest: inout Substring) {
        while true {
            skipWhitespace(&rest)
            guard rest.first == "@" else {
                return
            }
            rest.removeFirst()
            _ = takeIdentifier(from: &rest)
            skipWhitespace(&rest)
            if rest.first == "(" {
                skipBalancedParens(from: &rest)
            }
        }
    }

    /// Consumes a matching `(...)` group.
    private static func skipBalancedParens(from rest: inout Substring) {
        guard rest.first == "(" else {
            return
        }
        var depth = 0
        while let character = rest.first {
            rest.removeFirst()
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return
                }
            }
        }
    }

    /// Whether the declaration is public API after consuming its modifier prefix.
    ///
    /// Consumes access-control and declaration modifiers, including parenthesized
    /// forms such as `private(set)`, until the next token is a kind in `kinds` or
    /// is not a modifier. An explicit `public` or `open` is public. An explicit
    /// narrower access modifier is not. Setter-only forms do not change access.
    /// When `inheritsPublicAccess` is true, unmarked declarations are public.
    ///
    /// - Parameters:
    ///   - rest: Remaining declaration text.
    ///   - kinds: Keywords that end the modifier prefix.
    ///   - inheritsPublicAccess: Treat unmarked declarations as public.
    /// - Returns: Whether the declaration is public API.
    private static func consumePublicAPIModifiers(
        from rest: inout Substring,
        stoppingBefore kinds: [String],
        inheritsPublicAccess: Bool = false
    ) -> Bool {
        var isPublicAPI = inheritsPublicAccess
        let kindSet = Set(kinds)
        let accessModifiers: Set<String> = [
            "public", "open", "package", "internal", "fileprivate", "private"
        ]
        while true {
            skipWhitespace(&rest)
            guard let word = peekIdentifier(rest) else {
                return isPublicAPI
            }
            if kindSet.contains(word) {
                return isPublicAPI
            }
            guard declarationModifiers.contains(word) else {
                return isPublicAPI
            }
            _ = takeIdentifier(from: &rest)
            skipWhitespace(&rest)
            let hasArgument = rest.first == "("
            if hasArgument {
                skipBalancedParens(from: &rest)
            }
            if accessModifiers.contains(word), !hasArgument {
                isPublicAPI = word == "public" || word == "open"
            }
        }
    }

    /// Returns the next identifier without consuming it.
    private static func peekIdentifier(_ rest: Substring) -> String? {
        var copy = rest
        return takeIdentifier(from: &copy)
    }

    /// Consumes `keyword` when it is the next identifier.
    @discardableResult
    private static func consumeKeyword(_ keyword: String, from rest: inout Substring) -> Bool {
        skipWhitespace(&rest)
        guard rest.hasPrefix(keyword) else {
            return false
        }
        let after = rest.index(rest.startIndex, offsetBy: keyword.count)
        if after < rest.endIndex, isIdentifierContinue(rest[after]) {
            return false
        }
        rest = rest[after...]
        return true
    }

    /// Consumes the first matching keyword in `keywords`.
    private static func consumeOne(of keywords: [String], from rest: inout Substring) -> String? {
        for keyword in keywords where consumeKeyword(keyword, from: &rest) {
            return keyword
        }
        return nil
    }

    /// Reads a Swift identifier from the start of `rest`.
    private static func takeIdentifier(from rest: inout Substring) -> String? {
        skipWhitespace(&rest)
        guard let first = rest.first, isIdentifierStart(first) else {
            return nil
        }
        var end = rest.startIndex
        while end < rest.endIndex, isIdentifierContinue(rest[end]) {
            end = rest.index(after: end)
        }
        let name = String(rest[..<end])
        rest = rest[end...]
        return name
    }

    /// Skips leading ASCII whitespace.
    private static func skipWhitespace(_ rest: inout Substring) {
        while let first = rest.first, first.isWhitespace {
            rest.removeFirst()
        }
    }

    /// Whether `character` can start a Swift identifier.
    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    /// Whether `character` can continue a Swift identifier.
    private static func isIdentifierContinue(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}

// MARK: - Scanner unit tests

@Test("records each comma-separated enum case")
func recordsEachCommaSeparatedEnumCase() {
    let symbols = PublicAPIScanner.scan(
        source: """
        public enum Palette {
            case red, green, blue
        }
        """
    )
    #expect(symbols.contains("Palette"))
    #expect(symbols.contains("Palette.red"))
    #expect(symbols.contains("Palette.green"))
    #expect(symbols.contains("Palette.blue"))
}

@Test("records same-line enum cases before the type frame closes")
func recordsSameLineEnumCasesBeforeTheTypeFrameCloses() {
    let symbols = PublicAPIScanner.scan(source: "public enum Flag { case on, off }")
    #expect(symbols.contains("Flag"))
    #expect(symbols.contains("Flag.on"))
    #expect(symbols.contains("Flag.off"))
}

@Test("records comma-separated cases with associated values individually")
func recordsCommaSeparatedCasesWithAssociatedValuesIndividually() {
    let symbols = PublicAPIScanner.scan(
        source: """
        public enum ScanResult {
            case success(Int), failure(String)
        }
        """
    )
    #expect(symbols.contains("ScanResult.success"))
    #expect(symbols.contains("ScanResult.failure"))
}

@Test("records types when access and declaration modifiers appear in any order")
func recordsTypesWhenModifiersAppearInAnyOrder() {
    let symbols = PublicAPIScanner.scan(
        source: """
        final public class Ordered {
            public var member: Int
        }
        open class Visible {
            public var member: Int
            open func hook() {}
        }
        public indirect enum Tree {
            case leaf
        }
        """
    )
    #expect(symbols.contains("Ordered"))
    #expect(symbols.contains("Ordered.member"))
    #expect(symbols.contains("Visible"))
    #expect(symbols.contains("Visible.member"))
    #expect(symbols.contains("Visible.hook()"))
    #expect(symbols.contains("Tree"))
    #expect(symbols.contains("Tree.leaf"))
}

@Test("records members that use access-control and declaration modifiers")
func recordsMembersThatUseAccessControlAndDeclarationModifiers() {
    let symbols = PublicAPIScanner.scan(
        source: """
        public class Widget {
            public private(set) var locked: Int
            public mutating func flip() {}
            public nonisolated func ping() {}
            public final func close() {}
            public convenience init() {}
            public required init(name: String) {}
        }
        """
    )
    #expect(symbols.contains("Widget.locked"))
    #expect(symbols.contains("Widget.flip()"))
    #expect(symbols.contains("Widget.ping()"))
    #expect(symbols.contains("Widget.close()"))
    #expect(symbols.contains("Widget.init()"))
    #expect(symbols.contains("Widget.init(name:)"))
}

@Test("does not attribute members after a typealias to the alias")
func doesNotAttributeMembersAfterATypealiasToTheAlias() {
    let symbols = PublicAPIScanner.scan(
        source: """
        public struct Container {
            public typealias AliasName = Int
            public var member: Int
        }
        """
    )
    #expect(symbols.contains("Container"))
    #expect(symbols.contains("AliasName"))
    #expect(symbols.contains("Container.member"))
    #expect(!symbols.contains("AliasName.member"))
}

@Test("records unmarked requirements of a public protocol")
func recordsUnmarkedRequirementsOfAPublicProtocol() {
    let symbols = PublicAPIScanner.scan(
        source: """
        public protocol Drawable {
            var size: Int { get }
            func draw()
            init()
        }
        """
    )
    #expect(symbols.contains("Drawable"))
    #expect(symbols.contains("Drawable.size"))
    #expect(symbols.contains("Drawable.draw()"))
    #expect(symbols.contains("Drawable.init()"))
}

@Test("records unmarked members of a public extension")
func recordsUnmarkedMembersOfAPublicExtension() {
    let symbols = PublicAPIScanner.scan(
        source: """
        public struct Widget {}
        public extension Widget {
            var label: String { "x" }
            private(set) var locked: Int
            func ping() {}
            public func poke() {}
            private func hide() {}
            internal func stash() {}
        }
        """
    )
    #expect(symbols.contains("Widget"))
    #expect(symbols.contains("Widget.label"))
    #expect(symbols.contains("Widget.locked"))
    #expect(symbols.contains("Widget.ping()"))
    #expect(symbols.contains("Widget.poke()"))
    #expect(!symbols.contains("Widget.hide()"))
    #expect(!symbols.contains("Widget.stash()"))
}

@Test("scanned public API matches the approved inventory")
func scannedPublicAPIMatchesApprovedInventory() throws {
    let scanned = try PublicAPIScanner.scanSources()
    if PublicAPIInventoryWriter.isRequested {
        try PublicAPIInventoryWriter.write(scanned)
        return
    }
    let unexpected = scanned.subtracting(PublicAPIInventory.symbols).sorted()
    let missing = PublicAPIInventory.symbols.subtracting(scanned).sorted()
    #expect(
        unexpected.isEmpty,
        """
        Unexpected public API: \(unexpected.joined(separator: ", ")). \
        If approved, run \(PublicAPIInventoryWriter.environmentVariable)=1 \
        swift test --filter scannedPublicAPIMatchesApprovedInventory and review the inventory diff.
        """
    )
    #expect(
        missing.isEmpty,
        """
        Missing public API: \(missing.joined(separator: ", ")). \
        If approved, run \(PublicAPIInventoryWriter.environmentVariable)=1 \
        swift test --filter scannedPublicAPIMatchesApprovedInventory and review the inventory diff.
        """
    )
}
