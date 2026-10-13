import SwiftUI

/// A pending KyIdentity sign-in request. Approving needs the two-digit number the browser shows;
/// each answer takes exactly one Face ID / passcode prompt.
struct MfaRequestCard: View {
    @Environment(AppModel.self) private var model
    let challenge: MfaChallenge
    @State private var digits = ""
    @State private var working = false
    @FocusState private var digitsFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = challenge.isExpired(now: context.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(challenge.purposeText, systemImage: "person.badge.shield.checkmark")
                        .font(.headline)
                    Spacer()
                    if !expired {
                        Text("\(challenge.secondsRemaining(now: context.date))s")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let host = URL(string: challenge.serverUrl)?.host() {
                    Text(challenge.username.map { "\($0) at \(host)" } ?? host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let digits = model.demoBrowserDigits, !expired {
                    Text("Demo: the sign-in screen shows \(digits).")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                }
                if expired {
                    Text("This request expired.")
                    Button("Dismiss") { model.dismissExpiredChallenge() }
                } else {
                    typedApproval
                }
            }
            .padding()
            .background(Color.busnesSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(working)
    }

    private var typedApproval: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the number shown on the sign-in screen.")
                .font(.subheadline)
            TextField("00", text: $digits)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.largeTitle.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.center)
                .focused($digitsFocused)
                .onChange(of: digits) { _, value in
                    digits = String(value.filter(\.isNumber).prefix(2))
                }
                .padding(.vertical, 6)
                .background(Color.busnesBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Two-digit number")
            answerButtons(approveDisabled: !MfaMessage.isTwoDigits(digits)) { digits }
        }
    }

    private func answerButtons(approveDisabled: Bool, digits: @escaping () -> String) -> some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                answer(approve: false, digits: "")
            } label: {
                Text("Deny").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                answer(approve: true, digits: digits())
            } label: {
                Text("Approve").frame(maxWidth: .infinity)
            }
            .busnesProminentButton()
            .disabled(approveDisabled)
        }
        .controlSize(.large)
    }

    private func answer(approve: Bool, digits: String) {
        digitsFocused = false
        working = true
        Task {
            await model.answer(challenge, approve: approve, digits: digits)
            working = false
        }
    }
}
