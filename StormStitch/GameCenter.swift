import GameKit
import UIKit

/// Game Center: sign-in, leaderboards and achievements.
/// Set up these IDs in App Store Connect (Features > Game Center):
/// - Leaderboard `com.adambellow.stormstitch.daily` (recurring, resets daily, high score wins)
/// - Leaderboard `com.adambellow.stormstitch.endless` (classic, high score wins)
/// - Leaderboard `com.adambellow.stormstitch.stars` (classic, high score wins)
/// - One achievement per trophy: `com.adambellow.stormstitch.trophy.<name>` (see Trophy.gameCenterID)
enum GameCenter {
    static let dailyBoard = "com.adambellow.stormstitch.daily"
    static let endlessBoard = "com.adambellow.stormstitch.endless"
    static let starsBoard = "com.adambellow.stormstitch.stars"

    static var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }
    static var playerName: String? { isSignedIn ? GKLocalPlayer.local.alias : nil }

    /// Signs in quietly at launch. Game Center shows its own sign-in sheet if needed.
    static func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            if let viewController, let presenter = topViewController() {
                presenter.present(viewController, animated: true)
            } else if GKLocalPlayer.local.isAuthenticated {
                syncAll()
                LiveRace.shared.registerForInvites()
            }
        }
    }

    /// Sends everything earned while signed out: trophies and the star total.
    static func syncAll() {
        let earned = Progress.shared.data.trophies.compactMap { Trophy(rawValue: $0) }
        if !earned.isEmpty {
            let achievements = earned.map { trophy -> GKAchievement in
                let achievement = GKAchievement(identifier: trophy.gameCenterID)
                achievement.percentComplete = 100
                achievement.showsCompletionBanner = false
                return achievement
            }
            GKAchievement.report(achievements) { _ in }
        }
        submit(Progress.shared.totalStars, to: starsBoard)
    }

    static func submit(_ score: Int, to board: String) {
        guard isSignedIn, score > 0 else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [board]) { _ in }
    }

    static func report(_ trophy: Trophy) {
        guard isSignedIn else { return }
        let achievement = GKAchievement(identifier: trophy.gameCenterID)
        achievement.percentComplete = 100
        achievement.showsCompletionBanner = true
        GKAchievement.report([achievement]) { _ in }
    }

    /// Opens the Game Center leaderboards, or asks the player to sign in.
    static func showLeaderboards(_ board: String? = nil) {
        guard let presenter = topViewController() else { return }
        guard isSignedIn else {
            let alert = UIAlertController(title: "Sign in to Game Center",
                                          message: "Open Settings > Game Center to sign in and compare scores with friends.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter.present(alert, animated: true)
            return
        }
        let controller: GKGameCenterViewController
        if let board {
            controller = GKGameCenterViewController(leaderboardID: board, playerScope: .global, timeScope: .today)
        } else {
            controller = GKGameCenterViewController(state: .leaderboards)
        }
        controller.gameCenterDelegate = Dismisser.shared
        presenter.present(controller, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            gameCenterViewController.dismiss(animated: true)
        }
    }
}
