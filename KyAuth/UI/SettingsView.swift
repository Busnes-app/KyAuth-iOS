import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showPairing = false
    @State private var showPinSetup = false
    @State private var confirmUnpair = false
    @State private var confirmErase = false
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            BusnesForm {
                if model.isDemo {
                    Section {
                        Button("Exit Demo") { model.lock() }
                    } header: {
                        Text("Demo Mode")
                    } footer: {
                        Text("Codes and sign-in requests here are simulated and kept in memory: none are saved or sent anywhere. Exit the demo to pair with KyIdentity.")
                    }
                } else {
                    kyIdentitySection
                }
                if model.isPaired {
                    Section {
                        LabeledContent("Notifications", value: notificationText)
                        if notificationStatus == .denied {
                            Button("Open Settings") {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        }
                        if model.needsPushRefresh {
                            Button("Reconnect Sign-in Requests") { Task { await model.reconnectPush() } }
                        }
                    } header: {
                        Text("Sign-in Requests")
                    } footer: {
                        Text("KyIdentity sends sign-in requests to this phone through Apple Push.")
                    }
                }
                if !model.isDemo {
                    Section {
                        Picker("Auto-Lock", selection: $model.idleMinutes) {
                            ForEach(IdleLock.minuteChoices, id: \.self) { minutes in
                                Text(minutes == 60 ? "1 hour" : "\(minutes) minute\(minutes == 1 ? "" : "s")")
                            }
                        }
                        if model.pinEnabled {
                            Button("Change PIN") { showPinSetup = true }
                            Button("Turn Off PIN", role: .destructive) { model.removePin() }
                        } else {
                            Button("Set a PIN") { showPinSetup = true }
                        }
                    } header: {
                        Text("Security")
                    } footer: {
                        Text("KyAuth locks when you leave it, and after the auto-lock time in the app. A PIN is asked after \(UserPresence.biometryName). Five wrong PINs erase KyAuth's data on this phone.")
                    }
                }
                Section {
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("System switches between Busnes Light and Busnes Dark with this iPhone's setting.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Link("Source Code", destination: URL(string: "https://github.com/Busnes-app/KyAuth-iOS")!)
                    NavigationLink("License") { LicenseView() }
                } header: {
                    Text("About")
                } footer: {
                    Text("Codes are stored only on this phone, encrypted, with no backup or sync. If you lose the phone, use your KyIdentity recovery codes.")
                }
                if !model.isDemo {
                    Section {
                        Button("Erase All Data", role: .destructive) { confirmErase = true }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPairing) { PairingView() }
            .sheet(isPresented: $showPinSetup) { PinSetupView() }
            .confirmationDialog("Unpair from KyIdentity?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { model.unpair() }
            } message: {
                Text("This phone will stop receiving sign-in requests and its device key is deleted. Remove the device on the KyIdentity devices page too.")
            }
            .confirmationDialog("Erase all KyAuth data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase All Data", role: .destructive) { model.eraseAllData() }
            } message: {
                Text("Every code, the KyIdentity pairing and the PIN are deleted from this phone. This cannot be undone.")
            }
            .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }
    }

    @ViewBuilder
    private var kyIdentitySection: some View {
        Section {
            if let account = model.account {
                LabeledContent("Server", value: URL(string: account.serverUrl)?.host() ?? account.serverUrl)
                LabeledContent("Account", value: account.username ?? account.userId ?? "Unknown")
                LabeledContent("Device", value: account.deviceName)
                LabeledContent("Verification") {
                    Text(AttestationReason.summary(level: account.attestedLevel, reason: account.attestationReason))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Sign in to apps", value: account.canSignOn ? "On" : "Off")
                Button("Pair Again") { showPairing = true }
                Button("Unpair", role: .destructive) { confirmUnpair = true }
            } else {
                Button("Pair with KyIdentity") { showPairing = true }
            }
        } header: {
            Text("KyIdentity")
        } footer: {
            if model.account?.canSignOn == false {
                Text("To let suite apps such as KyPost sign in through this phone, turn on sign-in for this device on the KyIdentity devices page, then pair again.")
            }
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not set"
        }
    }
}

struct LicenseView: View {
    var body: some View {
        ScrollView {
            Text(Self.text)
                .font(.footnote.monospaced())
                .padding()
        }
        .navigationTitle("License")
    }

    static var text: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "MIT License" }
        return text
    }
}

extension Bundle {
    var versionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

struct PinSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            BusnesForm {
                Section {
                    SecureField("New PIN", text: $pin)
                        .keyboardType(.numberPad)
                    SecureField("Confirm PIN", text: $confirmation)
                        .keyboardType(.numberPad)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("\(PinPolicy.minLength) to \(PinPolicy.maxLength) digits. Avoid common or sequential numbers.")
                    }
                }
            }
            .navigationTitle("KyAuth PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(pin.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let problem = PinPolicy.validate(pin) {
            error = problem
        } else if pin != confirmation {
            error = "The PINs do not match."
        } else {
            do {
                try model.setPin(pin)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
