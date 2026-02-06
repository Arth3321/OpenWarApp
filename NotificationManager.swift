//
//  NotificationManager.swift
//  OpenWar
//
//  Created by famille IGLESIAS on 25/01/2026.
//

import Foundation
import UserNotifications
import BackgroundTasks
import UIKit

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    // MARK: - Configuration
    private let specialMessageURL = "https://Helloword.com"
    private let notificationTimes = [10, 12, 14, 16, 18, 20] // Heures possibles
    private let backgroundTaskIdentifier = "exemple.OpenWar"
    
    // MARK: - Messages Pool (30+)
    private let messages = [
        "Aujourd'hui, le front peut basculer ⚔️",
        "Chaque décision compte sur le champ de bataille 🧠",
        "Vos territoires ne se défendent pas seuls 🛡️",
        "Un bon stratège anticipe toujours le prochain coup ♟️",
        "Le moment est peut-être venu d'attaquer 🚀",
        "La défense gagne des guerres autant que l'attaque 🏰",
        "Un front oublié est un front perdu 🌍",
        "Vos adversaires n'attendent pas ⏳",
        "Consolidez vos positions avant qu'il ne soit trop tard 🔧",
        "La victoire appartient aux plus constants 🏆",
        "Une petite avancée peut changer toute la guerre 📈",
        "Les ressources bien gérées font la différence 💰",
        "Chaque partie écrit une nouvelle histoire 📜",
        "Observez avant d'agir 👀",
        "Le calme précède souvent l'offensive 🌫️",
        "Un bon timing vaut mieux qu'une grande armée ⏱️",
        "Vos alliances peuvent tout changer 🤝",
        "Un territoire de plus, un pas vers la domination 🌐",
        "La carte évolue, adaptez-vous 🗺️",
        "Les erreurs d'hier sont les leçons d'aujourd'hui 📚",
        "La patience est une arme sous-estimée 🧩",
        "Un ennemi affaibli reste dangereux ⚠️",
        "Votre stratégie mérite d'être affinée 🛠️",
        "Les fronts actifs attirent les opportunités 🔥",
        "Chaque action influence l'équilibre global ⚖️",
        "Ne laissez pas le hasard décider pour vous 🎲",
        "Un bon plan maintenant évite une défaite plus tard 🧱",
        "Votre empire ne se construira pas tout seul 👑",
        "Analysez la situation avant le prochain mouvement 📊",
        "Une guerre se gagne aussi avec la tête 🧠",
        "Le monde est instable, profitez-en 🌍",
        "Votre progression dépend de vos choix, pas de la chance ⭐"
    ]
    
    // MARK: - UserDefaults Keys
    private let lastMessageIndexKey = "lastMessageIndex"
    private let lastNotificationDateKey = "lastNotificationDate"
    private let scheduledTimeKey = "scheduledNotificationTime"
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    func setup() {
        requestAuthorization()
        registerBackgroundTasks()
        scheduleBackgroundRefresh()
    }
    
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notifications autorisées")
                Task { await self.scheduleNextNotification() }
            } else if let error = error {
                print("❌ Erreur autorisation: \(error)")
            }
        }
    }
    
    // MARK: - Badge Management (✅ AJOUTÉ)
    func clearBadge() {
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
            UNUserNotificationCenter.current().setBadgeCount(0)
            print("🧹 Badge supprimé")
        }
    }
    
    // MARK: - Background Tasks
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        
        // Exécution quotidienne à 00:01
        var dateComponents = DateComponents()
        dateComponents.hour = 0
        dateComponents.minute = 1
        
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
            let nextRun = Calendar.current.date(bySettingHour: 0, minute: 1, second: 0, of: tomorrow)
            request.earliestBeginDate = nextRun
        }
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background task programmée")
        } catch {
            print("❌ Erreur scheduling background task: \(error)")
        }
    }
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Programme la prochaine exécution
        scheduleBackgroundRefresh()
        
        // Nettoie les anciennes notifications
        clearPendingNotifications()
        
        // Vérifie et planifie la notification du jour
        Task {
            await scheduleNextNotification()
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Main Scheduling Logic
    func scheduleNextNotification() async {
        // Vérifie si une notification a déjà été programmée aujourd'hui
        if isNotificationScheduledForToday() {
            print("ℹ️ Notification déjà programmée pour aujourd'hui")
            return
        }
        
        // 1. Vérifie d'abord s'il y a un message spécial
        if let specialNotification = await checkSpecialMessage() {
            scheduleSpecialNotification(specialNotification)
            markNotificationAsScheduledToday()
            return
        }
        
        // 2. Sinon, programme une notification aléatoire
        scheduleRandomNotification()
        markNotificationAsScheduledToday()
    }
    
    // MARK: - Special Message Check
    private func checkSpecialMessage() async -> SpecialNotification? {
        guard let url = URL(string: specialMessageURL) else {
            print("❌ URL invalide")
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            let lines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            guard lines.count >= 2 else {
                print("ℹ️ Pas de message spécial disponible")
                return nil
            }
            
            let message = lines[0]
            let dateString = lines[1]
            
            // Parse la date (format JJ/MM/AAAA)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy"
            dateFormatter.timeZone = TimeZone.current
            
            guard let targetDate = dateFormatter.date(from: dateString) else {
                print("❌ Format de date invalide: \(dateString)")
                return nil
            }
            
            // Vérifie si c'est aujourd'hui
            let today = Calendar.current.startOfDay(for: Date())
            let target = Calendar.current.startOfDay(for: targetDate)
            
            if today == target {
                print("✅ Message spécial trouvé pour aujourd'hui")
                return SpecialNotification(message: message, time: 12)
            } else {
                print("ℹ️ Message spécial trouvé mais pour une autre date: \(dateString)")
                return nil
            }
            
        } catch {
            print("❌ Erreur lors de la récupération du message spécial: \(error)")
            return nil
        }
    }
    
    // MARK: - Schedule Special Notification
    private func scheduleSpecialNotification(_ special: SpecialNotification) {
        let content = UNMutableNotificationContent()
        content.title = "Message Spécial"
        content.body = special.message
        content.sound = .default
        content.badge = 1
        
        var dateComponents = DateComponents()
        dateComponents.hour = special.time
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "special-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Erreur programmation notification spéciale: \(error)")
            } else {
                print("✅ Notification spéciale programmée à \(special.time)h")
            }
        }
    }
    
    // MARK: - Schedule Random Notification
    private func scheduleRandomNotification() {
        // Choix aléatoire de l'heure
        let randomHour = notificationTimes.randomElement() ?? 12
        
        // Choix du message (évite répétition)
        let messageIndex = getRandomMessageIndex()
        let message = messages[messageIndex]
        
        // Sauvegarde pour éviter répétition
        UserDefaults.standard.set(messageIndex, forKey: lastMessageIndexKey)
        UserDefaults.standard.set(randomHour, forKey: scheduledTimeKey)
        
        // Création de la notification
        let content = UNMutableNotificationContent()
        content.title = "Rappel du jour"
        content.body = message
        content.sound = .default
        content.badge = 1
        
        var dateComponents = DateComponents()
        dateComponents.hour = randomHour
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "daily-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Erreur programmation notification: \(error)")
            } else {
                print("✅ Notification programmée à \(randomHour)h: \(message)")
            }
        }
    }
    
    // MARK: - Helper Methods
    private func getRandomMessageIndex() -> Int {
        let lastIndex = UserDefaults.standard.integer(forKey: lastMessageIndexKey)
        var newIndex: Int
        
        // Évite la répétition si possible
        if messages.count > 1 {
            repeat {
                newIndex = Int.random(in: 0..<messages.count)
            } while newIndex == lastIndex
        } else {
            newIndex = 0
        }
        
        return newIndex
    }
    
    private func isNotificationScheduledForToday() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: lastNotificationDateKey) as? Date else {
            return false
        }
        
        let calendar = Calendar.current
        return calendar.isDateInToday(lastDate)
    }
    
    private func markNotificationAsScheduledToday() {
        UserDefaults.standard.set(Date(), forKey: lastNotificationDateKey)
    }
    
    private func clearPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("🧹 Notifications en attente nettoyées")
    }
    
    // MARK: - Manual Trigger (pour tests)
    func triggerManualRefresh() {
        Task {
            clearPendingNotifications()
            UserDefaults.standard.removeObject(forKey: lastNotificationDateKey)
            await scheduleNextNotification()
        }
    }
}

// MARK: - Models
struct SpecialNotification {
    let message: String
    let time: Int // Heure (0-23)
}
