import SwiftUI

@main
struct StormStitchApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
