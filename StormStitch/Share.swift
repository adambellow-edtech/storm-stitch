import UIKit

/// Sharing results and friend challenges.
///
/// Challenge links look like `https://stormstitchgame.com/c/?d=42&t=1234&n=Adam`:
/// the website page opens the app with `stormstitch://challenge?d=42&t=1234&n=Adam`,
/// or sends people without the app to the App Store. Everyone on the same daily number
/// runs the exact same course, so the challenge is fair.
enum Share {
    static let site = "https://stormstitchgame.com"

    static func challengeURL(daily: Int, score: Int, name: String) -> URL? {
        var parts = URLComponents(string: "\(site)/c/")
        parts?.queryItems = [
            URLQueryItem(name: "d", value: String(daily)),
            URLQueryItem(name: "t", value: String(score)),
            URLQueryItem(name: "n", value: String(name.prefix(20)))
        ]
        return parts?.url
    }

    /// Turns an opened link (custom scheme or website link) into a challenge.
    static func challenge(from url: URL) -> (daily: Int, target: Int, from: String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let isScheme = url.scheme == "stormstitch" && url.host == "challenge"
        let isSite = (url.host ?? "").hasSuffix("stormstitchgame.com") && url.path.hasPrefix("/c")
        guard isScheme || isSite else { return nil }
        let items = parts.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let daily = value("d").flatMap(Int.init), daily > 0,
              let target = value("t").flatMap(Int.init), target >= 0 else { return nil }
        let name = (value("n") ?? "A friend").trimmingCharacters(in: .whitespacesAndNewlines)
        return (daily, target, name.isEmpty ? "A friend" : String(name.prefix(20)))
    }

    /// The text that goes with a shared result, Wordle style.
    static func text(storm: DailyStorm, stats: RunStats, stars: Int, beat: (name: String, target: Int)? = nil) -> String {
        let starLine = String(repeating: "⭐", count: stars) + String(repeating: "▫️", count: max(0, 3 - stars))
        var lines = [
            "Storm Stitch Daily #\(storm.number) \(storm.rule.emoji) \(storm.rule.name)",
            "\(starLine)  🧵 \(stats.spools)  📏 \(Int(stats.distance)) m",
            "Score: \(stats.score.formatted())"
        ]
        if let beat {
            lines.append(stats.score > beat.target ? "I beat \(beat.name)'s \(beat.target.formatted())! 🏆" : "\(beat.name) still leads with \(beat.target.formatted()).")
        }
        lines.append("Can you outrun the storm?")
        return lines.joined(separator: "\n")
    }

    /// A shareable picture of the result.
    static func card(storm: DailyStorm?, title: String, stats: RunStats, stars: Int, monsterID: String) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            UIColor(hex: 0x8FD3FF).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if let art = UIImage(named: "title-card") {
                let scale = size.width / art.size.width
                art.draw(in: CGRect(x: 0, y: 0, width: size.width, height: art.size.height * scale))
            }

            // Paper panel.
            let panel = CGRect(x: 70, y: 760, width: 940, height: 520)
            ctx.setFillColor(UIColor(white: 0, alpha: 0.25).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: panel.offsetBy(dx: 0, dy: 12), cornerRadius: 40).cgPath)
            ctx.fillPath()
            if let paper = UIImage(named: "ui-card") {
                paper.draw(in: panel)
            } else {
                ctx.setFillColor(Palette.paper.cgColor)
                ctx.addPath(UIBezierPath(roundedRect: panel, cornerRadius: 40).cgPath)
                ctx.fillPath()
            }

            if let monster = UIImage(named: "\(monsterID)-front") {
                let h: CGFloat = 300
                let w = h * monster.size.width / monster.size.height
                monster.draw(in: CGRect(x: 130, y: panel.midY - h / 2, width: min(w, 300), height: h * min(w, 300) / w))
            }

            func draw(_ string: String, at point: CGPoint, size: CGFloat, color: UIColor, heading: Bool) {
                let name = heading ? "Fredoka-Bold" : "NunitoSans-ExtraBold"
                let font = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color,
                    .strokeColor: Palette.ink, .strokeWidth: heading ? -6 : 0
                ]
                (string as NSString).draw(at: point, withAttributes: attrs)
            }
            let x: CGFloat = 470
            draw(title, at: CGPoint(x: x, y: panel.minY + 70), size: 58, color: Palette.stitchGold, heading: true)
            if let storm {
                draw("\(storm.rule.emoji) \(storm.rule.name)", at: CGPoint(x: x, y: panel.minY + 150), size: 38, color: Palette.ink, heading: false)
            }
            draw(String(repeating: "★", count: stars) + String(repeating: "☆", count: max(0, 3 - stars)),
                 at: CGPoint(x: x, y: panel.minY + 210), size: 64, color: Palette.stitchGold, heading: true)
            draw("\(stats.spools) spools  ·  \(Int(stats.distance)) m", at: CGPoint(x: x, y: panel.minY + 300), size: 38, color: Palette.ink, heading: false)
            draw("Score \(stats.score.formatted())", at: CGPoint(x: x, y: panel.minY + 360), size: 52, color: .white, heading: true)
            draw("stormstitchgame.com", at: CGPoint(x: x, y: panel.minY + 440), size: 30, color: Palette.stormDark, heading: false)
        }
    }

    /// Shows the system share sheet.
    static func present(items: [Any], from sourcePoint: CGPoint? = nil) {
        guard let presenter = GameCenter.topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            let point = sourcePoint ?? CGPoint(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY)
            popover.sourceRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        }
        presenter.present(sheet, animated: true)
    }
}

/// Holds a link the app was opened with until the game is ready to act on it.
enum DeepLink {
    static let opened = Notification.Name("StormStitchOpenedLink")
    static var pending: URL?

    static func handle(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: opened, object: nil)
    }
}
