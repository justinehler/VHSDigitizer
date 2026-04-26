import AppKit
import SwiftUI

@main
struct VHSDigitizerApp: App {
    @StateObject private var capture = CaptureController()
    @AppStorage("useDarkMode") private var useDarkMode = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(capture)
                .preferredColorScheme(useDarkMode ? .dark : .light)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    capture.requestPermissionsAndStart()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About VHS Digitizer") {
                    showAboutPanel()
                }
            }
            CommandGroup(replacing: .newItem) { }
        }
    }

    private func showAboutPanel() {
        let credits = NSMutableAttributedString(string: "Created by Justin Ehler\n")
        credits.append(NSAttributedString(
            string: "justinehler.com\n",
            attributes: [.link: URL(string: "https://justinehler.com") as Any]
        ))
        credits.append(NSAttributedString(string: "Copyright 2026 Justin Ehler"))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "VHS Digitizer",
            .applicationVersion: "0.1.0",
            .credits: credits
        ])
    }
}
