import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]
    @State private var lock = AppLock()
    @State private var content = ContentStore()

    private var current: AppSettings? { settings.first }

    var body: some View {
        ZStack {
            switch content.state {
            case .loading:
                ProgressView("Loading your programs")
            case .failed(let message):
                ContentUnavailableView("Couldn't load programs", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .ready:
                if current?.onboardingComplete == true {
                    MainTabView()
                } else {
                    OnboardingFlow()
                }
            }
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            } else if scenePhase != .active && lock.enabled {
                // Hides health data in the app switcher.
                PrivacyShield()
            }
        }
        .environment(lock)
        .environment(content)
        .preferredColorScheme(.dark)
        .tint(Color.gold)
        .task {
            await content.load()
            if current == nil {
                context.insert(AppSettings())
                try? context.save()
            }
            syncLock()
            lock.lockNow()
            if ProcessInfo.processInfo.arguments.contains("-UITestForceLock") {
                lock.configure(enabled: true, timeoutSeconds: 0)
                lock.lockNow()
            }
        }
        .onChange(of: current?.lockEnabled) { _, _ in syncLock() }
        .onChange(of: current?.lockTimeoutSeconds) { _, _ in syncLock() }
        .onChange(of: current?.onboardingComplete) { _, _ in syncLock() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active: lock.willEnterForeground()
            default: break
            }
        }
    }

    /// The lock only applies once onboarding is finished and it's switched on.
    private func syncLock() {
        if ProcessInfo.processInfo.arguments.contains("-UITestForceLock") { return }
        guard let s = current else { return }
        lock.configure(enabled: s.onboardingComplete && s.lockEnabled, timeoutSeconds: s.lockTimeoutSeconds)
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Color("Plum").ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(LinearGradient.brand)
                    .accessibilityHidden(true)
                Text("Steady Strength is locked")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                if let error = lock.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(AppLock.biometryName)", systemImage: AppLock.biometrySymbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gold)
                .foregroundStyle(Color.night)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("unlockButton")
                Spacer().frame(height: 40)
            }
        }
        .task {
            // Ask for Face ID straight away (not under UI tests, which tap the button).
            if !ProcessInfo.processInfo.arguments.contains("-UITestBypassAuth") { await lock.unlock() }
        }
    }
}

struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Color("Plum").ignoresSafeArea()
            Text("Steady Strength")
                .font(.title.bold())
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}
