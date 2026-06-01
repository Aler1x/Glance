import Foundation
internal import Combine

final class QuoteService: ObservableObject {
    @Published var text: String = ""
    private var timer: Timer?

    init() {
        Task { await fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { await self?.fetch() }
        }
    }

    private func fetch() async {
        guard let url = URL(string: "https://theytoldme.com/random"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return }

        let pattern = #"id="ttm-advice-text-big"[^>]*>\s*([\s\S]*?)\s*</strong>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return }

        let raw = String(html[range])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        await MainActor.run { self.text = raw }
    }
}
