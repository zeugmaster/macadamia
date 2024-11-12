import SwiftUI
import SwiftData
import CashuSwift
import Flow
import CryptoKit

struct MintInfoView: View {
    
    @Bindable var mint: Mint
    
    @State var info: CashuSwift.MintInfo?

    // Access the model context
    @Environment(\.modelContext) private var modelContext
    // Access the dismiss action to pop the view
    @Environment(\.dismiss) private var dismiss
    
    @State private var motd: String?

    // State variables for alert handling
    @State private var showDeleteConfirmation = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 80
    
    @State private var nicknameInput = ""
    
    var body: some View {
        List {
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: iconSize, height: iconSize)
                    Image(systemName: "building.columns")
                        .foregroundColor(.white)
                        .font(.title)
                }
                Spacer()
            }
            // Adjust the list row to remove default insets and background
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.bottom, 24) 
            if let motd {
                MOTDCell(message: motd, onDismiss: dismissMOTD)
            }
            Section {
                TextDescriptionCell(description: "URL", text: mint.url.absoluteString)
                VStack(alignment: .leading) {
                    Text("Nickname")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Enter a nickname...", text: $nicknameInput)
                        .onAppear {
                            nicknameInput = mint.nickName ?? ""
                        }
                        .onSubmit {
                            mint.nickName = nicknameInput
                            try? modelContext.save()
                        }
                }
            } footer: {
                Text("To save a nickname press Return.")
            }
            
            if let info {
                MintInfoDetailV0_16_0(info: info)
            }

            Section {
                Button(role: .destructive) {
                    // Show confirmation alert
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Remove this mint")
                        Spacer()
                        Image(systemName: "trash")
                    }
                }
                // Confirmation alert for deletion
                .alert("Remove Mint", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        deleteMint()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Are you sure you want to remove this mint?")
                }
            }
        }
        // Error alert if deletion fails
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            // fetch mint info
            do {
                logger.info("loading info for mint: \(mint.url.absoluteString)...")
                info = try await CashuSwift.loadInfoFromMint(mint)
            } catch {
                logger.warning("could not load mint info \(error)")
            }
            // show MOTD if changed
            if let infoV_0_16 = info as? CashuSwift.MintInfo0_16 {
                if mint.lastDismissedMOTDHash != infoV_0_16.motd.hashString() {
                    motd = infoV_0_16.motd
                }
            }
        }
    }

    // Function to delete the mint
    private func deleteMint() {
        // Delete the mint from the context
        modelContext.delete(mint)

        do {
            // Save the context to persist changes
            try modelContext.save()
            // Dismiss the view to go back
            dismiss()
        } catch {
            // Handle errors and show an alert
            errorMessage = "Failed to delete mint: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    private func dismissMOTD() {
        guard let infoV_0_16 = info as? CashuSwift.MintInfo0_16 else {
            return
        }
        mint.lastDismissedMOTDHash = infoV_0_16.motd.hashString()
        withAnimation {
            motd = nil
        }
    }
}

struct MintInfoDetailV0_16_0: View {
    var info: CashuSwift.MintInfo
    
    var body: some View {
        Section {
            TextDescriptionCell(description: "Version", text: info.version)
            TextDescriptionCell(description: "Name", text: info.name)
            if let short = info.descriptionShort {
                TextDescriptionCell(description: "Description", text: short)
            }
        }
        if let infoV_0_16 = info as? CashuSwift.MintInfo0_16 {
            
            Section {
                HFlow {
                    Tag(text: "Mint", enabled: !(infoV_0_16.nuts["4"]?.disabled ?? true))
                    Tag(text: "Melt", enabled: !(infoV_0_16.nuts["5"]?.disabled ?? true))
                    Tag(text: "Restore", enabled: (infoV_0_16.nuts["9"]?.supported == .bool(true)))
                    Tag(text: "P2PK", enabled: (infoV_0_16.nuts["11"]?.supported == .bool(true)))
                }
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }
    }
}

struct Tag: View {
    var text: String
    var enabled: Bool
    
    var body: some View {
        Text(text)
            .foregroundStyle(enabled ? .black : .white.opacity(0.6))
            .strikethrough(!enabled)
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .background(enabled ? .white.opacity(0.6) : .white.opacity(0.1))
            .cornerRadius(4)
    }
}

struct MOTDCell: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(message)
                .padding()
                .padding(.trailing, 32) // Ensure text doesn't overlap with the "x" button
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.6), lineWidth: 2)
                )
        )
        .overlay(
            // Close Button positioned at the top-right corner
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.orange)
                    .padding(8)
            }
            .buttonStyle(.plain),
            alignment: .topTrailing
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Consume taps on the entire cell to prevent default selection
        }
        // Match default cell insets
        .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
        // Add vertical padding to prevent clipping
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}


struct TextDescriptionCell: View {
    var description: String
    var text: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
    }
}

extension String {
    func hashString() -> String? {
        if !self.isEmpty {
            guard let data = self.data(using: .utf8) else {
                return nil
            }
            return String(bytes: SHA256.hash(data: data).bytes)
        } else {
            return nil
        }
    }
}
