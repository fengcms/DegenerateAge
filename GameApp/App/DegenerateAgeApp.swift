import SwiftUI

@main
struct DegenerateAgeApp: App {
    var body: some Scene {
        WindowGroup("末法纪元：最后的守护者") {
            GameRootView()
                .frame(minWidth: 800, minHeight: 550)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
