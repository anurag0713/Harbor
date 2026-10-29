import SwiftUI
import UniformTypeIdentifiers

public struct FloatingWidgetView: View {
    @ObservedObject var discovery = SimulatorDiscovery.shared
    @ObservedObject var queue = QueueManager.shared
    @ObservedObject var controller = FloatingWidgetController.shared

    @State private var isTargeted: Bool = false

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
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
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
                        .foregroundColor(.accentColor)

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

                // Quick Send Button if collapsed and has items
                if controller.isCollapsed && !queue.items.isEmpty {
                    Button(action: {
                        Task {
                            await queue.sendAll(targetDevice: discovery.targetDeviceIdentifier)
                        }
                    }) {
                        HStack(spacing: 4) {
                            if queue.isSending {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10))
                                Text("Send")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(queue.isSending)
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
                        QueueItemRow(item: item) {
                            queue.remove(id: item.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 180)

            // Mini drop strip below queue to add more
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 10))
                Text("Drop more files to add to queue")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
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
            if let status = queue.statusMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: queue.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(queue.isSuccess ? .green : .red)
                        .padding(.top, 1)

                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(queue.isSuccess ? .green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .help(status)
            }

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
                    Task {
                        await queue.sendAll(targetDevice: discovery.targetDeviceIdentifier)
                    }
                }) {
                    HStack(spacing: 5) {
                        if queue.isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                        }
                        Text(sendButtonTitle)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(queue.items.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(queue.items.isEmpty || queue.isSending)
            }
        }
    }

    private var sendButtonTitle: String {
        if queue.isSending {
            return "Sending..."
        }
        let count = queue.items.count
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
}
