import Foundation
import Swarm

struct RonaldoResearchTopic: Sendable {
    let id: String
    let title: String
    let objective: String
    let queries: [String]
    let domains: [[String]]
}

struct RonaldoResearchRunResult: Sendable {
    let totalWebsearchCalls: Int
    let evidencePackets: [String]
    let sectionDrafts: [String]
    let executiveSummary: String
    let finalPaper: String
}

enum RonaldoResearchWorkflow {
    static let topics: [RonaldoResearchTopic] = [
        RonaldoResearchTopic(
            id: "origins",
            title: "Origins, Early Life, and Sporting CP",
            objective: "Cover Ronaldo's birth, upbringing in Madeira, early youth development, and the transition from Sporting CP to elite European football.",
            queries: [
                "Cristiano Ronaldo early life Madeira Sporting CP biography",
                "Cristiano Ronaldo Sporting CP youth development official source",
                "Cristiano Ronaldo first team Sporting CP breakthrough source",
                "Cristiano Ronaldo transfer from Sporting CP to Manchester United source",
            ]
            ,
            domains: [
                ["britannica.com", "sporting.pt"],
                ["sporting.pt", "uefa.com"],
                ["sporting.pt", "manutd.com"],
                ["manutd.com", "sporting.pt", "uefa.com"],
            ]
        ),
        RonaldoResearchTopic(
            id: "clubs",
            title: "Club Career Across Manchester United, Real Madrid, Juventus, and Al Nassr",
            objective: "Cover the major phases of Ronaldo's club career, the tactical evolution of his role, and the scale of his production at each club.",
            queries: [
                "Cristiano Ronaldo Manchester United Real Madrid Juventus Al Nassr official career history",
                "Cristiano Ronaldo Real Madrid records official source",
                "Cristiano Ronaldo Juventus career official source",
                "Cristiano Ronaldo Al Nassr statistics current official source",
            ]
            ,
            domains: [
                ["manutd.com", "realmadrid.com", "juventus.com", "alnassr.sa"],
                ["realmadrid.com", "uefa.com"],
                ["juventus.com"],
                ["alnassr.sa", "spl.com.sa"],
            ]
        ),
        RonaldoResearchTopic(
            id: "international",
            title: "Portugal and International Legacy",
            objective: "Cover Ronaldo's Portugal career, major tournaments, captaincy, goalscoring records, and his place in international football history.",
            queries: [
                "Cristiano Ronaldo Portugal national team official record source",
                "Cristiano Ronaldo Euro 2016 Portugal legacy source",
                "Cristiano Ronaldo international goals record official source",
                "Cristiano Ronaldo Nations League Portugal source",
            ]
            ,
            domains: [
                ["fpf.pt", "uefa.com", "fifa.com"],
                ["uefa.com", "fpf.pt"],
                ["fifa.com", "uefa.com", "fpf.pt"],
                ["uefa.com", "fpf.pt"],
            ]
        ),
        RonaldoResearchTopic(
            id: "playstyle",
            title: "Playing Style, Athletic Development, and Records",
            objective: "Explain how Ronaldo's playing style evolved from winger to penalty-box scorer, and summarize his landmark records and technical profile.",
            queries: [
                "Cristiano Ronaldo playing style tactical analysis source",
                "Cristiano Ronaldo goals records official source",
                "Cristiano Ronaldo Champions League records official source",
                "Cristiano Ronaldo athletic evolution analysis source",
            ]
            ,
            domains: [
                ["uefa.com", "fifa.com", "britannica.com"],
                ["fifa.com", "uefa.com", "guinnessworldrecords.com"],
                ["uefa.com"],
                ["uefa.com", "fifa.com", "britannica.com"],
            ]
        ),
        RonaldoResearchTopic(
            id: "impact",
            title: "Commercial Reach, Media Presence, and Cultural Impact",
            objective: "Cover Ronaldo's business footprint, global audience, endorsements, philanthropy, controversies only where necessary, and wider cultural influence.",
            queries: [
                "Cristiano Ronaldo commercial brand global influence source",
                "Cristiano Ronaldo social media reach current source",
                "Cristiano Ronaldo philanthropy source",
                "Cristiano Ronaldo cultural impact football history source",
            ]
            ,
            domains: [
                ["forbes.com", "britannica.com"],
                ["instagram.com", "guinnessworldrecords.com"],
                ["unicef.org", "savechildren.org", "looktothestars.org"],
                ["britannica.com", "fifa.com", "uefa.com"],
            ]
        ),
    ]

