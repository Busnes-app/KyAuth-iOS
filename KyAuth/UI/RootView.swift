import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
            switch model.lockState {
            case .unlocked: MainTabView()
            case .needsPin: PinUnlockView()
            case .locked: LockView()
            }
            if scenePhase != .active || model.screenCaptured {
                PrivacyCover()
            }
        }
        .tint(.accentColor)
        .background(ActivityTracker { model.recordActivity() })
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in model.checkIdle() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            model.screenCaptured = ScreenCapture.isActive
        }
        .onAppear { model.screenCaptured = ScreenCapture.isActive }
        .sheet(item: Binding(get: { model.signOnRequest.map(SignOnSheetItem.init) }, set: { _ in })) { item in
            SignOnSheet(request: item.request)
        }
        .alert(
            "Sign-in",
            isPresented: Binding(get: { model.signOnNotice != nil }, set: { if !$0 { model.signOnNotice = nil } }),
            presenting: model.signOnNotice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .overlay(alignment: .bottom) { Toast(message: $model.notice) }
    }
}

private struct SignOnSheetItem: Identifiable {
    let request: SignOnRequest
    var id: String { request.nonce }
}

/// Hides codes in the app switcher snapshot and while the screen is recorded or mirrored.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            BrandMark(size: 72)
        }
        .ignoresSafeArea()
    }
}

enum ScreenCapture {
    @MainActor static var isActive: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.traitCollection.sceneCaptureState == .active }
    }
}

struct BrandMark: View {
    var size: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
                .accessibilityHidden(true)
            Text("KyAuth")
                .font(.largeTitle.weight(.bold))
        }
    }
}

struct Toast: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { self.message = nil }
                }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Records every touch for the idle lock without consuming it.
struct ActivityTracker: UIViewRepresentable {
    let onActivity: () -> Void

    func makeUIView(context: Context) -> TrackerView {
        TrackerView(onActivity: onActivity)
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {}

    final class TrackerView: UIView {
        private let recognizer: TouchRecognizer

        init(onActivity: @escaping () -> Void) {
            recognizer = TouchRecognizer(onActivity: onActivity)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }
    }

    final class TouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private let onActivity: () -> Void

        init(onActivity: @escaping () -> Void) {
            self.onActivity = onActivity
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onActivity()
            state = .failed
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
