import SwiftUI
import Combine
import WebKit
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import UserNotifications
import StoreKit

// MARK: - App Entry Point avec Notifications
@main
struct OpenFrontApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppReviewManager (INCHANGÉ)
final class AppReviewManager {
    static let shared = AppReviewManager()
    private init() {}
    
    private let launchCountKey = "appLaunchCount"
    private let hasRequestedReviewKey = "hasRequestedAppReview"
    
    func incrementLaunchCount() {
        let currentCount = UserDefaults.standard.integer(forKey: launchCountKey)
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: launchCountKey)
        print("📊 Nombre d'ouvertures: \(newCount)")
    }
    
    func checkAndRequestReview() {
        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        let hasRequested = UserDefaults.standard.bool(forKey: hasRequestedReviewKey)
        
        guard !hasRequested else {
            print("⭐️ Évaluation déjà demandée précédemment")
            return
        }
        
        guard launchCount >= 3 else {
            print("⏳ Pas encore assez d'ouvertures (\(launchCount)/3)")
            return
        }
        
        print("⭐️ 3ème ouverture détectée - Demande d'évaluation")
        
        // Marquer comme demandé
        UserDefaults.standard.set(true, forKey: hasRequestedReviewKey)
        
        // Demander l'évaluation avec un léger délai pour une meilleure UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }
}

// MARK: - ✅ AJOUTÉ - DisclaimerManager
final class DisclaimerManager {
    static let shared = DisclaimerManager()
    private init() {}
    
    private let hasReadDisclaimerKey = "hasReadLegalDisclaimer"
    
    func hasReadDisclaimer() -> Bool {
        return UserDefaults.standard.bool(forKey: hasReadDisclaimerKey)
    }
    
    func markDisclaimerAsRead() {
        UserDefaults.standard.set(true, forKey: hasReadDisclaimerKey)
        print("✅ Disclaimer légal marqué comme lu")
    }
}
// MARK: - AppDelegate pour Notifications + Ads
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // ✅ Configuration du Notification Manager
        NotificationManager.shared.setup()
        
        // ✅ Définir le delegate pour les notifications
        UNUserNotificationCenter.current().delegate = self
        
        // ✅ Incrémenter le compteur d'ouvertures
        AppReviewManager.shared.incrementLaunchCount()
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        Task {
            await NotificationManager.shared.scheduleNextNotification()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()  // ✅ AJOUTÉ - Efface les notifications du centre
        
        Task {
            await NotificationManager.shared.scheduleNextNotification()
        }
    }
}

// MARK: - Extension UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("📱 Notification ouverte: \(response.notification.request.content.body)")
        completionHandler()
    }
}

// MARK: - ConsentManager (INCHANGÉ)
final class ConsentManager {
    static let shared = ConsentManager()
    private var isMobileAdsStarted = false
    private init() {}

    func requestConsent(from viewController: UIViewController, completion: @escaping (Bool, Error?) -> Void) {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completion(false, error)
                return
            }

            if ConsentInformation.shared.formStatus == .available {
                ConsentForm.load { form, loadError in
                    if let loadError = loadError {
                        completion(false, loadError)
                        return
                    }

                    guard let form = form else {
                        completion(false, NSError(domain: "ConsentManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Formulaire non disponible"]))
                        return
                    }

                    if ConsentInformation.shared.consentStatus == .required {
                        form.present(from: viewController) { _ in
                            completion(ConsentInformation.shared.canRequestAds, nil)
                        }
                    } else {
                        completion(ConsentInformation.shared.canRequestAds, nil)
                    }
                }
            } else {
                completion(ConsentInformation.shared.canRequestAds, nil)
            }
        }
    }

    func startMobileAdsIfNeeded(completion: @escaping () -> Void) {
        guard !isMobileAdsStarted else {
            completion()
            return
        }

        guard ConsentInformation.shared.canRequestAds else {
            completion()
            return
        }

        MobileAds.shared.start { status in
            self.isMobileAdsStarted = true
            print("✅ Mobile Ads initialisé")
            completion()
        }
    }

    func canRequestAds() -> Bool {
        return ConsentInformation.shared.canRequestAds
    }

    func consentStatus() -> ConsentStatus {
        return ConsentInformation.shared.consentStatus
    }

    func resetConsent() {
        ConsentInformation.shared.reset()
        isMobileAdsStarted = false
    }

    func showPrivacyOptionsForm(from viewController: UIViewController, completion: @escaping (Error?) -> Void) {
        ConsentForm.presentPrivacyOptionsForm(from: viewController) { error in
            completion(error)
        }
    }
}

