import SwiftUI

public struct QueueItemRow: View {
    public let item: QueueItem
    public let onRemove: () -> Void
    public let onDestinationChange: (QueueItemDestination) -> Void

    @ObservedObject private var catalog = AppCatalog.shared
    @ObservedObject private var discovery = SimulatorDiscovery.shared
    @State private var showingPicker = false

    public init(
        item: QueueItem,
        onRemove: @escaping () -> Void,
        onDestinationChange: @escaping (QueueItemDestination) -> Void
    ) {
        self.item = item
        self.onRemove = onRemove
        self.onDestinationChange = onDestinationChange
    }

    public var body: some View {
        HStack(spacing: 8) {
            // ── File-type icon ───────────────────────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)

                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            // ── Name + meta row ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    // Kind label
                    Text(item.kind.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if !item.formattedSize.isEmpty {
                        Text("·")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(item.formattedSize)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    // Destination chip — only for items that support override
                    if item.supportsDestinationOverride {
                        Spacer(minLength: 0)
                        destinationChip
                    }
                }
            }

            Spacer(minLength: 0)

            // ── Remove button ────────────────────────────────────────────────
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

    // MARK: - Destination Chip

    private var destinationChip: some View {
        Button(action: {
            // Trigger lazy app list load when the chip is first tapped.
            if let udid = discovery.selectedDevice?.udid {
                catalog.fetchIfNeeded(for: udid)
            }
            showingPicker = true
        }) {
            HStack(spacing: 3) {
                Image(systemName: chipIcon)
                    .font(.system(size: 9, weight: .semibold))
                Text(chipLabel)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(item.destination.isAuto ? .secondary : .accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(item.destination.isAuto
                          ? Color.primary.opacity(0.07)
                          : Color.accentColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            destinationPickerPopover
        }
    }

    /// The SF Symbol shown on the chip.
    private var chipIcon: String {
        switch item.destination {
        case .auto:
            // Show what auto resolves to as the icon, greyed out
            return QueueItemDestination.autoResolved(for: item.kind).systemImage
        default:
            return item.destination.systemImage
        }
    }

    /// The text shown on the chip.
    private var chipLabel: String {
        switch item.destination {
        case .auto:
            let resolved = QueueItemDestination.autoResolved(for: item.kind)
            return "Auto · \(resolved.chipLabel)"
        case .photos:
            return "Photos"
        case .filesApp:
            return "Files"
        case .appDocuments(let bundleId):
            // Resolve display name from catalog
            return catalog.apps.first(where: { $0.bundleId == bundleId })?.displayName ?? bundleId
        }
    }

    // MARK: - Picker Popover

    private var destinationPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Send to")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    // ── Auto ──────────────────────────────────────────────
                    destinationRow(
                        icon: "wand.and.stars",
                        label: "Auto",
                        subtitle: "Smart routing by file type",
                        destination: .auto
                    )

                    Divider().padding(.leading, 36)

                    // ── Photos ────────────────────────────────────────────
                    destinationRow(
                        icon: "photo.on.rectangle.fill",
                        label: "Photos",
                        subtitle: "Simulator photo library",
                        destination: .photos
                    )

                    // ── Files app ─────────────────────────────────────────
                    destinationRow(
                        icon: "folder.fill",
                        label: "Files",
                        subtitle: "On My iPhone · Files app",
                        destination: .filesApp
                    )

                    // ── Installed apps ────────────────────────────────────
                    if catalog.isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Loading apps…")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else if catalog.apps.isEmpty {
                        Text("No third-party apps installed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    } else {
                        Divider().padding(.leading, 36)

                        Text("App Documents")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(catalog.apps) { app in
                            destinationRow(
                                icon: "app.badge.fill",
                                label: app.displayName,
                                subtitle: app.bundleId,
                                destination: .appDocuments(bundleId: app.bundleId)
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 240)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func destinationRow(
        icon: String,
        label: String,
        subtitle: String,
        destination: QueueItemDestination
    ) -> some View {
        let isSelected = item.destination == destination

        Button(action: {
            onDestinationChange(destination)
            showingPicker = false
        }) {
            HStack(spacing: 8) {
                // Checkmark or spacer
                Image(systemName: isSelected ? "checkmark" : "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 14)

                // Destination icon
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)

                // Labels
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.07) : Color.clear)
    }
}
