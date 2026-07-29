import AppKit
import ImageCaptureCore
import SwiftUI
import UniformTypeIdentifiers

struct IPhoneImportedPhoto {
    let data: Data
    let filename: String
    let creationDate: Date?
}

enum IPhonePhotoImportError: LocalizedError {
    case deviceDisconnected
    case imageTooLarge
    case unreadableImage
    case transferInProgress
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceDisconnected:
            "Das iPhone wurde getrennt. Verbinde es erneut und versuche es noch einmal."
        case .imageTooLarge:
            "Dieses iPhone-Foto ist für eine sichere Profilbild-Vorschau zu groß."
        case .unreadableImage:
            "Das ausgewählte iPhone-Foto konnte nicht gelesen werden."
        case .transferInProgress:
            "Ein iPhone-Foto wird bereits geladen."
        case let .transferFailed(message):
            "Das Foto konnte nicht vom iPhone geladen werden. \(message)"
        }
    }
}

struct IPhoneImportOperationGate {
    private(set) var token: UUID?

    mutating func begin() -> UUID {
        let token = UUID()
        self.token = token
        return token
    }

    mutating func invalidate() {
        token = nil
    }

    func accepts(_ token: UUID) -> Bool {
        self.token == token
    }
}

enum IPhoneSessionCleanupDecision: Equatable {
    case succeeded
    case retry
    case failed
}

enum IPhoneBrowserEnumerationTimeoutDecision: Equatable {
    case retry(nextAttempt: Int)
    case fail
}

enum IPhoneSessionTransitionRecoveryDecision: Equatable {
    case settled
    case waitForCallbackOrReconnect
}

enum IPhonePhotoImportSupport {
    private static let imageUTIs: Set<String> = [
        "public.image",
        "public.jpeg",
        "public.jpeg-2000",
        "public.png",
        "public.heic",
        "public.heif",
        "public.tiff",
        "public.camera-raw-image",
        "com.compuserve.gif",
        "com.microsoft.bmp",
        "com.adobe.raw-image",
    ]

    private static let imageExtensions: Set<String> = [
        "bmp",
        "dng",
        "gif",
        "heic",
        "heif",
        "jpeg",
        "jpg",
        "png",
        "tif",
        "tiff",
    ]

    static func isIPhone(productKind: String?, name: String?) -> Bool {
        [productKind, name]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("iphone") }
    }

    static func isImage(uti: String?, filename: String) -> Bool {
        if let uti {
            let normalizedUTI = uti.lowercased()
            if imageUTIs.contains(normalizedUTI)
                || UTType(uti)?.conforms(to: .image) == true {
                return true
            }
        }
        let fileExtension = URL(fileURLWithPath: filename)
            .pathExtension
            .lowercased()
        return imageExtensions.contains(fileExtension)
    }

    static func validatedByteCount(_ byteCount: Int64) throws -> Int64 {
        guard byteCount > 0 else {
            throw IPhonePhotoImportError.unreadableImage
        }
        guard byteCount <= Int64(ProfileImageSourceDecoder.maximumInputBytes)
        else {
            throw IPhonePhotoImportError.imageTooLarge
        }
        return byteCount
    }

    static func sessionCleanupDecision(
        hasOpenSession: Bool,
        remainingRetries: Int
    ) -> IPhoneSessionCleanupDecision {
        guard hasOpenSession else {
            return .succeeded
        }
        return remainingRetries > 0 ? .retry : .failed
    }

    static func sessionCleanupTimeoutDecision(
        hasOpenSession: Bool,
        completedRetries: Int,
        maximumRetries: Int
    ) -> IPhoneSessionCleanupDecision {
        sessionCleanupDecision(
            hasOpenSession: hasOpenSession,
            remainingRetries: maximumRetries - completedRetries
        )
    }

    static func cleanupQueueBlocksBrowser(
        hasCurrentDevice: Bool,
        queuedDeviceCount: Int,
        pendingTransitionCount: Int
    ) -> Bool {
        hasCurrentDevice
            || queuedDeviceCount > 0
            || pendingTransitionCount > 0
    }

    static func allowsBrowserStart(
        started: Bool,
        pendingGenerationMatches: Bool,
        browserAlreadyRunning: Bool,
        sessionCleanupBlocksStart: Bool,
        sessionTransitionBlocksStart: Bool
    ) -> Bool {
        started
            && pendingGenerationMatches
            && !browserAlreadyRunning
            && !sessionCleanupBlocksStart
            && !sessionTransitionBlocksStart
    }

    static func browserEnumerationTimeoutDecision(
        completedRecoveries: Int,
        maximumRecoveries: Int
    ) -> IPhoneBrowserEnumerationTimeoutDecision {
        guard completedRecoveries < maximumRecoveries else {
            return .fail
        }
        return .retry(nextAttempt: completedRecoveries + 1)
    }

    static func browserCallbackCompletesEnumeration(
        isSupportedDevice: Bool,
        moreComing: Bool
    ) -> Bool {
        isSupportedDevice || !moreComing
    }

    static func hasTimedOut(
        since lastProgressDate: Date,
        now: Date,
        timeout: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(lastProgressDate) >= timeout
    }

    static func shouldCloseStaleSession(
        hasOpenSession: Bool,
        isSessionDevice: Bool,
        isActiveDevice: Bool,
        isTransitionDevice: Bool,
        matchesCurrentDeviceID: Bool
    ) -> Bool {
        hasOpenSession
            && !isSessionDevice
            && !isActiveDevice
            && !isTransitionDevice
            && !matchesCurrentDeviceID
    }

    static func sessionTransitionRecoveryDecision(
        isOpening: Bool,
        hasOpenSession: Bool
    ) -> IPhoneSessionTransitionRecoveryDecision {
        let reachedExpectedState = isOpening
            ? hasOpenSession
            : !hasOpenSession
        return reachedExpectedState
            ? .settled
            : .waitForCallbackOrReconnect
    }

    static func resolvedAccessRestriction(
        reportedByEvent: Bool?,
        deviceProperty: Bool
    ) -> Bool {
        reportedByEvent ?? deviceProperty
    }

    static func shouldPreserveRecentUnlockEvent(
        eventDate: Date?,
        now: Date,
        graceInterval: TimeInterval
    ) -> Bool {
        guard let eventDate else { return false }
        let elapsed = now.timeIntervalSince(eventDate)
        return elapsed >= 0 && elapsed < graceInterval
    }

    static func shouldRequestBrowserAfterTransition(
        started: Bool,
        hasActiveConnection: Bool,
        hasPendingBrowserStart: Bool,
        browserAlreadyRunning: Bool
    ) -> Bool {
        started
            && !hasActiveConnection
            && !hasPendingBrowserStart
            && !browserAlreadyRunning
    }
}

struct ConnectedIPhone: Identifiable, Equatable {
    let id: String
    let name: String
}

struct IPhonePhotoItem: Identifiable {
    let id: String
    let filename: String
    let creationDate: Date?
    let byteCount: Int64
    let width: Int
    let height: Int
    fileprivate let file: ICCameraFile

    var isTooLarge: Bool {
        byteCount > Int64(ProfileImageSourceDecoder.maximumInputBytes)
    }
}

enum IPhonePhotoImportPhase: Equatable {
    case idle
    case searching
    case noDevice
    case connecting(String)
    case locked(String)
    case loading(String, Int)
    case ready(String)
    case failed(String)
}

private enum IPhoneSessionTransitionKind: Equatable {
    case opening
    case closing
}

private struct IPhoneSessionCleanupError: LocalizedError {
    let underlyingDescription: String?

    var errorDescription: String? {
        if let underlyingDescription,
           !underlyingDescription.isEmpty {
            return underlyingDescription
        }
        return "Image Capture meldet die iPhone-Verbindung weiterhin als geöffnet."
    }
}

private enum IPhoneSessionCleanupEvent {
    case drained
    case failed(IPhoneSessionCleanupError)
}

enum IPhoneOrphanTransitionBarrierState: Equatable {
    case awaitingCallback
    case timedOut
}

struct IPhoneOrphanTransitionBarrierRegistry<DeviceID: Hashable> {
    private struct Entry {
        let deviceID: DeviceID
        var state: IPhoneOrphanTransitionBarrierState
    }

    private var entries: [UUID: Entry] = [:]
    private var resetObservationGenerations: [DeviceID: UUID] = [:]

    var blocksBrowserStart: Bool {
        !entries.isEmpty
    }

    var hasTimedOutBarrier: Bool {
        entries.values.contains { $0.state == .timedOut }
    }

    var count: Int {
        entries.count
    }

    @discardableResult
    mutating func register(
        transitionToken: UUID,
        deviceID: DeviceID,
        resetObservationGeneration: UUID
    ) -> Bool {
        guard entries[transitionToken] == nil else {
            return false
        }
        entries[transitionToken] = Entry(
            deviceID: deviceID,
            state: .awaitingCallback
        )
        resetObservationGenerations[deviceID] =
            resetObservationGeneration
        return true
    }

    @discardableResult
    mutating func markTimedOut(
        transitionToken: UUID,
        deviceID: DeviceID
    ) -> Bool {
        guard var entry = entries[transitionToken],
              entry.deviceID == deviceID
        else {
            return false
        }
        entry.state = .timedOut
        entries[transitionToken] = entry
        return true
    }

    @discardableResult
    mutating func resolve(
        transitionToken: UUID,
        deviceID: DeviceID
    ) -> Bool {
        guard let entry = entries[transitionToken],
              entry.deviceID == deviceID
        else {
            return false
        }
        entries.removeValue(forKey: transitionToken)
        if !containsBarrier(for: deviceID) {
            resetObservationGenerations.removeValue(
                forKey: deviceID
            )
        }
        return true
    }

    func containsTransition(
        token: UUID,
        deviceID: DeviceID
    ) -> Bool {
        entries[token]?.deviceID == deviceID
    }

    func containsBarrier(for deviceID: DeviceID) -> Bool {
        entries.values.contains { $0.deviceID == deviceID }
    }

    mutating func resolveAfterConfirmedDeviceReset(
        deviceID: DeviceID,
        resetObservationGeneration: UUID
    ) -> Set<UUID> {
        guard resetObservationGenerations[deviceID]
                == resetObservationGeneration
        else {
            return []
        }
        let matchingTokens = Set(entries.compactMap {
            token,
            entry in
            entry.deviceID == deviceID ? token : nil
        })
        for token in matchingTokens {
            entries.removeValue(forKey: token)
        }
        resetObservationGenerations.removeValue(forKey: deviceID)
        return matchingTokens
    }
}

private final class IPhoneDeviceResetObserver:
    NSObject,
    ICDeviceDelegate
{
    let generation: UUID
    private let onRemove: (ICCameraDevice, UUID) -> Void

    init(
        generation: UUID,
        onRemove: @escaping (ICCameraDevice, UUID) -> Void
    ) {
        self.generation = generation
        self.onRemove = onRemove
        super.init()
    }

    func device(
        _ device: ICDevice,
        didCloseSessionWithError error: (any Error)?
    ) {}

    func device(
        _ device: ICDevice,
        didOpenSessionWithError error: (any Error)?
    ) {}

    func didRemove(_ device: ICDevice) {
        guard let camera = device as? ICCameraDevice else {
            return
        }
        onRemove(camera, generation)
    }
}

private final class IPhoneSessionCleanupCoordinator {
    static let shared = IPhoneSessionCleanupCoordinator()