// MARK: - WebViewConfigurationManager (INCHANGÉ)
class WebViewConfigurationManager {
    static let shared = WebViewConfigurationManager()
    
    let processPool = WKProcessPool()
    let configuration: WKWebViewConfiguration
    private var isScriptsConfigured = false
    
    private init() {
        configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        if #available(iOS 15.0, *) {
            configuration.upgradeKnownHostsToHTTPS = false
        }
    }
    
    func configureUserScriptsOnce(coordinator: WKScriptMessageHandler) {
        guard !isScriptsConfigured else {
            print("⚠️ Scripts déjà configurés - injection ignorée")
            return
        }
        
        let contentController = configuration.userContentController
        
        contentController.removeAllUserScripts()
        contentController.removeScriptMessageHandler(forName: "clickHandler")
        contentController.removeScriptMessageHandler(forName: "interactionHandler")
        
        let script = """
        window.addEventListener('blur', function(e) {
            console.log('Window blur detected');
        }, false);
        
        document.addEventListener('click', function(e) {
            window.webkit.messageHandlers.clickHandler.postMessage({
                x: e.clientX,
                y: e.clientY,
                target: e.target.tagName
            });
        }, false);
        
        document.addEventListener('touchstart', function(e) {
            window.webkit.messageHandlers.interactionHandler.postMessage({
                touches: e.touches.length,
                target: e.target.tagName
            });
        }, false);
        
        setInterval(function() {
            console.log('Keep-alive ping');
        }, 30000);
        """
        
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        contentController.add(coordinator, name: "clickHandler")
        contentController.add(coordinator, name: "interactionHandler")
        
        isScriptsConfigured = true
        print("✅ Scripts et handlers configurés une seule fois")
    }
    
    func resetScripts() {
        configuration.userContentController.removeAllUserScripts()
        configuration.userContentController.removeScriptMessageHandler(forName: "clickHandler")
        configuration.userContentController.removeScriptMessageHandler(forName: "interactionHandler")
        isScriptsConfigured = false
    }
}

// MARK: - AppManager (✅ MODIFIÉ - Plus de vérification serveur)
class AppManager: ObservableObject {
    @Published var isAdSystemReady = false
    @Published var isWebViewLoaded = false
    @Published var showConsentError = false
    // ✅ SUPPRIMÉ: adsAllowedByServer - Les pubs sont toujours autorisées

    var consentErrorMessage: String = ""
    
    func requestConsentAndInitializeAds() {
        guard isWebViewLoaded else {
            print("⏳ En attente du chargement de la WebView...")
            return
        }

        // ✅ SUPPRIMÉ: Vérification serveur - Initialisation directe des pubs
        print("📣 Initialisation des pubs sans vérification serveur")
        continueAdsInitialization()
    }
    
    private func continueAdsInitialization() {
        self.requestAppTrackingIfNeeded { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?
                    .rootViewController {

                    ConsentManager.shared.requestConsent(from: rootVC) { [weak self] _, _ in
                        guard let self = self else { return }

                        ConsentManager.shared.startMobileAdsIfNeeded {
                            DispatchQueue.main.async {
                                self.isAdSystemReady = ConsentManager.shared.canRequestAds()
                                print("📣 Ads system ready: \(self.isAdSystemReady)")
                            }
                        }
                    }
                } else {
                    ConsentManager.shared.startMobileAdsIfNeeded {
                        DispatchQueue.main.async {
                            self.isAdSystemReady = ConsentManager.shared.canRequestAds()
                            print("📣 Ads system ready (no VC path): \(self.isAdSystemReady)")
                        }
                    }
                }
            }
        }
    }

    
    private func requestAppTrackingIfNeeded(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            switch status {
            case .notDetermined:
                ATTrackingManager.requestTrackingAuthorization { _ in
                    completion(true)
                }
            default:
                completion(true)
            }
        } else {
            completion(true)
        }
    }
}

