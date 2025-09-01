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
        setupInitialView()
    }
    
    private func setupInitialView() {
        requestPresentationStyle(.compact)
    }
    
    // MARK: - Conversation Handling
    override func willBecomeActive(with conversation: MSConversation) {
        presentViewController(for: conversation, with: presentationStyle)
    }
    
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        if let url = message.url {
            openInMainApp(url: url)
        }
    }
    
    // Present appropriate view based on presentation style
    private func presentViewController(for conversation: MSConversation, 
                                     with presentationStyle: MSMessagesAppPresentationStyle) {
        
        removeAllChildViewControllers()
        
        let hostingController: UIHostingController<AnyView>
        
        switch presentationStyle {
        case .compact:
            hostingController = UIHostingController(rootView: AnyView(
                NavigationView {
                    MessageMintList(delegate: self)
                }
                .modelContainer(modelContainer)
            ))
        case .expanded:
            hostingController = UIHostingController(rootView: AnyView(
                NavigationView {
                    MessageMintList(delegate: self)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .modelContainer(modelContainer)
            ))
        @unknown default:
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
        extensionContext?.open(url, completionHandler: nil)
    }
}

// MARK: - Presentation Style Changes
extension MessagesViewController {
    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        guard let conversation = activeConversation else { return }
        presentViewController(for: conversation, with: presentationStyle)
    }
}
