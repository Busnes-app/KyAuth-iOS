import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = MainTab.codes

    var body: some View {
        TabView(selection: $tab) {
            VaultView()
                .tabItem { TabLabel(title: "Codes", symbol: "lock.shield", selected: tab == .codes) }
                .tag(MainTab.codes)
            SettingsView()
                .tabItem { TabLabel(title: "Settings", symbol: "gearshape", selected: tab == .settings) }
                .tag(MainTab.settings)
        }
        // A pairing form that was open when KyAuth locked comes back once it is unlocked.
        .sheet(isPresented: Binding(get: { model.resumePairing }, set: { if !$0 { model.pairingFormClosed() } })) {
            PairingView().privacyCovered()
        }
    }
}

struct VaultView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var sheet: VaultSheet?
    @State private var pendingDelete: TotpEntry?

    var body: some View {
        NavigationStack {
            ThemedList {
                if model.needsPushRefresh {
                    Section {
                        ReconnectBanner()
                            .listRowBackground(Rectangle().fill(.themeWarningSoft))
                    }
                }
                if let challenge = model.pendingChallenge {
                    Section {
                        MfaRequestCard(challenge: challenge)
                            .id(challenge.challengeId)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if let error = model.vaultError {
                    Section {
                        StatusLabel(error, .danger)
                            .listRowBackground(Rectangle().fill(.themeDangerSoft))
                    }
                }
                Section {
                    ForEach(filtered) { entry in
                        TotpRow(entry: entry)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                                Button("Edit", systemImage: "pencil") { sheet = .edit(entry) }
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { sheet = .edit(entry) }
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                            }
                    }
                }
            }
            .overlay {
                // Only over an empty list: drawn over a request card or the reconnect banner, it covers their buttons.
                if model.entries.isEmpty && model.vaultError == nil && model.pendingChallenge == nil && !model.needsPushRefresh {
                    ContentUnavailableView {
                        Label("No Codes Yet", systemImage: "key.viewfinder")
                    } description: {
                        Text("Add an account by scanning its setup QR code or entering its key.")
                    } actions: {
                        Button("Scan QR Code") { sheet = .scan }
                            .themedProminentButton()
                        if !model.isPaired && !model.isDemo {
                            Button("Explore the Demo") { model.startDemo() }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: Text("Search codes").placeholderStyle())
            .navigationTitle("Codes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lock", systemImage: "lock") { model.lock() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Scan QR Code", systemImage: "qrcode.viewfinder") { sheet = .scan }
                        Button("Enter Setup Key", systemImage: "keyboard") { sheet = .manual }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $sheet) { sheet in
                Group {
                    switch sheet {
                    case .scan: AddByScanView()
                    case .manual: EntryFormView(mode: .add)
                    case .edit(let entry): EntryFormView(mode: .edit(entry))
                    }
                }
                .privacyCovered()
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.title ?? "")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    do { try model.deleteEntry(entry) } catch { model.notice = error.localizedDescription }
                }
            } message: { _ in
                Text("KyAuth keeps no backup. You will need a new setup code from the service to add it again.")
            }
        }
    }

    private var filtered: [TotpEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.issuer ?? "").localizedCaseInsensitiveContains(query)
        }
    }
}

enum MainTab {
    case codes, settings
}

/// A tab item whose icon is outline unless selected. The iOS 26 tab bar fills every SF Symbol
/// and ignores `symbolVariants`, so the icon is handed over as a template `UIImage`.
private struct TabLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let selected: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: UIImage(systemName: selected ? symbol + ".fill" : symbol)!.withRenderingMode(.alwaysTemplate))
        }
    }
}

enum VaultSheet: Identifiable {
    case scan, manual, edit(TotpEntry)

    var id: String {
        switch self {
        case .scan: "scan"
        case .manual: "manual"
        case .edit(let entry): "edit-\(entry.id)"
        }
    }
}

struct ReconnectBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sign-in requests paused", systemImage: "bell.slash")
                .font(AppFont.ui(.headline, weight: .semibold))
                .foregroundStyle(.themeWarning)
            Text("Apple gave KyAuth a new push address. Reconnect so KyIdentity can reach this device.")
                .font(AppFont.ui(.subheadline))
                .foregroundStyle(.secondary)
            Button("Reconnect") { Task { await model.reconnectPush() } }
                .themedProminentButton()
        }
        .padding(.vertical, 4)
    }
}

struct TotpRow: View {
    @Environment(AppModel.self) private var model
    let entry: TotpEntry

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = Int64(context.date.timeIntervalSince1970)
            let code = try? TotpGenerator.code(entry, at: now)
            let remaining = TotpGenerator.secondsRemaining(entry, at: now)
            let isShort = TotpGenerator.isShortSecret(entry.secretBase32)
            Button {
                if code != nil { model.copy(entry) }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(AppFont.ui(.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(code.map(TotpGenerator.formatted) ?? "Unavailable")
                            .font(AppFont.ui(.title, weight: .semibold).monospacedDigit())
                            .foregroundStyle(remaining <= 5 ? AnyShapeStyle(ThemeColor.themeWarning) : AnyShapeStyle(Color.primary))
                            .contentTransition(.numericText())
                        if code == nil {
                            Text("Set up this account again at its service using a new key. Keep your recovery codes until it works.")
                                .font(AppFont.ui(.subheadline))
                                .foregroundStyle(.secondary)
                        } else if isShort {
                            StatusLabel("Short setup key. If the service offers a longer one, set this account up again.", .warning)
                                .font(AppFont.ui(.subheadline))
                        }
                    }
                    Spacer()
                    if code != nil {
                        CountdownRing(remaining: remaining, period: entry.periodSeconds)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(code == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(code.map { "\(entry.title), code \($0.map(String.init).joined(separator: " ")), \(remaining) seconds left\(isShort ? ". Short setup key" : "")" }
                ?? "\(entry.title), code unavailable. Set up this account again at its service using a new key. Keep your recovery codes until it works.")
            .accessibilityHint(code == nil ? "" : "Copies the code")
        }
    }
}

struct CountdownRing: View {
    let remaining: Int64
    let period: Int64

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(remaining) / CGFloat(period))
                .stroke(remaining <= 5 ? ThemeColor.themeWarning : .themeAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(remaining)")
                .font(AppFont.ui(.caption2).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
    }
}
