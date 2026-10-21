import SwiftUI

/// Shown while locked. A pending sign-in request is shown alone and suppresses the automatic unlock
/// prompt: answering it needs only the device key, never the vault.
struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var prompted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let challenge = model.pendingChallenge {
                        MfaRequestCard(challenge: challenge)
                            .padding(.top, 24)
                    } else {
                        Spacer(minLength: 80)
                        BrandMark(size: 96)
                        Text("Your codes are locked.")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await model.unlock() }
                    } label: {
                        Label("Unlock with \(UserPresence.biometryName)", systemImage: UserPresence.biometrySymbol)
                            .frame(maxWidth: .infinity)
                    }
                    .busnesProminentButton()
                    .controlSize(.large)
                    if !model.isPaired && model.pendingChallenge == nil {
                        Button("Try Demo") { model.startDemo() }
                    }
                }
                .padding(.horizontal, 24)
                // Phone-width on iPad, so the buttons don't stretch across a landscape screen.
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color.busnesBackground)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // A launch from a notification or a sign-on link delivers it just after the first frame.
            try? await Task.sleep(for: .milliseconds(400))
            guard !prompted, model.promptsUnlockOnLaunch, model.pendingChallenge == nil, model.signOnRequest == nil else { return }
            prompted = true
            await model.unlock()
        }
    }
}

struct PinUnlockView: View {
    @Environment(AppModel.self) private var model
    @State private var pin = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            BusnesForm {
                Section {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .onSubmit(submit)
                } header: {
                    Text("Enter your KyAuth PIN")
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Unlock", action: submit)
                        .disabled(pin.count < PinPolicy.minLength)
                }
            }
            .navigationTitle("KyAuth")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.lock() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        error = model.submitPin(pin)
        pin = ""
    }
}