// MARK: - ✅ AJOUTÉ - Fonction de vibration
extension UIImpactFeedbackGenerator {
    static func lightVibration() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    static func mediumVibration() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}


// MARK: - NotificationSettingsView (✅ AJOUTÉ vibrations)
struct NotificationSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var notificationStatus = "Vérification..."
    @State private var scheduledTime: String = "Aucune"
    @State private var lastMessage: String = "Aucun"
    @State private var isAuthorized = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Notifications Quotidiennes")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(isAuthorized ? "✅ Activées" : "❌ Désactivées")
                            .foregroundColor(isAuthorized ? .green : .red)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 20)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 15) {
                        InfoRow(title: "Statut", value: notificationStatus)
                        InfoRow(title: "Heure programmée", value: scheduledTime)
                        InfoRow(title: "Dernier message", value: lastMessage)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    VStack(spacing: 15) {
                        Button(action: {
                            UIImpactFeedbackGenerator.lightVibration()  // ✅ AJOUTÉ
                            Task {
                                await refreshNotificationInfo()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Actualiser les infos")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button(action: {
                            UIImpactFeedbackGenerator.mediumVibration()  // ✅ AJOUTÉ
                            NotificationManager.shared.triggerManualRefresh()
                            notificationStatus = "Notification reprogrammée"
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                Task {
                                    await refreshNotificationInfo()
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                Text("Forcer nouvelle notification")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button(action: {
                            UIImpactFeedbackGenerator.lightVibration()  // ✅ AJOUTÉ
                            openSettings()
                        }) {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                Text("Paramètres notifications")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ℹ️ Informations")
                            .font(.headline)
                        
                        Text("• Une notification par jour")
                        Text("• Heure aléatoire: 10h, 12h, 14h, 16h, 18h ou 20h")
                        Text("• Messages variés (pas de répétition)")
                        Text("• Messages spéciaux prioritaires à 12h")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(colorScheme == .dark ? Color.orange.opacity(0.15) : Color.orange.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        UIImpactFeedbackGenerator.lightVibration()  // ✅ AJOUTÉ
                        dismiss()
                    }
                }
            }
            .onAppear {
                Task {
                    await checkAuthorizationStatus()
                    await refreshNotificationInfo()
                }
            }
        }
    }
    
    private func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        DispatchQueue.main.async {
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }
    
    private func refreshNotificationInfo() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        
        DispatchQueue.main.async {
            if let firstRequest = requests.first {
                if let trigger = firstRequest.trigger as? UNCalendarNotificationTrigger,
                   let hour = trigger.dateComponents.hour {
                    scheduledTime = "\(hour)h00"
                } else {
                    scheduledTime = "Heure non disponible"
                }
                lastMessage = firstRequest.content.body
                notificationStatus = "✅ Programmée"
            } else {
                scheduledTime = "Aucune"
                lastMessage = "Aucun"
                notificationStatus = "❌ Aucune notification programmée"
            }
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
// MARK: - ✅ AJOUTÉ - LegalDisclaimerView
struct LegalDisclaimerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let isFirstLaunch: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("AVERTISSEMENT LÉGAL")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    Divider()
                    
                    Group {
                        DisclaimerSection(
                            title: "Application non officielle – Accès via WebView",
                            content: "Cette application constitue un client non officiel permettant d'accéder au site OpenFront.io au moyen d'une WebView intégrée.\n\nElle n'est ni développée, ni maintenue, ni sponsorisée, ni approuvée par les créateurs, développeurs ou ayants droit du site OpenFront.io."
                        )
                        
                        DisclaimerSection(
                            title: "Propriété intellectuelle",
                            content: "Le site OpenFront.io, incluant notamment son nom, son contenu, son interface, ses fonctionnalités et ses éléments graphiques, est la propriété exclusive de ses auteurs et ayants droit respectifs.\n\nCette application :\n• ne revendique aucun droit de propriété sur le contenu affiché,\n• n'altère pas le contenu du site,\n• agit uniquement comme un moyen technique d'accès.\n\nTous les droits relatifs au site OpenFront.io demeurent réservés à leurs propriétaires."
                        )
                        
                        DisclaimerSection(
                            title: "Licence open-source",
                            content: "Le site OpenFront.io est distribué sous la licence GNU Affero General Public License v3 (AGPL-3.0).\n\nLe code source du client utilisé par cette application est rendu public conformément aux exigences de cette licence."
                        )
                        
                        DisclaimerSection(
                            title: "Achats intégrés et publicités",
                            content: "Les achats intégrés proposés sur le site OpenFront.io (notamment ceux présentés comme permettant de supprimer des publicités) sont :\n• gérés exclusivement par le site OpenFront.io,\n• indépendants de cette application.\n\nCes achats n'ont aucun effet sur les publicités affichées dans cette application.\n\nLes publicités présentes dans l'application :\n• sont indépendantes de celles éventuellement affichées sur le site OpenFront.io,\n• ne sont ni gérées ni contrôlées par les ayants droit du site OpenFront.io.\n\nEn utilisant cette application, l'utilisateur reconnaît expressément qu'un achat effectué sur le site OpenFront.io ne supprime pas les publicités affichées dans cette application."
                        )
                        
                        DisclaimerSection(
                            title: "Limitation de responsabilité",
                            content: "Le développeur de cette application :\n• n'est pas responsable du contenu affiché via le site OpenFront.io,\n• n'est pas responsable du fonctionnement, de la disponibilité ou des services proposés par le site,\n• n'est pas responsable des achats, paiements ou engagements effectués sur le site OpenFront.io.\n\nL'application agit uniquement comme un outil d'accès technique au site."
                        )
                        
                        DisclaimerSection(
                            title: "Acceptation",
                            content: "L'utilisation de cette application implique l'acceptation pleine et entière du présent avertissement, ainsi que des conditions d'utilisation propres au site OpenFront.io."
                        )
                    }
                    .padding(.horizontal)
                    
                    if isFirstLaunch {
                        Button(action: {
                            UIImpactFeedbackGenerator.mediumVibration()
                            DisclaimerManager.shared.markDisclaimerAsRead()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("J'ai lu et j'accepte")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .font(.headline)
                        }
                        .padding()
                    }
                    
                    Spacer()
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Disclaimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstLaunch {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Fermer") {
                            UIImpactFeedbackGenerator.lightVibration()
                            dismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isFirstLaunch)
    }
}

struct DisclaimerSection: View {
    let title: String
    let content: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
// MARK: - SettingsView (✅ MODIFIÉ - Ajout disclaimer légal)
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showLegalDisclaimer = false  // ✅ AJOUTÉ
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Réglages")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 20)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Informations")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 0) {
                            SettingRow(title: "Version", value: "2.4")
                            
                            Divider()
                                .padding(.leading, 16)
                        }
                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // ✅ AJOUTÉ - Section Légal
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Légal")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Button(action: {
                            UIImpactFeedbackGenerator.lightVibration()
                            showLegalDisclaimer = true
                        }) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.orange)
                                Text("Avertissement légal")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Informations importantes")
                                .font(.headline)
                        }
                        
                        Text("Cette application n'est pas l'application officielle d'OpenFront.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("Il s'agit d'une application tierce développée par des fans pour faciliter l'accès au jeu.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color.orange.opacity(0.15) : Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Rejoignez la communauté")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            Button(action: {
                                UIImpactFeedbackGenerator.lightVibration()
                                if let url = URL(string: "https://www.youtube.com/@Lynxculture") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundColor(.red)
                                    Text("Abonnez-vous à notre chaîne YouTube")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(10)
                            }
                            
                            Button(action: {
                                UIImpactFeedbackGenerator.lightVibration()
                                if let url = URL(string: "https://discord.gg/S4jRCM8j95") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "message.fill")
                                        .foregroundColor(Color(red: 0.5, green: 0.0, blue: 0.8))
                                    Text("Rejoignez notre Discord")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        UIImpactFeedbackGenerator.lightVibration()
                        dismiss()
                    }
                }
            }
            // ✅ AJOUTÉ - Sheet pour afficher le disclaimer
            .sheet(isPresented: $showLegalDisclaimer) {
                LegalDisclaimerView(isFirstLaunch: false)
            }
        }
    }
}

