import SwiftUI
import UIKit

struct AuthView: View {
    private enum Field: Hashable { case email, password }
    private enum AccessibilityTarget: Hashable { case error, reset }
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityTarget: AccessibilityTarget?
#if DEBUG
    private enum TestAccount {
        static let email = "test@dailywhiskers.app"
        static let password = "WhiskersTest123!"
    }

#endif

    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email: String = ""
    @State private var password: String = ""
    @StateObject private var request = AuthRequestState()

    private var isWorking: Bool { request.isWorking }

    var body: some View {
        ZStack {
            // Background (cool -> warm) + subtle title glow
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.94, blue: 0.98), // soft lavender-gray
                    Color(red: 1.00, green: 0.97, blue: 0.92)  // warm ivory
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GlowOverlay(reduceMotion: reduceMotion)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            SparkleOverlay(reduceMotion: reduceMotion)
                .compositingGroup()
                .blendMode(.plusLighter)
                .opacity(0.4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // MARK: - Content
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    ScrollView {
                        loginContent
                            .frame(maxWidth: 520)
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: request.errorMessage) { _, message in
                        guard message != nil else { return }
                        scroll.scrollTo("auth-error", anchor: .bottom)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") { focusedField = nil }
                    .frame(minHeight: 44)
            }
        }
        .preferredColorScheme(.light)
        .alert("Check Your Email", isPresented: Binding(
            get: { request.confirmation != nil },
            set: { if !$0 { dismissResetConfirmation() } }
        )) {
            Button("OK", role: .cancel) { dismissResetConfirmation() }
        } message: {
            Text(request.confirmation ?? "")
        }
        .onChange(of: email) { _, _ in
            request.clearFeedback()
        }
        .onChange(of: password) { _, _ in
            request.clearFeedback()
        }
        .onChange(of: request.operation) { _, operation in
            guard let message = operation?.announcement else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private var loginContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("Daily Whiskers")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("A calm cat moment, once per day.")
                    .font(.headline)
                    .foregroundStyle(Color.primary.opacity(0.60))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 26)
            .padding(.bottom, 10)

            VStack(spacing: 14) {
                // Email
                TextField("Email", text: $email, prompt: Text("Email").foregroundStyle(Color(white: 0.38)))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { if !isWorking { focusedField = .password } }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 54)
                    .background(fieldBackground)
                    .overlay(fieldBorder)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
                    .accessibilityLabel("Email")
                    .accessibilityHint("Enter the email for your account.")

                // Password
                SecureField("Password", text: $password, prompt: Text("Password").foregroundStyle(Color(white: 0.38)))
                    .textContentType(.password)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        guard canSubmit else { return }
                        Task { await handleEmailSignIn() }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 54)
                    .background(fieldBackground)
                    .overlay(fieldBorder)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
                    .accessibilityLabel("Password")
                    .accessibilityHint("Enter your password.")
            }
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .disabled(isWorking)

            Button {
                focusedField = nil
                Task {
                    await request.resetPassword(email: email) { address in
                        try await router.sendPasswordReset(email: address)
                    }
                }
            } label: {
                HStack {
                    if request.operation == .passwordReset {
                        ProgressView()
                    }
                    Text(request.operation == .passwordReset ? "Sending Reset Link..." : "Forgot password?")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
            .tint(Color(red: 0.60, green: 0.34, blue: 0.12))
            .padding(.horizontal, 26)
            .disabled(isWorking)
            .accessibilityHint("Sends a password reset link to the email entered above.")
            .accessibilityFocused($accessibilityTarget, equals: .reset)

            VStack(spacing: 14) {
                // Primary: Sign In
                Button {
                    Task { await handleEmailSignIn() }
                } label: {
                    Group {
                        if request.operation == .signIn || request.operation == .testAccount {
                            ProgressView()
                                .tint(Color(red: 0.24, green: 0.12, blue: 0.04))
                                .accessibilityLabel("Signing in")
                        } else {
                            Text("Sign In")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.24, green: 0.12, blue: 0.04))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .frame(minHeight: 54)
                    .background(primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.orange.opacity(0.22), radius: 10, y: 6)
                }
                .padding(.horizontal, 26)
                .saturation(canSubmit || isWorking ? 1 : 0.25)
                .disabled(!canSubmit)
                .accessibilityHint("Signs into your account.")

                // Secondary: Create Account (outline)
                Button {
                    Task { await handleEmailCreateAccount() }
                } label: {
                    Text(request.operation == .createAccount ? "Creating Account..." : "Create Account")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.55, green: 0.29, blue: 0.08))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(minHeight: 54)
                        .background(Color.white.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(red: 0.55, green: 0.29, blue: 0.08).opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 26)
                .saturation(canSubmit ? 1 : 0.25)
                .disabled(!canSubmit)
                .accessibilityHint("Creates a new account with your email and password.")
            }
            .padding(.top, 10)

            // Dev-only helper
#if DEBUG
            Button {
                email = TestAccount.email
                password = TestAccount.password
                Task { await handleTestAccountSignInOrCreate() }
            } label: {
                Text("Use Test Account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .padding(.top, 2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .opacity(isWorking ? 0.45 : 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 26)
            .disabled(isWorking)
            .accessibilityHint("Uses the built-in debug account.")
#endif

            if let authError = request.errorMessage {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.65, green: 0.12, blue: 0.12))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                    .id("auth-error")
                    .accessibilityFocused($accessibilityTarget, equals: .error)
                    .onAppear { accessibilityTarget = .error }
            }

        }
    }

    // MARK: - Subviews

    private var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.72, blue: 0.40), // soft amber
                Color(red: 0.91, green: 0.63, blue: 0.28)  // deeper gold
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.65))
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 3)
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.black.opacity(0.06), lineWidth: 1)
    }

    private var canSubmit: Bool {
        AuthRequestState.isValidEmail(email) && password.count >= 6 && !isWorking
    }

    private func dismissResetConfirmation() {
        request.confirmation = nil
        accessibilityTarget = .reset
    }

    private func handleEmailSignIn() async {
        guard canSubmit else { return }
        focusedField = nil
        await request.perform(.signIn) {
            try await router.signInWithEmail(
                email: AuthRequestState.normalizedEmail(email), password: password
            )
        }
    }

    private func handleEmailCreateAccount() async {
        guard canSubmit else { return }
        focusedField = nil
        await request.perform(.createAccount) {
            try await router.createEmailAccount(
                email: AuthRequestState.normalizedEmail(email), password: password
            )
        }
    }

