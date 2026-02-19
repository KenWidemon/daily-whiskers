import SwiftUI

struct DailyWhiskersView: View {
    @EnvironmentObject private var router: AppRouter

    private let provider = DailyContentProvider()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if let entry = provider.contentForToday() {
                    VStack(spacing: 16) {
                        Image(entry.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 260, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Text("\"\(entry.quote.text)\"")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let vibe = entry.quote.vibe, !vibe.isEmpty {
                            Text(vibe.uppercased())
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 20, y: 8)
                    .padding(20)
                } else {
                    Text("No daily content found.")
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log Out", role: .destructive) {
                            do {
                                try router.signOut()
                            } catch {
                                // Keep UI minimal for v1.
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationTitle("Daily Whiskers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
