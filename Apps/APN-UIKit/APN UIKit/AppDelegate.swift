import CioDataPipelines
import CioMessagingInApp
import CioMessagingPushAPN
import UIKit

@main
class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}

class AppDelegate: UIResponder, UIApplicationDelegate {
    var storage = DIGraphShared.shared.storage
    var deepLinkHandler = DIGraphShared.shared.deepLinksHandlerUtil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        initializeCioAndInAppListeners()

        /*
         Registers the `AppDelegate` class to handle when a push notification gets clicked.
         This line of code is optional and only required if you have custom code that needs to run when a push notification gets clicked on.
         Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature.
         Therefore, this line of code is not required if you only want to handle push notifications sent by Customer.io.
         */
//        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func initializeCioAndInAppListeners() {
        // Set default setting if those don't exist
        DIGraphShared.shared.settingsService.setDefaultSettings()

        // Initialize CustomerIO SDK
        guard let settings = storage.settings else {
            assertionFailure("Settings should not be nil")
            return
        }

        let config = SDKConfigBuilder(cdpApiKey: settings.dataPipelines.cdpApiKey)
            .region(settings.dataPipelines.region.toCIORegion())
            .autoTrackDeviceAttributes(settings.dataPipelines.autoTrackDeviceAttributes)
            .trackApplicationLifecycleEvents(settings.dataPipelines.trackApplicationLifecycleEvents)
            .screenViewUse(screenView: settings.dataPipelines.screenViewUse.toCIOScreenViewUse())
            .logLevel(settings.dataPipelines.logLevel.toCIOLogLevel())
            .migrationSiteId(settings.dataPipelines.siteId)

        if settings.dataPipelines.autoTrackUIKitScreenViews {
            config.autoTrackUIKitScreenViews()
        }
        if case let apiHost = settings.internalSettings.apiHost, !apiHost.isEmpty {
            config.apiHost(apiHost)
        }
        if case let cdnHost = settings.internalSettings.cdnHost, !cdnHost.isEmpty {
            config.cdnHost(cdnHost)
        }
        if settings.internalSettings.testMode {
            config.flushAt(1)
        }
        CustomerIO.initialize(withConfig: config.build())

        // Initialize messaging features after initializing Customer.io SDK
        MessagingPushAPN.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoFetchDeviceToken(settings.messaging.autoFetchDeviceToken)
                .autoTrackPushEvents(settings.messaging.autoTrackPushEvents)
                .showPushAppInForeground(settings.messaging.showPushAppInForeground)
                .build()
        )
        MessagingInApp
            .initialize(withConfig: MessagingInAppConfigBuilder(
                siteId: settings.inApp.siteId,
                region: settings.inApp.region.toCIORegion()
            ).build())
            .setEventListener(self)
    }

    // Handle Universal Link deep link from the Customer.io SDK. This function will get called if a push notification
    // gets clicked that has a Universal Link deep link attached and the app is in the foreground. Otherwise, another function
    // in your app may get called depending on what technology you use (Scenes, UIKit, Swift UI).
    //
    // Learn more: https://customer.io/docs/sdk/ios/push/#universal-links-deep-links
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let universalLinkUrl = userActivity.webpageURL else {
            return false
        }

        return deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

/*
 The lines of code below are optional and only required if you:
 - want fine-grained control over whether notifications are shown in the foreground
 - have custom code that needs to run when a push notification gets clicked on.
 Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature.
 Therefore, lines of code below are not required if you only want to handle push notifications sent by Customer.io.
 */
// extension AppDelegate: UNUserNotificationCenterDelegate {
//    // Function called when a push notification is clicked or swiped away.
//    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
//        // Track custom event with Customer.io.
//        // NOT required for basic PN tap tracking - that is done automatically with `CioAppDelegateWrapper`.
//        CustomerIO.shared.track(
//            name: "custom push-clicked event",
//            properties: ["push": response.notification.request.content.userInfo]
//        )
//
//        completionHandler()
//    }
//
//    // To test sending of local notifications, display the push while app in foreground. So when you press the button to display local push in the app, you are able to see it and click on it.
//    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
//        completionHandler([.banner, .badge, .sound])
//    }
// }

// In-app event listeners to handle user's response to in-app messages.
// Registering event listeners is requiredf
extension AppDelegate: InAppEventListener {
    // Message is sent and shown to the user
    func messageShown(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp shown",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // User taps X (close) button and in-app message is dismissed
    func messageDismissed(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp dismissed",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // In-app message produces an error - preventing message from appearing to the user
    func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // User perform an action on in-app message
    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        if actionName == "remove" || actionName == "test" {
            MessagingInApp.shared.dismissMessage()
        }
        CustomerIO.shared.track(name: "inapp action", properties: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}
