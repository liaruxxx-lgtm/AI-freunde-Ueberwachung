import AVFoundation
import AppKit
import SwiftUI

enum ProfileCameraKind: String, CaseIterable, Identifiable {
    case mac
    case iPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mac:
            "Mac-Kamera"
        case .iPhone:
            "iPhone-Kamera"
        }
    }

    var symbolName: String {
        switch self {
        case .mac:
            "laptopcomputer"
        case .iPhone:
            "iphone"
        }
    }
}

private struct ProfileCameraOption: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: ProfileCameraKind

    var displayName: String {
        "\(name) · \(kind == .iPhone ? "iPhone" : "Mac")"
    }
}

private enum ProfileCameraStatus: Equatable {
    case idle
    case needsPermission
    case requestingPermission
    case denied
    case restricted
    case searching
    case ready
    case noCamera(ProfileCameraKind)
    case capturing
    case failed(String)
}

private enum ProfileCameraCaptureError: LocalizedError {
    case unavailable
    case inputUnavailable
    case outputUnavailable
    case connectionUnavailable
    case interrupted
    case noPhotoData

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Die Kamera ist nicht mehr verfügbar."
        case .inputUnavailable:
            "Die ausgewählte Kamera konnte nicht geöffnet werden. Sie wird möglicherweise von einer anderen App verwendet."
        case .outputUnavailable:
            "Die Fotoaufnahme konnte nicht vorbereitet werden."
        case .connectionUnavailable:
            "Die Kameraverbindung ist nicht mehr aktiv. Suche die Kamera erneut."
        case .interrupted:
            "Die Kameraverbindung wurde unterbrochen."
        case .noPhotoData:
            "Die Kamera hat kein lesbares Foto geliefert."
        }
    }
}

