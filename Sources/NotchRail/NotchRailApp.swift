import SwiftUI
import AppKit
import NotchRailKit

@main
struct NotchRailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
