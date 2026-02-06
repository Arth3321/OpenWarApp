
import SwiftUI
import GoogleMobileAds
import Combine
import Foundation

final class InterstitialAdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    // Use Google's official test interstitial unit ID during development. Replace with your real unit ID for production.
    /// Google test interstitial ad unit
    private let adUnitID = "xxxxxxxxxxxxxx"

    // Keep a strong reference to the loaded interstitial until it's shown or fails.
    private var interstitial: InterstitialAd?

    // Request a new interstitial. Should be called initially and again after presentation/dismissal.
    func load() {
        let request = Request() // Default ad request; customize if you need targeting or test device IDs
        InterstitialAd.load(with: adUnitID, request: request) { [weak self] ad, error in // Asynchronously load the interstitial; capture self weakly to avoid retain cycles
            if let error { print("Interstitial failed to load: \(error)"); return } // Log and bail if the request failed
            self?.interstitial = ad // Hold onto the loaded ad for later presentation
            self?.interstitial?.fullScreenContentDelegate = self // Receive presentation/dismissal callbacks to manage the load cycle
            print("Interstitial loaded")
        }
    }

    // Present the interstitial if available; otherwise kick off a load.
    func present() {
        guard let root = UIApplication.shared.firstKeyWindowRootViewController() else { return } // Required: interstitials must be presented from a UIViewController
        guard let interstitial else {
            print("Interstitial not ready — loading now") ; load() ; return // If not ready, trigger load and exit; UI can try again later
        }
        interstitial.present(from: root) // Show the ad
    }

    // MARK: - GADFullScreenContentDelegate
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("Interstitial dismissed — loading next") // After dismissal, clear reference and load the next ad
        self.interstitial = nil
        self.load()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Interstitial failed to present: \(error)") // If presentation fails, clear and attempt to load again
        self.interstitial = nil
        self.load()
    }
}

// Helper to locate a root view controller for presentation in multi-scene apps.
private extension UIApplication {
    func firstKeyWindowRootViewController() -> UIViewController? {
        connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow } // Iterate active scenes and find the key window
            .first?
            .rootViewController
    }
}

// Convenience to fetch the key window for a scene
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}