#if DEBUG
    private func handleTestAccountSignInOrCreate() async {
        focusedField = nil
        await request.perform(.testAccount) {
            try await router.signInOrCreateEmail(email: TestAccount.email, password: TestAccount.password)
        }
    }
#endif

}

private struct GlowOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            glow(pulse: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { timeline in
                let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 3) + 1) / 2
                glow(pulse: pulse)
            }
        }
    }

    private func glow(pulse: Double) -> some View {
        RadialGradient(
            colors: [
                Color.orange.opacity(0.12 + 0.08 * pulse),
                Color.clear
            ],
            center: UnitPoint(x: 0.5, y: 0.18),
            startRadius: 8 + 12 * pulse,
            endRadius: 420
        )
        .scaleEffect(0.98 + 0.05 * pulse)
    }
}

private struct SparkleOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Canvas { context, size in
                drawSparkles(context: context, size: size, time: 0, animated: false)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                Canvas { context, size in
                    drawSparkles(context: context, size: size, time: t, animated: true)
                }
            }
        }
    }

    private func drawSparkles(context: GraphicsContext, size: CGSize, time: Double, animated: Bool) {
        let dotCount = animated ? 75 : 36

        for index in 0..<dotCount {
            let baseX = pseudoRandom(index: index, seed: 0.73) * size.width
            let yBias = pow(pseudoRandom(index: index, seed: 0.39), 1.6)
            let baseY = yBias * size.height

            let phase = Double(pseudoRandom(index: index, seed: 0.17)) * Double.pi * 2
            let speed = 0.6 + Double(pseudoRandom(index: index, seed: 0.41)) * 1.6
            let twinkle = animated ? (sin(time * speed + phase) + 1) / 2 : 0.35

            let driftX = animated ? CGFloat(sin(time * 0.18 + phase)) * 0.7 : 0
            let driftY = animated ? CGFloat(cos(time * 0.14 + phase)) * 0.5 : 0

            let x = baseX + driftX
            let y = baseY + driftY

            let baseRadius = 1.6 + pseudoRandom(index: index, seed: 0.11) * 2.2
            let radius = baseRadius + CGFloat(twinkle) * (animated ? 1.4 : 0.5)

            let baseAlpha = 0.07 + pseudoRandom(index: index, seed: 0.91) * 0.07
            let alpha = min(0.38, baseAlpha + CGFloat(twinkle) * (animated ? 0.18 : 0.07))

            let tintMix = pseudoRandom(index: index, seed: 0.66)
            let sparkleColor: Color = (tintMix > 0.6)
                ? Color(red: 1.0, green: 0.96, blue: 0.90)
                : Color(red: 0.93, green: 0.95, blue: 1.0)

            let rect = CGRect(x: x, y: y, width: radius, height: radius)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(sparkleColor.opacity(alpha))
            )

            if index % 20 == 0 {
                let starRadius = radius * (2.4 + CGFloat(twinkle) * 1.1)
                let starRect = CGRect(
                    x: x - starRadius * 0.35,
                    y: y - starRadius * 0.35,
                    width: starRadius,
                    height: starRadius
                )
                context.fill(
                    Path(ellipseIn: starRect),
                    with: .color(sparkleColor.opacity(min(0.26, alpha * 0.85)))
                )
            }
        }
    }

    private func pseudoRandom(index: Int, seed: Double) -> CGFloat {
        let value = sin(Double(index) * 12.9898 + seed * 78.233) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