private final class ProfileCameraCaptureController:
    NSObject,
    ObservableObject,
    AVCapturePhotoCaptureDelegate
{
    let session = AVCaptureSession()

    @Published private(set) var status: ProfileCameraStatus = .idle
    @Published private(set) var cameras: [ProfileCameraOption] = []
    @Published private(set) var selectedCameraID: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(
        label: "local.elias.freundeblick.profile-camera"
    )
    private let captureResultLock = NSLock()

    private var currentInput: AVCaptureDeviceInput?
    private var preferredKind: ProfileCameraKind = .mac
    private var configurationGeneration = 0
    private var isActive = false
    private var observers: [NSObjectProtocol] = []
    private var captureCompletion: (
        token: UUID,
        handler: (Result<Data, Error>) -> Void
    )?
    private var activeCaptureToken: UUID?
    private var activeCaptureSettingsID: Int64?
    private var pendingCaptureResult: Result<Data, Error>?
    private var pendingRefreshAfterCapture = false
    private var expectedSessionStops = 0
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationDevice: AVCaptureDevice?
    private var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    private var captureRotationAngle: CGFloat = 0

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: AVCaptureDevice.wasConnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice,
                      device.hasMediaType(.video)
                else {
                    return
                }
                self?.refresh()
            },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice,
                      device.hasMediaType(.video)
                else {
                    return
                }
                self?.refresh()
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                let message = (
                    notification.userInfo?[AVCaptureSessionErrorKey]
                        as? Error
                )?.localizedDescription
                    ?? "Die Kamera hat einen Laufzeitfehler gemeldet."
                self?.handleSessionFailure(message)
            },
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.handleSessionFailure(
                    ProfileCameraCaptureError.interrupted.localizedDescription
                )
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            },
            center.addObserver(
                forName: AVCaptureSession.didStopRunningNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                guard let self,
                      !self.consumeExpectedSessionStop()
                else {
                    return
                }
                self.handleSessionFailure(
                    "Die Kamera wurde angehalten. Suche sie erneut."
                )
            },
        ]
    }

    deinit {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func start(preferredKind: ProfileCameraKind) {
        captureResultLock.lock()
        isActive = true
        captureResultLock.unlock()
        self.preferredKind = preferredKind
        updateAuthorizationState()
    }

    func stop() {
        captureResultLock.lock()
        isActive = false
        activeCaptureToken = nil
        activeCaptureSettingsID = nil
        pendingCaptureResult = nil
        captureResultLock.unlock()
        configurationGeneration += 1
        captureCompletion = nil
        pendingRefreshAfterCapture = false
        rotationObservations.removeAll()
        rotationCoordinator = nil
        rotationDevice = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.markExpectedSessionStop()
                self.session.stopRunning()
            }
        }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        guard previewLayer !== layer else { return }
        previewLayer = layer
        installRotationCoordinator()
    }

    func requestPermission() {
        status = .requestingPermission
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.controllerIsActive else { return }
                if granted {
                    self.refresh()
                } else {
                    self.status = .denied
                }
            }
        }
    }

    func selectKind(_ kind: ProfileCameraKind) {
        guard status != .capturing else {
            pendingRefreshAfterCapture = true
            return
        }
        preferredKind = kind
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        else {
            updateAuthorizationState()
            return
        }
        refresh()
    }

    func selectCamera(id: String) {
        guard status != .capturing else {
            pendingRefreshAfterCapture = true
            return
        }
        guard let option = cameras.first(where: { $0.id == id }),
              let device = discoveredDevices().first(where: {
                  $0.uniqueID == option.id
              })
        else {
            status = .noCamera(preferredKind)
            return
        }
        preferredKind = option.kind
        configure(device)
    }

    func refresh() {
        guard controllerIsActive else { return }
        guard status != .capturing else {
            pendingRefreshAfterCapture = true
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        else {
            updateAuthorizationState()
            return
        }

        status = .searching
        let devices = discoveredDevices()
        cameras = devices.map {
            ProfileCameraOption(
                id: $0.uniqueID,
                name: $0.localizedName,
                kind: $0.isContinuityCamera ? .iPhone : .mac
            )
        }

        let matching = devices.filter {
            ($0.isContinuityCamera ? ProfileCameraKind.iPhone : .mac)
                == preferredKind
        }
        let preferredDevice = AVCaptureDevice.systemPreferredCamera.flatMap {
            systemCamera in
            matching.first { $0.uniqueID == systemCamera.uniqueID }
        }
        let existingDevice = selectedCameraID.flatMap { selectedID in
            matching.first { $0.uniqueID == selectedID }
        }
        guard let selected =
            existingDevice ?? preferredDevice ?? matching.first
        else {
            selectedCameraID = nil
            rotationDevice = nil
            installRotationCoordinator()
            status = .noCamera(preferredKind)
            stopSessionWithoutChangingStatus()
            return
        }
        configure(selected)
    }

    func capture(
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard status == .ready,
              selectedCameraID != nil,
              controllerIsActive
        else {
            completion(.failure(ProfileCameraCaptureError.unavailable))
            return
        }

        let token = UUID()
        captureResultLock.lock()
        guard activeCaptureToken == nil else {
            captureResultLock.unlock()
            completion(.failure(ProfileCameraCaptureError.unavailable))
            return
        }
        activeCaptureToken = token
        activeCaptureSettingsID = nil
        pendingCaptureResult = nil
        captureResultLock.unlock()

        status = .capturing
        captureCompletion = (token, completion)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
                )
            } else {
                settings = AVCapturePhotoSettings()
            }

            self.captureResultLock.lock()
            let isCurrentCapture =
                self.isActive && self.activeCaptureToken == token
            self.captureResultLock.unlock()
            guard isCurrentCapture,
                  self.session.isRunning,
                  let connection = self.photoOutput.connection(
                      with: .video
                  ),
                  connection.isEnabled,
                  connection.isActive
            else {
                DispatchQueue.main.async {
                    self.pendingRefreshAfterCapture = true
                    self.finishCapture(
                        token: token,
                        result: .failure(
                            ProfileCameraCaptureError.connectionUnavailable
                        )
                    )
                }
                return
            }
            if connection.isVideoRotationAngleSupported(
                self.captureRotationAngle
            ) {
                connection.videoRotationAngle =
                    self.captureRotationAngle
            }

            self.captureResultLock.lock()
            guard self.isActive,
                  self.activeCaptureToken == token
            else {
                self.captureResultLock.unlock()
                return
            }
            self.activeCaptureSettingsID = settings.uniqueID
            self.captureResultLock.unlock()

            self.photoOutput.capturePhoto(
                with: settings,
                delegate: self
            )
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(),
                  !data.isEmpty {
            result = .success(data)
        } else {
            result = .failure(ProfileCameraCaptureError.noPhotoData)
        }

        captureResultLock.lock()
        if isActive,
           activeCaptureToken != nil,
           activeCaptureSettingsID == photo.resolvedSettings.uniqueID {
            pendingCaptureResult = result
        }
        captureResultLock.unlock()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        captureResultLock.lock()
        guard let token = activeCaptureToken,
              activeCaptureSettingsID == resolvedSettings.uniqueID
        else {
            captureResultLock.unlock()
            return
        }
        let result = pendingCaptureResult
            ?? error.map { .failure($0) }
            ?? .failure(ProfileCameraCaptureError.noPhotoData)
        activeCaptureSettingsID = nil
        pendingCaptureResult = nil
        captureResultLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.finishCapture(token: token, result: result)
        }
    }

    private var controllerIsActive: Bool {
        captureResultLock.lock()
        defer { captureResultLock.unlock() }
        return isActive
    }

    private func markExpectedSessionStop() {
        captureResultLock.lock()
        expectedSessionStops += 1
        captureResultLock.unlock()
    }

    private func consumeExpectedSessionStop() -> Bool {
        captureResultLock.lock()
        defer { captureResultLock.unlock() }
        guard expectedSessionStops > 0 else { return false }
        expectedSessionStops -= 1
        return true
    }

    private func finishCapture(
        token: UUID,
        result: Result<Data, Error>
    ) {
        captureResultLock.lock()
        guard isActive, activeCaptureToken == token else {
            captureResultLock.unlock()
            return
        }
        activeCaptureToken = nil
        activeCaptureSettingsID = nil
        pendingCaptureResult = nil
        captureResultLock.unlock()

        guard captureCompletion?.token == token else {
            return
        }
        let completion = captureCompletion?.handler
        captureCompletion = nil

        let shouldRefresh = pendingRefreshAfterCapture
            || selectedCameraID == nil
        pendingRefreshAfterCapture = false
        if shouldRefresh {
            status = .searching
            refresh()
        } else {
            status = .ready
        }
        completion?(result)
    }

    private func handleSessionFailure(_ message: String) {
        guard controllerIsActive else { return }
        configurationGeneration += 1

        captureResultLock.lock()
        let token = activeCaptureToken
        activeCaptureToken = nil
        activeCaptureSettingsID = nil
        pendingCaptureResult = nil
        captureResultLock.unlock()

        let completion = captureCompletion
        captureCompletion = nil
        pendingRefreshAfterCapture = false
        selectedCameraID = nil
        rotationDevice = nil
        installRotationCoordinator()
        status = .failed(message)

        if let token,
           completion?.token == token {
            completion?.handler(
                .failure(ProfileCameraCaptureError.interrupted)
            )
        }
    }

    private func installRotationCoordinator() {
        rotationObservations.removeAll()
        rotationCoordinator = nil
        guard let rotationDevice else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: rotationDevice,
            previewLayer: previewLayer
        )
        rotationCoordinator = coordinator
        rotationObservations = [
            coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                guard let self,
                      let connection = self.previewLayer?.connection
                else {
                    return
                }
                let angle =
                    coordinator.videoRotationAngleForHorizonLevelPreview
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            },
            coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                let angle =
                    coordinator.videoRotationAngleForHorizonLevelCapture
                self?.sessionQueue.async { [weak self] in
                    self?.captureRotationAngle = angle
                }
            },
        ]
    }

    private func updateAuthorizationState() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            refresh()
        case .notDetermined:
            cameras = discoveredDevices().map {
                ProfileCameraOption(
                    id: $0.uniqueID,
                    name: $0.localizedName,
                    kind: $0.isContinuityCamera ? .iPhone : .mac
                )
            }
            status = .needsPermission
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .failed(
                "Der Kamerazugriff hat einen unbekannten Zustand."
            )
        }
    }

    private func discoveredDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
        .devices
        .filter(\.isConnected)
        .sorted { left, right in
            if left.isContinuityCamera != right.isContinuityCamera {
                return !left.isContinuityCamera
            }
            return left.localizedName.localizedCaseInsensitiveCompare(
                right.localizedName
            ) == .orderedAscending
        }
    }

    private func configure(_ device: AVCaptureDevice) {
        guard status != .capturing else {
            pendingRefreshAfterCapture = true
            return
        }
        configurationGeneration += 1
        let generation = configurationGeneration
        status = .searching

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                }

                let previousInput = self.currentInput
                let outputWasPresent = self.session.outputs.contains(where: {
                    $0 === self.photoOutput
                })
                var addedOutput = false

                if !outputWasPresent {
                    guard self.session.canAddOutput(self.photoOutput) else {
                        self.session.commitConfiguration()
                        throw ProfileCameraCaptureError.outputUnavailable
                    }
                    self.session.addOutput(self.photoOutput)
                    addedOutput = true
                }

                if let previousInput {
                    self.session.removeInput(previousInput)
                }

                guard self.session.canAddInput(newInput) else {
                    if addedOutput {
                        self.session.removeOutput(self.photoOutput)
                    }
                    var restoredPreviousInput = false
                    if let previousInput,
                       self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                        restoredPreviousInput = true
                    }
                    self.session.commitConfiguration()
                    self.currentInput = restoredPreviousInput
                        ? previousInput
                        : nil
                    throw ProfileCameraCaptureError.inputUnavailable
                }
                self.session.addInput(newInput)
                self.session.commitConfiguration()
                self.currentInput = newInput

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                DispatchQueue.main.async {
                    guard generation == self.configurationGeneration,
                          self.controllerIsActive
                    else {
                        return
                    }
                    self.selectedCameraID = device.uniqueID
                    self.rotationDevice = device
                    self.installRotationCoordinator()
                    self.status = self.session.isRunning
                        ? .ready
                        : .failed(
                            "Die Kamera konnte nicht gestartet werden."
                        )
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.configurationGeneration,
                          self.controllerIsActive
                    else {
                        return
                    }
                    self.selectedCameraID = nil
                    self.rotationDevice = nil
                    self.installRotationCoordinator()
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func stopSessionWithoutChangingStatus() {
        configurationGeneration += 1
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.markExpectedSessionStop()
                self.session.stopRunning()
            }
        }
    }
}

