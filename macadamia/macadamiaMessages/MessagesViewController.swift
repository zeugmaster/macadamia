import Messages
import SwiftUI
import SwiftData

class MessagesViewController: MSMessagesAppViewController {
    
    
    // Access the shared container - same one used by main app!
    private var modelContainer: ModelContainer {
        DatabaseManager.shared.container
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }
    
    override func willBecomeActive(with conversation: MSConversation) {
        print("willBecomeActive called")
        
        // Check if there's a selected message when becoming active
        if let selectedMessage = conversation.selectedMessage {
            print("Selected message: \(selectedMessage)")
            handleMessage(selectedMessage)
        }
    }
    
    private func setupView() {
        let hostingController = UIHostingController(rootView: 
            MessageMintList(vc: self)
                .modelContainer(modelContainer)
        )
        
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
    
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        print("didSelect called: \(message)")
        handleMessage(message)
    }
    
    private func handleMessage(_ message: MSMessage) {
        guard let url = message.url else {
            print("No URL in message")
            return 
        }
        
        print("Message URL: \(url)")
        
        // Check if it's a data URL with token
        if url.scheme == "data" {
            let tokenString = String(url.absoluteString.dropFirst("data:".count))
            print("Found token: \(tokenString)")
            
            // Notify the view to show the token
            NotificationCenter.default.post(name: .messageSelected, object: tokenString)
        } else {
            // For other URLs, create cashu scheme and open in main app
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "cashu"
            guard let cashuURL = components?.url else {
                print("Failed to create cashu URL")
                return
            }
            extensionContext?.open(cashuURL)
        }
    }
}
