import SwiftUI

// MARK: - Insertion Indicator

struct InsertionIndicator: View {
    var body: some View {
        Rectangle()
            .fill(Color.blue.opacity(0.72))
            .frame(width: 4, height: 120)
            .cornerRadius(2)
            .shadow(color: .blue.opacity(0.5), radius: 6)
    }
}
