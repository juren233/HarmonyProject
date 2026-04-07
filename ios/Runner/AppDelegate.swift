import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IosNativeDockPlugin") {
      IosNativeDockPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PetNoteNotificationPlugin") {
      PetNoteNotificationPlugin.register(with: registrar)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    PetNoteNotificationPlugin.shared?.updatePushToken(deviceToken)
  }
}

private enum IosNativeDockTab: Int, CaseIterable {
  case checklist
  case overview
  case pets
  case me

  var channelName: String {
    switch self {
    case .checklist:
      return "checklist"
    case .overview:
      return "overview"
    case .pets:
      return "pets"
    case .me:
      return "me"
    }
  }

  var title: String {
    switch self {
    case .checklist:
      return "清单"
    case .overview:
      return "总览"
    case .pets:
      return "爱宠"
    case .me:
      return "我的"
    }
  }

  var iconName: String {
    switch self {
    case .checklist:
      return "checklist"
    case .overview:
      return "sparkles"
    case .pets:
      return "pawprint.fill"
    case .me:
      return "person.fill"
    }
  }
}

final class PetNoteNotificationPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  static let channelName = "petnote/notifications"
  static var shared: PetNoteNotificationPlugin?

  private let channel: FlutterMethodChannel
  private var initialLaunchIntent: [String: Any]?
  private var pendingForegroundTap: [String: Any]?
  private var pushToken: String?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PetNoteNotificationPlugin(channel: channel)
    shared = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(nil)
    case "getPermissionState":
      getPermissionState(result: result)
    case "requestPermission":
      requestPermission(result: result)
    case "scheduleLocalNotification":
      scheduleLocalNotification(arguments: call.arguments as? [String: Any], result: result)
    case "cancelNotification":
      cancelNotification(key: call.arguments as? String)
      result(nil)
    case "getInitialLaunchIntent":
      result(initialLaunchIntent)
      initialLaunchIntent = nil
    case "consumeForegroundTap":
      result(pendingForegroundTap)
      pendingForegroundTap = nil
    case "registerPushToken":
      UIApplication.shared.registerForRemoteNotifications()
      result(pushToken)
    case "openNotificationSettings":
      openSettings(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func updatePushToken(_ deviceToken: Data) {
    pushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
  }

  private func getPermissionState(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        result(self.permissionLabel(from: settings.authorizationStatus))
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      DispatchQueue.main.async {
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(granted ? "authorized" : "denied")
      }
    }
  }

  private func scheduleLocalNotification(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard
      let arguments,
      let key = arguments["key"] as? String,
      let epochMillis = arguments["scheduledAtEpochMs"] as? NSNumber,
      let payload = arguments["payload"] as? [String: Any]
    else {
      result(nil)
      return
    }

    let content = UNMutableNotificationContent()
    content.title = arguments["title"] as? String ?? "宠记提醒"
    content.body = arguments["body"] as? String ?? ""
    content.sound = .default
    content.userInfo = payload

    let scheduledAt = Date(timeIntervalSince1970: epochMillis.doubleValue / 1000.0)
    let triggerDate = max(Date().addingTimeInterval(1), scheduledAt)
    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: triggerDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    let request = UNNotificationRequest(identifier: key, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        result(error == nil ? nil : FlutterError(code: "schedule_failed", message: error?.localizedDescription, details: nil))
      }
    }
  }

  private func cancelNotification(key: String?) {
    guard let key else {
      return
    }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [key])
    center.removeDeliveredNotifications(withIdentifiers: [key])
  }

  private func openSettings(result: @escaping FlutterResult) {
    let urlString: String
    if #available(iOS 16.0, *) {
      urlString = UIApplication.openNotificationSettingsURLString
    } else if #available(iOS 15.4, *) {
      urlString = UIApplicationOpenNotificationSettingsURLString
    } else {
      urlString = UIApplication.openSettingsURLString
    }

    guard let url = URL(string: urlString) else {
      result("failed")
      return
    }
    UIApplication.shared.open(url, options: [:], completionHandler: { opened in
      DispatchQueue.main.async {
        result(opened ? "opened" : "failed")
      }
    })
  }

  private func permissionLabel(from status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .provisional, .ephemeral:
      return "provisional"
    case .denied:
      return "denied"
    case .notDetermined:
      return "unknown"
    @unknown default:
      return "unknown"
    }
  }

  private func intentMap(
    userInfo: [AnyHashable: Any],
    fromForeground: Bool
  ) -> [String: Any] {
    return [
      "payload": [
        "sourceType": userInfo["sourceType"] as? String ?? "todo",
        "sourceId": userInfo["sourceId"] as? String ?? "",
        "petId": userInfo["petId"] as? String ?? "",
        "routeTarget": userInfo["routeTarget"] as? String ?? "checklist",
      ],
      "fromForeground": fromForeground,
    ]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = intentMap(
      userInfo: response.notification.request.content.userInfo,
      fromForeground: UIApplication.shared.applicationState == .active
    )
    if UIApplication.shared.applicationState == .active {
      pendingForegroundTap = payload
    } else {
      initialLaunchIntent = payload
    }
    completionHandler()
  }
}

final class IosNativeDockPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = IosNativeDockViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "petnote/ios_native_dock")
  }
}

final class IosNativeDockViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    IosNativeDockPlatformView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any],
      messenger: messenger
    )
  }
}

