import SwiftUI
import SwiftData

@Observable
class AppState {
    static let shared = AppState()
    var trueLayerCallback: (code: String, state: String)?
    var snapTradeCallbackReceived = false
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

        guard let url = URL(string: urlString),
              url.scheme == "accounts" else {
            DebugLog.write("URL callback parsing failed")
            return
        }

        if url.host == "snaptrade-callback" {
            DebugLog.write("SnapTrade callback received")
            AppState.shared.snapTradeCallbackReceived = true
            return
        }

        guard url.host == "truelayer-callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            DebugLog.write("URL callback parsing failed")
            return
        }
        AppState.shared.trueLayerCallback = (code: code, state: state)
    }
}

@main
struct AccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    init() {
        PersistentStoreBackup.prepareStore()

        do {
            let configuration = ModelConfiguration(url: PersistentStoreBackup.storeURL)
            modelContainer = try ModelContainer(
                for: Account.self,
                Holding.self,
                SecurityMetadata.self,
                CashBalance.self,
                BalanceEntry.self,
                BankBalance.self,
                BankTransaction.self,
                configurations: configuration
            )
        } catch {
            DebugLog.write("SwiftData model container failed: \(error.localizedDescription)")
            fatalError("SwiftData model container failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AccountListView()
                .modelContainer(modelContainer)
                .environment(AppState.shared)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
