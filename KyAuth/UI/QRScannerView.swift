import SwiftUI
import VisionKit

/// The system camera scanner for QR codes. Every recognised payload is passed on; the caller decides
/// whether it is one it accepts.
struct QRScannerView: View {
    let onScan: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScanner(onScan: onScan)
        } else {
            ContentUnavailableView(
                "Camera Unavailable",
                systemImage: "camera",
                description: Text("Allow camera access for KyAuth in Settings, or enter the details by hand.")
            )
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