private final class ProfileCameraPreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

private struct ProfileCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let onLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeNSView(context: Context) -> ProfileCameraPreviewNSView {
        let view = ProfileCameraPreviewNSView(session: session)
        onLayerReady(view.previewLayer)
        return view
    }

    func updateNSView(
        _ nsView: ProfileCameraPreviewNSView,
        context: Context
    ) {
        nsView.previewLayer.session = session
        onLayerReady(nsView.previewLayer)
    }
}

struct ProfileCameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    let initialKind: ProfileCameraKind
    let onChooseFile: () -> Void
    let onCapture: (Data, Date, String) throws -> Void

    @StateObject private var camera =
        ProfileCameraCaptureController()
    @State private var selectedKind: ProfileCameraKind
    @State private var errorMessage: String?

    init(
        initialKind: ProfileCameraKind,
        onChooseFile: @escaping () -> Void,
        onCapture: @escaping (Data, Date, String) throws -> Void
    ) {
        self.initialKind = initialKind
        self.onChooseFile = onChooseFile
        self.onCapture = onCapture
        _selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profilfoto aufnehmen")
                        .font(.title2.weight(.bold))
                    Text("Mac-Kamera oder iPhone mit Continuity Camera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            VStack(spacing: 16) {
                Picker("Kameraquelle", selection: $selectedKind) {
                    ForEach(ProfileCameraKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedKind) { _, newKind in
                    camera.selectKind(newKind)
                }
                .disabled(camera.status == .capturing)

                ZStack {
                    ProfileCameraPreview(
                        session: camera.session,
                        onLayerReady: camera.attachPreviewLayer
                    )
                        .opacity(showsLivePreview ? 1 : 0.18)

                    if !showsLivePreview {
                        statusOverlay
                            .padding(30)
                    }

                    if camera.status == .capturing {
                        Color.white
                            .opacity(0.55)
                            .transition(.opacity)
                    }
                }
                .frame(height: 390)
                .background(Color.black)
                .clipShape(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                HStack(spacing: 12) {
                    if camera.status == .ready {
                        Button(action: camera.refresh) {
                            Label(
                                "Neu suchen",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    }

                    if !matchingCameras.isEmpty,
                       showsLivePreview {
                        Picker(
                            "Kamera",
                            selection: selectedCameraBinding
                        ) {
                            ForEach(matchingCameras) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }
                        .frame(maxWidth: 300)
                        .disabled(camera.status == .capturing)
                    }

                    Spacer()

                    Button(action: takePhoto) {
                        Label("Foto aufnehmen", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    .controlSize(.large)
                    .disabled(camera.status != .ready)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 760, height: 620)
        .onAppear {
            camera.start(preferredKind: initialKind)
        }
        .onDisappear {
            camera.stop()
        }
        .alert("Foto konnte nicht übernommen werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var matchingCameras: [ProfileCameraOption] {
        camera.cameras.filter { $0.kind == selectedKind }
    }

    private var selectedCameraBinding: Binding<String> {
        Binding(
            get: {
                if let selectedCameraID = camera.selectedCameraID,
                   matchingCameras.contains(where: {
                       $0.id == selectedCameraID
                   }) {
                    return selectedCameraID
                }
                return matchingCameras.first?.id ?? ""
            },
            set: camera.selectCamera(id:)
        )
    }

    private var showsLivePreview: Bool {
        camera.status == .ready || camera.status == .capturing
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch camera.status {
        case .idle, .searching:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Kameras werden gesucht …")
                    .foregroundStyle(.white)
            }
        case .needsPermission:
            cameraMessage(
                symbol: "camera.fill",
                title: "Kamerazugriff erlauben",
                message: "Freundeblick verwendet die Kamera nur, um dieses Profilfoto aufzunehmen."
            ) {
                HStack {
                    Button("Kamerazugriff erlauben") {
                        camera.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
                    fileAlternativeButton
                }
            }
        case .requestingPermission:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Kamerazugriff wird angefragt …")
                    .foregroundStyle(.white)
            }
        case .denied:
            cameraMessage(
                symbol: "camera.fill",
                title: "Kamerazugriff ist ausgeschaltet",
                message: "Erlaube Freundeblick den Zugriff unter Datenschutz & Sicherheit → Kamera."
            ) {
                HStack {
                    Button("Systemeinstellungen öffnen") {
                        openCameraPrivacySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    fileAlternativeButton
                }
            }
        case .restricted:
            cameraMessage(
                symbol: "lock.fill",
                title: "Kamera ist eingeschränkt",
                message: "Der Kamerazugriff ist auf diesem Mac durch eine Systemeinstellung eingeschränkt."
            ) {
                fileAlternativeButton
            }
        case let .noCamera(kind):
            cameraMessage(
                symbol: kind.symbolName,
                title: "\(kind.title) nicht gefunden",
                message: noCameraMessage(for: kind)
            ) {
                HStack {
                    Button("Erneut suchen", action: camera.refresh)
                        .buttonStyle(.borderedProminent)
                    fileAlternativeButton
                }
            }
        case let .failed(message):
            cameraMessage(
                symbol: "exclamationmark.triangle.fill",
                title: "Kamera konnte nicht gestartet werden",
                message: message
            ) {
                HStack {
                    Button("Erneut versuchen", action: camera.refresh)
                        .buttonStyle(.borderedProminent)
                    fileAlternativeButton
                }
            }
        case .ready, .capturing:
            EmptyView()
        }
    }

    private func cameraMessage<Actions: View>(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            actions()
        }
    }

    private func cameraMessage(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        cameraMessage(
            symbol: symbol,
            title: title,
            message: message
        ) {
            EmptyView()
        }
    }

    private func noCameraMessage(for kind: ProfileCameraKind) -> String {
        switch kind {
        case .mac:
            "Es wurde keine eingebaute oder angeschlossene Kamera gefunden."
        case .iPhone:
            "Sperre dein iPhone und bringe es in die Nähe des Macs oder verbinde es per USB. Beide Geräte müssen dieselbe Apple-ID verwenden; WLAN, Bluetooth und Continuity Camera müssen aktiviert sein."
        }
    }

    private func takePhoto() {
        let capturedAt = Date()
        camera.capture { result in
            switch result {
            case let .success(data):
                do {
                    try onCapture(
                        data,
                        capturedAt,
                        cameraFilename(for: capturedAt)
                    )
                    camera.stop()
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel() {
        camera.stop()
        dismiss()
    }

    private var fileAlternativeButton: some View {
        Button("Datei auswählen") {
            camera.stop()
            onChooseFile()
            dismiss()
        }
        .buttonStyle(.bordered)
    }

    private func cameraFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Kameraaufnahme-\(formatter.string(from: date)).jpg"
    }

    private func openCameraPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
