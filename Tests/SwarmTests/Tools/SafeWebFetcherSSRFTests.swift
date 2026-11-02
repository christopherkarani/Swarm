#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

@Suite("SafeWebFetcher SSRF host validation")
struct SafeWebFetcherSSRFTests {
    @Test(
        "Blocks every spelling of loopback, private and reserved IP literals",
        arguments: [
            // IPv6 loopback / unspecified in non-compressed forms
            "http://[::1]/",
            "http://[0:0:0:0:0:0:0:1]/",
            "http://[0000:0000:0000:0000:0000:0000:0000:0001]/",
            "http://[::]/",
            "http://[0:0:0:0:0:0:0:0]/",
            // IPv4-mapped / translated / compatible loopback and private
            "http://[::ffff:127.0.0.1]/",
            "http://[0:0:0:0:0:ffff:7f00:1]/",
            "http://[::ffff:7f00:1]/",
            "http://[::ffff:a00:1]/",
            "http://[::ffff:0:7f00:1]/",
            "http://[::127.0.0.1]/",
            "http://[::7f00:1]/",
            "http://[::8.8.8.8]/",
            // NAT64 and 6to4 with embedded private IPv4
            "http://[64:ff9b::7f00:1]/",
            "http://[64:ff9b::a9fe:a9fe]/",
            "http://[64:ff9b:1::808:808]/",
            "http://[2002:7f00:1::]/",
            "http://[2002:a9fe:a9fe::1]/",
            // Link-local, ULA, site-local, multicast, Teredo, documentation, discard
            "http://[fe80::1]/",
            "http://[FE80:0:0:0:0:0:0:1]/",
            "http://[febf::1]/",
            "http://[fc00::1]/",
            "http://[fd12:3456::1]/",
            "http://[fec0::1]/",
            "http://[ff02::1]/",
            "http://[2001:0:4136:e378::1]/",
            "http://[2001:db8::1]/",
            "http://[100::1]/",
            // Zone identifiers and malformed IPv6
            "http://[fe80::1%25en0]/",
            // Non-canonical IPv4: octal, hex, shorthand, integer, leading zeros
            "http://0177.0.0.1/",
            "http://0177.000.000.001/",
            "http://010.0.0.1/",
            "http://0x7f.0.0.1/",
            "http://0x7f000001/",
            "http://127.1/",
            "http://127.0.1/",
            "http://2130706433/",
            "http://017700000001/",
            "http://00.0.0.0/",
            "http://1.2.3.04/",
            "http://256.0.0.1/",
            "http://1.2.3.4.5/",
            // Canonical private IPv4 literals (regression)
            "http://127.0.0.1/",
            "http://127.0.0.1./",
            "http://10.0.0.1/",
            "http://169.254.169.254/",
            "http://172.16.0.1/",
            "http://192.168.1.1/",
            "http://100.64.0.1/",
            "http://0.0.0.0/",
            "http://224.0.0.1/",
            "http://255.255.255.255/",
        ]
    )
    func blocksIPLiteral(_ urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(throws: AgentError.self) {
            try SafeWebFetcher.validate(url: url)
        }
    }

    @Test(
        "Allows public IP literals",
        arguments: [
            "http://93.184.216.34/",
            "https://8.8.8.8/",
            "http://1.1.1.1/",
            "http://[2606:4700:4700::1111]/",
            "http://[2001:4860:4860:0:0:0:0:8888]/",
            "http://[::ffff:8.8.8.8]/",
            "http://[::ffff:808:808]/",
            "http://[64:ff9b::808:808]/",
            "http://[2002:808:808::1]/",
        ]
    )
    func allowsPublicIPLiteral(_ urlString: String) throws {
        let url = try #require(URL(string: urlString))
        try SafeWebFetcher.validate(url: url)
    }

    @Test(
        "Classifies equivalent IPv6 spellings identically",
        arguments: [
            ("::1", "0:0:0:0:0:0:0:1"),
            ("::ffff:127.0.0.1", "0:0:0:0:0:ffff:7f00:1"),
            ("fe80::1", "FE80:0000:0000:0000:0000:0000:0000:0001"),
        ]
    )
    func ipv6SpellingsNormalize(_ lhs: String, _ rhs: String) throws {
        let left = try #require(try ResolvedHostAddress.literalAddress(lhs))
        let right = try #require(try ResolvedHostAddress.literalAddress(rhs))
        #expect(left == right)
        #expect(left.isBlockedForFetch)
    }

    @Test("DNS names are not treated as IP literals", arguments: ["example.com", "1.2.3.4.example", "cafe.be", "0x.example"])
    func dnsNamesAreNotLiterals(_ host: String) throws {
        #expect(try ResolvedHostAddress.literalAddress(host) == nil)
    }
}
#endif
