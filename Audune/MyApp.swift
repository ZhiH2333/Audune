import SwiftUI
#if os(macOS)
import AppKit
#endif

@main struct MyApp: App {
    #if os(macOS)
    @State private var spike = ProcessTapSpike()
    #endif

    var body: some Scene {
        WindowGroup(id: "debug") {
            #if os(macOS)
            ContentView(spike: spike)
                .background(MenuBarInstaller(spike: spike))
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    spike.stop()
                }
            #else
            ContentView()
            #endif
        }
    }
}
