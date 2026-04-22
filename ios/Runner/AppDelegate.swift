import CoreHaptics
import Flutter
import PhotosUI
import Security
import UniformTypeIdentifiers
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PetNoteAiSecretStorePlugin") {
      PetNoteAiSecretStorePlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PetNoteDataPackageFileAccessPlugin") {
      PetNoteDataPackageFileAccessPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PetNoteNativeOptionPickerPlugin") {
      PetNoteNativeOptionPickerPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PetNoteIntroHapticsPlugin") {
      PetNoteIntroHapticsPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IosNativeOverviewRangeButtonPlugin") {
      IosNativeOverviewRangeButtonPlugin.register(with: registrar)
    }
    if #available(iOS 14.0, *),
      let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PetNoteNativePetPhotoPickerPlugin")
    {
      PetNoteNativePetPhotoPickerPlugin.register(with: registrar)
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

final class PetNoteAiSecretStorePlugin: NSObject, FlutterPlugin {
  static let channelName = "petnote/ai_secret_store"
  private static let service = "com.krustykrab.petnote.ai-secret-store"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PetNoteAiSecretStorePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let configId = arguments?["configId"] as? String
    switch call.method {
    case "isAvailable":
      result(true)
    case "readKey":
      guard let configId else {
        result(nil)
        return
      }
      result(readKey(configId: configId))
    case "writeKey":
      guard let configId, let value = arguments?["value"] as? String else {
        result(nil)
        return
      }
      result(writeKey(configId: configId, value: value) ? nil : FlutterError(
        code: "write_failed",
        message: "Failed to write AI secret to Keychain.",
        details: nil
      ))
    case "deleteKey":
      guard let configId else {
        result(nil)
        return
      }
      deleteKey(configId: configId)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func readKey(configId: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: configId,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func writeKey(configId: String, value: String) -> Bool {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: configId,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess {
      return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }
    var insertQuery = query
    insertQuery[kSecValueData as String] = data
    return SecItemAdd(insertQuery as CFDictionary, nil) == errSecSuccess
  }

  private func deleteKey(configId: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: configId,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

final class PetNoteDataPackageFileAccessPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate, UINavigationControllerDelegate {
  static let channelName = "petnote/data_package_file_access"

  private enum OperationKind {
    case pickBackup
    case saveBackup
  }

  private struct PendingOperation {
    let kind: OperationKind
    let rawJson: String?
    let tempURL: URL?
  }

  private var pendingResult: FlutterResult?
  private var pendingOperation: PendingOperation?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PetNoteDataPackageFileAccessPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(Self.errorPayload(code: "invalidResponse", message: "Another file request is already running."))
      return
    }

    switch call.method {
    case "pickBackupFile":
      presentImportPicker(kind: .pickBackup, result: result)
    case "saveBackupFile":
      let arguments = call.arguments as? [String: Any]
      guard
        let suggestedFileName = arguments?["suggestedFileName"] as? String,
        let rawJson = arguments?["rawJson"] as? String
      else {
        result(Self.errorPayload(code: "invalidResponse", message: "Missing suggestedFileName or rawJson."))
        return
      }
      presentExportPicker(
        suggestedFileName: suggestedFileName,
        rawJson: rawJson,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: Self.cancelledPayload())
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else {
      finish(with: Self.errorPayload(code: "invalidResponse", message: "System file manager did not return a file URL."))
      return
    }

    guard let operation = pendingOperation else {
      finish(with: Self.errorPayload(code: "invalidResponse", message: "Missing pending file operation."))
      return
    }

    switch operation.kind {
    case .pickBackup:
      let payload = readPickedFile(from: url)
      finish(with: payload)
    case .saveBackup:
      let payload = saveResultPayload(for: url, rawJson: operation.rawJson ?? "")
      finish(with: payload)
    }
  }

  private func presentImportPicker(kind: OperationKind, result: @escaping FlutterResult) {
    let picker = UIDocumentPickerViewController(documentTypes: ["public.json"], in: .import)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingResult = result
    pendingOperation = PendingOperation(kind: kind, rawJson: nil, tempURL: nil)
    present(picker, result: result)
  }

  private func presentExportPicker(
    suggestedFileName: String,
    rawJson: String,
    result: @escaping FlutterResult
  ) {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFileName)
    do {
      try rawJson.data(using: .utf8)?.write(to: tempURL, options: .atomic)
      let picker = UIDocumentPickerViewController(url: tempURL, in: .exportToService)
      picker.delegate = self
      pendingResult = result
      pendingOperation = PendingOperation(kind: .saveBackup, rawJson: rawJson, tempURL: tempURL)
      present(picker, result: result)
    } catch {
      result(Self.errorPayload(code: "writeFailed", message: error.localizedDescription))
    }
  }

  private func present(
    _ picker: UIDocumentPickerViewController,
    result: @escaping FlutterResult
  ) {
    guard let presenter = Self.topViewController() else {
      pendingResult = nil
      pendingOperation = nil
      result(Self.errorPayload(code: "unavailable", message: "Unable to present the system file manager."))
      return
    }
    presenter.present(picker, animated: true)
  }

  private func readPickedFile(from url: URL) -> [String: Any?] {
    let needsAccess = url.startAccessingSecurityScopedResource()
    defer {
      if needsAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let rawJson = try String(contentsOf: url, encoding: .utf8)
      return Self.successPayload(
        displayName: url.lastPathComponent,
        locationLabel: url.deletingLastPathComponent().lastPathComponent,
        byteLength: rawJson.lengthOfBytes(using: .utf8),
        rawJson: rawJson
      )
    } catch {
      return Self.errorPayload(code: "readFailed", message: error.localizedDescription)
    }
  }

  private func saveResultPayload(for url: URL, rawJson: String) -> [String: Any?] {
    return Self.successPayload(
      displayName: url.lastPathComponent,
      locationLabel: url.deletingLastPathComponent().lastPathComponent,
      byteLength: rawJson.lengthOfBytes(using: .utf8),
      rawJson: nil
    )
  }

  private func finish(with payload: [String: Any?]) {
    let callback = pendingResult
    let tempURL = pendingOperation?.tempURL
    pendingResult = nil
    pendingOperation = nil
    if let tempURL {
      try? FileManager.default.removeItem(at: tempURL)
    }
    callback?(payload)
  }

  private static func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigationController = base as? UINavigationController {
      return topViewController(base: navigationController.visibleViewController)
    }
    if let tabBarController = base as? UITabBarController {
      return topViewController(base: tabBarController.selectedViewController)
    }
    if let presentedViewController = base?.presentedViewController {
      return topViewController(base: presentedViewController)
    }
    return base
  }

  private static func successPayload(
    displayName: String,
    locationLabel: String,
    byteLength: Int,
    rawJson: String?
  ) -> [String: Any?] {
    return [
      "status": "success",
      "displayName": displayName,
      "locationLabel": locationLabel.isEmpty ? "Files" : locationLabel,
      "byteLength": byteLength,
      "rawJson": rawJson,
    ]
  }

  private static func cancelledPayload() -> [String: Any?] {
    return [
      "status": "cancelled",
      "errorCode": "cancelled",
    ]
  }

  private static func errorPayload(code: String, message: String) -> [String: Any?] {
    return [
      "status": "error",
      "errorCode": code,
      "errorMessage": message,
    ]
  }
}

final class PetNoteNativeOptionPickerPlugin: NSObject, FlutterPlugin, UIAdaptivePresentationControllerDelegate {
  static let channelName = "petnote/native_option_picker"

  private struct OptionItem {
    let value: String
    let label: String
  }

  private var pendingResult: FlutterResult?
  private var presentedController: UIAlertController?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PetNoteNativeOptionPickerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(Self.errorPayload(code: "invalidResponse", message: "Another native option picker request is already running."))
      return
    }

    switch call.method {
    case "pickSingleOption":
      guard
        let arguments = call.arguments as? [String: Any],
        let title = arguments["title"] as? String,
        let rawOptions = arguments["options"] as? [[String: Any]]
      else {
        result(Self.errorPayload(code: "invalidResponse", message: "Missing title or options for native option picker."))
        return
      }
      let selectedValue = arguments["selectedValue"] as? String
      let options = rawOptions.compactMap(Self.parseOption)
      guard !title.isEmpty, !options.isEmpty else {
        result(Self.errorPayload(code: "invalidResponse", message: "Missing title or options for native option picker."))
        return
      }
      presentActionSheet(
        title: title,
        selectedValue: selectedValue,
        options: options,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if pendingResult != nil {
      finish(with: Self.cancelledPayload())
    }
  }

  private func presentActionSheet(
    title: String,
    selectedValue: String?,
    options: [OptionItem],
    result: @escaping FlutterResult
  ) {
    guard let presenter = Self.topViewController() else {
      result(Self.errorPayload(code: "unavailable", message: "Unable to present the native option picker."))
      return
    }

    let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    alert.presentationController?.delegate = self
    for option in options {
      let actionTitle = option.value == selectedValue ? "当前：\(option.label)" : option.label
      alert.addAction(
        UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
          self?.resolveSelection(
            payload: Self.successPayload(selectedValue: option.value)
          )
        }
      )
    }
    alert.addAction(
      UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
        self?.resolveSelection(payload: Self.cancelledPayload())
      }
    )
    if UIDevice.current.userInterfaceIdiom == .pad,
      let popover = alert.popoverPresentationController {
      popover.sourceView = presenter.view
      let bounds = presenter.view.bounds
      popover.sourceRect = CGRect(
        x: bounds.midX,
        y: bounds.maxY - 1,
        width: 1,
        height: 1
      )
      popover.permittedArrowDirections = []
    }

    pendingResult = result
    presentedController = alert
    presenter.present(alert, animated: true)
  }

  private func finish(with payload: [String: Any?]) {
    let callback = pendingResult
    pendingResult = nil
    presentedController = nil
    callback?(payload)
  }

  private func resolveSelection(payload: [String: Any?]) {
    let callback = pendingResult
    pendingResult = nil
    presentedController = nil
    DispatchQueue.main.async {
      callback?(payload)
    }
  }

  private static func parseOption(_ raw: [String: Any]) -> OptionItem? {
    guard
      let value = raw["value"] as? String,
      let label = raw["label"] as? String,
      !value.isEmpty,
      !label.isEmpty
    else {
      return nil
    }
    return OptionItem(value: value, label: label)
  }

  private static func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigationController = base as? UINavigationController {
      return topViewController(base: navigationController.visibleViewController)
    }
    if let tabBarController = base as? UITabBarController {
      return topViewController(base: tabBarController.selectedViewController)
    }
    if let presentedViewController = base?.presentedViewController {
      return topViewController(base: presentedViewController)
    }
    return base
  }

  private static func successPayload(selectedValue: String) -> [String: Any?] {
    return [
      "status": "success",
      "selectedValue": selectedValue,
    ]
  }

  private static func cancelledPayload() -> [String: Any?] {
    return [
      "status": "cancelled",
      "errorCode": "cancelled",
    ]
  }

  private static func errorPayload(code: String, message: String) -> [String: Any?] {
    return [
      "status": "error",
      "errorCode": code,
      "errorMessage": message,
    ]
  }
}

