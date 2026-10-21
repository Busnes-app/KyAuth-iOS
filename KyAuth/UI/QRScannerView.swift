import AVFoundation
import SwiftUI
import VisionKit

/// The system camera scanner for QR codes. Every recognised payload is passed on; the caller decides
/// whether it is one it accepts. Camera access is asked for here, on first use: the scanner itself
/// reports unavailable until it is granted, which would leave KyAuth out of the Camera list in Settings.
struct QRScannerView: View {
    let onScan: (String) -> Void
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)
    @Environment(\.openURL) private var openURL

    var body: some View {
        if access == .notDetermined {
            ProgressView()
                .task {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    access = AVCaptureDevice.authorizationStatus(for: .video)
                }
        } else if access == .authorized && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScanner(onScan: onScan)
        } else {
            ContentUnavailableView {
                Label("Camera Unavailable", systemImage: "camera")
            } description: {
                Text(access == .authorized
                    ? "This device can't scan QR codes. Tap Cancel and enter the details by hand."
                    : "Allow camera access for KyAuth in Settings, or tap Cancel and enter the details by hand.")
            } actions: {
                if access == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .busnesProminentButton()
                }
            }
        }
    }
}

private struct DataScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var last: String?

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in items {
                guard let value = barcode.payloadStringValue, value != last else { continue }
                last = value
                onScan(value)
            }
        }
    }
}
