//
//  BarcodeScannerView.swift
//  DOSBTS
//

import AVFoundation
import SwiftUI

// MARK: - BarcodeScannerView

/// Barcode scanner that auto-navigates to staging plate when OFF API returns a result.
struct BarcodeScannerView: View {
    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    @State private var hasScanned = false

    private var shouldShowStagingPlate: Binding<Bool> {
        Binding(
            get: { store.state.foodAnalysisResult != nil },
            set: { if !$0 { store.dispatch(.setFoodAnalysisResult(result: nil)) } }
        )
    }

    var body: some View {
        ZStack {
            if store.state.foodAnalysisLoading {
                loadingView
            } else if let error = store.state.foodAnalysisError, !error.isEmpty {
                errorView(error)
            } else {
                scannerView
            }
        }
        // Auto-push to staging plate when the OFF lookup populates a result.
        .navigationDestination(isPresented: shouldShowStagingPlate) {
            FoodPhotoAnalysisView()
                .environmentObject(store)
                .navigationBarHidden(true)
        }
        .dosNavigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    store.dispatch(.setFoodAnalysisResult(result: nil))
                    store.dispatch(.setFoodAnalysisLoading(isLoading: false))
                    dismiss()
                }
                .foregroundStyle(AmberTheme.amber)
            }
        }
        .onDisappear {
            if !hasScanned {
                store.dispatch(.setFoodAnalysisResult(result: nil))
                store.dispatch(.setFoodAnalysisLoading(isLoading: false))
            }
        }
    }

    // MARK: - Scanner

    private var scannerView: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            #if targetEnvironment(simulator)
            simulatorFallback
            #else
            ScannerVC_Wrapper(onScan: handleScan)
                .edgesIgnoringSafeArea(.all)
            #endif

            viewfinderOverlay
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: DOSSpacing.md) {
            ProgressView()
                .tint(AmberTheme.amber)

            Text("Looking up product...")
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.amber)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(AmberTheme.cgaRed)

            Text(error)
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.cgaRed)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: DOSSpacing.md) {
                Button("Try Again") {
                    hasScanned = false
                    // Clear error state — setFoodAnalysisResult(nil) clears both error and loading
                    store.dispatch(.setFoodAnalysisResult(result: nil))
                }
                .foregroundStyle(AmberTheme.amber)

                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(AmberTheme.amberDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Viewfinder Overlay

    private var viewfinderOverlay: some View {
        VStack {
            Spacer()

            RoundedRectangle(cornerRadius: 2)
                .stroke(AmberTheme.amber, lineWidth: 2)
                .frame(width: 280, height: 120)

            Text("Point camera at barcode")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
                .padding(.top, DOSSpacing.sm)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Scan Handler

    private func handleScan(_ code: String) {
        guard !hasScanned else { return }
        hasScanned = true
        store.dispatch(.setFoodAnalysisLoading(isLoading: true))
        store.dispatch(.analyzeFoodBarcode(code: code))
    }

    // MARK: - Simulator Fallback

    #if targetEnvironment(simulator)
    @State private var manualBarcode = ""

    private var simulatorFallback: some View {
        VStack(spacing: DOSSpacing.md) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(AmberTheme.amber)

            Text("Camera unavailable in simulator")
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.amber)

            TextField("Enter barcode", text: $manualBarcode)
                .font(DOSTypography.body)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            Button("Look Up") {
                let trimmed = manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                handleScan(trimmed)
            }
            .foregroundStyle(AmberTheme.amber)
        }
    }
    #endif
}

// MARK: - AVCaptureSession Scanner (Device Only)

#if !targetEnvironment(simulator)

struct ScannerVC_Wrapper: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}
}

class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.dosbts.barcode.session", qos: .userInteractive)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        feedbackGenerator.prepare()
        checkPermissionAndSetup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didScan = false
        sessionQueue.async { [weak self] in
            if self?.captureSession.isRunning == false {
                self?.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            if self?.captureSession.isRunning == true {
                self?.captureSession.stopRunning()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupSession() }
                }
            }
        default:
            break
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else { return }

            self.captureSession.addInput(input)

            let metadataOutput = AVCaptureMetadataOutput()
            guard self.captureSession.canAddOutput(metadataOutput) else { return }

            self.captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            // EAN/UPC only — no QR/Code128 (security: prevents arbitrary string injection)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce]

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = self.view.bounds
                self.view.layer.addSublayer(previewLayer)
                self.previewLayer = previewLayer
            }

            self.captureSession.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }

        didScan = true
        captureSession.stopRunning()
        feedbackGenerator.notificationOccurred(.success)
        onScan?(code)
    }
}

#endif
