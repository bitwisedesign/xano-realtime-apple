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
        /// Brace depth of the type or extension body.
        var bodyDepth: Int
    }

    /// A parsed `actor` / `class` / `struct` / `enum` / `protocol` / `typealias` line.
    private struct TypeDeclaration {
        /// Declared type name.
        var name: String
        /// Swift keyword for the declaration.
        var kind: String
        /// Whether the declaration is marked `public`.
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

    /// A parsed `public` member on one line.
    private struct MemberDeclaration {
        /// `func`, `var`, `let`, `subscript`, or `init`.
        var kind: String
        /// Member name (`init` / `subscript` for those kinds).
        var name: String
        /// Remainder of the line after the name (generics, parameters, accessors).
        var remainder: String
    }

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
    private static func scan(source: String) -> Set<String> {
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
            let opensBody = trimmed.contains("{")
            stack.append(
                TypeFrame(
                    name: typeDecl.name,
                    recordsCases: typeDecl.isPublic && typeDecl.kind == "enum",
                    bodyDepth: opensBody ? depth + 1 : depth
                )
            )
            return
        }
        if let extensionName = parseExtensionName(trimmed) {
            let opensBody = trimmed.contains("{")
            stack.append(
                TypeFrame(
                    name: extensionName,
                    recordsCases: false,
                    bodyDepth: opensBody ? depth + 1 : depth
                )
            )
            return
        }
        guard let current = stack.last, depth == current.bodyDepth else {
            return
        }
        if current.recordsCases, let caseName = parseEnumCaseName(trimmed) {
            symbols.insert("\(current.name).\(caseName)")
            return
        }
        if let member = parsePublicMember(trimmed) {
            recordMember(member, on: current.name, pending: &pending, symbols: &symbols)
        }
    }

    /// Parses `public actor|class|struct|enum|protocol|typealias Name`.
    private static func parseTypeDeclaration(_ trimmed: String) -> TypeDeclaration? {
        var rest = trimmed[...]
        skipAttributes(from: &rest)
        let isPublic = consumeKeyword("public", from: &rest)
        skipKeyword("final", from: &rest)
        guard let kind = consumeOne(
            of: ["actor", "class", "struct", "enum", "protocol", "typealias"],
            from: &rest
        ) else {
            return nil
        }
        skipWhitespace(&rest)
        guard let name = takeIdentifier(from: &rest) else {
            return nil
        }
        return TypeDeclaration(name: name, kind: kind, isPublic: isPublic)
    }

    /// Parses `extension TypeName`.
    private static func parseExtensionName(_ trimmed: String) -> String? {
        var rest = trimmed[...]
        skipAttributes(from: &rest)
        guard consumeKeyword("extension", from: &rest) else {
            return nil
        }
        skipWhitespace(&rest)
        return takeIdentifier(from: &rest)
    }

    /// Parses a public enum `case name` (not a switch `case .name`).
    private static func parseEnumCaseName(_ trimmed: String) -> String? {
        var rest = trimmed[...]
        guard consumeKeyword("case", from: &rest) else {
            return nil
        }
        skipWhitespace(&rest)
        if rest.first == "." {
            return nil
        }
        return takeIdentifier(from: &rest)
    }

    /// Parses `public [static] func|var|let|subscript|init`.
    private static func parsePublicMember(_ trimmed: String) -> MemberDeclaration? {
        var rest = trimmed[...]
        skipAttributes(from: &rest)
        guard consumeKeyword("public", from: &rest) else {
            return nil
        }
        skipKeyword("static", from: &rest)
        skipKeyword("class", from: &rest)
        guard let kind = consumeOne(
            of: ["func", "var", "let", "subscript", "init"],
            from: &rest
        ) else {
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

    /// Consumes `keyword` when present.
    private static func skipKeyword(_ keyword: String, from rest: inout Substring) {
        _ = consumeKeyword(keyword, from: &rest)
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
