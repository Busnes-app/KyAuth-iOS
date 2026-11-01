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
            ThemedForm {
                if model.isDemo {
                    Section {
                        Button("Exit demo") { model.lock() }
                    } header: {
                        Text("Demo mode").sectionHeaderStyle()
                    } footer: {
                        Text("Codes and sign-in requests here are simulated and kept in memory: none are saved or sent anywhere. Exit the demo to pair with KyIdentity.")
                    }
                } else {
                    kyIdentitySection
                }
                if model.isPaired {
                    Section {
                        LabeledContent("Notifications") { notificationStatusView }
                        if notificationStatus == .denied {
                            Button {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            } label: {
                                SettingsRowLabel("Open Settings", trailing: .external)
                            }
                        }
                        if model.needsPushRefresh {
                            Button { Task { await model.reconnectPush() } } label: { SettingsRowLabel("Reconnect sign-in requests") }
                        }
                    } header: {
                        Text("Sign-in requests").sectionHeaderStyle()
                    } footer: {
                        Text("KyIdentity sends sign-in requests to this device through Apple Push.")
                    }
                }
                if !model.isDemo {
                    Section {
                        Picker("Auto-lock", selection: $model.idleMinutes) {
                            ForEach(IdleLock.minuteChoices, id: \.self) { minutes in
                                Text(minutes == 60 ? "1 hour" : "\(minutes) minute\(minutes == 1 ? "" : "s")")
                            }
                        }
                        if model.pinEnabled {
                            Button { showPinSetup = true } label: { SettingsRowLabel("Change PIN", trailing: .chevron) }
                            Button("Turn off PIN", role: .destructive) { model.removePin() }
                        } else {
                            Button { showPinSetup = true } label: { SettingsRowLabel("Set a PIN", trailing: .chevron) }
                        }
                    } header: {
                        Text("Security").sectionHeaderStyle()
                    } footer: {
                        Text("KyAuth locks when you leave it, and after the auto-lock time in the app. A PIN is asked after \(UserPresence.biometryName). Five wrong PINs erase KyAuth's data on this device.")
                    }
                }
                Section {
                    Picker("Light or dark", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    // Not a `.navigationLink` picker: its pushed list keeps the system background.
                    NavigationLink {
                        ThemePickerView(selection: $model.themePair)
                    } label: {
                        LabeledContent("Theme") {
                            HStack(spacing: 8) {
                                ThemeSwatch(pair: model.themePair)
                                Text(model.themePair.title)
                            }
                        }
                    }
                } header: {
                    Text("Appearance").sectionHeaderStyle()
                } footer: {
                    Text("Each theme has a light and a dark version. System switches between them with this device's setting.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Link(destination: URL(string: "https://github.com/Busnes-app/KyAuth-iOS")!) {
                        SettingsRowLabel("Source code", trailing: .external)
                    }
                    NavigationLink("License") { LicenseView() }
                    Link(destination: URL(string: "https://busnes.app/privacy.html")!) {
                        SettingsRowLabel("Privacy policy", trailing: .external)
                    }
                } header: {
                    Text("About").sectionHeaderStyle()
                } footer: {
                    Text("Codes are stored only on this device, encrypted, with no backup or sync. If you lose the device, use your KyIdentity recovery codes.")
                }
                if !model.isDemo {
                    Section {
                        Button("Erase all data", role: .destructive) { confirmErase = true }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPairing) { PairingView() }
            .sheet(isPresented: $showPinSetup) { PinSetupView() }
            .confirmationDialog("Unpair from KyIdentity?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { model.unpair() }
            } message: {
                Text("This device will stop receiving sign-in requests and its device key is deleted. Remove the device on the KyIdentity devices page too.")
            }
            .confirmationDialog("Erase all KyAuth data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase All Data", role: .destructive) { model.eraseAllData() }
            } message: {
                Text("Every code, the KyIdentity pairing and the PIN are deleted from this device. This cannot be undone.")
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
                Button { showPairing = true } label: { SettingsRowLabel("Pair again", trailing: .chevron) }
                Button("Unpair", role: .destructive) { confirmUnpair = true }
            } else {
                Button { showPairing = true } label: { SettingsRowLabel("Pair with KyIdentity", trailing: .chevron) }
            }
        } header: {
            Text("KyIdentity").sectionHeaderStyle()
        } footer: {
            if model.account?.canSignOn == false {
                Text("To let suite apps such as KyPost sign in through this device, turn on sign-in for this device on the KyIdentity devices page, then pair again.")
            }
        }
    }

    @ViewBuilder
    private var notificationStatusView: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: StatusLabel("On", .success)
        case .denied: StatusLabel("Off", .warning)
        default: Text("Not set")
        }
    }
}

/// A Settings row title in ink, so the accent marks only Exit demo. A chevron means it opens a
/// sheet or screen, an arrow that it leaves KyAuth.
struct SettingsRowLabel: View {
    enum Trailing { case none, chevron, external }

    let title: LocalizedStringKey
    let trailing: Trailing

    init(_ title: LocalizedStringKey, trailing: Trailing = .none) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            // Concrete colors: `.primary` here would resolve against the button's accent tint.
            Text(title).foregroundStyle(Color.primary)
            Spacer()
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
        }
    }

    private var symbol: String? {
        switch trailing {
        case .none: nil
        case .chevron: "chevron.right"
        case .external: "arrow.up.right"
        }
    }
}

/// The six pairs on the theme background, each row previewing both halves.
struct ThemePickerView: View {
    @Binding var selection: ThemePair

    var body: some View {
        ThemedForm {
            ForEach(ThemePair.allCases) { pair in
                Button { selection = pair } label: {
                    HStack(spacing: 12) {
                        ThemeSwatch(pair: pair)
                        Text(pair.title)
                        Spacer()
                        if pair == selection {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.themeAccent)
                        }
                    }
                }
                // A Form button tints its whole label; only the checkmark takes the accent.
                .tint(.primary)
                .accessibilityAddTraits(pair == selection ? .isSelected : [])
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseView: View {
    var body: some View {
        ScrollView {
            Text(Self.text)
                .font(.footnote.monospaced())
                .padding()
        }
        .background(.themeBackground)
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
        // The App Store version field allows only digits and dots, so the "v" is added here.
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "v\(version)"
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
            ThemedForm {
                Section {
                    SecureField("New PIN", text: $pin, prompt: Text("New PIN").placeholderStyle())
                        .keyboardType(.numberPad)
                    SecureField("Confirm PIN", text: $confirmation, prompt: Text("Confirm PIN").placeholderStyle())
                        .keyboardType(.numberPad)
                } footer: {
                    if let error {
                        StatusLabel(error, .danger)
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
