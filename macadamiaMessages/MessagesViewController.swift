import Messages
import SwiftUI
import SwiftData
import CashuSwift
import OSLog

let messagesLogger = Logger(subsystem: "macadamia Messages", category: "iMessage Extension")

class MessagesViewController: MSMessagesAppViewController {
    
    // Access the shared container - same one used by main app!
    private var modelContainer: ModelContainer {
        DatabaseManager.shared.container
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        messagesLogger.info("macadamiaMessages extension loaded")
        setupInitialView()
    }
    
    private func setupInitialView() {
        // Start with compact presentation
        requestPresentationStyle(.compact)
    }
    
    // MARK: - Conversation Handling
    override func willBecomeActive(with conversation: MSConversation) {
        messagesLogger.info("Extension becoming active with conversation")
        presentViewController(for: conversation, with: presentationStyle)
    }
    
    override func didBecomeActive(with conversation: MSConversation) {
        messagesLogger.info("Extension became active")
    }
    
    override func willSelect(_ message: MSMessage, conversation: MSConversation) {
        messagesLogger.info("Will select message")
    }
    
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        messagesLogger.info("Did select message")
        // Handle when user taps on an existing ecash message
        if let url = message.url {
            // Force open in main Macadamia app instead of extension
            openInMainApp(url: url)
        }
    }
    
    // Present appropriate view based on presentation style
    private func presentViewController(for conversation: MSConversation, 
                                     with presentationStyle: MSMessagesAppPresentationStyle) {
        
        // Remove existing child view controllers
        removeAllChildViewControllers()
        
        let hostingController: UIHostingController<AnyView>
        
        switch presentationStyle {
        case .compact:
            hostingController = UIHostingController(rootView: AnyView(
                CompactView(delegate: self)
                    .modelContainer(modelContainer)
            ))
        case .expanded:
            hostingController = UIHostingController(rootView: AnyView(
                ExpandedView(delegate: self)
                    .modelContainer(modelContainer)
            ))
        @unknown default:
            messagesLogger.error("Unknown presentation style")
            fatalError("Unknown presentation style")
        }
        
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
    
    private func removeAllChildViewControllers() {
        children.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }
    
    private func openInMainApp(url: URL) {
        messagesLogger.info("Opening URL in main Macadamia app: \(url.absoluteString)")
        
        // Use extension context to open URL in the main app
        extensionContext?.open(url, completionHandler: { success in
            if success {
                messagesLogger.info("Successfully opened URL in main app")
            } else {
                messagesLogger.error("Failed to open URL in main app")
            }
        })
    }
}

// MARK: - Message Creation
extension MessagesViewController {
    func createMessage() {
        messagesLogger.info("Creating test message")
        
        guard let conversation = activeConversation else {
            messagesLogger.error("No active conversation")
            return
        }
        
        let message = MSMessage()
        
        // Create simple test URL
        guard let testURL = URL(string: "https://example.com") else {
            messagesLogger.error("Failed to create test URL")
            return
        }
        
        message.url = testURL
        message.layout = createMessageLayout()
        
        print("📨 Extension: Attempting to insert test message...")
        messagesLogger.info("Attempting to insert test message")
        
        conversation.insert(message) { error in
            if let error {
                messagesLogger.error("Failed to insert message: \(error.localizedDescription)")
                print("❌ Extension Error: Failed to insert message: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
            } else {
                messagesLogger.info("Successfully inserted test message")
                print("✅ Extension: Successfully inserted test message")
                // Return to compact view after sending
                DispatchQueue.main.async {
                    self.requestPresentationStyle(.compact)
                }
            }
        }
    }
    

    
    private func createMessageLayout() -> MSMessageTemplateLayout {
        let layout = MSMessageTemplateLayout()
        
        // Use custom message banner graphic from asset catalog
        layout.image = UIImage(named: "message-banner")
        layout.caption = "Test Message"
        layout.subcaption = "Tap to open example.com"
        layout.trailingCaption = "Test"
        
        return layout
    }
}

// MARK: - Presentation Style Changes
extension MessagesViewController {
    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        guard let conversation = activeConversation else { return }
        
        messagesLogger.info("Will transition to presentation style: \(presentationStyle.rawValue)")
        presentViewController(for: conversation, with: presentationStyle)
    }
}
