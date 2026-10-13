import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            VaultView()
                .tabItem { Label("Codes", systemImage: "lock.shield") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
            BusnesList {
                if model.needsPushRefresh {
                    Section {
                        ReconnectBanner()
                    }
                }
                if let challenge = model.pendingChallenge {
                    Section {
                        MfaRequestCard(challenge: challenge)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if let error = model.vaultError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
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
                if model.entries.isEmpty && model.vaultError == nil {
                    ContentUnavailableView {
                        Label("No Codes Yet", systemImage: "key.viewfinder")
                    } description: {
                        Text("Add an account by scanning its setup QR code or entering its key.")
                    } actions: {
                        Button("Scan QR Code") { sheet = .scan }
                            .busnesProminentButton()
                    }
                }
            }
            .searchable(text: $search, prompt: "Search codes")
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
                switch sheet {
                case .scan: AddByScanView()
                case .manual: EntryFormView(mode: .add)
                case .edit(let entry): EntryFormView(mode: .edit(entry))
                }
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
                .font(.headline)
            Text("Apple gave KyAuth a new push address. Reconnect so KyIdentity can reach this phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Reconnect") { Task { await model.reconnectPush() } }
                .busnesProminentButton()
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
            Button {
                if let code { model.copy(code, entry: entry) }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(code.map(TotpGenerator.formatted) ?? "Unavailable")
                            .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                            .foregroundStyle(remaining <= 5 ? Color.red : Color.primary)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    CountdownRing(remaining: remaining, period: entry.periodSeconds)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.title), code \(code.map { $0.map(String.init).joined(separator: " ") } ?? "unavailable"), \(remaining) seconds left")
            .accessibilityHint("Copies the code")
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
                .stroke(remaining <= 5 ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(remaining)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
    }
}
