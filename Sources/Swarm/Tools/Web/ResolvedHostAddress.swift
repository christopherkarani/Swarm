#if SWARM_INTEGRATIONS
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A numeric address a fetch host resolves to, classified for SSRF filtering.
///
/// IPv6 addresses are held as their 16 network-order bytes so that every textual
/// spelling of the same address (`::1`, `0:0:0:0:0:0:0:1`, `::ffff:7f00:1`, ...)
/// is classified identically.
internal enum ResolvedHostAddress: Sendable, Equatable {
    case ipv4(UInt8, UInt8, UInt8, UInt8)
    case ipv6([UInt8])

    var isBlockedForFetch: Bool {
        switch self {
        case let .ipv4(first, second, _, _):
            Self.isBlockedIPv4(first: first, second: second)
        case let .ipv6(bytes):
            Self.isBlockedIPv6(bytes)
        }
    }

    private static func isBlockedIPv4(first: UInt8, second: UInt8) -> Bool {
        switch first {
        case 0, 10, 127:
            true
        case 100:
            (64 ... 127).contains(second)
        case 169:
            second == 254
        case 172:
            (16 ... 31).contains(second)
        case 192:
            second == 0 || second == 168
        case 198:
            (18 ... 19).contains(second) || second == 51
        case 203:
            second == 0
        case 224 ... 255:
            true
        default:
            false
        }
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else {
            return true
        }
        if let embedded = embeddedIPv4(in: bytes) {
            return embedded.isBlockedForFetch
        }
        // ::/96 covers the unspecified address, loopback, and the deprecated
        // IPv4-compatible range (RFC 4291 §2.5.5.1); none is a public destination.
        if bytes[0 ..< 12].allSatisfy({ $0 == 0 }) {
            return true
        }
        let first = bytes[0]
        let second = bytes[1]
        let firstWord = UInt16(first) << 8 | UInt16(second)
        let secondWord = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        return first == 0xFF // multicast ff00::/8
            || (first & 0xFE) == 0xFC // unique local fc00::/7
            || (firstWord & 0xFFC0) == 0xFE80 // link-local fe80::/10
            || (firstWord & 0xFFC0) == 0xFEC0 // deprecated site-local fec0::/10
            || (firstWord == 0x0064 && secondWord == 0xFF9B && bytes[4] == 0 && bytes[5] == 1) // local NAT64 64:ff9b:1::/48
            || (firstWord == 0x2001 && secondWord == 0x0000) // Teredo 2001::/32
            || (firstWord == 0x2001 && secondWord == 0x0DB8) // documentation 2001:db8::/32
            || (firstWord == 0x0100 && bytes[2 ..< 8].allSatisfy { $0 == 0 }) // discard 100::/64
    }

    /// Returns the IPv4 address embedded in an IPv4-mapped (`::ffff:0:0/96`),
    /// IPv4-translated (`::ffff:0:0:0/96`), NAT64 (`64:ff9b::/96`) or 6to4
    /// (`2002::/16`) IPv6 address.
    private static func embeddedIPv4(in bytes: [UInt8]) -> ResolvedHostAddress? {
        let isMapped = bytes[0 ..< 10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        let isTranslated = bytes[0 ..< 8].allSatisfy { $0 == 0 }
            && bytes[8] == 0xFF && bytes[9] == 0xFF && bytes[10] == 0 && bytes[11] == 0
        let isNAT64 = bytes[0 ..< 12].elementsEqual([0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0])
        if isMapped || isTranslated || isNAT64 {
            return .ipv4(bytes[12], bytes[13], bytes[14], bytes[15])
        }
        if bytes[0] == 0x20, bytes[1] == 0x02 {
            return .ipv4(bytes[2], bytes[3], bytes[4], bytes[5])
        }
        return nil
    }

    /// Resolves a URL host to the numeric addresses it denotes.
    ///
    /// IP literals are parsed without DNS. A host whose last label is numeric is
    /// treated as an IPv4 literal (as the WHATWG URL parser and `inet_aton` do)
    /// and must be in canonical dotted-decimal form: octal (`0177.0.0.1`), hex
    /// (`0x7f.0.0.1`), shorthand (`127.1`) and integer (`2130706433`) spellings
    /// are rejected because resolvers disagree on what they mean.
    static func resolve(host: String) throws -> [ResolvedHostAddress] {
        if let literal = try literalAddress(host) {
            return [literal]
        }
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        #if canImport(Darwin) || canImport(Glibc)
        #if canImport(Glibc)
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: numericCast(SOCK_STREAM.rawValue),
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_addr: nil,
            ai_canonname: nil,
            ai_next: nil
        )
        #else
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        #endif
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(normalizedHost, nil, &hints, &result)
        guard status == 0, let result else {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Unable to resolve URL host")
        }
        defer { freeaddrinfo(result) }

        var addresses: [ResolvedHostAddress] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let current = cursor {
            if let address = numericAddress(from: current.pointee) {
                addresses.append(address)
            }
            cursor = current.pointee.ai_next
        }
        guard !addresses.isEmpty else {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Unable to resolve URL host")
        }
        return addresses
        #else
        throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Host resolution is unavailable on this platform")
        #endif
    }

