import SwiftUI

struct RootView: View {
    var body: some View {
        // Bundled content is available before and independently of Firebase's session.
        DailyWhiskersView()
    }
}