    private static let requestTimeout: TimeInterval = 3
    private static let retryDelay: TimeInterval = 0.25
    private static let maximumRetries = 2

    private var queuedDevices: [ICCameraDevice] = []
    private var currentDevice: ICCameraDevice?
    private var currentRequestToken: UUID?
    private var retryStartToken: UUID?
    private var requestTimeoutTimer: Timer?
    private var completedRetries = 0
    private var lastErrorDescription: String?
    private var failure: IPhoneSessionCleanupError?
    private var orphanTransitionFailure:
        IPhoneSessionCleanupError?
    private var orphanTransitionBarriers =
        IPhoneOrphanTransitionBarrierRegistry<ObjectIdentifier>()
    private var pendingTransitionDevices:
        [UUID: ICCameraDevice] = [:]
    private var deviceResetObservers:
        [ObjectIdentifier: IPhoneDeviceResetObserver] = [:]
    private var observers:
        [UUID: (IPhoneSessionCleanupEvent) -> Void] = [:]

    private init() {}

    var blocksBrowserStart: Bool {
        IPhonePhotoImportSupport.cleanupQueueBlocksBrowser(
            hasCurrentDevice: currentDevice != nil,
            queuedDeviceCount: queuedDevices.count,
            pendingTransitionCount:
                orphanTransitionBarriers.count
        )
    }

    var hasFailedCleanup: Bool {
        failure != nil || orphanTransitionFailure != nil
    }

    func isCleaning(_ device: ICCameraDevice) -> Bool {
        currentDevice === device
            || queuedDevices.contains(where: { $0 === device })
            || pendingTransitionDevices.values.contains(
                where: { $0 === device }
            )
    }

    func awaitOrphanedTransition(
        for device: ICCameraDevice,
        transitionToken: UUID,
        timeout: TimeInterval
    ) {
        let deviceIdentity = ObjectIdentifier(device)
        let resetObservationGeneration = UUID()
        guard orphanTransitionBarriers.register(
            transitionToken: transitionToken,
            deviceID: deviceIdentity,
            resetObservationGeneration:
                resetObservationGeneration
        ) else {
            return
        }
        pendingTransitionDevices[transitionToken] = device
        let resetObserver = IPhoneDeviceResetObserver(
            generation: resetObservationGeneration
        ) { [weak self] resetDevice, generation in
            self?.confirmDeviceReset(
                for: resetDevice,
                resetObservationGeneration: generation
            )
        }
        deviceResetObservers[deviceIdentity] = resetObserver
        device.delegate = resetObserver
        DispatchQueue.main.asyncAfter(
            deadline: .now() + timeout
        ) { [weak self, device] in
            guard let self,
                  self.pendingTransitionDevices[transitionToken]
                    === device,
                  self.orphanTransitionBarriers.markTimedOut(
                    transitionToken: transitionToken,
                    deviceID: deviceIdentity
                  )
            else {
                return
            }
            let error = IPhoneSessionCleanupError(
                underlyingDescription:
                    "Image Capture hat den Abschluss einer iPhone-Verbindung nicht bestätigt. Die Verbindung bleibt aus Sicherheitsgründen gesperrt. Trenne das iPhone vollständig; falls der Rückruf danach weiter fehlt, starte die App neu."
            )
            self.orphanTransitionFailure = error
            self.notify(.failed(error))
        }
    }

    func resolveOrphanedTransition(
        for device: ICCameraDevice,
        transitionToken: UUID
    ) {
        let deviceIdentity = ObjectIdentifier(device)
        guard pendingTransitionDevices[transitionToken] === device,
              orphanTransitionBarriers.resolve(
                transitionToken: transitionToken,
                deviceID: deviceIdentity
              )
        else {
            return
        }
        pendingTransitionDevices.removeValue(
            forKey: transitionToken
        )
        refreshOrphanTransitionFailure()
        guard !orphanTransitionBarriers.containsBarrier(
            for: deviceIdentity
        ) else {
            return
        }
        detachAsDeviceResetObserver(from: device)
        enqueueIfOpenOrNotifyDrain(device)
    }

    private func confirmDeviceReset(
        for device: ICCameraDevice,
        resetObservationGeneration: UUID
    ) {
        let deviceIdentity = ObjectIdentifier(device)
        guard let resetObserver =
                deviceResetObservers[deviceIdentity],
              resetObserver.generation
                == resetObservationGeneration,
              device.delegate === resetObserver
        else {
            return
        }
        let resolvedTokens =
            orphanTransitionBarriers
                .resolveAfterConfirmedDeviceReset(
                    deviceID: deviceIdentity,
                    resetObservationGeneration:
                        resetObservationGeneration
                )
        guard !resolvedTokens.isEmpty else { return }
        for token in resolvedTokens {
            pendingTransitionDevices.removeValue(forKey: token)
        }
        detachAsDeviceResetObserver(from: device)
        refreshOrphanTransitionFailure()
        notifyDrainIfPossible()
    }

    @discardableResult
    func addObserver(
        _ observer: @escaping (IPhoneSessionCleanupEvent) -> Void
    ) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    func enqueue(_ device: ICCameraDevice) {
        if currentDevice === device
            || queuedDevices.contains(where: { $0 === device }) {
            if failure != nil {
                retryFailedCleanup()
            }
            return
        }
        queuedDevices.append(device)
        startNextDeviceIfNeeded()
    }

    func retryFailedCleanup() {
        if let orphanTransitionFailure {
            notify(.failed(orphanTransitionFailure))
        }
        guard failure != nil,
              currentDevice != nil
        else {
            return
        }
        failure = nil
        completedRetries = 0
        lastErrorDescription = nil
        startCurrentCloseAttempt()
    }

    private func startNextDeviceIfNeeded() {
        guard currentDevice == nil,
              !queuedDevices.isEmpty
        else {
            return
        }
        currentDevice = queuedDevices.removeFirst()
        completedRetries = 0
        lastErrorDescription = nil
        failure = nil
        startCurrentCloseAttempt()
    }

    private func startCurrentCloseAttempt() {
        guard failure == nil,
              let device = currentDevice
        else {
            return
        }
        retryStartToken = nil
        guard device.hasOpenSession else {
            finishCurrentDevice()
            return
        }

        let requestToken = UUID()
        currentRequestToken = requestToken
        startRequestTimeout(
            for: device,
            requestToken: requestToken
        )
        device.requestCloseSession(options: nil) {
            [weak self, device] error in
            DispatchQueue.main.async {
                guard let self,
                      self.currentDevice === device,
                      self.currentRequestToken == requestToken
                else {
                    return
                }
                self.stopRequestTimeout()
                self.currentRequestToken = nil
                if let error {
                    self.lastErrorDescription =
                        error.localizedDescription
                }
                self.handleAttemptCompletion(for: device)
            }
        }
    }

    private func startRequestTimeout(
        for device: ICCameraDevice,
        requestToken: UUID
    ) {
        stopRequestTimeout()
        let timer = Timer(
            timeInterval: Self.requestTimeout,
            repeats: false
        ) { [weak self, device] timer in
            guard let self,
                  self.currentDevice === device,
                  self.currentRequestToken == requestToken
            else {
                timer.invalidate()
                return
            }
            self.stopRequestTimeout()
            self.currentRequestToken = nil
            self.lastErrorDescription =
                "Image Capture hat auf das Schließen der iPhone-Verbindung nicht geantwortet."
            self.handleAttemptCompletion(for: device)
        }
        timer.tolerance = 0.2
        requestTimeoutTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRequestTimeout() {
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
    }

    private func handleAttemptCompletion(
        for device: ICCameraDevice
    ) {
        switch IPhonePhotoImportSupport.sessionCleanupTimeoutDecision(
            hasOpenSession: device.hasOpenSession,
            completedRetries: completedRetries,
            maximumRetries: Self.maximumRetries
        ) {
        case .succeeded:
            finishCurrentDevice()
        case .retry:
            completedRetries += 1
            scheduleRetry(for: device)
        case .failed:
            let error = IPhoneSessionCleanupError(
                underlyingDescription: lastErrorDescription
            )
            failure = error
            notify(.failed(error))
        }
    }

    private func scheduleRetry(for device: ICCameraDevice) {
        let retryToken = UUID()
        retryStartToken = retryToken
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.retryDelay
        ) { [weak self, device] in
            guard let self,
                  self.currentDevice === device,
                  self.retryStartToken == retryToken,
                  self.failure == nil
            else {
                return
            }
            self.startCurrentCloseAttempt()
        }
    }

    private func finishCurrentDevice() {
        stopRequestTimeout()
        currentRequestToken = nil
        retryStartToken = nil
        currentDevice = nil
        completedRetries = 0
        lastErrorDescription = nil
        failure = nil
        if queuedDevices.isEmpty,
           !orphanTransitionBarriers.blocksBrowserStart {
            notify(.drained)
        } else {
            startNextDeviceIfNeeded()
        }
    }

    private func enqueueIfOpenOrNotifyDrain(
        _ device: ICCameraDevice
    ) {
        if device.hasOpenSession {
            enqueue(device)
        } else {
            notifyDrainIfPossible()
        }
    }

    private func refreshOrphanTransitionFailure() {
        if !orphanTransitionBarriers.hasTimedOutBarrier {
            orphanTransitionFailure = nil
        }
    }

    private func detachAsDeviceResetObserver(
        from device: ICCameraDevice
    ) {
        let deviceIdentity = ObjectIdentifier(device)
        guard let resetObserver =
                deviceResetObservers.removeValue(
                    forKey: deviceIdentity
                )
        else {
            return
        }
        if device.delegate === resetObserver {
            device.delegate = nil
        }
    }

    private func notifyDrainIfPossible() {
        if currentDevice == nil,
           queuedDevices.isEmpty,
           !orphanTransitionBarriers.blocksBrowserStart {
            notify(.drained)
        }
    }

    private func notify(_ event: IPhoneSessionCleanupEvent) {
        for observer in Array(observers.values) {
            observer(event)
        }
    }
}

