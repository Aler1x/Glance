//
//  QuoteService.swift
//  DateWidget
//
//  Created by Alerix and Claude on 1.06.2026.
//

import Foundation

enum QuoteService {
    static func fetch() async -> String {
        guard let url = URL(string: "https://theytoldme.com/random"),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let html = String(data: data, encoding: .utf8)
        else { return "" }

        // The quote is split across two elements: the big "setup" line and the
        // small "punchline" line. Put the big line on its own line above the small.
        let big = extract(id: "ttm-advice-text-big", from: html)
        let small = extract(id: "ttm-advice-text-small", from: html)
        return [big, small].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Pulls the text content of the element carrying `id`, up to its closing tag.
    private static func extract(id: String, from html: String) -> String {
        let pattern = #"id="\#(id)"[^>]*>\s*([\s\S]*?)\s*</"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: 1), in: html)
        else { return "" }
        return clean(String(html[range]))
    }

    private static func clean(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#,  with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
