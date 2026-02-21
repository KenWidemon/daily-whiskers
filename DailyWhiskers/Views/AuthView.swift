import SwiftUI

struct AuthView: View {
    private enum TestAccount {
        static let email = "test@dailywhiskers.app"
        static let password = "WhiskersTest123!"
    }

    @EnvironmentObject private var router: AppRouter

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var authError: String?
    @State private var isWorking = false

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

            GlowOverlay()
                .ignoresSafeArea()

            SparkleOverlay()
                .compositingGroup()
                .blendMode(.plusLighter)
                .opacity(0.4)
                .allowsHitTesting(false)

            // MARK: - Content
            VStack(spacing: 18) {
                Spacer()
                    .frame(height: 140)

                VStack(spacing: 10) {
                    Text("Daily Whiskers")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.primary)

                    Text("A calm cat moment, once per day.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.60))
                }
                .padding(.bottom, 10)

                VStack(spacing: 14) {
                    // Email
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 20, weight: .regular))
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(fieldBackground)
                        .overlay(fieldBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
                    
                    // Password
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 20, weight: .regular))
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(fieldBackground)
                        .overlay(fieldBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
                }
                .padding(.horizontal, 26)
                .padding(.top, 6)

                VStack(spacing: 14) {
                    // Primary: Sign In
                    Button {
                        Task { await handleEmailSignIn() }
                    } label: {
                        Text("Sign In")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.orange.opacity(0.22), radius: 10, y: 6)
                    }
                    .padding(.horizontal, 26)
                    .opacity(canSubmit ? 1 : 0.45)
                    .disabled(!canSubmit)
                    
                    // Secondary: Create Account (outline)
                    Button {
                        Task { await handleEmailCreateAccount() }
                    } label: {
                        Text("Create Account")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 0.90, green: 0.62, blue: 0.28))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color(red: 0.90, green: 0.62, blue: 0.28).opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.horizontal, 26)
                    .opacity(canSubmit ? 1 : 0.45)
                    .disabled(!canSubmit)
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .padding(.top, 2)
                }
                .opacity(isWorking ? 0.45 : 1)
                .disabled(isWorking)
#endif

                if let authError {
                    Text(authError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }

                Spacer()
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
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !isWorking
    }

    private func handleEmailSignIn() async {
        guard !isWorking else { return }
        isWorking = true
        authError = nil
        defer { isWorking = false }

        do {
            try await router.signInWithEmail(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    private func handleEmailCreateAccount() async {
        guard !isWorking else { return }
        isWorking = true
        authError = nil
        defer { isWorking = false }

        do {
            try await router.createEmailAccount(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    private func handleTestAccountSignInOrCreate() async {
        guard !isWorking else { return }
        isWorking = true
        authError = nil
        defer { isWorking = false }

        do {
            try await router.signInOrCreateEmail(
                email: TestAccount.email,
                password: TestAccount.password
            )
        } catch {
            authError = error.localizedDescription
        }
    }
}

private struct GlowOverlay: View {
    @State private var pulse = false

    var body: some View {
        // A subtle animated glow that draws attention to the title area
        RadialGradient(
            colors: [
                Color.orange.opacity(pulse ? 0.20 : 0.12),
                Color.clear
            ],
            center: UnitPoint(x: 0.5, y: 0.18),
            startRadius: pulse ? 20 : 8,
            endRadius: 420
        )
        .scaleEffect(pulse ? 1.03 : 0.98)
        .animation(
            .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
    }
}

private struct SparkleOverlay: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geometry in
                Canvas { context, size in
                    let dotCount = 75

                    for index in 0..<dotCount {
                        // Base positions
                        let baseX = pseudoRandom(index: index, seed: 0.73) * size.width
                        let yBias = pow(pseudoRandom(index: index, seed: 0.39), 1.6)
                        let baseY = yBias * size.height

                        // Each dot twinkles at a slightly different rate/phase
                        let phase = Double(pseudoRandom(index: index, seed: 0.17)) * Double.pi * 2
                        let speed = 0.6 + Double(pseudoRandom(index: index, seed: 0.41)) * 1.6
                        let twinkle = (sin(t * speed + phase) + 1) / 2 // 0...1

                        // Gentle drift (very small) so the field feels alive
                        let driftX = CGFloat(sin(t * 0.18 + phase)) * 0.7
                        let driftY = CGFloat(cos(t * 0.14 + phase)) * 0.5

                        let x = baseX + driftX
                        let y = baseY + driftY

                        // Bigger points so they read on a light background
                        let baseRadius = 1.6 + pseudoRandom(index: index, seed: 0.11) * 2.2
                        let radius = baseRadius + CGFloat(twinkle) * 1.4

                        // Higher alpha so sparkles are actually visible
                        let baseAlpha = 0.07 + pseudoRandom(index: index, seed: 0.91) * 0.07
                        let alpha = min(0.38, baseAlpha + CGFloat(twinkle) * 0.18)

                        // Slight tint so sparkles read on a very light background
                        let tintMix = pseudoRandom(index: index, seed: 0.66)
                        let sparkleColor: Color = (tintMix > 0.6)
                            ? Color(red: 1.0, green: 0.96, blue: 0.90) // warm ivory sparkle
                            : Color(red: 0.93, green: 0.95, blue: 1.0) // cool lunar sparkle

                        let rect = CGRect(x: x, y: y, width: radius, height: radius)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(sparkleColor.opacity(alpha))
                        )

                        // Occasionally draw a slightly larger star sparkle
                        if index % 20 == 0 {
                            let starRadius = radius * (2.4 + CGFloat(twinkle) * 1.1)
                            let starRect = CGRect(x: x - starRadius * 0.35, y: y - starRadius * 0.35, width: starRadius, height: starRadius)
                            context.fill(
                                Path(ellipseIn: starRect),
                                with: .color(sparkleColor.opacity(min(0.26, alpha * 0.85)))
                            )
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func pseudoRandom(index: Int, seed: Double) -> CGFloat {
        let value = sin(Double(index) * 12.9898 + seed * 78.233) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
