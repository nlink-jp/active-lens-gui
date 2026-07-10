import AppKit
import SwiftUI

@main
struct ActiveLensApp: App {
    @StateObject private var model = Self.makeModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            // Current state glyph + the active time of the session you are in.
            Image(systemName: model.currentState?.icon ?? "pause.circle")
            Text(model.sessionActiveLabel)
        }
        .menuBarExtraStyle(.window)

        Window("Activity Analysis", id: "analysis") {
            AnalysisView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
    }

    /// Build the model and kick off its refresh loop at launch.
    private static func makeModel() -> ActivityModel {
        let m = ActivityModel()
        m.start()
        return m
    }
}
