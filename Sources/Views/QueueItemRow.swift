import SwiftUI

public struct QueueItemRow: View {
    public let item: QueueItem
    public let onRemove: () -> Void

    public init(item: QueueItem, onRemove: @escaping () -> Void) {
        self.item = item
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)

                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(item.kind.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if !item.formattedSize.isEmpty {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(item.formattedSize)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Remove from queue")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
