import SwiftUI

struct Relays: View {
    
    @Binding var urls: [URL]
    
    @State private var newURL = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            Section {
                ForEach(urls, id: \.self) { url in
                    Text(url.absoluteString)
                }
                .onDelete(perform: deleteRelay)
            }
            Section {
                TextField("", text: $newURL, prompt: Text("wss://relay..."))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        addRelay()
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Add") {
                                addRelay()
                            }
                            .disabled(newURL.isEmpty)
                        }
                    }
            }
        }
        .alert("Invalid URL", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func addRelay() {
        guard !newURL.isEmpty else { return }
        
        // Check for websocket prefix
        guard newURL.lowercased().hasPrefix("ws://") || newURL.lowercased().hasPrefix("wss://") else {
            errorMessage = "Relay URL must start with ws:// or wss://"
            showError = true
            return
        }
        
        guard let url = URL(string: newURL) else {
            errorMessage = "Invalid URL format"
            showError = true
            return
        }
        
        // Check if URL already exists
        guard !urls.contains(url) else {
            errorMessage = "This relay is already in your list"
            showError = true
            return
        }
        
        urls.append(url)
        newURL = ""
    }
    
    private func deleteRelay(at offsets: IndexSet) {
        urls.remove(atOffsets: offsets)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var urls = [
            URL(string: "wss://relay.to")!,
            URL(string: "wss://damuswasrein.io")!,
            URL(string: "wss://relayasdf.io")!,
        ]
        
        var body: some View {
            Relays(urls: $urls)
        }
    }
    
    return PreviewWrapper()
}
