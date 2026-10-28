import SwiftUI

public struct ShortcutFixView: View {
    @State private var isFixActive: Bool = false
    @State private var feedbackText: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Host Shortcut Policy", systemImage: "command")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $isFixActive)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: isFixActive) { newValue in
                        applyChange(enabled: newValue)
                    }
            }

            Text("Prevents Device Hub from swallowing ⌘H, ⌘Tab, and global system shortcuts.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let feedback = feedbackText {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                    Text(feedback)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .onAppear {
            isFixActive = DefaultsService.shared.isHostKeybindingFixActive()
        }
    }

    private func applyChange(enabled: Bool) {
        let result = DefaultsService.shared.setHostKeybindingFix(enabled: enabled)
        if result.isSuccess {
            feedbackText = "Saved. Restart Device Hub/Xcode if already open."
        } else {
            feedbackText = result.message
        }
    }
}
