import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String =
    "xxxxxxxxxxxxxxxx"
    
    // The available width drives the adaptive banner size. Adaptive banners choose a height automatically
    // that fits the current device and orientation for the given width, maximizing performance and fill.
    let width: CGFloat

    func makeUIView(context: Context) -> BannerView {
        // Create an anchored adaptive banner size that matches the current width. This tells the SDK to pick
        // an optimal height for this width and orientation.
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        let banner = BannerView(adSize: adSize) // Instantiate the GMA banner with the computed adaptive size
        banner.adUnitID = adUnitID // Assign your banner ad unit ID (test during development)
        banner.delegate = context.coordinator // Receive load success/failure callbacks via Coordinator
        banner.rootViewController = UIApplication.shared.firstKeyWindowRootViewController() // Required by the SDK to present in-app content (e.g., clickthroughs) from a view controller
        banner.load(Request()) // Start loading the banner with default request parameters
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // If the container width changes (rotation, split view, etc.), recompute the adaptive size
        // so the banner height and layout remain valid.
        let newSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        if !CGSizeEqualToSize(newSize.size, uiView.adSize.size) { // Only update and reload if the size actually changed to avoid redundant requests
            uiView.adSize = newSize // Apply the new adaptive size
            uiView.load(Request()) // Reload the banner for the new size
        }
    }

    // SwiftUI bridge: Coordinator lets UIKit delegates communicate back to SwiftUI
    func makeCoordinator() -> Coordinator { Coordinator() }

    // Implement the banner delegate to observe ad load results. Useful for logging, analytics,
    // or triggering UI changes when an ad loads or fails.
    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { print("Banner loaded") } // Called when an ad successfully loads
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("Banner failed: \(error.localizedDescription)")
        } // Called when an ad fails to load (inspect error for details)
    }
}

// Helper to find a root view controller for presenting from UIKit APIs. Google Mobile Ads requires
// a valid UIViewController to present clickthroughs and other full-screen content.
private extension UIApplication {
    func firstKeyWindowRootViewController() -> UIViewController? {
        connectedScenes // Support multi-scene apps (iPadOS/macOS Catalyst); find the active key window
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
    }
}

// Convenience to get the current key window from a scene
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}

