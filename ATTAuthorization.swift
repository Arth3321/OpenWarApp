
import Foundation
import AppTrackingTransparency // Framework that provides the ATT API (ATTrackingManager)
import AdSupport // Access to advertising identifiers if authorized (not used directly here, but commonly paired with ATT)

// Simple namespace for ATT-related utilities
enum ATTAuthorization {
    // Only request tracking authorization if we haven't asked before. This avoids repeat prompts
    // and follows Apple's guidance for respectful timing and context.
    static func requestIfNeeded() {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return } // If the user already made a choice (allowed/denied), do nothing.
        // Small delay gives the app time to finish launching UI before presenting the system dialog,
        // creating a smoother experience and avoiding potential presentation warnings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                // Optional: react to the new status (e.g., configure SDKs for limited tracking if denied).
            }
        }
    }
}
