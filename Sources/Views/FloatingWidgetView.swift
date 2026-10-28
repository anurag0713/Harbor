import SwiftUI
import UniformTypeIdentifiers

public struct FloatingWidgetView: View {
    @ObservedObject var discovery = SimulatorDiscovery.shared
    @State private var isTargeted: Bool = false
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = true

    public init() {}

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.accentColor : Color.primary.opacity(0.08))
                    .frame(width: 38, height: 38)

                Image(systemName: isTargeted ? "arrow.down" : "ferry.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isTargeted ? .white : .primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let status = statusMessage {
                    Text(status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSuccess ? .green : .red)
                        .lineLimit(1)
                } else {
                    Text("Harbor Drop")
                        .font(.system(size: 12, weight: .semibold))
                    Text(discovery.selectedDevice?.name ?? "No Sim Booted")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: {
                FloatingWidgetPanel.shared.orderOut(nil)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 210, height: 60)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isTargeted ? 2 : 1)
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

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
            self.statusMessage = "Importing..."
            self.isSuccess = true

            Task {
                let targetUDID = discovery.targetDeviceIdentifier
                let result = await FileRouter.shared.routeAndTransfer(urls: collectedURLs, targetDevice: targetUDID)
                await MainActor.run {
                    self.statusMessage = result.isSuccess ? "Imported!" : "Failed"
                    self.isSuccess = result.isSuccess
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.statusMessage = nil
                    }
                }
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