final class IPhonePhotoImportController:
    NSObject,
    ObservableObject,
    ICDeviceBrowserDelegate,
    ICCameraDeviceDelegate
{
    private static let browserEnumerationTimeoutInterval: TimeInterval = 3
    private static let browserReplacementSettleDelay: TimeInterval = 0.35
    private static let sessionCloseSettleDelay: TimeInterval = 0.5
    private static let sessionTransitionTimeoutInterval: TimeInterval = 20
    private static let transferTimeoutInterval: TimeInterval = 45
    private static let catalogStallTimeoutInterval: TimeInterval = 20
    private static let thumbnailTimeoutInterval: TimeInterval = 5
    private static let explicitUnlockGraceInterval: TimeInterval = 5
    private static let maximumAutomaticBrowserRecoveries = 2
    private static let maximumCatalogStallRecoveries = 1
    private static let maximumThumbnailRetries = 2

    @Published private(set) var devices: [ConnectedIPhone] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var photos: [IPhonePhotoItem] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var failedThumbnailIDs: Set<String> = []
    @Published private(set) var phase: IPhonePhotoImportPhase = .idle
    @Published private(set) var importingPhotoID: String?

    private var browser = ICDeviceBrowser()
    private var browserRunToken: UUID?
    private var deviceByID: [String: ICCameraDevice] = [:]
    private var activeDevice: ICCameraDevice?
    private var sessionDevice: ICCameraDevice?
    private var sessionTransitionKind: IPhoneSessionTransitionKind?
    private var sessionTransitionToken: UUID?
    private var sessionTransitionDevice: ICCameraDevice?
    private var sessionTransitionTimedOut = false
    private var sessionTransitionTimeoutTimer: Timer?
    private var catalogTimer: Timer?
    private var catalogProgressDeviceID: ObjectIdentifier?
    private var catalogLastProgress = 0
    private var catalogLastProgressDate = Date()
    private var catalogStallRecoveryAttempt = 0
    private var accessRestrictionTimer: Timer?
    private var accessRestrictionWatchToken: UUID?
    private var readyRestrictionTimer: Timer?
    private var readyRestrictionWatchToken: UUID?
    private var thumbnailRequests: Set<String> = []
    private var thumbnailRequestTokens: [String: UUID] = [:]
    private var thumbnailTimeoutTimers: [String: Timer] = [:]
    private var thumbnailRetryCounts: [String: Int] = [:]
    private var accessRestrictionByDevice: [ObjectIdentifier: Bool] = [:]
    private var accessUnrestrictionEventDateByDevice:
        [ObjectIdentifier: Date] = [:]
    private var connectionGate = IPhoneImportOperationGate()
    private var transferGate = IPhoneImportOperationGate()
    private var transferTemporaryDirectory: URL?
    private var transferProgress: Progress?
    private var transferTimeoutTimer: Timer?
    private var pendingBrowserStartToken: UUID?
    private var cleanupObserverToken: UUID?
    private var browserEnumerationTimer: Timer?
    private var browserEnumerationCompleted = false
    private var browserRecoveryAttempt = 0
    private var started = false

    override init() {
        super.init()
        cleanupObserverToken =
            IPhoneSessionCleanupCoordinator.shared.addObserver {
                [weak self] event in
                self?.handleSessionCleanupEvent(event)
            }
    }

    deinit {
        let orphanedTransitionDevice = sessionTransitionDevice
        let orphanedTransitionToken = sessionTransitionToken
        let unfinishedTransferDirectory =
            transferTemporaryDirectory
        let cleanupCandidates = [
            sessionDevice,
            activeDevice,
        ]
        catalogTimer?.invalidate()
        accessRestrictionTimer?.invalidate()
        readyRestrictionTimer?.invalidate()
        browserEnumerationTimer?.invalidate()
        sessionTransitionTimeoutTimer?.invalidate()
        transferTimeoutTimer?.invalidate()
        transferProgress?.cancel()
        if let unfinishedTransferDirectory {
            Self.scheduleTemporaryDirectoryRemoval(
                unfinishedTransferDirectory,
                initialDelay: 0.25
            )
        }
        for timer in thumbnailTimeoutTimers.values {
            timer.invalidate()
        }
        pendingBrowserStartToken = nil
        browserRunToken = nil
        browser.stop()
        browser.delegate = nil
        detachAllCameraDelegates()
        if let orphanedTransitionDevice,
           let orphanedTransitionToken {
            IPhoneSessionCleanupCoordinator.shared
                .awaitOrphanedTransition(
                    for: orphanedTransitionDevice,
                    transitionToken: orphanedTransitionToken,
                    timeout:
                        Self.sessionTransitionTimeoutInterval
                )
        }
        var queuedDeviceIDs: Set<ObjectIdentifier> = []
        for device in cleanupCandidates.compactMap({ $0 })
        where device !== orphanedTransitionDevice
            && device.hasOpenSession
            && queuedDeviceIDs.insert(
                ObjectIdentifier(device)
            ).inserted {
            IPhoneSessionCleanupCoordinator.shared.enqueue(device)
        }
        if let cleanupObserverToken {
            IPhoneSessionCleanupCoordinator.shared.removeObserver(
                cleanupObserverToken
            )
        }
    }

    func start() {
        guard !started else { return }
        started = true
        Self.cleanUpStaleTemporaryDirectories()
        browserRecoveryAttempt = 0
        catalogStallRecoveryAttempt = 0
        if sessionTransitionToken != nil {
            if recoverTimedOutSessionTransitionIfPossible() {
                return
            }
            phase = sessionTransitionTimedOut
                ? .failed(sessionTransitionRecoveryMessage)
                : .connecting(
                    sessionTransitionDevice?.name ?? "iPhone"
                )
            return
        }
        phase = .searching
        if IPhoneSessionCleanupCoordinator.shared.hasFailedCleanup {
            IPhoneSessionCleanupCoordinator.shared.retryFailedCleanup()
        }
        requestBrowserStart()
    }

    private func requestBrowserStart(
        after delay: TimeInterval = 0
    ) {
        let startToken = UUID()
        pendingBrowserStartToken = startToken
        scheduleBrowserStart(
            token: startToken,
            expectedBrowser: browser,
            after: delay
        )
    }

    private func schedulePendingBrowserStart(
        after delay: TimeInterval = 0
    ) {
        guard let pendingBrowserStartToken else { return }
        scheduleBrowserStart(
            token: pendingBrowserStartToken,
            expectedBrowser: browser,
            after: delay
        )
    }

    private func scheduleBrowserStart(
        token: UUID,
        expectedBrowser: ICDeviceBrowser,
        after delay: TimeInterval
    ) {
        let cleanupBlocksStart =
            IPhoneSessionCleanupCoordinator.shared.blocksBrowserStart
        let transitionBlocksStart = sessionTransitionToken != nil
        guard !cleanupBlocksStart,
              !transitionBlocksStart
        else {
            return
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay
        ) { [weak self, expectedBrowser] in
            guard let self else { return }
            let pendingGenerationMatches =
                self.pendingBrowserStartToken == token
                    && self.browser === expectedBrowser
            let cleanupBlocksStart =
                IPhoneSessionCleanupCoordinator.shared
                    .blocksBrowserStart
            let transitionBlocksStart =
                self.sessionTransitionToken != nil
            guard IPhonePhotoImportSupport.allowsBrowserStart(
                started: self.started,
                pendingGenerationMatches: pendingGenerationMatches,
                browserAlreadyRunning: self.browserRunToken != nil,
                sessionCleanupBlocksStart: cleanupBlocksStart,
                sessionTransitionBlocksStart:
                    transitionBlocksStart
            ) else {
                return
            }
            self.pendingBrowserStartToken = nil
            self.beginBrowsing()
        }
    }

    private func beginBrowsing() {
        browser.delegate = self
        browserEnumerationCompleted = false
        let runToken = UUID()
        browserRunToken = runToken
        let rawMask =
            ICDeviceTypeMask.camera.rawValue
                | ICDeviceLocationTypeMask.local.rawValue
        if let mask = ICDeviceTypeMask(rawValue: rawMask) {
            browser.browsedDeviceTypeMask = mask
        } else {
            browser.browsedDeviceTypeMask = .camera
        }
        startBrowserEnumerationTimeout(
            for: browser,
            runToken: runToken
        )
        browser.start()
    }

    private func startBrowserEnumerationTimeout(
        for expectedBrowser: ICDeviceBrowser,
        runToken: UUID
    ) {
        stopBrowserEnumerationTimeout()
        let timer = Timer(
            timeInterval: Self.browserEnumerationTimeoutInterval,
            repeats: false
        ) { [weak self, expectedBrowser] timer in
            guard let self,
                  self.started,
                  self.browser === expectedBrowser,
                  self.browserRunToken == runToken
            else {
                timer.invalidate()
                return
            }
            self.handleBrowserEnumerationTimeout()
        }
        timer.tolerance = 0.2
        browserEnumerationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBrowserEnumerationTimeout() {
        browserEnumerationTimer?.invalidate()
        browserEnumerationTimer = nil
    }

    private func markBrowserResponsive(
        enumerationComplete: Bool
    ) {
        if enumerationComplete {
            browserEnumerationCompleted = true
            stopBrowserEnumerationTimeout()
            browserRecoveryAttempt = 0
        } else if !browserEnumerationCompleted,
                  !IPhoneSessionCleanupCoordinator.shared
                    .hasFailedCleanup,
                  let browserRunToken {
            startBrowserEnumerationTimeout(
                for: browser,
                runToken: browserRunToken
            )
        }
    }

    private func handleBrowserEnumerationTimeout() {
        stopBrowserEnumerationTimeout()
        guard let runToken = browserRunToken else { return }
        let recoveryIsBlocked =
            sessionTransitionToken != nil
                || IPhoneSessionCleanupCoordinator.shared
                    .blocksBrowserStart
        if recoveryIsBlocked {
            if IPhoneSessionCleanupCoordinator.shared
                .hasFailedCleanup {
                return
            }
            startBrowserEnumerationTimeout(
                for: browser,
                runToken: runToken
            )
            return
        }

        switch IPhonePhotoImportSupport.browserEnumerationTimeoutDecision(
            completedRecoveries: browserRecoveryAttempt,
            maximumRecoveries: Self.maximumAutomaticBrowserRecoveries
        ) {
        case let .retry(nextAttempt):
            if restartWithFreshBrowserSnapshot(
                resetBrowserRecoveryAttempts: false,
                startDelay: Self.browserReplacementSettleDelay
            ) {
                browserRecoveryAttempt = nextAttempt
            } else {
                startBrowserEnumerationTimeout(
                    for: browser,
                    runToken: runToken
                )
            }
        case .fail:
            let sessionToClose =
                replaceBrowserAndClearDeviceSnapshot()
            if let sessionToClose {
                beginTrackedCleanupClose(for: sessionToClose)
            }
            phase = .failed(
                "Die iPhone-Suche antwortet gerade nicht. Prüfe das Kabel und ob das iPhone entsperrt ist. Mit „Erneut versuchen“ wird die Verbindung vollständig neu aufgebaut."
            )
        }
    }

    func stop() {
        pendingBrowserStartToken = nil
        browserRunToken = nil
        browserEnumerationCompleted = false
        guard started else { return }
        started = false
        let orphanedTransitionDevice = sessionTransitionDevice
        let orphanedTransitionToken = sessionTransitionToken
        stopSessionTransitionTimeout()
        let sessionToClose = replaceBrowserAndClearDeviceSnapshot()
        if let orphanedTransitionDevice,
           let orphanedTransitionToken {
            sessionTransitionKind = nil
            sessionTransitionToken = nil
            sessionTransitionDevice = nil
            sessionTransitionTimedOut = false
            IPhoneSessionCleanupCoordinator.shared
                .awaitOrphanedTransition(
                    for: orphanedTransitionDevice,
                    transitionToken: orphanedTransitionToken,
                    timeout:
                        Self.sessionTransitionTimeoutInterval
                )
        }
        phase = .idle
        if let sessionToClose {
            beginTrackedCleanupClose(for: sessionToClose)
        }
    }

    func restart() {
        guard started,
              importingPhotoID == nil
        else {
            return
        }
        if sessionTransitionToken != nil {
            if !recoverTimedOutSessionTransitionIfPossible() {
                phase = sessionTransitionTimedOut
                    ? .failed(sessionTransitionRecoveryMessage)
                    : .connecting(
                        sessionTransitionDevice?.name ?? "iPhone"
                    )
            }
            return
        }
        catalogStallRecoveryAttempt = 0
        resetCatalogProgressObservation()
        if IPhoneSessionCleanupCoordinator.shared.hasFailedCleanup {
            IPhoneSessionCleanupCoordinator.shared.retryFailedCleanup()
            if IPhoneSessionCleanupCoordinator.shared
                .hasFailedCleanup {
                return
            }
        }
        if let activeDevice,
           let selectedDeviceID {
            let identity = ObjectIdentifier(activeDevice)
            if effectiveIsAccessRestricted(activeDevice)
                || accessUnrestrictionEventDateByDevice[
                    identity
                ] != nil {
                refreshAccessRestriction(
                    for: activeDevice,
                    connectionToken: connectionGate.token
                )
            } else if sessionDevice === activeDevice,
               activeDevice.hasOpenSession {
                startCatalogTimer(for: activeDevice)
                refreshCatalog(for: activeDevice)
            } else {
                connect(to: activeDevice, id: selectedDeviceID)
            }
            return
        }
        restartWithFreshBrowserSnapshot()
    }

    func selectDevice(id: String) {
        guard importingPhotoID == nil,
              selectedDeviceID != id,
              let device = deviceByID[id]
        else {
            return
        }
        catalogStallRecoveryAttempt = 0
        resetCatalogProgressObservation()
        connect(to: device, id: id)
    }

    func refresh() {
        guard importingPhotoID == nil else { return }
        if sessionTransitionToken != nil {
            if !recoverTimedOutSessionTransitionIfPossible() {
                phase = sessionTransitionTimedOut
                    ? .failed(sessionTransitionRecoveryMessage)
                    : .connecting(
                        sessionTransitionDevice?.name ?? "iPhone"
                    )
            }
            return
        }
        catalogStallRecoveryAttempt = 0
        resetCatalogProgressObservation()
        if let activeDevice {
            let identity = ObjectIdentifier(activeDevice)
            if effectiveIsAccessRestricted(activeDevice)
                || accessUnrestrictionEventDateByDevice[
                    identity
                ] != nil {
                refreshAccessRestriction(
                    for: activeDevice,
                    connectionToken: connectionGate.token
                )
            } else if sessionDevice === activeDevice,
                      activeDevice.hasOpenSession {
                startCatalogTimer(for: activeDevice)
                refreshCatalog(for: activeDevice)
            } else if let selectedDeviceID {
                connect(to: activeDevice, id: selectedDeviceID)
            }
        } else {
            restart()
        }
    }

    @discardableResult
    private func restartWithFreshBrowserSnapshot(
        resetBrowserRecoveryAttempts: Bool = true,
        resetCatalogStallRecoveryAttempts: Bool = true,
        startDelay: TimeInterval? = nil
    ) -> Bool {
        guard started,
              sessionTransitionToken == nil
        else {
            return false
        }

        if resetBrowserRecoveryAttempts {
            browserRecoveryAttempt = 0
        }
        if resetCatalogStallRecoveryAttempts {
            catalogStallRecoveryAttempt = 0
        }
        let sessionToClose = replaceBrowserAndClearDeviceSnapshot()
        phase = .searching

        if let sessionToClose {
            beginTrackedCleanupClose(for: sessionToClose)
        }
        requestBrowserStart(
            after: startDelay ?? Self.browserReplacementSettleDelay
        )
        return true
    }

    @discardableResult
    private func replaceBrowserAndClearDeviceSnapshot()
        -> ICCameraDevice? {
        let sessionToClose: ICCameraDevice?
        if sessionTransitionToken == nil,
           let sessionDevice,
           sessionDevice.hasOpenSession {
            sessionToClose = sessionDevice
        } else {
            sessionToClose = nil
        }

        pendingBrowserStartToken = nil
        browserRunToken = nil
        connectionGate.invalidate()
        invalidateTransfer()
        stopBrowserEnumerationTimeout()
        catalogTimer?.invalidate()
        catalogTimer = nil
        resetCatalogProgressObservation()
        stopAccessRestrictionWatcher()
        stopReadyRestrictionMonitor()
        detachAllCameraDelegates()
        browser.stop()
        browser.delegate = nil
        browser = ICDeviceBrowser()
        sessionDevice = nil
        activeDevice = nil
        selectedDeviceID = nil
        devices = []
        deviceByID = [:]
        accessRestrictionByDevice = [:]
        accessUnrestrictionEventDateByDevice = [:]
        photos = []
        thumbnails = [:]
        failedThumbnailIDs = []
        cancelAllThumbnailRequests()
        return sessionToClose
    }

    private func beginTrackedCleanupClose(for device: ICCameraDevice) {
        detachCameraDelegate(from: device)
        IPhoneSessionCleanupCoordinator.shared.enqueue(device)
    }

    private func handleSessionCleanupEvent(
        _ event: IPhoneSessionCleanupEvent
    ) {
        switch event {
        case .drained:
            if started,
               !browserEnumerationCompleted,
               let browserRunToken {
                startBrowserEnumerationTimeout(
                    for: browser,
                    runToken: browserRunToken
                )
            }
            resumeCurrentConnection()
            schedulePendingBrowserStart(
                after: Self.sessionCloseSettleDelay
            )
        case let .failed(error):
            guard started else { return }
            stopBrowserEnumerationTimeout()
            phase = .failed(
                "Die vorherige iPhone-Verbindung konnte nicht sicher geschlossen werden. \(error.localizedDescription) Trenne das iPhone kurz und versuche es erneut."
            )
        }
    }

    func thumbnail(for item: IPhonePhotoItem) -> NSImage? {
        thumbnails[item.id]
    }

    func requestThumbnail(for item: IPhonePhotoItem) {
        guard started,
              photos.contains(where: { $0.id == item.id }),
              thumbnails[item.id] == nil,
              !thumbnailRequests.contains(item.id)
        else {
            return
        }
        failedThumbnailIDs.remove(item.id)
        thumbnailRetryCounts[item.id] = 0
        beginThumbnailRequest(for: item)
    }

    private func beginThumbnailRequest(
        for item: IPhonePhotoItem
    ) {
        guard started,
              photos.contains(where: { $0.id == item.id }),
              thumbnails[item.id] == nil,
              thumbnailRequests.insert(item.id).inserted
        else {
            return
        }
        let requestToken = UUID()
        thumbnailRequestTokens[item.id] = requestToken
        startThumbnailTimeout(
            for: item,
            requestToken: requestToken
        )
        item.file.requestThumbnailData(options: nil) {
            [weak self] data,
            error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.finishThumbnailRequest(
                    id: item.id,
                    requestToken: requestToken
                ) else {
                    return
                }
                guard self.started,
                      self.photos.contains(where: { $0.id == item.id })
                else {
                    self.thumbnailRetryCounts.removeValue(
                        forKey: item.id
                    )
                    return
                }
                guard let data,
                      error == nil,
                      let image = NSImage(data: data)
                else {
                    self.retryOrFailThumbnail(for: item)
                    return
                }
                self.failedThumbnailIDs.remove(item.id)
                self.thumbnailRetryCounts.removeValue(
                    forKey: item.id
                )
                self.thumbnails[item.id] = image
            }
        }
    }

    private func startThumbnailTimeout(
        for item: IPhonePhotoItem,
        requestToken: UUID
    ) {
        thumbnailTimeoutTimers[item.id]?.invalidate()
        let timer = Timer(
            timeInterval: Self.thumbnailTimeoutInterval,
            repeats: false
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard self.finishThumbnailRequest(
                id: item.id,
                requestToken: requestToken
            ) else {
                timer.invalidate()
                return
            }
            guard self.started,
                  self.photos.contains(where: { $0.id == item.id })
            else {
                self.thumbnailRetryCounts.removeValue(
                    forKey: item.id
                )
                return
            }
            self.retryOrFailThumbnail(for: item)
        }
        timer.tolerance = 0.25
        thumbnailTimeoutTimers[item.id] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @discardableResult
    private func finishThumbnailRequest(
        id: String,
        requestToken: UUID
    ) -> Bool {
        guard thumbnailRequestTokens[id] == requestToken else {
            return false
        }
        thumbnailTimeoutTimers.removeValue(forKey: id)?.invalidate()
        thumbnailRequestTokens.removeValue(forKey: id)
        thumbnailRequests.remove(id)
        return true
    }

    private func retryOrFailThumbnail(
        for item: IPhonePhotoItem
    ) {
        let completedRetries = thumbnailRetryCounts[item.id] ?? 0
        switch IPhonePhotoImportSupport.browserEnumerationTimeoutDecision(
            completedRecoveries: completedRetries,
            maximumRecoveries: Self.maximumThumbnailRetries
        ) {
        case let .retry(nextAttempt):
            thumbnailRetryCounts[item.id] = nextAttempt
            beginThumbnailRequest(for: item)
        case .fail:
            thumbnailRetryCounts.removeValue(forKey: item.id)
            failedThumbnailIDs.insert(item.id)
        }
    }

    private func cancelAllThumbnailRequests() {
        for timer in thumbnailTimeoutTimers.values {
            timer.invalidate()
        }
        thumbnailTimeoutTimers = [:]
        thumbnailRequestTokens = [:]
        thumbnailRetryCounts = [:]
        thumbnailRequests = []
    }

    func importPhoto(
        id: String,
        completion: @escaping (Result<IPhoneImportedPhoto, Error>) -> Void
    ) {
        guard importingPhotoID == nil else {
            completion(.failure(
                IPhonePhotoImportError.transferInProgress
            ))
            return
        }
        guard started,
              let activeDevice,
              activeDevice.hasOpenSession,
              let item = photos.first(where: { $0.id == id })
        else {
            completion(.failure(IPhonePhotoImportError.deviceDisconnected))
            return
        }

        do {
            _ = try IPhonePhotoImportSupport.validatedByteCount(
                item.byteCount
            )
        } catch {
            completion(.failure(error))
            return
        }

        let temporaryDirectory =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Freundeblick-iPhone-\(UUID().uuidString)",
                    isDirectory: true
                )
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            completion(.failure(
                IPhonePhotoImportError.transferFailed(
                    "Der geschützte Zwischenspeicher konnte nicht erstellt werden."
                )
            ))
            return
        }

        let originalExtension = URL(fileURLWithPath: item.filename)
            .pathExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(10)
        let downloadFilename =
            "iphone-photo-\(UUID().uuidString)"
                + (originalExtension.isEmpty
                    ? ""
                    : ".\(originalExtension)")
        let transferToken = transferGate.begin()
        transferTemporaryDirectory = temporaryDirectory
        importingPhotoID = id

        transferProgress = item.file.requestDownload(
            options: [
                .downloadsDirectoryURL: temporaryDirectory,
                .saveAsFilename: downloadFilename,
                .overwrite: false,
                .deleteAfterSuccessfulDownload: false,
            ]
        ) {
            [weak self, weak activeDevice] downloadedFilename,
            error in
            let returnedFilename = downloadedFilename?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveFilename = returnedFilename.flatMap {
                $0.isEmpty ? nil : $0
            } ?? downloadFilename
            let safeFilename = URL(
                fileURLWithPath: effectiveFilename
            ).lastPathComponent
            let downloadedURL = temporaryDirectory
                .appendingPathComponent(safeFilename)
            let result: Result<IPhoneImportedPhoto, Error>
            if let error {
                result = .failure(
                    IPhonePhotoImportError.transferFailed(
                        error.localizedDescription
                    )
                )
            } else {
                do {
                    let resourceValues = try downloadedURL.resourceValues(
                        forKeys: [
                            .fileSizeKey,
                            .isRegularFileKey,
                            .isSymbolicLinkKey,
                        ]
                    )
                    guard resourceValues.isRegularFile == true,
                          resourceValues.isSymbolicLink != true,
                          let fileSize = resourceValues.fileSize
                    else {
                        throw IPhonePhotoImportError.unreadableImage
                    }
                    _ = try IPhonePhotoImportSupport.validatedByteCount(
                        Int64(fileSize)
                    )
                    let data = try Data(contentsOf: downloadedURL)
                    _ = try IPhonePhotoImportSupport
                        .validatedByteCount(Int64(data.count))
                    result = .success(IPhoneImportedPhoto(
                        data: data,
                        filename: item.filename,
                        creationDate: item.creationDate
                    ))
                } catch let error as IPhonePhotoImportError {
                    result = .failure(error)
                } catch {
                    result = .failure(
                        IPhonePhotoImportError.transferFailed(
                            error.localizedDescription
                        )
                    )
                }
            }
            Self.scheduleTemporaryDirectoryRemoval(
                temporaryDirectory,
                initialDelay: 0
            )

            DispatchQueue.main.async {
                guard let self,
                      let activeDevice,
                      self.started,
                      self.transferGate.accepts(transferToken),
                      self.activeDevice === activeDevice,
                      self.selectedDeviceID
                        == self.deviceID(for: activeDevice)
                else {
                    return
                }
                self.stopTransferTimeout()
                self.transferProgress = nil
                self.transferGate.invalidate()
                self.transferTemporaryDirectory = nil
                self.importingPhotoID = nil
                completion(result)
            }
        }
        startTransferTimeout(
            transferToken: transferToken,
            expectedDevice: activeDevice,
            completion: completion
        )
    }

    private func startTransferTimeout(
        transferToken: UUID,
        expectedDevice: ICCameraDevice,
        completion: @escaping (
            Result<IPhoneImportedPhoto, Error>
        ) -> Void
    ) {
        stopTransferTimeout()
        let timer = Timer(
            timeInterval: Self.transferTimeoutInterval,
            repeats: false
        ) { [weak self, expectedDevice] timer in
            guard let self,
                  self.started,
                  self.transferGate.accepts(transferToken),
                  self.activeDevice === expectedDevice,
                  self.selectedDeviceID
                    == self.deviceID(for: expectedDevice)
            else {
                timer.invalidate()
                return
            }
            self.stopTransferTimeout()
            self.transferGate.invalidate()
            self.transferProgress?.cancel()
            self.transferProgress = nil
            expectedDevice.cancelDownload()
            self.removeTransferTemporaryDirectory()
            self.importingPhotoID = nil
            completion(.failure(
                IPhonePhotoImportError.transferFailed(
                    "Die Übertragung hat zu lange gedauert und wurde abgebrochen."
                )
            ))
        }
        timer.tolerance = 0.5
        transferTimeoutTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTransferTimeout() {
        transferTimeoutTimer?.invalidate()
        transferTimeoutTimer = nil
    }

    func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didAdd device: ICDevice,
        moreComing: Bool
    ) {
        let callbackToken = browserRunToken
        performOnMain {
            guard self.started,
                  self.browser === browser,
                  let callbackToken,
                  self.browserRunToken == callbackToken
            else {
                return
            }
            let isSupportedDevice =
                (device as? ICCameraDevice).map {
                    IPhonePhotoImportSupport.isIPhone(
                        productKind: $0.productKind,
                        name: $0.name
                    )
                } == true
            self.markBrowserResponsive(
                enumerationComplete:
                    IPhonePhotoImportSupport
                        .browserCallbackCompletesEnumeration(
                            isSupportedDevice:
                                isSupportedDevice,
                            moreComing: moreComing
                        )
            )
            self.handleAddedDevice(
                device,
                moreComing: moreComing
            )
        }
    }

    func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didRemove device: ICDevice,
        moreGoing: Bool
    ) {
        let callbackToken = browserRunToken
        performOnMain {
            guard self.started,
                  self.browser === browser,
                  let callbackToken,
                  self.browserRunToken == callbackToken
            else {
                return
            }
            self.markBrowserResponsive(
                enumerationComplete: false
            )
            self.handleRemovedDevice(device)
        }
    }

    func deviceBrowserDidEnumerateLocalDevices(
        _ browser: ICDeviceBrowser
    ) {
        let callbackToken = browserRunToken
        performOnMain {
            guard self.started,
                  self.browser === browser,
                  let callbackToken,
                  self.browserRunToken == callbackToken
            else {
                return
            }
            self.markBrowserResponsive(
                enumerationComplete: true
            )
            if self.devices.isEmpty {
                self.phase = .noDevice
            }
        }
    }

    func device(
        _ device: ICDevice,
        didCloseSessionWithError error: (any Error)?
    ) {}

    func didRemove(_ device: ICDevice) {}

    func device(
        _ device: ICDevice,
        didOpenSessionWithError error: (any Error)?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice,
        didAdd items: [ICCameraItem]
    ) {
        performOnMain {
            guard self.canRefreshCatalogFromDelegate(camera) else {
                return
            }
            self.refreshCatalog(for: camera)
        }
    }

    func cameraDevice(
        _ camera: ICCameraDevice,
        didRemove items: [ICCameraItem]
    ) {
        performOnMain {
            guard self.canRefreshCatalogFromDelegate(camera) else {
                return
            }
            self.refreshCatalog(for: camera)
        }
    }

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveThumbnail thumbnail: CGImage?,
        for item: ICCameraItem,
        error: (any Error)?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveMetadata metadata: [AnyHashable: Any]?,
        for item: ICCameraItem,
        error: (any Error)?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice,
        didRenameItems items: [ICCameraItem]
    ) {
        performOnMain {
            guard self.canRefreshCatalogFromDelegate(camera) else {
                return
            }
            self.refreshCatalog(for: camera)
        }
    }

    func cameraDeviceDidChangeCapability(
        _ camera: ICCameraDevice
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceivePTPEvent eventData: Data
    ) {}

    func deviceDidBecomeReady(
        withCompleteContentCatalog device: ICCameraDevice
    ) {
        performOnMain {
            guard self.canRefreshCatalogFromDelegate(device) else {
                return
            }
            self.refreshCatalog(for: device)
        }
    }

    func cameraDeviceDidRemoveAccessRestriction(
        _ device: ICDevice
    ) {
        performOnMain {
            guard let camera = device as? ICCameraDevice else {
                return
            }
            self.reconcileCurrentAccessRestriction(
                for: camera,
                reportedIsRestricted: false
            )
        }
    }

    func cameraDeviceDidEnableAccessRestriction(
        _ device: ICDevice
    ) {
        performOnMain {
            guard let camera = device as? ICCameraDevice else {
                return
            }
            self.reconcileCurrentAccessRestriction(
                for: camera,
                reportedIsRestricted: true
            )
        }
    }

    private func reconcileCurrentAccessRestriction(
        for camera: ICCameraDevice,
        reportedIsRestricted: Bool? = nil
    ) {
        guard started,
              deviceByID[deviceID(for: camera)] === camera
        else {
            return
        }
        let isRestricted =
            IPhonePhotoImportSupport.resolvedAccessRestriction(
                reportedByEvent: reportedIsRestricted,
                deviceProperty:
                    camera.isAccessRestrictedAppleDevice
            )
        let identity = ObjectIdentifier(camera)
        accessRestrictionByDevice[identity] = isRestricted
        if reportedIsRestricted == false {
            accessUnrestrictionEventDateByDevice[identity] = Date()
        } else if reportedIsRestricted != nil {
            accessUnrestrictionEventDateByDevice.removeValue(
                forKey: identity
            )
        }
        guard activeDevice === camera,
              let connectionToken = connectionGate.token,
              connectionGate.accepts(connectionToken)
        else {
            return
        }

        if isRestricted {
            catalogTimer?.invalidate()
            catalogTimer = nil
            resetCatalogProgressObservation()
            stopReadyRestrictionMonitor()
            if importingPhotoID != nil {
                invalidateTransfer()
            }
            photos = []
            thumbnails = [:]
            failedThumbnailIDs = []
            cancelAllThumbnailRequests()
            enterLockedState(
                for: camera,
                connectionToken: connectionToken
            )
        } else {
            stopAccessRestrictionWatcher()
        }
        guard sessionTransitionToken == nil else { return }
        continueConnection(
            to: camera,
            connectionToken: connectionToken
        )
    }

    private func refreshAccessRestriction(
        for device: ICCameraDevice,
        connectionToken: UUID?
    ) {
        guard started,
              activeDevice === device,
              let connectionToken,
              connectionGate.accepts(connectionToken)
        else {
            return
        }

        let identity = ObjectIdentifier(device)
        let cachedState = accessRestrictionByDevice[identity]
        let preservesRecentUnlock =
            cachedState == false
                && IPhonePhotoImportSupport
                    .shouldPreserveRecentUnlockEvent(
                        eventDate:
                            accessUnrestrictionEventDateByDevice[
                                identity
                            ],
                        now: Date(),
                        graceInterval:
                            Self.explicitUnlockGraceInterval
                    )
        if !preservesRecentUnlock {
            accessRestrictionByDevice[identity] =
                device.isAccessRestrictedAppleDevice
            accessUnrestrictionEventDateByDevice.removeValue(
                forKey: identity
            )
        }

        if effectiveIsAccessRestricted(device) {
            enterLockedState(
                for: device,
                connectionToken: connectionToken
            )
        } else {
            stopAccessRestrictionWatcher()
            continueConnection(
                to: device,
                connectionToken: connectionToken
            )
        }
    }

    private func handleAddedDevice(
        _ device: ICDevice,
        moreComing: Bool
    ) {
        guard started else { return }
        guard let camera = device as? ICCameraDevice,
              IPhonePhotoImportSupport.isIPhone(
                  productKind: camera.productKind,
                  name: camera.name
              )
        else {
            if !moreComing, devices.isEmpty {
                phase = .noDevice
            }
            return
        }

        let id = deviceID(for: camera)
        if let previousDevice = deviceByID[id],
           previousDevice !== camera {
            detachCameraDelegate(from: previousDevice)
            accessRestrictionByDevice.removeValue(
                forKey: ObjectIdentifier(previousDevice)
            )
            accessUnrestrictionEventDateByDevice.removeValue(
                forKey: ObjectIdentifier(previousDevice)
            )
        }
        let cameraIdentity = ObjectIdentifier(camera)
        accessRestrictionByDevice[cameraIdentity] =
            camera.isAccessRestrictedAppleDevice
        accessUnrestrictionEventDateByDevice.removeValue(
            forKey: cameraIdentity
        )
        camera.delegate = self
        deviceByID[id] = camera
        let option = ConnectedIPhone(
            id: id,
            name: camera.name ?? "iPhone"
        )
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index] = option
        } else {
            devices.append(option)
            devices.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
        }

        if selectedDeviceID == nil
            || (selectedDeviceID == id && activeDevice !== camera) {
            connect(to: camera, id: id)
        }
    }

    private func handleRemovedDevice(_ device: ICDevice) {
        guard started else { return }
        guard let camera = device as? ICCameraDevice else { return }
        let id = deviceID(for: camera)
        let isCurrentRegisteredDevice = deviceByID[id] === camera
        detachCameraDelegate(from: camera)
        accessRestrictionByDevice.removeValue(
            forKey: ObjectIdentifier(camera)
        )
        accessUnrestrictionEventDateByDevice.removeValue(
            forKey: ObjectIdentifier(camera)
        )
        if isCurrentRegisteredDevice {
            deviceByID.removeValue(forKey: id)
            devices.removeAll { $0.id == id }
        }

        if sessionDevice === camera {
            sessionDevice = nil
        }
        let interruptedTransition =
            sessionTransitionDevice === camera
        if interruptedTransition {
            stopSessionTransitionTimeout()
            sessionTransitionKind = nil
            sessionTransitionToken = nil
            sessionTransitionDevice = nil
            sessionTransitionTimedOut = false
        }

        guard isCurrentRegisteredDevice else {
            if interruptedTransition {
                resumeAfterSessionTransition()
            }
            return
        }
        guard selectedDeviceID == id else {
            if interruptedTransition {
                resumeAfterSessionTransition()
            }
            return
        }
        catalogTimer?.invalidate()
        catalogTimer = nil
        resetCatalogProgressObservation()
        stopAccessRestrictionWatcher()
        stopReadyRestrictionMonitor()
        connectionGate.invalidate()
        invalidateTransfer()
        activeDevice = nil
        selectedDeviceID = nil
        photos = []
        thumbnails = [:]
        failedThumbnailIDs = []
        cancelAllThumbnailRequests()

        if let next = devices.first,
           let nextDevice = deviceByID[next.id] {
            catalogStallRecoveryAttempt = 0
            connect(to: nextDevice, id: next.id)
        } else {
            phase = .noDevice
        }
    }

    private func connect(to device: ICCameraDevice, id: String) {
        guard started else { return }
        catalogTimer?.invalidate()
        catalogTimer = nil
        resetCatalogProgressObservation()
        stopAccessRestrictionWatcher()
        stopReadyRestrictionMonitor()
        connectionGate.invalidate()
        invalidateTransfer()
        let connectionToken = connectionGate.begin()

        activeDevice = device
        selectedDeviceID = id
        photos = []
        thumbnails = [:]
        failedThumbnailIDs = []
        cancelAllThumbnailRequests()
        phase = effectiveIsAccessRestricted(device)
            ? .locked(device.name ?? "iPhone")
            : .connecting(device.name ?? "iPhone")

        continueConnection(
            to: device,
            connectionToken: connectionToken
        )
    }

    private func resumeCurrentConnection() {
        guard started,
              let activeDevice,
              let connectionToken = connectionGate.token
        else {
            return
        }
        if deviceByID[deviceID(for: activeDevice)] === activeDevice {
            activeDevice.delegate = self
        }
        continueConnection(
            to: activeDevice,
            connectionToken: connectionToken
        )
    }

    private func continueConnection(
        to device: ICCameraDevice,
        connectionToken: UUID
    ) {
        guard started,
              connectionGate.accepts(connectionToken),
              activeDevice === device,
              sessionTransitionToken == nil
        else {
            return
        }
        let isAccessRestricted = effectiveIsAccessRestricted(device)
        if !isAccessRestricted {
            stopAccessRestrictionWatcher()
        }

        if let sessionDevice,
           sessionDevice.hasOpenSession {
            if sessionDevice === device,
               !isAccessRestricted {
                startCatalogTimer(for: device)
                refreshCatalog(for: device)
            } else {
                closeSession(
                    for: sessionDevice,
                    connectionToken: connectionToken
                )
            }
            return
        }

        sessionDevice = nil
        if isAccessRestricted {
            enterLockedState(
                for: device,
                connectionToken: connectionToken
            )
            return
        }
        openSession(
            for: device,
            connectionToken: connectionToken
        )
    }

    private func handleStaleSessionCallback(
        for device: ICCameraDevice
    ) {
        if IPhoneSessionCleanupCoordinator.shared.isCleaning(device) {
            return
        }
        let staleDeviceID = deviceID(for: device)
        let matchesCurrentDeviceID =
            selectedDeviceID == staleDeviceID
                || sessionDevice.map {
                    deviceID(for: $0) == staleDeviceID
                } == true
                || sessionTransitionDevice.map {
                    deviceID(for: $0) == staleDeviceID
                } == true
        let shouldClose = IPhonePhotoImportSupport.shouldCloseStaleSession(
            hasOpenSession: device.hasOpenSession,
            isSessionDevice: sessionDevice === device,
            isActiveDevice: activeDevice === device,
            isTransitionDevice: sessionTransitionDevice === device,
            matchesCurrentDeviceID: matchesCurrentDeviceID
        )
        if shouldClose {
            beginTrackedCleanupClose(for: device)
        } else {
            resumeAfterSessionTransition()
        }
    }

    private func startSessionTransitionTimeout(
        kind: IPhoneSessionTransitionKind,
        device: ICCameraDevice,
        transitionToken: UUID
    ) {
        stopSessionTransitionTimeout()
        let timer = Timer(
            timeInterval: Self.sessionTransitionTimeoutInterval,
            repeats: false
        ) { [weak self, device] timer in
            guard let self,
                  self.sessionTransitionKind == kind,
                  self.sessionTransitionToken == transitionToken,
                  self.sessionTransitionDevice === device
            else {
                timer.invalidate()
                return
            }
            self.stopSessionTransitionTimeout()
            self.sessionTransitionTimedOut = true
            if self.recoverTimedOutSessionTransitionIfPossible() {
                return
            }
            self.stopBrowserEnumerationTimeout()
            if self.started {
                self.phase = .failed(
                    self.sessionTransitionRecoveryMessage
                )
            }
        }
        timer.tolerance = 0.25
        sessionTransitionTimeoutTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSessionTransitionTimeout() {
        sessionTransitionTimeoutTimer?.invalidate()
        sessionTransitionTimeoutTimer = nil
    }

    private func resumeAfterSessionTransition() {
        let hasActiveConnection =
            activeDevice != nil && connectionGate.token != nil
        if hasActiveConnection {
            resumeCurrentConnection()
            return
        }
        if pendingBrowserStartToken != nil {
            schedulePendingBrowserStart(
                after: Self.sessionCloseSettleDelay
            )
            return
        }
        if IPhonePhotoImportSupport
            .shouldRequestBrowserAfterTransition(
                started: started,
                hasActiveConnection: hasActiveConnection,
                hasPendingBrowserStart:
                    pendingBrowserStartToken != nil,
                browserAlreadyRunning: browserRunToken != nil
            ) {
            phase = .searching
            requestBrowserStart(
                after: Self.sessionCloseSettleDelay
            )
        }
    }

    private var sessionTransitionRecoveryMessage: String {
        let operation = sessionTransitionKind == .closing
            ? "Schließen"
            : "Öffnen"
        return "Das iPhone hat den Abschluss beim \(operation) der Foto-Verbindung noch nicht bestätigt. Tippe nach kurzer Wartezeit auf „Erneut versuchen“. Falls das nicht hilft, trenne das USB-Kabel kurz, verbinde es erneut und entsperre das iPhone."
    }

    @discardableResult
    private func recoverTimedOutSessionTransitionIfPossible()
        -> Bool {
        guard sessionTransitionTimedOut,
              let kind = sessionTransitionKind,
              let device = sessionTransitionDevice,
              sessionTransitionToken != nil
        else {
            return false
        }

        let decision =
            IPhonePhotoImportSupport
                .sessionTransitionRecoveryDecision(
                    isOpening: kind == .opening,
                    hasOpenSession: device.hasOpenSession
                )
        guard decision == .settled else {
            return false
        }

        stopSessionTransitionTimeout()
        sessionTransitionKind = nil
        sessionTransitionToken = nil
        sessionTransitionDevice = nil
        sessionTransitionTimedOut = false

        switch kind {
        case .opening:
            if started,
               activeDevice === device,
               let connectionToken = connectionGate.token,
               connectionGate.accepts(connectionToken) {
                sessionDevice = device
                startCatalogTimer(for: device)
                refreshCatalog(for: device)
            } else {
                sessionDevice = nil
                if device.hasOpenSession {
                    beginTrackedCleanupClose(for: device)
                }
                if started {
                    phase = .searching
                    requestBrowserStart(
                        after: Self.sessionCloseSettleDelay
                    )
                }
            }
        case .closing:
            if sessionDevice === device {
                sessionDevice = nil
            }
            if started {
                resumeAfterSessionTransition()
            }
        }
        return true
    }

    private func closeSession(
        for device: ICCameraDevice,
        connectionToken: UUID
    ) {
        let transitionToken = UUID()
        sessionTransitionKind = .closing
        sessionTransitionToken = transitionToken
        sessionTransitionDevice = device
        sessionTransitionTimedOut = false
        startSessionTransitionTimeout(
            kind: .closing,
            device: device,
            transitionToken: transitionToken
        )
        device.requestCloseSession(options: nil) {
            [weak self, device] _ in
            DispatchQueue.main.async {
                guard let self else {
                    IPhoneSessionCleanupCoordinator.shared
                        .resolveOrphanedTransition(
                            for: device,
                            transitionToken: transitionToken
                        )
                    return
                }
                guard self.sessionTransitionKind == .closing,
                      self.sessionTransitionToken == transitionToken,
                      self.sessionTransitionDevice === device
                else {
                    IPhoneSessionCleanupCoordinator.shared
                        .resolveOrphanedTransition(
                            for: device,
                            transitionToken: transitionToken
                        )
                    self.handleStaleSessionCallback(for: device)
                    return
                }
                self.stopSessionTransitionTimeout()
                self.sessionTransitionKind = nil
                self.sessionTransitionToken = nil
                self.sessionTransitionDevice = nil
                self.sessionTransitionTimedOut = false
                if device.hasOpenSession {
                    self.sessionDevice = nil
                    self.beginTrackedCleanupClose(for: device)
                    return
                }
                if self.sessionDevice === device {
                    self.sessionDevice = nil
                }
                self.resumeAfterSessionTransition()
            }
        }
    }

    private func openSession(
        for device: ICCameraDevice,
        connectionToken: UUID
    ) {
        guard sessionTransitionToken == nil else { return }
        if device.hasOpenSession {
            sessionDevice = device
            startCatalogTimer(for: device)
            refreshCatalog(for: device)
            return
        }

        let transitionToken = UUID()
        sessionTransitionKind = .opening
        sessionTransitionToken = transitionToken
        sessionTransitionDevice = device
        sessionTransitionTimedOut = false
        phase = .connecting(device.name ?? "iPhone")
        startSessionTransitionTimeout(
            kind: .opening,
            device: device,
            transitionToken: transitionToken
        )
        device.requestOpenSession(options: nil) {
            [weak self, device] error in
            DispatchQueue.main.async {
                guard let self else {
                    IPhoneSessionCleanupCoordinator.shared
                        .resolveOrphanedTransition(
                            for: device,
                            transitionToken: transitionToken
                        )
                    return
                }
                guard self.sessionTransitionKind == .opening,
                      self.sessionTransitionToken == transitionToken,
                      self.sessionTransitionDevice === device
                else {
                    IPhoneSessionCleanupCoordinator.shared
                        .resolveOrphanedTransition(
                            for: device,
                            transitionToken: transitionToken
                        )
                    self.handleStaleSessionCallback(for: device)
                    return
                }
                self.stopSessionTransitionTimeout()
                self.sessionTransitionKind = nil
                self.sessionTransitionToken = nil
                self.sessionTransitionDevice = nil
                self.sessionTransitionTimedOut = false

                if let error {
                    if self.started,
                       self.connectionGate.accepts(connectionToken),
                       self.activeDevice === device {
                        if device.hasOpenSession {
                            self.sessionDevice = device
                            self.startCatalogTimer(for: device)
                            self.refreshCatalog(for: device)
                        } else if self.effectiveIsAccessRestricted(device) {
                            self.enterLockedState(
                                for: device,
                                connectionToken: connectionToken
                            )
                        } else {
                            self.phase = .failed(
                                "Die Verbindung zu \(device.name ?? "dem iPhone") konnte nicht geöffnet werden: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        self.handleStaleSessionCallback(for: device)
                    }
                    return
                }

                guard self.started else {
                    self.sessionDevice = nil
                    if device.hasOpenSession {
                        self.beginTrackedCleanupClose(for: device)
                    }
                    return
                }

                if self.connectionGate.accepts(connectionToken),
                   self.activeDevice === device {
                    self.sessionDevice = device
                    self.startCatalogTimer(for: device)
                    self.refreshCatalog(for: device)
                } else {
                    if self.sessionDevice === device {
                        self.sessionDevice = nil
                    }
                    self.handleStaleSessionCallback(for: device)
                }
            }
        }
    }

    private func startCatalogTimer(for device: ICCameraDevice) {
        stopAccessRestrictionWatcher()
        stopReadyRestrictionMonitor()
        catalogTimer?.invalidate()
        beginCatalogProgressObservation(for: device)
        let timer = Timer(
            timeInterval: 1,
            repeats: true
        ) { [weak self, weak device] _ in
            guard let self,
                  let device,
                  self.activeDevice === device
            else {
                return
            }
            self.refreshCatalog(for: device)
        }
        timer.tolerance = 0.2
        catalogTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshCatalog(for device: ICCameraDevice) {
        guard activeDevice === device else { return }
        let deviceName = device.name ?? "iPhone"
        if effectiveIsAccessRestricted(device) {
            catalogTimer?.invalidate()
            catalogTimer = nil
            resetCatalogProgressObservation()
            photos = []
            if let connectionToken = connectionGate.token {
                enterLockedState(
                    for: device,
                    connectionToken: connectionToken
                )
            } else {
                phase = .locked(deviceName)
            }
            return
        }

        let progress = min(
            max(Int(device.contentCatalogPercentCompleted), 0),
            100
        )
        guard progress >= 100 else {
            if catalogProgressHasStalled(
                for: device,
                progress: progress
            ) {
                handleCatalogStall(for: device)
                return
            }
            phase = .loading(deviceName, progress)
            return
        }

        catalogTimer?.invalidate()
        catalogTimer = nil
        catalogStallRecoveryAttempt = 0
        resetCatalogProgressObservation()
        let currentPhotos = (device.mediaFiles ?? [])
            .compactMap { $0 as? ICCameraFile }
            .filter {
                IPhonePhotoImportSupport.isImage(
                    uti: $0.uti,
                    filename: $0.originalFilename ?? $0.name ?? ""
                )
            }
            .map {
                photoItem(
                    from: $0,
                    deviceID: selectedDeviceID ?? deviceID(for: device)
                )
            }
            .sorted {
                let firstDate = $0.creationDate ?? .distantPast
                let secondDate = $1.creationDate ?? .distantPast
                if firstDate != secondDate {
                    return firstDate > secondDate
                }
                return $0.filename.localizedCaseInsensitiveCompare(
                    $1.filename
                ) == .orderedAscending
            }

        photos = currentPhotos
        phase = .ready(deviceName)
        if let connectionToken = connectionGate.token {
            startReadyRestrictionMonitor(
                for: device,
                connectionToken: connectionToken
            )
        }
    }

    private func beginCatalogProgressObservation(
        for device: ICCameraDevice
    ) {
        let identifier = ObjectIdentifier(device)
        guard catalogProgressDeviceID != identifier else {
            return
        }
        catalogProgressDeviceID = identifier
        catalogLastProgress = min(
            max(Int(device.contentCatalogPercentCompleted), 0),
            100
        )
        catalogLastProgressDate = Date()
    }

    private func resetCatalogProgressObservation() {
        catalogProgressDeviceID = nil
        catalogLastProgress = 0
        catalogLastProgressDate = Date()
    }

    private func catalogProgressHasStalled(
        for device: ICCameraDevice,
        progress: Int,
        now: Date = Date()
    ) -> Bool {
        let identifier = ObjectIdentifier(device)
        if catalogProgressDeviceID != identifier {
            catalogProgressDeviceID = identifier
            catalogLastProgress = progress
            catalogLastProgressDate = now
            return false
        }
        if progress != catalogLastProgress {
            catalogLastProgress = progress
            catalogLastProgressDate = now
            return false
        }
        return IPhonePhotoImportSupport.hasTimedOut(
            since: catalogLastProgressDate,
            now: now,
            timeout: Self.catalogStallTimeoutInterval
        )
    }

    private func handleCatalogStall(
        for device: ICCameraDevice
    ) {
        guard started,
              activeDevice === device,
              sessionTransitionToken == nil
        else {
            return
        }
        catalogTimer?.invalidate()
        catalogTimer = nil
        resetCatalogProgressObservation()
        switch IPhonePhotoImportSupport.browserEnumerationTimeoutDecision(
            completedRecoveries: catalogStallRecoveryAttempt,
            maximumRecoveries: Self.maximumCatalogStallRecoveries
        ) {
        case let .retry(nextAttempt):
            if restartWithFreshBrowserSnapshot(
                resetCatalogStallRecoveryAttempts: false,
                startDelay: Self.browserReplacementSettleDelay
            ) {
                catalogStallRecoveryAttempt = nextAttempt
            } else {
                phase = .failed(
                    "Die iPhone-Fotomediathek lädt nicht weiter. Mit „Erneut versuchen“ wird die Verbindung neu aufgebaut."
                )
            }
        case .fail:
            phase = .failed(
                "Die iPhone-Fotomediathek lädt nicht weiter. Entsperre das iPhone, bestätige den Zugriff und versuche es erneut."
            )
        }
    }

    private func enterLockedState(
        for device: ICCameraDevice,
        connectionToken: UUID
    ) {
        guard started,
              connectionGate.accepts(connectionToken),
              activeDevice === device
        else {
            return
        }
        phase = .locked(device.name ?? "iPhone")
        startAccessRestrictionWatcher(
            for: device,
            connectionToken: connectionToken
        )
    }

    private func startAccessRestrictionWatcher(
        for device: ICCameraDevice,
        connectionToken: UUID
    ) {
        stopAccessRestrictionWatcher()
        let watchToken = UUID()
        accessRestrictionWatchToken = watchToken
        let timer = Timer(
            timeInterval: 1,
            repeats: true
        ) {
            [weak self, weak device] timer in
            guard let self,
                  let device
            else {
                timer.invalidate()
                return
            }
            guard self.accessRestrictionWatchToken == watchToken else {
                timer.invalidate()
                return
            }
            guard self.started,
                  self.connectionGate.accepts(connectionToken),
                  self.activeDevice === device,
                  self.selectedDeviceID == self.deviceID(for: device)
            else {
                self.stopAccessRestrictionWatcher(
                    expected: watchToken
                )
                return
            }
            guard self.sessionTransitionToken == nil,
                  !self.effectiveIsAccessRestricted(device)
            else {
                return
            }
            self.stopAccessRestrictionWatcher(expected: watchToken)
            self.continueConnection(
                to: device,
                connectionToken: connectionToken
            )
        }
        timer.tolerance = 0.2
        accessRestrictionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAccessRestrictionWatcher(
        expected watchToken: UUID? = nil
    ) {
        if let watchToken,
           accessRestrictionWatchToken != watchToken {
            return
        }
        accessRestrictionTimer?.invalidate()
        accessRestrictionTimer = nil
        accessRestrictionWatchToken = nil
    }

    private func startReadyRestrictionMonitor(
        for device: ICCameraDevice,
        connectionToken: UUID
    ) {
        stopReadyRestrictionMonitor()
        let watchToken = UUID()
        readyRestrictionWatchToken = watchToken
        let timer = Timer(
            timeInterval: 1,
            repeats: true
        ) {
            [weak self, weak device] timer in
            guard let self,
                  let device
            else {
                timer.invalidate()
                return
            }
            guard self.readyRestrictionWatchToken == watchToken else {
                timer.invalidate()
                return
            }
            guard self.started,
                  self.connectionGate.accepts(connectionToken),
                  self.activeDevice === device,
                  self.selectedDeviceID == self.deviceID(for: device)
            else {
                self.stopReadyRestrictionMonitor(
                    expected: watchToken
                )
                return
            }
            guard self.sessionTransitionToken == nil,
                  self.importingPhotoID == nil
            else {
                return
            }

            if self.effectiveIsAccessRestricted(device) {
                self.stopReadyRestrictionMonitor(
                    expected: watchToken
                )
                self.photos = []
                self.thumbnails = [:]
                self.failedThumbnailIDs = []
                self.cancelAllThumbnailRequests()
                self.enterLockedState(
                    for: device,
                    connectionToken: connectionToken
                )
                self.continueConnection(
                    to: device,
                    connectionToken: connectionToken
                )
            } else if self.sessionDevice !== device
                        || !device.hasOpenSession {
                self.stopReadyRestrictionMonitor(
                    expected: watchToken
                )
                self.continueConnection(
                    to: device,
                    connectionToken: connectionToken
                )
            }
        }
        timer.tolerance = 0.2
        readyRestrictionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopReadyRestrictionMonitor(
        expected watchToken: UUID? = nil
    ) {
        if let watchToken,
           readyRestrictionWatchToken != watchToken {
            return
        }
        readyRestrictionTimer?.invalidate()
        readyRestrictionTimer = nil
        readyRestrictionWatchToken = nil
    }

    private func effectiveIsAccessRestricted(
        _ device: ICCameraDevice
    ) -> Bool {
        accessRestrictionByDevice[ObjectIdentifier(device)]
            ?? device.isAccessRestrictedAppleDevice
    }

    private func canRefreshCatalogFromDelegate(
        _ device: ICCameraDevice
    ) -> Bool {
        started
            && activeDevice === device
            && sessionTransitionToken == nil
            && sessionDevice === device
            && device.hasOpenSession
            && !effectiveIsAccessRestricted(device)
    }

    private func detachCameraDelegate(
        from device: ICCameraDevice
    ) {
        if device.delegate === self {
            device.delegate = nil
        }
    }

    private func detachAllCameraDelegates() {
        var detachedDeviceIDs: Set<ObjectIdentifier> = []
        func detach(_ device: ICCameraDevice?) {
            guard let device else { return }
            let id = ObjectIdentifier(device)
            guard detachedDeviceIDs.insert(id).inserted else { return }
            detachCameraDelegate(from: device)
        }
        for device in deviceByID.values {
            detach(device)
        }
        detach(activeDevice)
        detach(sessionDevice)
        detach(sessionTransitionDevice)
    }

    private func photoItem(
        from file: ICCameraFile,
        deviceID: String
    ) -> IPhonePhotoItem {
        let filename =
            file.originalFilename
                ?? file.name
                ?? "iPhone-Foto"
        let handle = file.ptpObjectHandle
        let fallbackID = UInt(bitPattern: ObjectIdentifier(file))
        let itemID = handle == 0
            ? "\(deviceID)-object-\(fallbackID)"
            : "\(deviceID)-ptp-\(handle)"
        return IPhonePhotoItem(
            id: itemID,
            filename: filename,
            creationDate: file.creationDate,
            byteCount: max(Int64(file.fileSize), 0),
            width: max(file.width, 0),
            height: max(file.height, 0),
            file: file
        )
    }

    private func deviceID(for device: ICCameraDevice) -> String {
        if let uuid = device.uuidString,
           !uuid.isEmpty {
            return uuid
        }
        return "iphone-\(UInt(bitPattern: ObjectIdentifier(device)))"
    }

    private func invalidateTransfer() {
        let hadTransfer =
            importingPhotoID != nil
                || transferTemporaryDirectory != nil
                || transferProgress != nil
                || transferGate.token != nil
        stopTransferTimeout()
        transferGate.invalidate()
        importingPhotoID = nil
        transferProgress?.cancel()
        transferProgress = nil
        if hadTransfer {
            activeDevice?.cancelDownload()
        }
        removeTransferTemporaryDirectory()
    }

    private func removeTransferTemporaryDirectory() {
        guard let directory = transferTemporaryDirectory else {
            return
        }
        transferTemporaryDirectory = nil
        Self.scheduleTemporaryDirectoryRemoval(
            directory,
            initialDelay: 0.25
        )
    }

    private static func scheduleTemporaryDirectoryRemoval(
        _ directory: URL,
        initialDelay: TimeInterval
    ) {
        let retryDelays: [TimeInterval] = [
            initialDelay,
            max(initialDelay, 0.75),
            2,
            5,
            10,
            30,
            60,
        ]
        for delay in retryDelays {
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + delay
            ) {
                try? FileManager.default.removeItem(
                    at: directory
                )
            }
        }
    }

    private static func cleanUpStaleTemporaryDirectories() {
        let root = FileManager.default.temporaryDirectory
        DispatchQueue.global(qos: .utility).async {
            let resourceKeys: Set<URLResourceKey> = [
                .contentModificationDateKey,
                .isDirectoryKey,
            ]
            guard let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                return
            }
            let expirationDate = Date().addingTimeInterval(-24 * 60 * 60)
            for directory in directories
            where directory.lastPathComponent.hasPrefix(
                "Freundeblick-iPhone-"
            ) {
                guard let values = try? directory.resourceValues(
                    forKeys: resourceKeys
                ),
                      values.isDirectory == true,
                      let modified = values.contentModificationDate,
                      modified < expirationDate
                else {
                    continue
                }
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}

struct ProfileIPhoneImportView: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (IPhoneImportedPhoto) throws -> Void

    @ObservedObject private var controller: IPhonePhotoImportController
    @State private var selectedPhotoID: String?
    @State private var photoSearch = ""
    @State private var errorMessage: String?

    init(
        controller: IPhonePhotoImportController,
        onImport: @escaping (IPhoneImportedPhoto) throws -> Void
    ) {
        self.controller = controller
        self.onImport = onImport
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            deviceBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 820, height: 650)
        .onAppear {
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.photos.map(\.id)) { _, photoIDs in
            if let selectedPhotoID,
               !photoIDs.contains(selectedPhotoID) {
                self.selectedPhotoID = nil
            }
        }
        .onChange(of: photoSearch) { _, _ in
            if let selectedPhotoID,
               !visiblePhotos.contains(where: {
                   $0.id == selectedPhotoID
               }) {
                self.selectedPhotoID = nil
            }
        }
        .alert(
            "iPhone-Foto konnte nicht importiert werden",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.berryText)
                .frame(width: 42, height: 42)
                .background(
                    AppTheme.berry.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 13)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Vom iPhone importieren")
                    .font(.title2.weight(.bold))
                Text("Vorhandenes Foto auswählen und anschließend zuschneiden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abbrechen") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    @ViewBuilder
    private var deviceBar: some View {
        HStack(spacing: 12) {
            if controller.devices.count > 1 {
                Picker(
                    "iPhone",
                    selection: Binding(
                        get: { controller.selectedDeviceID ?? "" },
                        set: controller.selectDevice(id:)
                    )
                ) {
                    ForEach(controller.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .frame(maxWidth: 300)
                .disabled(controller.importingPhotoID != nil)
            } else if let device = controller.devices.first {
                Label(device.name, systemImage: "iphone")
                    .font(.callout.weight(.semibold))
            } else {
                Label("Kein iPhone verbunden", systemImage: "iphone.slash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !controller.photos.isEmpty {
                TextField("Dateiname suchen", text: $photoSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Text(photoCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                controller.refresh()
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(controller.importingPhotoID != nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if controller.photos.isEmpty {
            emptyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if case let .loading(name, progress) = controller.phase {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(progress), total: 100)
                            .frame(maxWidth: 220)
                        Text("\(name) wird geladen · \(progress) %")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                ScrollView {
                    if visiblePhotos.isEmpty {
                        ContentUnavailableView(
                            "Keine passenden Fotos",
                            systemImage: "photo.badge.magnifyingglass",
                            description: Text(
                                "Prüfe den eingegebenen Dateinamen."
                            )
                        )
                        .padding(40)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: 145),
                                    spacing: 14
                                ),
                            ],
                            spacing: 14
                        ) {
                            ForEach(visiblePhotos) { item in
                                photoCard(item)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch controller.phase {
        case .idle, .searching:
            statusView(
                symbol: "iphone",
                title: "iPhone wird gesucht …",
                message: connectionInstructions,
                showsProgress: true
            )
        case .noDevice:
            statusView(
                symbol: "iphone.slash",
                title: "Kein iPhone gefunden",
                message: connectionInstructions,
                actionTitle: "Erneut suchen",
                action: controller.restart,
                secondaryActionTitle: "Dateien-&-Ordner-Einstellungen öffnen",
                secondaryAction: openRemovableVolumesPrivacySettings
            )
        case let .connecting(name):
            statusView(
                symbol: "cable.connector",
                title: "Verbindung zu \(name) …",
                message: "Lass das iPhone entsperrt und bestätige dort bei Bedarf „Diesem Computer vertrauen“.",
                showsProgress: true
            )
        case let .locked(name):
            statusView(
                symbol: "lock.iphone",
                title: "\(name) wartet auf Freigabe",
                message: "Halte das iPhone entsperrt. Bestätige dort bei Bedarf „Diesem Computer vertrauen“. Freundeblick fährt danach automatisch fort; mit Aktualisieren kannst du sofort erneut prüfen.",
                actionTitle: "Aktualisieren",
                action: controller.refresh
            )
        case let .loading(name, progress):
            statusView(
                symbol: "photo.stack",
                title: "Fotos von \(name) werden geladen",
                message: "\(progress) % · Bei einer großen Mediathek kann das kurz dauern.",
                showsProgress: true
            )
        case let .ready(name):
            statusView(
                symbol: "photo.badge.exclamationmark",
                title: "Keine Fotos auf \(name) verfügbar",
                message: "Nur Fotos, die auf dem iPhone lokal verfügbar sind, können per Kabel importiert werden. Bei aktiviertem „iPhone-Speicher optimieren“ können iCloud-Originale fehlen.",
                actionTitle: "Aktualisieren",
                action: controller.refresh
            )
        case let .failed(message):
            statusView(
                symbol: "exclamationmark.triangle.fill",
                title: "iPhone konnte nicht geöffnet werden",
                message: message,
                actionTitle: "Erneut versuchen",
                action: controller.restart,
                secondaryActionTitle: "Dateien-&-Ordner-Einstellungen öffnen",
                secondaryAction: openRemovableVolumesPrivacySettings
            )
        }
    }

    private func statusView(
        symbol: String,
        title: String,
        message: String,
        showsProgress: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.berryText)
                }
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(message)")
            .accessibilityAddTraits(.updatesFrequently)

            HStack {
                if let actionTitle,
                   let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.berry)
                }
                if let secondaryActionTitle,
                   let secondaryAction {
                    Button(
                        secondaryActionTitle,
                        action: secondaryAction
                    )
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(32)
    }

    private func photoCard(_ item: IPhonePhotoItem) -> some View {
        let selected = selectedPhotoID == item.id
        return Button {
            if controller.failedThumbnailIDs.contains(item.id) {
                controller.requestThumbnail(for: item)
            }
            guard !item.isTooLarge else {
                errorMessage =
                    IPhonePhotoImportError.imageTooLarge.localizedDescription
                return
            }
            selectedPhotoID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.07))
                    if let thumbnail = controller.thumbnail(for: item) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else if controller.failedThumbnailIDs.contains(
                        item.id
                    ) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, AppTheme.berry)
                            .padding(8)
                    }
                }

                Text(item.filename)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(photoDetails(item))
                    .font(.caption2)
                    .foregroundStyle(
                        item.isTooLarge ? .red : .secondary
                    )
                    .lineLimit(1)
            }
            .padding(9)
            .background(
                selected
                    ? AppTheme.berry.opacity(0.11)
                    : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        selected ? AppTheme.berry : Color.clear,
                        lineWidth: 2
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.importingPhotoID != nil)
        .onAppear {
            controller.requestThumbnail(for: item)
        }
        .accessibilityLabel(
            "\(item.filename), \(photoDetails(item))"
        )
        .accessibilityValue(
            selected ? "Ausgewählt" : "Nicht ausgewählt"
        )
        .accessibilityAddTraits(
            selected ? .isSelected : []
        )
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Das Original bleibt auf deinem iPhone.")
                    .font(.caption.weight(.semibold))
                Text("Freundeblick speichert erst nach dem Zuschneiden nur das quadratische Profilbild.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                importSelection()
            } label: {
                if controller.importingPhotoID != nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Foto wird geladen …")
                    }
                } else {
                    Label(
                        "Ausgewähltes Foto übernehmen",
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.berry)
            .controlSize(.large)
            .disabled(
                selectedPhotoID == nil
                    || !visiblePhotos.contains(where: {
                        $0.id == selectedPhotoID
                    })
                    || controller.importingPhotoID != nil
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var connectionInstructions: String {
        "Verbinde dein iPhone per USB-Kabel, entsperre es und bestätige auf dem iPhone „Diesem Computer vertrauen“. Schließe „Digitale Bilder“ oder „Fotos“, falls eine dieser Apps das iPhone bereits verwendet. Falls es weiterhin fehlt, erlaube Freundeblick unter Datenschutz & Sicherheit → Fotos den Zugriff."
    }

    private var visiblePhotos: [IPhonePhotoItem] {
        let query = photoSearch
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return controller.photos
        }
        return controller.photos.filter {
            $0.filename.localizedCaseInsensitiveContains(query)
        }
    }

    private var photoCountLabel: String {
        let count = visiblePhotos.count
        return count == 1 ? "1 Foto" : "\(count) Fotos"
    }

    private func photoDetails(_ item: IPhonePhotoItem) -> String {
        if item.isTooLarge {
            return "Für den Profilbild-Import zu groß"
        }
        let date = item.creationDate?.formatted(
            date: .abbreviated,
            time: .omitted
        )
        let dimensions = item.width > 0 && item.height > 0
            ? "\(item.width) × \(item.height)"
            : nil
        return [date, dimensions]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func importSelection() {
        guard let selectedPhotoID,
              visiblePhotos.contains(where: {
                  $0.id == selectedPhotoID
              })
        else {
            return
        }
        controller.importPhoto(id: selectedPhotoID) { result in
            switch result {
            case let .success(photo):
                do {
                    try onImport(photo)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openRemovableVolumesPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