    static func shouldRun(from environment: [String: String], input: String) -> Bool {
        if environment["SWARM_DEMO_WORKFLOW"] == "ronaldo_research" {
            return true
        }
        return input.lowercased().contains("cristiano ronaldo") && input.lowercased().contains("research")
    }

    static func run(
        environment: [String: String],
        tracer: any Tracer
    ) async throws -> RonaldoResearchRunResult {
        let synthesisTimeoutSeconds = environment["SWARM_RONALDO_SYNTHESIS_TIMEOUT_SECONDS"].flatMap(Double.init) ?? 120
        let writingTimeoutSeconds = environment["SWARM_RONALDO_WRITER_TIMEOUT_SECONDS"].flatMap(Double.init) ?? 90
        let runID = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let runDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-ronaldo-research", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let searchTool = WebSearchTool(
            configuration: .init(
                apiKey: environment["TAVILY_API_KEY"],
                contextProfile: .strict4k,
                fetchTimeout: 8,
                storeURL: runDirectory.appendingPathComponent("web-memory", isDirectory: true)
            )
        )
        var totalWebsearchCalls = 0
        var evidencePackets: [String] = []
        var sectionDrafts: [String] = []

        for topic in topics {
            let evidenceRun = try await collectEvidence(
                for: topic,
                using: searchTool
            )
            totalWebsearchCalls += evidenceRun.websearchCalls
            let evidencePacket = """
            ## \(topic.title)
            \(evidenceRun.output)
            """
            evidencePackets.append(evidencePacket)

            let writerAgent = try Agent(
                tools: [],
                instructions: """
                You are a research writer drafting one section of a long-form paper.
                Write in sober analytical prose.
                Use only the supplied evidence packet.
                Produce a section between 450 and 650 words.
                End with a short 'Sources' list that repeats the URLs you used.
                """,
                configuration: AgentConfiguration.default
                    .contextProfile(.strict4k)
                    .maxIterations(6)
                    .timeout(.seconds(writingTimeoutSeconds)),
                memory: ConversationMemory(maxMessages: 12),
                tracer: tracer
            )

            let sectionDraft = try await writerAgent.run(
                makeSectionPrompt(for: topic, evidencePacket: evidencePacket)
            )

            let editorAgent = try Agent(
                tools: [],
                instructions: """
                You are a factual editor.
                Rewrite the section using only claims directly supported by the evidence packet.
                Remove speculation, remove unsupported details, and prefer omission over inference.
                Keep the section between 420 and 600 words.
                Do not mention controversies unless the evidence packet explicitly mentions them.
                Preserve the section title and preserve a short 'Sources:' list with URLs only.
                """,
                configuration: AgentConfiguration.default
                    .contextProfile(.strict4k)
                    .maxIterations(6)
                    .timeout(.seconds(45)),
                memory: ConversationMemory(maxMessages: 12),
                tracer: tracer
            )

            let editedSection = try await editorAgent.run(
                """
                Evidence packet:
                \(evidencePacket)

                Draft section:
                \(sectionDraft.output)
                """
            )
            sectionDrafts.append(editedSection.output)
        }

        let summaryAgent = try Agent(
            tools: [],
            instructions: """
            You are an executive editor.
            Write a 280-380 word executive summary for a research paper.
            Use only the supplied section drafts.
            Mention the major conclusions and avoid hype.
            """,
            configuration: AgentConfiguration.default
                .contextProfile(.strict4k)
                .maxIterations(6)
                .timeout(.seconds(synthesisTimeoutSeconds)),
            memory: ConversationMemory(maxMessages: 12),
            tracer: tracer
        )

        let executiveSummary = try await summaryAgent.run(
            makeExecutiveSummaryPrompt(sectionDrafts: sectionDrafts)
        )

        let finalPaper = assembleFinalPaper(
            executiveSummary: executiveSummary.output,
            sectionDrafts: sectionDrafts
        )

