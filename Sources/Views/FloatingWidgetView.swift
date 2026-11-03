import SwiftUI
import UniformTypeIdentifiers

public struct FloatingWidgetView: View {
    @ObservedObject var discovery = SimulatorDiscovery.shared
    @ObservedObject var queue = QueueManager.shared
    @ObservedObject var controller = FloatingWidgetController.shared
    @ObservedObject var catalog = AppCatalog.shared

    @State private var isTargeted: Bool = false
    @State private var isShowingLinkPrompt: Bool = false
    @State private var linkInputText: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar / Drag Handle
            headerBar

            if !controller.isCollapsed {
                Divider()
                    .opacity(0.3)

                // Expanded content
                VStack(spacing: 10) {
                    // Simulator Target Strip
                    simulatorTargetStrip

                    // Queue or Empty Drop Zone
                    if queue.items.isEmpty {
                        emptyDropArea
                    } else {
                        queueListView
                    }

                    // Footer actions
                    footerActionBar
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: FloatingWidgetPanel.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isTargeted ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isTargeted ? 2 : 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onDrop(of: [.fileURL, .url], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .alert("Open Link in Simulator", isPresented: $isShowingLinkPrompt) {
            TextField("myapp://path or https://...", text: $linkInputText)
            Button("Add to Queue") {
                addLink(linkInputText)
            }
            Button("Cancel", role: .cancel) {
                linkInputText = ""
            }
        } message: {
            Text("Opens deep links, OAuth callbacks, or web URLs directly in the simulator.")
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        ZStack {
            // Native Window Drag Handle (covers whole header)
            WindowDragHandle()

            HStack(spacing: 8) {
                // Icon & Title
                HStack(spacing: 6) {
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)

                    Text("Harbor Drop")
                        .font(.system(size: 12, weight: .semibold))
                }

                // If collapsed or items present, show count badge
                if !queue.items.isEmpty {
                    Text("\(queue.items.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }

                Spacer()

                // Quick Send / Stop Button if collapsed and has items
                if controller.isCollapsed && !queue.items.isEmpty {
                    Button(action: {
                        if queue.isSending {
                            queue.cancelSend()
                        } else {
                            Task {
                                await queue.sendAll(targetDevice: discovery.targetDeviceIdentifier)
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if queue.isSending {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Stop")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10))
                                Text("Send")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(queue.isSending ? Color.red.opacity(0.85) : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                // Collapse / Expand Button (Sticky notes style)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controller.toggleCollapsed()
                    }
                }) {
                    Image(systemName: controller.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(controller.isCollapsed ? "Expand Queue" : "Collapse to Bar")

                // Close Button
                Button(action: {
                    controller.hide()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Close Window")
            }
            .padding(.horizontal, 10)
        }
        .frame(height: FloatingWidgetPanel.collapsedHeight)
    }

    // MARK: - Simulator Target Strip
    private var simulatorTargetStrip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(discovery.selectedDevice?.isBooted == true ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 7, height: 7)

            Picker("", selection: $discovery.selectedDevice) {
                if !discovery.bootedDevices.isEmpty {
                    Section("Running") {
                        ForEach(discovery.bootedDevices) { dev in
                            Text(discovery.displayName(for: dev)).tag(Optional(dev))
                        }
                    }
                }

                ForEach(discovery.shutdownGroups) { group in
                    Section(group.runtime) {
                        ForEach(group.devices) { dev in
                            Text(dev.name).tag(Optional(dev))
                        }
                    }
                }
            }
            .labelsHidden()
            .controlSize(.small)

            Spacer()

            Button(action: { discovery.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh Simulators")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Empty Drop Area
    private var emptyDropArea: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.rectangle.on.folder.fill")
                .font(.system(size: 28))
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.8))

            Text(isTargeted ? "Drop to add to queue" : "Drop Files, Photos, or .app")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Text("Queue multiple files and send together")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Button(action: { isShowingLinkPrompt = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text("Add Link / Deep Link")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02))
                )
        )
    }

    // MARK: - Queue List View
    private var queueListView: some View {
        VStack(spacing: 6) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(queue.items) { item in
                        QueueItemRow(
                            item: item,
                            onRemove: { queue.remove(id: item.id) },
                            onDestinationChange: { dest in queue.setDestination(dest, for: item.id) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 180)

            // Mini drop strip below queue to add more
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                    Text("Drop more files")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)

                Spacer()

                Button("+ Link") {
                    isShowingLinkPrompt = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
    }

    // MARK: - Footer Action Bar
    private var footerActionBar: some View {
        VStack(spacing: 8) {
            if queue.isSending {
                HStack(alignment: .center, spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(queue.statusMessage ?? "Sending...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(queue.isSuccess ? .green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Success messages shown in green
                    if let success = queue.successMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .padding(.top, 1)

                            Text(success)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .help(success)
                    }

                    // Error messages shown in red
                    if let error = queue.errorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                                .padding(.top, 1)

                            Text(error)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            Button(action: {
                                withAnimation {
                                    queue.dismissError()
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                            .help("Dismiss error")
                        }
                        .padding(.horizontal, 4)
                        .help(error)
                    }
                }
            }

            // ── Batch destination row ─────────────────────────────────────────
            // Allows user to route all eligible files in one click.
            // Individual pills can still be overridden afterwards.
            if canConfigureBatchTarget {
                batchDestinationRow
            }

            // ── Clear / Send ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                if !queue.items.isEmpty {
                    Button("Clear") {
                        queue.clear()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(queue.isSending)
                }

                Spacer()

                Button(action: {
                    if queue.isSending {
                        queue.cancelSend()
                    } else {
                        Task {
                            await queue.sendAll(targetDevice: discovery.targetDeviceIdentifier)
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        if queue.isSending {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Stop")
                                .font(.system(size: 12, weight: .semibold))
                        } else {
                            Image(systemName: isAllQueuedItemsFailed ? "arrow.clockwise" : "paperplane.fill")
                                .font(.system(size: 11))
                            Text(sendButtonTitle)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        queue.isSending
                            ? Color.red.opacity(0.85)
                            : (queue.items.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(queue.items.isEmpty && !queue.isSending)
            }
        }
    }

    // MARK: - Batch Destination Row

    /// True when the queue has at least one item that supports destination override
    /// and a transfer is not actively in progress.
    private var canConfigureBatchTarget: Bool {
        !queue.isSending && queue.items.contains(where: \.supportsDestinationOverride)
    }

    /// A compact row in the footer that lets the user set the destination for
    /// all queued files in a single step, updating every individual row's pill.
    private var batchDestinationRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down.on.square")
                .renderingMode(.template)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text("Send all to →")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            Menu {
                // Auto (smart routing by file type) - no wand icon
                Button(action: {
                    queue.setDestinationForAll(.auto)
                }) {
                    Text("Auto (Smart routing)")
                }

                Divider()

                // Files app
                Button(action: {
                    queue.setDestinationForAll(.filesApp)
                }) {
                    Label("Files app", systemImage: "folder.fill")
                }

                // Installed apps
                if catalog.isLoading {
                    Divider()
                    Text("Loading apps…")
                } else if !catalog.apps.isEmpty {
                    Divider()
                    ForEach(catalog.apps) { app in
                        Button(action: {
                            queue.setDestinationForAll(.appDocuments(bundleId: app.bundleId))
                        }) {
                            Label(app.displayName, systemImage: "app.badge.fill")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let icon = batchTargetIcon {
                        Image(systemName: icon)
                            .renderingMode(.template)
                            .font(.system(size: 9))
                    }
                    Text(batchTargetLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 90)
                    Image(systemName: "chevron.up.chevron.down")
                        .renderingMode(.template)
                        .font(.system(size: 8))
                }
                .foregroundColor(isBatchTargetHighlighted ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isBatchTargetHighlighted
                              ? Color.white.opacity(0.12)
                              : Color.white.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onAppear {
                // Pre-load the app list when the footer becomes visible
                if let udid = discovery.selectedDevice?.udid {
                    catalog.fetchIfNeeded(for: udid)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var batchTargetLabel: String {
        switch queue.batchDestinationState {
        case .none:
            return "Auto"
        case .uniform(let dest):
            switch dest {
            case .auto:
                return "Auto"
            case .filesApp:
                return "Files"
            case .photos:
                return "Photos"
            case .appDocuments(let bundleId):
                return catalog.apps.first(where: { $0.bundleId == bundleId })?.displayName ?? bundleId
            }
        case .mixed:
            return "Mixed"
        }
    }

    private var batchTargetIcon: String? {
        switch queue.batchDestinationState {
        case .none, .uniform(.auto):
            return nil // Clean text only, no wand icon
        case .uniform(let dest):
            switch dest {
            case .auto:
                return nil
            case .filesApp:
                return "folder.fill"
            case .photos:
                return "photo.on.rectangle.fill"
            case .appDocuments:
                return "app.badge.fill"
            }
        case .mixed:
            return "slider.horizontal.3"
        }
    }

    private var isBatchTargetHighlighted: Bool {
        switch queue.batchDestinationState {
        case .none, .uniform(.auto):
            return false
        case .uniform, .mixed:
            return true
        }
    }

    private var isAllQueuedItemsFailed: Bool {
        !queue.items.isEmpty && queue.items.allSatisfy { $0.failureReason != nil || $0.failureMessage != nil }
    }

    private var sendButtonTitle: String {
        if queue.isSending {
            return "Sending..."
        }
        let count = queue.items.count
        if isAllQueuedItemsFailed {
            return count <= 1 ? "Retry" : "Retry \(count) Items"
        }
        if count <= 1 {
            return "Send to Simulator"
        } else {
            return "Send \(count) Items"
        }
    }

    // MARK: - Drop Handler
    private func handleDrop(providers: [NSItemProvider]) {
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    collectedURLs.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !collectedURLs.isEmpty else { return }
            self.queue.add(urls: collectedURLs)

            // Auto-expand if collapsed so user sees queued items
            if self.controller.isCollapsed {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.controller.isCollapsed = false
                }
            }
        }
    }

    private func addLink(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        queue.add(urls: [url])
        linkInputText = ""
    }
}