    /// Parses `host` as an IP literal.
    ///
    /// - Returns: The address, or `nil` when `host` is a DNS name.
    /// - Throws: When `host` looks like an IP literal but is malformed,
    ///   non-canonical, or carries an IPv6 zone identifier.
    static func literalAddress(_ host: String) throws -> ResolvedHostAddress? {
        let unbracketed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if unbracketed.contains(":") {
            guard let address = parseIPv6(unbracketed) else {
                throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Malformed IPv6 host is blocked")
            }
            return address
        }

        var labels = unbracketed.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count > 1, labels.last?.isEmpty == true {
            labels.removeLast() // a single trailing root dot
        }
        guard let last = labels.last, isNumericLabel(last) else {
            return nil
        }
        let octets = labels.compactMap(canonicalOctet)
        guard labels.count == 4, octets.count == 4 else {
            throw AgentError.invalidToolArguments(
                toolName: "websearch",
                reason: "Non-canonical IPv4 host forms are blocked"
            )
        }
        return .ipv4(octets[0], octets[1], octets[2], octets[3])
    }

    /// A label that a URL parser or `inet_aton` would read as a number:
    /// decimal digits, or `0x`/`0X` followed by hex digits.
    private static func isNumericLabel(_ label: Substring) -> Bool {
        if label.isEmpty {
            return false
        }
        if label.allSatisfy(\.isASCIIDigit) {
            return true
        }
        let lowered = label.lowercased()
        return lowered.hasPrefix("0x") && lowered.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A dotted-decimal octet with no leading zeros, in `0...255`.
    private static func canonicalOctet(_ label: Substring) -> UInt8? {
        guard !label.isEmpty, label.count <= 3, label.allSatisfy(\.isASCIIDigit) else {
            return nil
        }
        if label.count > 1, label.first == "0" {
            return nil
        }
        return UInt8(label)
    }

    private static func parseIPv6(_ text: String) -> ResolvedHostAddress? {
        // Zone identifiers (`fe80::1%en0`) only name link-local scopes.
        guard !text.contains("%") else {
            return nil
        }
        #if canImport(Darwin) || canImport(Glibc)
        var storage = in6_addr()
        guard inet_pton(AF_INET6, text, &storage) == 1 else {
            return nil
        }
        return .ipv6(withUnsafeBytes(of: &storage) { Array($0) })
        #else
        return nil
        #endif
    }

    #if canImport(Darwin) || canImport(Glibc)
    private static func numericAddress(from info: addrinfo) -> ResolvedHostAddress? {
        guard let socketAddress = info.ai_addr else {
            return nil
        }
        switch info.ai_family {
        case Int32(AF_INET):
            let bytes = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                var address = pointer.pointee.sin_addr
                return withUnsafeBytes(of: &address) { Array($0) }
            }
            guard bytes.count == 4 else {
                return nil
            }
            return .ipv4(bytes[0], bytes[1], bytes[2], bytes[3])
        case Int32(AF_INET6):
            let bytes = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                var address = pointer.pointee.sin6_addr
                return withUnsafeBytes(of: &address) { Array($0) }
            }
            return .ipv6(bytes)
        default:
            return nil
        }
    }
    #endif
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
#endif
