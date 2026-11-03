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
            // ── File-type icon (uniform clean white) ──────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)

                Image(systemName: item.kind.systemImage)
                    .renderingMode(.template)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            // ── Name & Subtitle ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(item.kind.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if !item.formattedSize.isEmpty {
                        Text("·")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(item.formattedSize)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
            }

            Spacer(minLength: 4)

            // ── Destination Pill ─────────────────────────────────────────────
            if item.supportsDestinationOverride {
                destinationChip
            }

            // ── Remove button ────────────────────────────────────────────────
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .renderingMode(.template)
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
            HStack(spacing: 4) {
                if let icon = chipIcon {
                    Image(systemName: icon)
                        .renderingMode(.template)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(chipContentColor)
                }

                Text(chipLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 130)
                    .foregroundColor(chipContentColor)

                Image(systemName: "chevron.down")
                    .renderingMode(.template)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(chipContentColor.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(chipBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            destinationPickerPopover
        }
    }

    /// SF Symbol for the chip. Auto has NO icon (clean text only).
    private var chipIcon: String? {
        switch item.destination {
        case .auto:
            return nil
        case .photos:
            return "photo.on.rectangle.fill"
        case .filesApp:
            return "folder.fill"
        case .appDocuments:
            return "app.badge.fill"
        }
    }

    /// Text shown inside the chip.
    private var chipLabel: String {
        switch item.destination {
        case .auto:
            return "Auto"
        case .photos:
            return "Photos"
        case .filesApp:
            return "Files"
        case .appDocuments(let bundleId):
            return catalog.apps.first(where: { $0.bundleId == bundleId })?.displayName ?? bundleId
        }
    }

    private var chipContentColor: Color {
        item.destination.isAuto ? Color.secondary : Color.white
    }

    private var chipBackgroundColor: Color {
        item.destination.isAuto ? Color.white.opacity(0.06) : Color.white.opacity(0.12)
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
                    // ── Auto (Smart routing) ──────────────────────────────
                    destinationRow(
                        icon: nil,
                        label: "Auto",
                        subtitle: item.kind == .photo || item.kind == .video ? "Photos library" : "Files app (On My iPhone)",
                        destination: .auto
                    )

                    // ── Photos (ONLY for media items) ─────────────────────
                    if item.kind == .photo || item.kind == .video {
                        Divider().padding(.leading, 36)
                        destinationRow(
                            icon: "photo.on.rectangle.fill",
                            label: "Photos",
                            subtitle: "Simulator photo library",
                            destination: .photos
                        )
                    }

                    Divider().padding(.leading, 36)

                    // ── Files app ─────────────────────────────────────────
                    destinationRow(
                        icon: "folder.fill",
                        label: "Files app",
                        subtitle: "On My iPhone",
                        destination: .filesApp
                    )

                    // ── Installed apps ────────────────────────────────────
                    if catalog.isLoading {
                        Divider().padding(.leading, 36)
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Loading apps…")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else if !catalog.apps.isEmpty {
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
            .frame(maxHeight: 280)
        }
        .frame(width: 230)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func destinationRow(
        icon: String?,
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
                // Checkmark or placeholder spacer
                if isSelected {
                    Image(systemName: "checkmark")
                        .renderingMode(.template)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 14)
                } else {
                    Spacer()
                        .frame(width: 14)
                }

                // Destination icon (if any)
                if let icon = icon {
                    Image(systemName: icon)
                        .renderingMode(.template)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .frame(width: 16)
                } else {
                    Spacer()
                        .frame(width: 16)
                }

                // Labels
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.white)
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
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
    }
}