final class PetNoteIntroHapticsPlugin: NSObject, FlutterPlugin {
  static let channelName = "petnote/intro_haptics"

  private var engine: CHHapticEngine?
  private var activePlayer: CHHapticAdvancedPatternPlayer?
  @available(iOS 13.0, *)
  private var introLaunchPattern: CHHapticPattern?
  @available(iOS 13.0, *)
  private var introToOnboardingPattern: CHHapticPattern?
  @available(iOS 13.0, *)
  private var introPrimaryButtonTapPattern: CHHapticPattern?
  @available(iOS 13.0, *)
  private var preparedIntroLaunchPlayer: CHHapticAdvancedPatternPlayer?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PetNoteIntroHapticsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepareIntroLaunchHaptics":
      prepareIntroLaunchHaptics(result: result)
    case "playIntroLaunchContinuous":
      playIntroLaunchContinuous(result: result)
    case "stopIntroLaunchContinuous":
      stopIntroLaunchContinuous(result: result)
    case "playIntroToOnboardingContinuous":
      playIntroToOnboardingContinuous(result: result)
    case "stopIntroToOnboardingContinuous":
      stopIntroToOnboardingContinuous(result: result)
    case "playIntroPrimaryButtonTap":
      playIntroPrimaryButtonTap(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepareIntroLaunchHaptics(result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *), supportsHaptics else {
      result(nil)
      return
    }

    do {
      _ = try prepareIntroLaunchPlayer()
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "platformError",
          message: "Failed to prepare intro launch haptics.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func playIntroLaunchContinuous(result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *), supportsHaptics else {
      result(nil)
      return
    }

    do {
      try stopActivePlayerIfNeeded()
      let player = try prepareIntroLaunchPlayer()
      activePlayer = player
      try player.start(atTime: CHHapticTimeImmediate)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "platformError",
          message: "Failed to play intro launch haptics.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func stopIntroLaunchContinuous(result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(nil)
      return
    }

    do {
      try stopActivePlayerIfNeeded()
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "platformError",
          message: "Failed to stop intro launch haptics.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func playIntroToOnboardingContinuous(result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *), supportsHaptics else {
      result(nil)
      return
    }

    do {
      let engine = try prepareEngine()
      try stopActivePlayerIfNeeded()
      let pattern = try cachedIntroToOnboardingPattern()
      let player = try engine.makeAdvancedPlayer(with: pattern)
      activePlayer = player
      try player.start(atTime: CHHapticTimeImmediate)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "platformError",
          message: "Failed to play intro onboarding haptics.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func stopIntroToOnboardingContinuous(result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(nil)
      return
    }

    do {
      try stopActivePlayerIfNeeded()
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "platformError",
          message: "Failed to stop intro onboarding haptics.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func playIntroPrimaryButtonTap(result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *), supportsHaptics else {
      result(nil)
      return
    }

    do {
      let engine = try prepareEngine()
      let pattern = try cachedIntroPrimaryButtonTapPattern()
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "platformError",
          message: "Failed to play intro primary button tap haptics.",
          details: error.localizedDescription
        )
      )
    }
  }

  private var supportsHaptics: Bool {
    guard #available(iOS 13.0, *) else {
      return false
    }
    return CHHapticEngine.capabilitiesForHardware().supportsHaptics
  }

  @available(iOS 13.0, *)
  private func prepareEngine() throws -> CHHapticEngine {
    if let engine {
      try engine.start()
      return engine
    }

    let engine = try CHHapticEngine()
    engine.isAutoShutdownEnabled = false
    engine.stoppedHandler = { [weak self] _ in
      self?.activePlayer = nil
    }
    engine.resetHandler = { [weak self] in
      self?.activePlayer = nil
      self?.preparedIntroLaunchPlayer = nil
      self?.engine = nil
    }
    try engine.start()
    self.engine = engine
    return engine
  }

  @available(iOS 13.0, *)
  private func stopActivePlayerIfNeeded() throws {
    guard let activePlayer else {
      return
    }
    try activePlayer.stop(atTime: CHHapticTimeImmediate)
    self.activePlayer = nil
  }

  @available(iOS 13.0, *)
  private func prepareIntroLaunchPlayer() throws -> CHHapticAdvancedPatternPlayer {
    let engine = try prepareEngine()
    if let preparedIntroLaunchPlayer {
      return preparedIntroLaunchPlayer
    }
    let player = try engine.makeAdvancedPlayer(with: try cachedIntroLaunchPattern())
    preparedIntroLaunchPlayer = player
    return player
  }

  @available(iOS 13.0, *)
  private func cachedIntroLaunchPattern() throws -> CHHapticPattern {
    if let introLaunchPattern {
      return introLaunchPattern
    }
    let pattern = try makeIntroLaunchPattern()
    introLaunchPattern = pattern
    return pattern
  }

  @available(iOS 13.0, *)
  private func cachedIntroToOnboardingPattern() throws -> CHHapticPattern {
    if let introToOnboardingPattern {
      return introToOnboardingPattern
    }
    let pattern = try makeIntroToOnboardingPattern()
    introToOnboardingPattern = pattern
    return pattern
  }

  @available(iOS 13.0, *)
  private func cachedIntroPrimaryButtonTapPattern() throws -> CHHapticPattern {
    if let introPrimaryButtonTapPattern {
      return introPrimaryButtonTapPattern
    }
    let pattern = try makeIntroPrimaryButtonTapPattern()
    introPrimaryButtonTapPattern = pattern
    return pattern
  }

  @available(iOS 13.0, *)
  private func makeIntroLaunchPattern() throws -> CHHapticPattern {
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.24),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
      ],
      relativeTime: 0,
      duration: 0.40
    )
    let intensityCurve = CHHapticParameterCurve(
      parameterID: .hapticIntensityControl,
      controlPoints: [
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.00, value: 0.00),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.06, value: 0.78),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.18, value: 1.00),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.30, value: 0.76),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.40, value: 0.00),
      ],
      relativeTime: 0
    )
    let sharpnessCurve = CHHapticParameterCurve(
      parameterID: .hapticSharpnessControl,
      controlPoints: [
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.00, value: 0.10),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.20, value: 0.18),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.40, value: 0.08),
      ],
      relativeTime: 0
    )
    return try CHHapticPattern(
      events: [event],
      parameterCurves: [intensityCurve, sharpnessCurve]
    )
  }

  @available(iOS 13.0, *)
  private func makeIntroToOnboardingPattern() throws -> CHHapticPattern {
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.28),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.18),
      ],
      relativeTime: 0,
      duration: 0.48
    )
    let intensityCurve = CHHapticParameterCurve(
      parameterID: .hapticIntensityControl,
      controlPoints: [
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.00, value: 0.00),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.05, value: 0.62),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.16, value: 1.00),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.30, value: 0.82),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.40, value: 0.46),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.48, value: 0.00),
      ],
      relativeTime: 0
    )
    let sharpnessCurve = CHHapticParameterCurve(
      parameterID: .hapticSharpnessControl,
      controlPoints: [
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.00, value: 0.10),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.18, value: 0.22),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.34, value: 0.18),
        CHHapticParameterCurve.ControlPoint(relativeTime: 0.48, value: 0.08),
      ],
      relativeTime: 0
    )
    return try CHHapticPattern(
      events: [event],
      parameterCurves: [intensityCurve, sharpnessCurve]
    )
  }

  @available(iOS 13.0, *)
  private func makeIntroPrimaryButtonTapPattern() throws -> CHHapticPattern {
    let event = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.20),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.16),
      ],
      relativeTime: 0
    )
    return try CHHapticPattern(events: [event], parameters: [])
  }
}

final class IosNativeOverviewRangeButtonPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = IosNativeOverviewRangeButtonViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "petnote/ios_overview_range_button")
  }
}

final class IosNativeOverviewRangeButtonViewFactory: NSObject, FlutterPlatformViewFactory {
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
    IosNativeOverviewRangeButtonPlatformView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any],
      messenger: messenger
    )
  }
}

final class IosNativeOverviewRangeButtonPlatformView: NSObject, FlutterPlatformView {
  private let containerView = UIView()
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any]?,
    messenger: FlutterBinaryMessenger
  ) {
    channel = FlutterMethodChannel(
      name: "petnote/ios_overview_range_button_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()
    configureButton()
    configureChannel()
    updateState(with: args)
  }

  func view() -> UIView {
    containerView
  }

  private func configureButton() {
    containerView.backgroundColor = .clear
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(handlePress), for: .touchUpInside)
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    button.layer.cornerRadius = 20
    button.layer.masksToBounds = true
    button.tintColor = .white
    containerView.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      button.topAnchor.constraint(equalTo: containerView.topAnchor),
      button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      button.heightAnchor.constraint(equalToConstant: 40)
    ])
  }

  private func configureChannel() {
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "updateState":
        self.updateState(with: call.arguments as? [String: Any])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func updateState(with args: [String: Any]?) {
    let label = (args?["label"] as? String) ?? "7天"
    let brightness = (args?["brightness"] as? String) ?? "light"
    let accent = UIColor(red: 0.62, green: 0.52, blue: 0.93, alpha: 1)
    button.backgroundColor = accent
    let title = NSAttributedString(
      string: label,
      attributes: [
        .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: UIColor.white
      ]
    )
    button.setAttributedTitle(title, for: .normal)
    let imageConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
    let image = UIImage(systemName: "chevron.down", withConfiguration: imageConfig)?
      .withTintColor(.white, renderingMode: .alwaysOriginal)
    button.setImage(image, for: .normal)
    button.semanticContentAttribute = .forceRightToLeft
    button.tintColor = .white
    button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
    containerView.overrideUserInterfaceStyle = brightness == "dark" ? .dark : .light
  }

  @objc private func handlePress() {
    channel.invokeMethod("pressed", arguments: nil)
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

@available(iOS 14.0, *)
final class PetNoteNativePetPhotoPickerPlugin: NSObject, FlutterPlugin, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  static let channelName = "petnote/native_pet_photo_picker"

  private static let photoDirectoryName = "pet_photos"

  private enum PendingPhotoMode {
    case single
    case multiple
  }

  private enum PhotoLoadPayload {
    case success(String)
    case failure([String: Any?])
  }

  private var pendingResult: FlutterResult?
  private var pendingPhotoMode: PendingPhotoMode = .single
  private var presentedController: UIViewController?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PetNoteNativePetPhotoPickerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickPetPhoto":
      guard pendingResult == nil else {
        result(Self.errorPayload(code: "invalidResponse", message: "Another native pet photo request is already running."))
        return
      }
      presentPicker(selectionLimit: 1, mode: .single, result: result)
    case "pickPetPhotos":
      guard pendingResult == nil else {
        result(Self.errorPayload(code: "invalidResponse", message: "Another native pet photo request is already running."))
        return
      }
      presentPicker(selectionLimit: 0, mode: .multiple, result: result)
    case "deletePetPhoto":
      let arguments = call.arguments as? [String: Any]
      deletePetPhoto(at: arguments?["path"] as? String)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if pendingResult != nil {
      finish(with: Self.cancelledPayload())
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let item = results.first else {
      finish(with: Self.cancelledPayload())
      return
    }

    if pendingPhotoMode == .multiple {
      loadMultiplePhotos(results)
      return
    }

    let typeIdentifier = UTType.image.identifier
    loadPhoto(item, typeIdentifier: typeIdentifier) { [weak self] payload in
      guard let self else { return }
      switch payload {
      case .success(let localPath):
        self.finish(with: Self.successPayload(localPath: localPath))
      case .failure(let errorPayload):
        self.finish(with: errorPayload)
      }
    }
  }

  private func presentPicker(
    selectionLimit: Int,
    mode: PendingPhotoMode,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 14, *) else {
      result(Self.errorPayload(code: "unavailable", message: "PHPickerViewController requires iOS 14 or later."))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(Self.errorPayload(code: "unavailable", message: "Unable to present the system photo picker."))
      return
    }

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = selectionLimit

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    picker.presentationController?.delegate = self
    pendingResult = result
    pendingPhotoMode = mode
    presentedController = picker
    presenter.present(picker, animated: true)
  }

  private func loadMultiplePhotos(_ results: [PHPickerResult]) {
    let typeIdentifier = UTType.image.identifier
    let group = DispatchGroup()
    let lock = NSLock()
    var localPaths = Array<String?>(repeating: nil, count: results.count)
    var firstErrorPayload: [String: Any?]?

    for (index, item) in results.enumerated() {
      group.enter()
      loadPhoto(item, typeIdentifier: typeIdentifier) { payload in
        lock.lock()
        switch payload {
        case .success(let localPath):
          localPaths[index] = localPath
        case .failure(let errorPayload):
          if firstErrorPayload == nil {
            firstErrorPayload = errorPayload
          }
        }
        lock.unlock()
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      if let firstErrorPayload {
        self.finish(with: firstErrorPayload)
        return
      }
      let parsedPaths = localPaths.compactMap { $0 }
      if parsedPaths.isEmpty {
        self.finish(with: Self.cancelledPayload())
        return
      }
      self.finish(with: Self.successPayload(localPaths: parsedPaths))
    }
  }

  private func loadPhoto(
    _ item: PHPickerResult,
    typeIdentifier: String,
    completion: @escaping (PhotoLoadPayload) -> Void
  ) {
    item.itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
      guard let self else { return }
      if let error {
        completion(.failure(Self.errorPayload(code: "platformError", message: error.localizedDescription)))
        return
      }
      guard let data else {
        completion(.failure(Self.errorPayload(code: "invalidResponse", message: "System photo picker did not return image data.")))
        return
      }
      do {
        let localPath = try self.writePhotoToSandbox(
          data: data,
          typeIdentifier: item.itemProvider.registeredTypeIdentifiers.first,
        )
        completion(.success(localPath))
      } catch {
        completion(.failure(Self.errorPayload(code: "platformError", message: error.localizedDescription)))
      }
    }
  }

  private func writePhotoToSandbox(
    data: Data,
    typeIdentifier: String?
  ) throws -> String {
    let directory = try photoDirectoryURL()
    let fileExtension = Self.fileExtension(for: typeIdentifier)
    let fileName = "pet_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8)).\(fileExtension)"
    let targetURL = directory.appendingPathComponent(fileName)
    try data.write(to: targetURL, options: .atomic)
    return targetURL.path
  }

  private func photoDirectoryURL() throws -> URL {
    let baseURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = baseURL.appendingPathComponent(Self.photoDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    return directory
  }

  private func deletePetPhoto(at path: String?) {
    guard let path, !path.isEmpty else {
      return
    }
    do {
      let safeDirectory = try photoDirectoryURL().standardizedFileURL.path
      let targetURL = URL(fileURLWithPath: path).standardizedFileURL
      guard targetURL.path.hasPrefix(safeDirectory) else {
        return
      }
      if FileManager.default.fileExists(atPath: targetURL.path) {
        try FileManager.default.removeItem(at: targetURL)
      }
    } catch {
      return
    }
  }

  private func finish(with payload: [String: Any?]) {
    let callback = pendingResult
    pendingResult = nil
    pendingPhotoMode = .single
    presentedController = nil
    DispatchQueue.main.async {
      callback?(payload)
    }
  }

  private static func fileExtension(for typeIdentifier: String?) -> String {
    guard let typeIdentifier else {
      return "jpg"
    }
    let lowered = typeIdentifier.lowercased()
    if lowered.contains("png") {
      return "png"
    }
    if lowered.contains("webp") {
      return "webp"
    }
    if lowered.contains("heic") {
      return "heic"
    }
    if lowered.contains("heif") {
      return "heif"
    }
    return "jpg"
  }

  private static func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigationController = base as? UINavigationController {
      return topViewController(base: navigationController.visibleViewController)
    }
    if let tabBarController = base as? UITabBarController {
      return topViewController(base: tabBarController.selectedViewController)
    }
    if let presentedViewController = base?.presentedViewController {
      return topViewController(base: presentedViewController)
    }
    return base
  }

  private static func successPayload(localPath: String) -> [String: Any?] {
    return [
      "status": "success",
      "localPath": localPath,
    ]
  }

  private static func successPayload(localPaths: [String]) -> [String: Any?] {
    return [
      "status": "success",
      "localPaths": localPaths,
    ]
  }

  private static func cancelledPayload() -> [String: Any?] {
    return [
      "status": "cancelled",
      "errorCode": "cancelled",
    ]
  }

  private static func errorPayload(code: String, message: String) -> [String: Any?] {
    return [
      "status": "error",
      "errorCode": code,
      "errorMessage": message,
    ]
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
    case "hasHandledPermissionPrompt":
      getPermissionPromptHandled(result: result)
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


  private func getPermissionPromptHandled(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        result(settings.authorizationStatus != .notDetermined)
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { previousSettings in
      center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
        center.getNotificationSettings { currentSettings in
          DispatchQueue.main.async {
            if granted {
              UIApplication.shared.registerForRemoteNotifications()
            }
            let state = self.permissionLabel(from: currentSettings.authorizationStatus)
            let promptHandled = previousSettings.authorizationStatus == .notDetermined &&
              currentSettings.authorizationStatus != .notDetermined
            result(self.permissionRequestResult(state: state, promptHandled: promptHandled))
          }
        }
      }
    }
  }


  private func permissionRequestResult(state: String, promptHandled: Bool) -> [String: Any] {
    return [
      "state": state,
      "promptHandled": promptHandled,
    ]
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
