import SwiftUI
import UIKit

/// Pairs this phone with KyIdentity from its 90-second QR code, a pasted pairing link, or the server
/// address, user ID and PIN shown beside the QR code. A code scanned in the Codes tab arrives as
/// `scanned` and waits for a tap, since pairing replaces the device key. What the form holds lives in
/// `AppModel.pairingDraft`, so a lock (leaving KyAuth to copy a link) brings the form back after unlock.
struct PairingView: View {
    var scanned: QrPairing?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var scanning = false
    @State private var working = false
    @State private var error: String?

    private var draft: Binding<PairingDraft> {
        Binding(get: { model.pairingDraft ?? PairingDraft(scanned: scanned) }, set: { model.pairingDraft = $0 })
    }

    var body: some View {
        NavigationStack {
            BusnesForm {
                if let scanned = draft.wrappedValue.scanned {
                    Section {
                        Button("Pair with \(URL(string: scanned.serverUrl)?.host() ?? scanned.serverUrl)") { run(scanned) }
                    } footer: {
                        Text("A KyIdentity pairing code was scanned. It is valid for 90 seconds.")
                    }
                } else {
                    entryOptions
                }
                Section {
                    TextField("Device name", text: draft.deviceName)
                } footer: {
                    Text("Shown on the KyIdentity devices page.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .disabled(working)
            .overlay { if working { ProgressView("Pairing…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
            .navigationTitle(model.isPaired ? "Pair Again" : "Pair with KyIdentity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScannerView { value in
                        scanning = false
                        pair(raw: value)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan Pairing Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { scanning = false }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(working)
        .onAppear {
            if model.pairingDraft == nil { model.pairingDraft = PairingDraft(scanned: scanned) }
        }
        .onDisappear { model.pairingFormClosed() }
    }

    @ViewBuilder
    private var entryOptions: some View {
        Section {
            Button("Scan Pairing QR Code", systemImage: "qrcode.viewfinder") { scanning = true }
            Button("Paste Pairing Link", systemImage: "doc.on.clipboard") { pasteLink() }
        } footer: {
            Text("Open the KyIdentity devices page and add a device. The code is valid for 90 seconds.")
        }
        Section("Or Enter the Details") {
            TextField("Server (https://…)", text: draft.serverUrl)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("User ID", text: draft.userId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Pairing PIN", text: draft.pinCode)
                .keyboardType(.numberPad)
            Button("Pair") { pairManually() }
                .disabled(draft.wrappedValue.serverUrl.isBlank || draft.wrappedValue.userId.isBlank || draft.wrappedValue.pinCode.isBlank)
        }
    }

    private func pasteLink() {
        guard let value = UIPasteboard.general.string else {
            error = "The clipboard has no pairing link."
            return
        }
        pair(raw: value)
    }

    private func pairManually() {
        let typed = draft.wrappedValue
        do {
            let pairing = try QrPairing(
                serverUrl: try PairingEndpoint.validateServerUrl(typed.serverUrl),
                pinCode: typed.pinCode.trimmedNonBlank,
                userId: typed.userId.trimmedNonBlank
            )
            run(pairing)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pair(raw: String) {
        do {
            run(try QrPairingParser.parse(raw))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ pairing: QrPairing) {
        error = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await model.pair(pairing, deviceName: draft.wrappedValue.deviceName.trimmedNonBlank ?? UIDevice.current.model)
                model.notice = "Paired with KyIdentity"
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A suite app asks to sign in through KyIdentity. Works while the vault is locked: only the device
/// key signs, with one Face ID / passcode prompt.
struct SignOnSheet: View {
    @Environment(AppModel.self) private var model
    let request: SignOnRequest
    @State private var working = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .padding(.top, 32)
                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        working = true
                        Task { await model.approveSignOn() }
                    } label: {
                        Text("Sign In").frame(maxWidth: .infinity)
                    }
                    .busnesProminentButton()
                    Button("Cancel", role: .cancel) { model.cancelSignOn() }
                }
                .controlSize(.large)
                .disabled(working)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.busnesBackground)
            .navigationTitle("Sign in with KyIdentity")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }

    private var message: String {
        let relay = request.origin.replacingOccurrences(of: "https://", with: "")
        let user = model.account?.username ?? model.account?.userId ?? "your account"
        let identity = URL(string: model.account?.serverUrl ?? "")?.host() ?? "KyIdentity"
        return "\(request.consumer.name) at \(relay) wants to sign in as \(user) at \(identity)."
    }
}
