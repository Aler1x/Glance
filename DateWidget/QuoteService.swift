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

        let pattern = #"id="ttm-advice-text-big"[^>]*>\s*([\s\S]*?)\s*</strong>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: 1), in: html)
        else { return "" }

        let raw = String(html[range])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw
    }
}