final class IosNativeDockPlatformView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  private let rootView = UIView()
  private let tabBarController = UITabBarController()
  private let channel: FlutterMethodChannel
  private var controllersByTab: [IosNativeDockTab: UIViewController] = [:]
  private var addPlaceholderController: UIViewController?
  private var isSyncingSelection = false
  private let interfaceStyle: UIUserInterfaceStyle
  private let centerSymbolSize: CGFloat
  private let centerSymbolCanvasOffset: CGFloat

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any]?,
    messenger: FlutterBinaryMessenger
  ) {
    let brightness = (args?["brightness"] as? String) ?? "light"
    centerSymbolSize = CGFloat((args?["centerSymbolSize"] as? Double) ?? 42)
    centerSymbolCanvasOffset = CGFloat((args?["centerSymbolCanvasOffset"] as? Double) ?? 8)
    interfaceStyle = brightness == "dark" ? .dark : .light
    channel = FlutterMethodChannel(
      name: "petnote/ios_native_dock_\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    configureRootView()
    configureTabBarController()
    configureChannel()

    if let selectedTab = args?["selectedTab"] as? String {
      setSelectedTab(named: selectedTab)
    } else {
      setSelectedTab(named: IosNativeDockTab.checklist.channelName)
    }
  }

  func view() -> UIView {
    rootView
  }

  private func configureRootView() {
    rootView.backgroundColor = .clear
    rootView.isOpaque = false
    let controllerView = tabBarController.view!
    controllerView.translatesAutoresizingMaskIntoConstraints = false
    controllerView.backgroundColor = .clear
    controllerView.isOpaque = false
    controllerView.clipsToBounds = false

    rootView.addSubview(controllerView)

    NSLayoutConstraint.activate([
      controllerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 10),
      controllerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -10),
      controllerView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
      controllerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -10),
    ])
  }

  private func configureTabBarController() {
    tabBarController.delegate = self
    tabBarController.viewControllers = makeViewControllers()
    tabBarController.selectedIndex = 0

    let tabBar = tabBarController.tabBar
    tabBar.isTranslucent = true
    tabBar.overrideUserInterfaceStyle = interfaceStyle
    tabBar.backgroundImage = nil
    tabBar.shadowImage = UIImage()

    let appearance = UITabBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.backgroundEffect = nil
    appearance.backgroundColor = UIColor.clear
    appearance.shadowColor = .clear
    configureItemAppearance(appearance.inlineLayoutAppearance)
    configureItemAppearance(appearance.stackedLayoutAppearance)
    configureItemAppearance(appearance.compactInlineLayoutAppearance)

    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }
    tabBar.backgroundColor = .clear
    tabBar.isOpaque = false
  }

  private func makeViewControllers() -> [UIViewController] {
    controllersByTab.removeAll()

    let checklist = makeTabController(for: .checklist)
    let overview = makeTabController(for: .overview)
    let placeholder = makeAddPlaceholderController()
    let pets = makeTabController(for: .pets)
    let me = makeTabController(for: .me)

    addPlaceholderController = placeholder
    return [checklist, overview, placeholder, pets, me]
  }

  private func makeTabController(for tab: IosNativeDockTab) -> UIViewController {
    let controller = UIViewController()
    controller.view.backgroundColor = .clear
    controller.tabBarItem = UITabBarItem(
      title: tab.title,
      image: UIImage(
        systemName: tab.iconName,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
      ),
      tag: tab.rawValue
    )
    controllersByTab[tab] = controller
    return controller
  }

  private func makeAddPlaceholderController() -> UIViewController {
    let controller = UIViewController()
    controller.view.backgroundColor = .clear
    let image = makeCenteredAddImage()
    let item = UITabBarItem(title: " ", image: image, tag: 999)
    item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
    controller.tabBarItem = item
    return controller
  }

  private func makeCenteredAddImage() -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: centerSymbolSize, weight: .semibold)
    guard let baseImage = UIImage(
      systemName: "plus.circle.fill",
      withConfiguration: configuration
    )?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) else {
      return nil
    }

    let horizontalPadding: CGFloat = 12
    let verticalPadding: CGFloat = 12
    let canvasSize = CGSize(
      width: max(44, baseImage.size.width + horizontalPadding),
      height: max(
        44,
        baseImage.size.height + verticalPadding + abs(centerSymbolCanvasOffset) * 2
      )
    )
    let renderer = UIGraphicsImageRenderer(size: canvasSize)

    return renderer.image { _ in
      let origin = CGPoint(
        x: (canvasSize.width - baseImage.size.width) / 2,
        y: (canvasSize.height - baseImage.size.height) / 2 + centerSymbolCanvasOffset
      )
      baseImage.draw(in: CGRect(origin: origin, size: baseImage.size))
    }.withRenderingMode(.alwaysOriginal)
  }

  private func configureItemAppearance(_ itemAppearance: UITabBarItemAppearance) {
    itemAppearance.selected.iconColor = .systemOrange
    itemAppearance.selected.titleTextAttributes = [
      .foregroundColor: UIColor.systemOrange,
      .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
    ]
    itemAppearance.normal.iconColor = UIColor.secondaryLabel
    itemAppearance.normal.titleTextAttributes = [
      .foregroundColor: UIColor.secondaryLabel,
      .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
    ]
  }

  private func configureChannel() {
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "setSelectedTab":
        self.setSelectedTab(named: call.arguments as? String)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setSelectedTab(named tabName: String?) {
    guard
      let tabName,
      let selectedTab = IosNativeDockTab.allCases.first(where: { $0.channelName == tabName }),
      let controller = controllersByTab[selectedTab]
    else {
      return
    }

    isSyncingSelection = true
    tabBarController.selectedViewController = controller
    isSyncingSelection = false
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    shouldSelect viewController: UIViewController
  ) -> Bool {
    if viewController === addPlaceholderController {
      channel.invokeMethod("addTapped", arguments: nil)
      return false
    }
    return true
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    guard !isSyncingSelection else {
      return
    }
    guard let tab = controllersByTab.first(where: { $0.value === viewController })?.key else {
      return
    }
    channel.invokeMethod("tabSelected", arguments: tab.channelName)
  }
}
