import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

// App entry point. Initializes the Google Mobile Ads SDK and requests ATT at an appropriate time.
struct GoogleAdMobExampleApp: App {
    @Environment(\.scenePhase) private var scenePhase // Observe app lifecycle to time privacy prompts and other behaviors
    
    init() {
        // Initialize the Google Mobile Ads SDK early so ad requests can proceed. Status is available
        // in the completion if you need to inspect adapter states.
        MobileAds.shared.start { status in }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in // Request ATT after the app becomes active to ensure the prompt appears over your UI
            if newPhase == .active { // Present ATT only when foregrounded for a better UX
                requestATTIfNeeded()
            }
        }
    }
    
    private func requestATTIfNeeded() {
        // Only prompt if status is not determined; otherwise, do nothing
        if #available(iOS 14, tvOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            guard status == .notDetermined else { return }
            ATTrackingManager.requestTrackingAuthorization { _ in
                // You can inspect the returned status if needed
            }
        }
    }
}
