import SwiftUI

struct DocumentConflictBanner: View {
    let conflictCount: Int
    let onUseNewest: () -> Void
    let onKeepCurrent: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud edit conflict")
                    .font(.headline)
                Text("\(conflictCount) other version\(conflictCount == 1 ? "" : "s") need a decision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Keep Current", action: onKeepCurrent)
            Button("Use Newest", action: onUseNewest)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}
