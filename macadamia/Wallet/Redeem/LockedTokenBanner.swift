import SwiftUI
import CashuSwift

struct LockedTokenBanner<Content: View>: View {
    
    let dleqState: CashuSwift.Crypto.DLEQVerificationResult
    let lockState: CashuSwift.Token.LockVerificationResult
    
    let button: () -> Content
    
    @State private var showTooltip = false
    
    init(dleqState: CashuSwift.Crypto.DLEQVerificationResult,
         lockState: CashuSwift.Token.LockVerificationResult,
         @ViewBuilder button: @escaping () -> Content) {
        self.dleqState = dleqState
        self.lockState = lockState
        self.button = button
    }
    
    private var tint: Color {
        switch lockState {
        case .match:
            switch dleqState {
            case .valid:
                return .successGreen
            case .fail, .noData:
                return .orange
            }
        case .mismatch:
            return .failureRed
        case .partial:
            return .orange
        case .noKey, .notLocked:
            return .clear
        }
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack {
                        switch dleqState {
                        case .valid:
                            Image(systemName: "checkmark"); Text("Token is authentic")
                        case .fail:
                            Image(systemName: "xmark"); Text("Not authentic")
                        case .noData:
                            Image(systemName: "xmark"); Text("Authenticity unknown")
                        }
                        Button {
                            let url = URL(string: "https://macadamia.cash/token-authenticity")!
                            if UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "questionmark.circle").font(.callout)
                        }
                    }
                    Spacer().frame(maxHeight: 8)
                    HStack {
                        switch lockState {
                        case .match:
                            Image(systemName: "checkmark"); Text("Locked to your key")
                        case .mismatch, .noKey:
                            Image(systemName: "xmark"); Text("Locked to unknown key")
                        case .partial:
                            Image(systemName: "xmark"); Text("Partially locked (not yet supported)")
                        case .notLocked:
                            Text("Error")
                        }
                    }
                }
                Spacer()
                Image(systemName: "lock")
                    .foregroundStyle(tint)
                    .bold()
            }
            
            button()
                .buttonStyle(.bordered)
                .disabled(self.lockState == .mismatch || self.dleqState == .fail)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.7), lineWidth: 2)
                .background(tint.opacity(0.07))
                .shadow(color: tint, radius: 2))
    }
}

#Preview {
    @Previewable @State var addedToQueue = false
    
    List {
        LockedTokenBanner(dleqState: .valid, lockState: .match) {
            Button {
                withAnimation {
                    addedToQueue = true
                }
            } label: {
                Spacer()
                Text(addedToQueue ? "\(Image(systemName: "checkmark")) Added" :
                        "\(Image(systemName: "hourglass")) Redeem Later").padding(2)
                Spacer()
            }
        }
        .listRowBackground(EmptyView())
        
        LockedTokenBanner(dleqState: .valid, lockState: .match) {
            EmptyView()
        }
        .listRowBackground(EmptyView())
        LockedTokenBanner(dleqState: .noData, lockState: .match) {
            EmptyView()
        }
        .listRowBackground(EmptyView())
        LockedTokenBanner(dleqState: .noData, lockState: .mismatch) {
            Button {
                withAnimation {
                    addedToQueue = true
                }
            } label: {
                Spacer()
                Text(addedToQueue ? "\(Image(systemName: "checkmark")) Added" :
                        "\(Image(systemName: "hourglass")) Redeem Later").padding(2)
                Spacer()
            }
        }
        .listRowBackground(EmptyView())
    }
}
