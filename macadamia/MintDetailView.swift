import SwiftUI
import SwiftData

struct MintDetailView: View {
    @Bindable var mint: Mint

    // Access the model context
    @Environment(\.modelContext) private var modelContext
    // Access the dismiss action to pop the view
    @Environment(\.dismiss) private var dismiss

    // State variables for alert handling
    @State private var showDeleteConfirmation = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 80

    var body: some View {
        List {
            if let info = mint.info {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            Group {
                                Color.gray.opacity(0.3)
                                if let imageURL = info.imageURL {
                                    AsyncImage(url: imageURL) { phase in
                                        switch phase {
                                        case let .success(image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                        case .failure:
                                            Image(systemName: "photo")
                                        case .empty:
                                            ProgressView()
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                } else {
                                    Image(systemName: "building.columns")
                                        .foregroundColor(.white)
                                        .font(.title)
                                }
                            }
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(Circle())
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Text("No mint info available.")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("URL")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(mint.url.absoluteString)
                }
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
}
