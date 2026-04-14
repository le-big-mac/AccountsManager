import SwiftUI
import SwiftData

@Observable
class AppState {
    static let shared = AppState()
    var trueLayerCallback: (code: String, state: String)?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? "nil"
        DebugLog.write("URL callback received: \(urlString)")

        guard let url = URL(string: urlString),
              url.scheme == "accounts",
              url.host == "truelayer-callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            DebugLog.write("URL callback parsing failed")
            return
        }
        DebugLog.write("Parsed code=\(code.prefix(20))... state=\(state.prefix(12))...")
        AppState.shared.trueLayerCallback = (code: code, state: state)
    }
}

@main
struct AccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AccountListView()
                .modelContainer(for: Account.self)
                .environment(AppState.shared)
        }
        .defaultSize(width: 750, height: 500)
    }
}