struct SettingRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding()
    }
}
// MARK: - WebViewManager (✅ MODIFIÉ - Gestion de persistance améliorée)
class WebViewManager: ObservableObject {
    @Published var isLoading = true
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var clickCount: Int = 0
    @Published var interactionCount: Int = 0
    
    var webView: WKWebView?
    weak var appManager: AppManager?
    
    func activate() {
        webView?.isUserInteractionEnabled = true
    }
    
    // ✅ MODIFIÉ - Ne recharge QUE si c'est une nouvelle session ou un changement d'URL
    func loadURL(urlString: String) {
        guard let webView = webView else { return }
        
        // Si on a déjà une URL chargée et que c'est la même, ne rien faire
        if let currentURL = webView.url?.absoluteString,
           currentURL == urlString || currentURL.contains(urlString) {
            print("🔄 URL déjà chargée, pas de rechargement: \(currentURL)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        // Sinon, charger la nouvelle URL
        if let url = URL(string: urlString) {
            print("🌐 Chargement de l'URL: \(urlString)")
            DispatchQueue.main.async {
                self.isLoading = true
            }
            webView.load(URLRequest(url: url))
        }
    }
    
    func saveCurrentState() {
        guard let webView = webView else { return }
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        print("💾 État sauvegardé: \(currentURL?.absoluteString ?? "nil")")
    }
    
    func notifyWebViewLoaded() {
        appManager?.isWebViewLoaded = true
        appManager?.requestConsentAndInitializeAds()
    }
    
    func incrementClick() {
        clickCount += 1
        print("🖱️ Clic détecté - Total: \(clickCount)")
    }
    
    func incrementInteraction() {
        interactionCount += 1
        print("👆 Interaction détectée - Total: \(interactionCount)")
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
}

// MARK: - ContentView (✅ MODIFIÉ - Gestion de la persistance)
struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var appManager = AppManager()
    @StateObject private var interstitial = InterstitialAdManager()
    @StateObject private var webViewManager = WebViewManager()
    @State private var availableWidth: CGFloat = 320
    @State private var showWebView: Bool = false
    @State private var showNotificationSettings: Bool = false
    @State private var showSettings: Bool = false
    @State private var showBackConfirmation: Bool = false
    @State private var isAnimating: Bool = false
    @State private var playButtonClickCount: Int = 0
    @State private var isBetaMode: Bool = false
    @State private var currentURLString: String = "https://openfront.io"  // ✅ AJOUTÉ - Mémoriser l'URL
    @State private var showLegalDisclaimer: Bool = false  // ✅ AJOUTÉ ICI
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()
            
            if !showWebView {
                Image("ar")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(0.6)
            }
            
            // ✅ MODIFIÉ - La WebView est TOUJOURS présente en mémoire
            OpenFrontWebView(manager: webViewManager, isBeta: isBetaMode)
                .frame(maxWidth: showWebView ? .infinity : 0,
                       maxHeight: showWebView ? .infinity : 0)
                .opacity(showWebView ? 1 : 0)
                .padding(.bottom, appManager.isAdSystemReady && showWebView ? 80 : 20)
                .ignoresSafeArea()
            
            if showWebView {
                VStack {
                    HStack {
                        Button(action: {
                            UIImpactFeedbackGenerator.lightVibration()
                            showNotificationSettings = true
                        }) {
                            Image(systemName: "bell.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                                .padding()
                        }
                        
                        Spacer()
                        
                        if isBetaMode {
                            Text("BETA")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            UIImpactFeedbackGenerator.mediumVibration()
                            showBackConfirmation = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(12)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 40)
            }
            
            if !showWebView {
                VStack(spacing: 0) {
                    Spacer()
                    
                    ZStack {
                        Text("OpenFront")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.7), .blue.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .blur(radius: 20)
                        
                        Text("OpenFront")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .cyan, .blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .cyan.opacity(0.9), radius: 12, x: 0, y: 0)
                            .shadow(color: .blue.opacity(0.7), radius: 20, x: 0, y: 0)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.4),
                                        .cyan.opacity(0.6),
                                        .white.opacity(0.4),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(30))
                            .offset(x: isAnimating ? 250 : -250)
                            .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: isAnimating)
                            .blendMode(.plusLighter)
                            .mask(
                                Text("OpenFront")
                                    .font(.system(size: 64, weight: .bold, design: .rounded))
                            )
                    }
                    .onAppear {
                        isAnimating = true
                    }
                    .padding(.bottom, 40)
                    
                    VStack(spacing: 16) {
                        Button(action: {
                            launchGame(isBeta: false)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                Text("Jouer")
                                    .font(.system(size: 24, weight: .bold))
                            }
                            .frame(width: 240)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: .blue.opacity(0.6), radius: 10, x: 0, y: 5)
                        }
                        
                        Button(action: {
                            launchGame(isBeta: true)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "flask.fill")
                                    .font(.caption)
                                Text("Version Beta")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(width: 160)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(color: .orange.opacity(0.4), radius: 5, x: 0, y: 3)
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Button(action: {
                                    UIImpactFeedbackGenerator.lightVibration()
                                    showNotificationSettings = true
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "bell.badge.fill")
                                            .font(.title3)
                                        Text("Notifs")
                                            .font(.system(size: 12))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(width: 110, height: 85)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.orange.opacity(0.6)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                Button(action: {
                                    UIImpactFeedbackGenerator.lightVibration()
                                    showSettings = true
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "gearshape.fill")
                                            .font(.title3)
                                        Text("Réglages")
                                            .font(.system(size: 12))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(width: 110, height: 85)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.gray.opacity(0.8), Color.gray.opacity(0.6)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                            
                            HStack(spacing: 10) {
                                Button(action: {
                                    UIImpactFeedbackGenerator.lightVibration()
                                    if let url = URL(string: "https://discord.gg/S4jRCM8j95") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "message.fill")
                                            .font(.title3)
                                        Text("Discord")
                                            .font(.system(size: 12))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(width: 110, height: 85)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color(red: 0.5, green: 0.0, blue: 0.8), Color(red: 0.4, green: 0.0, blue: 0.6)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                Button(action: {
                                    UIImpactFeedbackGenerator.lightVibration()
                                    if let url = URL(string: "https://www.youtube.com/@Lynxculture") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.title3)
                                        Text("YouTube")
                                            .font(.system(size: 12))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(width: 110, height: 85)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if appManager.isAdSystemReady {
                GeometryReader { geo in
                    BannerAdView(width: geo.size.width)
                        .frame(width: geo.size.width, height: 50, alignment: .center)
                        .background(.ultraThinMaterial)
                        .overlay(Divider(), alignment: .top)
                        .ignoresSafeArea(edges: .bottom)
                        .onAppear { availableWidth = geo.size.width }
                        .onChange(of: geo.size.width) { availableWidth = $0 }
                }
                .frame(height: 50, alignment: .bottom)
            }
        }
        .onAppear {
            webViewManager.appManager = appManager
            AppReviewManager.shared.checkAndRequestReview()
            UIApplication.shared.applicationIconBadgeNumber = 0
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            
            // ✅ AJOUTÉ - Vérifier si c'est le premier lancement
            if !DisclaimerManager.shared.hasReadDisclaimer() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showLegalDisclaimer = true
                }
            }
        
        }
        .onChange(of: appManager.isAdSystemReady) { isReady in
            if isReady {
                interstitial.load()
            }
        }
        .alert("Erreur de consentement", isPresented: $appManager.showConsentError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appManager.consentErrorMessage)
        }
        .alert("Voulez-vous revenir à l'accueil ?", isPresented: $showBackConfirmation) {
            Button("Annuler", role: .cancel) {
                UIImpactFeedbackGenerator.lightVibration()
            }
            Button("Confirmer", role: .destructive) {
                UIImpactFeedbackGenerator.mediumVibration()
                // ✅ MODIFIÉ - Sauvegarder l'état mais ne PAS détruire la WebView
                webViewManager.saveCurrentState()
                withAnimation {
                    showWebView = false
                    // Ne pas réinitialiser isBetaMode pour garder le mode actif
                }
            }
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // ✅ AJOUTÉ - Sheet pour le disclaimer au premier lancement
        .sheet(isPresented: $showLegalDisclaimer) {
            LegalDisclaimerView(isFirstLaunch: !DisclaimerManager.shared.hasReadDisclaimer())
        }
    }
    
    // ✅ FONCTION MODIFIÉE - Ne recharge pas si déjà sur la bonne URL
    private func launchGame(isBeta: Bool) {
        UIImpactFeedbackGenerator.mediumVibration()
        
        playButtonClickCount += 1
        let newURLString = isBeta ? "https://main.openfront.dev" : "https://openfront.io"
        
        // ✅ Afficher la WebView
        withAnimation {
            showWebView = true
            isBetaMode = isBeta
        }
        
        // ✅ Ne charger l'URL que si c'est différent ou première fois
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webViewManager.activate()
            webViewManager.loadURL(urlString: newURLString)
            currentURLString = newURLString
        }
        
        // Pub tous les 2 clics
        if playButtonClickCount % 2 == 0 && appManager.isAdSystemReady {
            print("🎯 2ème clic - Affichage pub interstitielle")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                interstitial.present()
            }
        }
    }
}


// MARK: - OpenFrontWebView (✅ MODIFIÉ - Support persistance)
struct OpenFrontWebView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var manager: WebViewManager
    let isBeta: Bool
    
    var body: some View {
        ZStack {
            // ✅ La WebView n'est créée qu'UNE SEULE FOIS
            PersistentWebView(
                urlString: isBeta ? "https://main.openfront.dev" : "https://openfront.io",
                manager: manager
            )
            
            if manager.isLoading {
                Color(colorScheme == .dark ? .black : .white)
                    .opacity(0.9)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(colorScheme == .dark ? .white : .blue)
                    
                    if isBeta {
                        Text("Chargement de la version Beta...")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.headline)
                        
                        Text("⚠️ Fonctionnalités expérimentales")
                            .foregroundColor(.orange)
                            .font(.caption)
                    } else {
                        Text("OpenFront charge en moyenne en 10s")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.headline)
                        
                        Text("OpenFront loads on average in 10s")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - PersistentWebView (✅ MODIFIÉ - Vraie persistance)
struct PersistentWebView: UIViewRepresentable {
    let urlString: String
    @ObservedObject var manager: WebViewManager
    
    // ✅ WebView partagée statique pour garantir la persistance
    private static var sharedWebView: WKWebView?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        print("🔧 makeUIView appelé")
        
        // ✅ Si la WebView existe déjà, la réutiliser
        if let existingWebView = PersistentWebView.sharedWebView {
            print("♻️ Réutilisation de la WebView existante")
            manager.webView = existingWebView
            return existingWebView
        }
        
        // ✅ Sinon, créer une nouvelle WebView
        WebViewConfigurationManager.shared.configureUserScriptsOnce(coordinator: context.coordinator)
        
        let config = WebViewConfigurationManager.shared.configuration
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.isUserInteractionEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        // ✅ Sauvegarder la WebView pour la réutiliser
        PersistentWebView.sharedWebView = webView
        manager.webView = webView
        
        // ✅ Charger l'URL seulement si aucune URL n'est déjà chargée
        if webView.url == nil, let url = URL(string: urlString) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            webView.load(request)
            print("🌐 WebView créée et URL initiale chargée")
        } else {
            print("⚠️ WebView recyclée avec session existante")
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // ✅ Ne rien faire ici pour éviter les rechargements
        print("🔄 updateUIView appelé - session maintenue")
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // ✅ NE PAS détruire la WebView
        print("⚠️ dismantleUIView appelé - WebView conservée en mémoire")
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let manager: WebViewManager
        
        init(manager: WebViewManager) {
            self.manager = manager
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "clickHandler" {
                DispatchQueue.main.async {
                    self.manager.incrementClick()
                }
            } else if message.name == "interactionHandler" {
                DispatchQueue.main.async {
                    self.manager.incrementInteraction()
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ WebView chargée: \(webView.url?.absoluteString ?? "unknown")")
            DispatchQueue.main.async {
                self.manager.isLoading = false
                self.manager.currentURL = webView.url
                self.manager.canGoBack = webView.canGoBack
                self.manager.canGoForward = webView.canGoForward
                self.manager.notifyWebViewLoaded()
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Erreur de chargement: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.manager.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ Erreur provisoire: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.manager.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            print("🔄 Navigation vers: \(urlString)")
            
            if url.scheme != "http" && url.scheme != "https" && url.scheme != "about" {
                print("📱 Scheme spécial détecté: \(url.scheme ?? "unknown"), ouverture externe")
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            
            print("✅ Navigation autorisée dans la WebView")
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                print("🪟 target='_blank' détecté, chargement dans la WebView actuelle: \(url.absoluteString)")
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
#Preview {
    ContentView()
}