        return RonaldoResearchRunResult(
            totalWebsearchCalls: totalWebsearchCalls,
            evidencePackets: evidencePackets,
            sectionDrafts: sectionDrafts,
            executiveSummary: executiveSummary.output,
            finalPaper: finalPaper
        )
    }

    private static func makeSectionPrompt(for topic: RonaldoResearchTopic, evidencePacket: String) -> String {
        """
        Write the section titled "\(topic.title)".
        Objective: \(topic.objective)

        Evidence packet:
        \(evidencePacket)

        Requirements:
        - 450 to 650 words
        - 4 to 6 short paragraphs
        - analytical tone
        - use only the evidence provided
        - if evidence is thin or conflicting, say so plainly instead of inventing details
        - do not mention controversies unless the evidence packet explicitly mentions them
        - end with 'Sources:' followed by URLs
        """
    }

    private static func makeExecutiveSummaryPrompt(sectionDrafts: [String]) -> String {
        """
        Write an executive summary for a Cristiano Ronaldo research paper.
        Use only the following section drafts.

        \(sectionDrafts.joined(separator: "\n\n"))
        """
    }

    private static func assembleFinalPaper(
        executiveSummary: String,
        sectionDrafts: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# Cristiano Ronaldo: A Grounded Research Report")
        lines.append("")
        lines.append("## Introduction")
        lines.append(makeIntroduction())
        lines.append("")
        lines.append("## Executive Summary")
        lines.append(executiveSummary)
        for draft in sectionDrafts {
            lines.append("")
            lines.append(draft)
        }
        lines.append("")
        lines.append("## Conclusion")
        lines.append(makeConclusion())
        return lines.joined(separator: "\n")
    }

    private static func makeIntroduction() -> String {
        """
        This report examines Cristiano Ronaldo from five connected angles: his early development, club career, international legacy, playing evolution, and commercial influence. The goal is not to retell every milestone in his career, but to assemble a grounded account from current web evidence that explains why he remains central to football history. The paper prioritizes primary or high-quality reference material, then uses those sources to identify durable patterns in Ronaldo's career: early acceleration through Sporting CP, elite production across multiple clubs, sustained influence with Portugal, a tactical shift from wide attacker to penalty-box finisher, and a commercial profile that reaches well beyond sport. Taken together, these themes show why Ronaldo is best understood not only as an outstanding goal-scorer, but as a figure whose athletic, tactical, and cultural significance has persisted across eras.
        """
    }

    private static func makeConclusion() -> String {
        """
        Cristiano Ronaldo's career is remarkable not simply because of the number of goals, trophies, or records attached to his name, but because of the durability of his influence across distinct football contexts. The evidence in this report points to a player who adapted repeatedly without losing elite output: from Sporting CP prospect, to Premier League star, to Real Madrid focal point, to veteran scorer and international leader. His Portugal record, Champions League legacy, and broad commercial presence all reinforce the same conclusion. Ronaldo's story is one of sustained reinvention under scrutiny, with technical skill, physical preparation, and global visibility combining to make him one of the defining football figures of the modern era.
        """
    }

    private static func collectEvidence(
        for topic: RonaldoResearchTopic,
        using searchTool: WebSearchTool
    ) async throws -> (output: String, websearchCalls: Int) {
        var bullets: [String] = []
        for (index, query) in topic.queries.enumerated() {
            let domains = index < topic.domains.count ? topic.domains[index] : []
            let result = try await searchTool.execute(arguments: [
                "mode": "search",
                "query": .string(query),
                "maxResults": .int(2),
                "detail": .string("compact"),
                "preferCached": .bool(false),
                "persist": .bool(true),
                "domains": .array(domains.map(SendableValue.string))
            ])
            let rendered = result.stringValue ?? result.description
            bullets.append(extractBestEvidenceBullet(from: rendered, query: query))
        }
        return (bullets.joined(separator: "\n"), topic.queries.count)
    }

    private static func extractBestEvidenceBullet(from rendered: String, query: String) -> String {
        let lines = rendered.split(separator: "\n").map(String.init)
        var bestTitle = ""
        var bestURL = ""
        var bestSnippet = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if bestTitle.isEmpty,
               let open = trimmed.range(of: "["),
               let close = trimmed.range(of: "]("),
               let end = trimmed.range(of: ")", range: close.upperBound..<trimmed.endIndex)
            {
                bestTitle = String(trimmed[open.upperBound..<close.lowerBound])
                bestURL = String(trimmed[close.upperBound..<end.lowerBound])
                continue
            }
            if !bestURL.isEmpty, !trimmed.isEmpty, !trimmed.hasPrefix("## "), !trimmed.hasPrefix("[EVIDENCE") {
                bestSnippet = trimmed
                break
            }
        }
        let title = bestTitle.isEmpty ? query : bestTitle
        let url = bestURL.isEmpty ? "source unavailable" : bestURL
        let snippet = bestSnippet.isEmpty ? rendered.prefix(240).trimmingCharacters(in: .whitespacesAndNewlines) : bestSnippet
        return "- \(title) (\(url)) — \(snippet)"
    }
}
