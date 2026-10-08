import Foundation

/// Resolves only links already supplied by the workspace. It never constructs URLs from assistant text.
public enum ServiceResolver {
    public static func resolve(_ query: String, in connections: [ServiceConnection]) -> [ServiceConnection] {
        func normalize(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        }
        let text = normalize(query)
        let aliases: [(ServiceProvider, [String])] = [
            (.expo, ["expo", "eas"]), (.oneSignal, ["onesignal", "one signal"]), (.searchConsole, ["search console", "gsc"]),
            (.cloudflare, ["cloudflare", "cf"]), (.vercel, ["vercel"]), (.revenueCat, ["revenuecat", "revenue cat"]),
            (.sentry, ["sentry"]), (.analytics, ["google analytics", "analytics", "ga4"]), (.appStore, ["app store connect", "appstoreconnect", "app store", "asc"]),
            (.googlePlay, ["google play", "googleplay", "play console"])
        ]
        let words = " " + text + " "
        let matches = aliases.flatMap { provider, names in names.filter { words.contains(" " + $0 + " ") }.map { (provider, $0) } }
            .sorted { $0.1.count > $1.1.count }
        let provider = matches.first?.0
        var remainder = text
        if let alias = matches.first?.1 { remainder = (" " + remainder + " ").replacingOccurrences(of: " " + alias + " ", with: " ") }
        let ignored: Set<String> = ["open", "the", "dashboard", "please", "for"]
        let terms = remainder.split(separator: " ").map(String.init).filter { !ignored.contains($0) }
        guard provider != nil || !terms.isEmpty else { return [] }
        return connections.filter { item in
            guard ServiceCatalog.safeURL(item.dashboardURL) != nil, provider == nil || item.provider == provider else { return false }
            let identity = normalize(item.name + " " + item.resourceID + " " + item.environment)
            return terms.allSatisfy { (" " + identity + " ").contains(" " + $0 + " ") }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
