import SwiftUI

/// Audune is a menu bar utility. `AppDelegate` creates the menu bar item and windows;
/// the only scene is an empty one because SwiftUI requires at least one.
@main struct MyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        Settings { EmptyView() }
        #else
        WindowGroup { Text("Audune runs on macOS.") }
        #endif
    }
}
