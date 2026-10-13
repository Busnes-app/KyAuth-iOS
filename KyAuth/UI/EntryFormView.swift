import SwiftUI

/// Adds an account from its setup key, or edits an existing one's name, website and notes.
/// A scanned entry arrives prefilled as `.add`, so the user can review it before saving.
struct EntryFormView: View {
    enum Mode {
        case add
        case scanned(TotpEntry)
        case edit(TotpEntry)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var title = ""
    @State private var secret = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var algorithm = TotpEntry.Algorithm.sha1
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            BusnesForm {
                Section("Account") {
                    TextField("Name", text: $title)
                        .textInputAutocapitalization(.words)
                    if case .add = mode {
                        // Secure entry: no keyboard learning, suggestions or screen echo of the secret.
                        SecureField("Setup key", text: $secret)
                            .textContentType(.oneTimeCode) // never offer to save it as a password
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .privacySensitive()
                    }
                }
                Section {
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Optional")
                }
                if case .add = mode {
                    Section("Advanced") {
                        Picker("Digits", selection: $digits) {
                            ForEach(6...8, id: \.self) { Text("\($0)") }
                        }
                        Picker("Period", selection: $period) {
                            ForEach([30, 60], id: \.self) { Text("\($0) seconds") }
                        }
                        Picker("Algorithm", selection: $algorithm) {
                            ForEach(TotpEntry.Algorithm.allCases, id: \.self) { Text($0.rawValue) }
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.isBlank || (isAdd && secret.isBlank))
                }
            }
            .onAppear(perform: load)
        }
    }

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .add: "Add Account"
        case .scanned: "New Account"
        case .edit: "Edit Account"
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .add: break
        case .scanned(let entry), .edit(let entry):
            title = entry.title
            website = entry.url ?? ""
            notes = entry.notes ?? ""
        }
    }

    private func save() {
        do {
            switch mode {
            case .add:
                try model.addEntry(TotpEntry(
                    title: title, secretBase32: secret, digits: digits, periodSeconds: Int64(period),
                    algorithm: algorithm, url: website, notes: notes
                ))
            case .scanned(var entry):
                try apply(to: &entry)
                try model.addEntry(entry)
            case .edit(var entry):
                try apply(to: &entry)
                try model.updateEntry(entry)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(to entry: inout TotpEntry) throws {
        guard !title.isBlank else { throw TotpError.invalid("Enter a name") }
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.url = website.trimmedNonBlank
        entry.notes = notes.trimmedNonBlank
    }
}

/// Scans an `otpauth://totp` QR code, then shows the prefilled form for review.
struct AddByScanView: View {
    @State private var scanned: TotpEntry?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let scanned {
            EntryFormView(mode: .scanned(scanned))
        } else {
            NavigationStack {
                QRScannerView { value in
                    do {
                        scanned = try TotpUriParser.parse(value)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) {
                    if let error {
                        Text(error)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
                }
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}
