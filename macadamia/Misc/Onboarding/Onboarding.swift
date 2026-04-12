//
//  Onboarding.swift
//  macadamia
//
//  Created by zm on 23.01.25.
//

import SwiftUI
import MarkdownUI
import SwiftData
import BIP39

// placeholder for previews
let dummySeed = "coil indicate path field habit ladder concert disease gate robot industry prison".components(separatedBy: " ")

// MARK: - Master View

enum OnboardingPage: Equatable {
    case welcome, warning, terms, setup, seed, restore, success
}

@available(iOS 18.0, *)
struct OnboardingCanvas: View {
    var onComplete: (Wallet) -> Void

    // -- navigation --
    /// Which phase is visible: 1 = intro (pages 0-2), 2 = wallet setup (pages 0-2 mapped to 3-5)
    @State private var phase = 1
    @State private var phase1Page: Int? = 0
    @State private var phase2Page: Int? = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var displayedHeaderTitle: LocalizedStringKey = "Hi there!"

    // -- phase 1 state --
    @State private var termsAccepted = false

    // -- phase 2 state --
    @State private var setupSelection: SetupSelectionState = .none
    @State private var seedPhraseConfirmed = false
    @State private var restoreInProgress = false
    @State private var restoreSucceeded = false

    // -- wallet --
    @State private var generatedMnemonic: Mnemonic? = nil
    @State private var wallet: Wallet? = nil

    // MARK: Computed

    /// The logical page index (0-5) across both phases.
    private var page: Int {
        if phase == 1 { return phase1Page ?? 0 }
        return (phase2Page ?? 0) + 3
    }
    
    private var currentPage: OnboardingPage {
        switch page {
        case 0: .welcome
        case 1: .warning
        case 2: .terms
        case 3: .setup
        case 4 where setupSelection.isRestoreFlow: .restore
        case 4: .seed
        case 5: .success
        default: .welcome
        }
    }

    private var headerTitle: LocalizedStringKey {
        switch page {
        case 0: "Hi there!"
        case 1: "Warning"
        case 2: "Terms"
        case 3: "Setup"
        case 4 where setupSelection.isRestoreFlow: "Restore Wallet"
        case 4: "Your Seed Phrase"
        case 5: "You're All Set"
        default: ""
        }
    }

    private var nextEnabled: Bool {
        switch currentPage {
        case .terms: termsAccepted
        case .setup:
            switch setupSelection {
            case .none, .pendingInput, .invalidInput: false
            case .createNew, .validSeedPhrase: true
            }
        case .seed: seedPhraseConfirmed
        case .restore: !restoreInProgress && restoreSucceeded
        case .success: wallet != nil
        default: true
        }
    }

    private var previousEnabled: Bool {
        if wallet != nil { return false }
        return switch currentPage {
        case .welcome, .setup: false
        case .restore: !restoreInProgress && !restoreSucceeded
        default: true
        }
    }
    

    /// Seed words for the restore flow, extracted from the setup selection.
    private var restoreSeedWords: [String] {
        if case .validSeedPhrase(let words) = setupSelection { return words }
        return []
    }

    // MARK: Body

    var body: some View {
        ZStack {
            OnboardingBackground(
                scrollOffset: scrollOffset,
                currentPage: page,
                pageCount: 6
            )

            VStack(spacing: 0) {
                OnboardingHeader(title: displayedHeaderTitle)
                    .onChange(of: page) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            displayedHeaderTitle = headerTitle
                        }
                    }

                // Two-phase content area
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        // Phase 1: Greeting, Caution, Terms
                        OnboardingPageContainer(
                            currentPage: $phase1Page,
                            scrollOffset: $scrollOffset,
                            scrollEnabled: true,
                            pageCount: 3
                        ) {
                            GreetingPage()
                                .containerRelativeFrame(.horizontal)
                                .id(0)
                            CautionPage()
                                .containerRelativeFrame(.horizontal)
                                .id(1)
                            TermsPage(termsAccepted: $termsAccepted)
                                .containerRelativeFrame(.horizontal)
                                .id(2)
                        }
                        .frame(width: geo.size.width)

                        // Phase 2: Wallet Choice, Setup, Success
                        OnboardingPageContainer(
                            currentPage: $phase2Page,
                            scrollOffset: .constant(0),
                            scrollEnabled: false,
                            pageCount: 3
                        ) {
                            SetupSelectionPage(state: $setupSelection)
                                .containerRelativeFrame(.horizontal)
                                .id(0)
                            WalletSetupPage(
                                setupSelection: setupSelection,
                                generatedSeed: generatedMnemonic?.phrase ?? [],
                                restoreSeed: restoreSeedWords,
                                seedPhraseConfirmed: $seedPhraseConfirmed,
                                restoreInProgress: $restoreInProgress,
                                restoreSucceeded: $restoreSucceeded,
                                onRestore: { restoredWallet in
                                    wallet = restoredWallet
                                    restoreSucceeded = true
                                }
                            )
                            .containerRelativeFrame(.horizontal)
                            .id(1)
                            SuccessPage()
                                .containerRelativeFrame(.horizontal)
                                .id(2)
                        }
                        .frame(width: geo.size.width)
                    }
                    .offset(x: phase == 1 ? 0 : -geo.size.width)
                }
            }

            if #available(iOS 26.0, *) {
                VStack {
                    Spacer()
                    ButtonBar(
                        currentPage: currentPage,
                        nextEnabled: nextEnabled,
                        previousEnabled: previousEnabled,
                        termsAccepted: $termsAccepted,
                        seedConfirmed: $seedPhraseConfirmed,
                        onPrevious: { goBack() },
                        onNext: {
                            if page == 5 { finish() }
                            else { goForward() }
                        }
                    )
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: Actions

    private func goForward() {
        let anim: Animation = .easeInOut(duration: 0.35)
        if phase == 1 {
            let p1 = phase1Page ?? 0
            if p1 < 2 {
                withAnimation(anim) { phase1Page = p1 + 1 }
            } else {
                // Transition from phase 1 to phase 2 — generate mnemonic for create-new flow
                if generatedMnemonic == nil {
                    generatedMnemonic = Mnemonic()
                }
                phase2Page = 0
                withAnimation(.easeInOut(duration: 0.45)) { phase = 2 }
            }
        } else {
            let p2 = phase2Page ?? 0

            // Create wallet for the create-new flow when advancing from seed page
            if currentPage == .seed, seedPhraseConfirmed, wallet == nil,
               let mnemonic = generatedMnemonic {
                let seed = String(bytes: mnemonic.seed)
                wallet = Wallet(mnemonic: mnemonic.phrase.joined(separator: " "),
                                seed: seed)
            }

            if p2 < 2 {
                withAnimation(anim) { phase2Page = p2 + 1 }
            }
        }
    }

    private func goBack() {
        let anim: Animation = .easeInOut(duration: 0.35)
        if phase == 2 {
            let p2 = phase2Page ?? 0
            if p2 > 0 {
                withAnimation(anim) { phase2Page = p2 - 1 }
            }
            // Phase 2 page 0 has previous disabled, so no transition back to phase 1
        } else {
            let p1 = phase1Page ?? 0
            if p1 > 0 {
                withAnimation(anim) { phase1Page = p1 - 1 }
            }
        }
    }

    private func finish() {
        guard let wallet else { return }
        onComplete(wallet)
    }
}

// MARK: - Header

struct OnboardingHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .fontWidth(.expanded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top)
            .contentTransition(.numericText())
    }
}

// MARK: - Page Container

@available(iOS 18.0, *)
struct OnboardingPageContainer<Content: View>: View {
    @Binding var currentPage: Int?
    @Binding var scrollOffset: CGFloat
    let scrollEnabled: Bool
    let pageCount: Int
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                content
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(!scrollEnabled)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentPage)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.x
        } action: { _, newOffset in
            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                scrollOffset = newOffset
            }
        }
    }
}

// MARK: - Background

struct OnboardingBackground: View {
    let scrollOffset: CGFloat
    let currentPage: Int
    let pageCount: Int

    /// Number of page swipes over which the background completes its full travel.
    private let parallaxPages: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            let bgWidth = screenWidth * 2
            // Clamp to [0, parallaxPages * screenWidth] so rubber-banding doesn't move the background out of frame
            let clampedOffset = max(0, min(scrollOffset, parallaxPages * screenWidth))
            let fraction = (parallaxPages * screenWidth) > 0
                ? clampedOffset / (parallaxPages * screenWidth)
                : 0
            // Total travel = bgWidth - screenWidth (the off-screen portion)
            let travel = bgWidth - screenWidth

            MeshBackground()
                .frame(width: bgWidth, height: screenHeight)
                .offset(x: -fraction * travel)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Phase 1 Pages

struct GreetingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let's bring back financial privacy.")
                .font(.title2.bold())
            Text("""
                You are using **macadamia**, the first fully native \
                ecash wallet for the Cashu protocol on iOS. \n
                Digital payments should be as natural as handing over cash in person. \
                Cashu brings simplicity back to online and real-life payments. \
                Tap [here](https://cashu.space) to learn more. \n
                The code for this project is **open-source** allowing anyone to view it or contribute. \
                You can find it on [Github](https://github.com/zeugmaster/macadamia). \n
                """)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct CautionPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
//            Text("Important Safety Information")
//                .font(.title2.bold())
            Text("""
               This wallet and the Cashu protocol are in active development. \
               Be cautious when using this software and follow best practices:
               
               • Mint only as much as you are ready to lose
               
               • Only use mints you trust
               
               • Back up your wallet
               
               If you experience any issues, don't hesitate to send a request for \
               support or feedback to [support@macadamia.cash](mailto:support@macadamia.cash) \
               or open an Issue on [Github](https://github.com/zeugmaster/macadamia/issues).
               """)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct TermsPage: View {
    @Binding var termsAccepted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
//            Text("Terms of Service")
//                .font(.title2.bold())

            ScrollView {
                Text(tos_rev1)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .contentMargins(.top, 20)
            .contentMargins(.bottom, 100)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)

                    Rectangle().fill(Color.black)

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
            }
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Phase 2 Pages

enum SetupSelectionState: Equatable {
    case none
    case createNew
    case pendingInput
    case invalidInput
    case validSeedPhrase([String])
    
    var isRestoreFlow: Bool {
        switch self {
        case .invalidInput, .pendingInput, .validSeedPhrase(_): return true
        default: return false
        }
    }
}

struct SetupSelectionPage: View {
    @Binding var state: SetupSelectionState
    
    @State private var input: String = ""
    
    @State private var showEmptyPasteboardWarning = false
    
    private let outerCornerRadius = 18.0
    private let innerCornerRadius = 10.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "plus")
                    Text("Create new wallet")
                    Spacer()
                    if state == .createNew {
                        Image(systemName: "checkmark")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: outerCornerRadius)
                    .fill(Color.primary.gradient.opacity(0.8))
                    .stroke(.primary, style: StrokeStyle())
                    .opacity(state == .createNew ? 0.15 : 0.08))
                .onTapGesture {
                    state = .createNew
                }
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        Text("Restore from seed phrase")
                        Spacer()
                        Group {
                            switch state {
                            case .invalidInput: Image(systemName: "questionmark")
                            case .validSeedPhrase(_): Image(systemName: "checkmark")
                            default: EmptyView()
                            }
                        }
                        .contentTransition(.symbolEffect(.replace))
                    }

                    if state.isRestoreFlow {
                        VStack {
                            TextField("Enter seed phrase", text: $input, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .lineLimit(3...5)
                                .background(
                                    RoundedRectangle(cornerRadius: innerCornerRadius)
                                        .fill(.primary.opacity(0.08))
                                )
                            Button {
                                if let string = UIPasteboard.general.string, !string.isEmpty {
                                    input = string
                                } else {
                                    withAnimation {
                                        showEmptyPasteboardWarning = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation {
                                            showEmptyPasteboardWarning = false
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "clipboard")
                                    Text(showEmptyPasteboardWarning ? "Pasteboard empty" : "Paste")
                                    Spacer()
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: innerCornerRadius)
                                    .fill(.primary.opacity(0.08)))
                                .font(.body)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: outerCornerRadius)
                    .fill(Color.primary.gradient.opacity(0.8))
                    .stroke(.primary, style: StrokeStyle())
                    .opacity(restoreInputBackgroundOpacity))
                .onTapGesture {
                    switch state {
                    case .none, .createNew: state = .pendingInput
                    default: break
                    }
                }
                Spacer()
            }
            .font(.title3)
            .fontWeight(.medium)
            .onChange(of: input) {
                if input.isEmpty {
                    state = .pendingInput
                } else if isSeedPhraseValid {
                    state = .validSeedPhrase(splitInput)
                } else {
                    state = .invalidInput
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.15), value: state)
            .padding()
        }
    }
    
    private var restoreInputBackgroundOpacity: Double {
        switch state {
        case .none, .createNew: 0.08
        default: 0.15
        }
    }
    
    private var splitInput: [String] {
        input.lowercased()
             .split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
             .map(String.init)
    }
    
    private var isSeedPhraseValid: Bool {
        if splitInput.isEmpty { return false }
        return (try? Mnemonic(phrase: splitInput)) != nil
    }
}

#Preview("Setup Selector") {
    @Previewable @State var selection: SetupSelectionState = .none
    SetupSelectionPage(state: $selection)
}

struct WalletSetupPage: View {
    let setupSelection: SetupSelectionState
    let generatedSeed: [String]
    let restoreSeed: [String]
    @Binding var seedPhraseConfirmed: Bool
    @Binding var restoreInProgress: Bool
    @Binding var restoreSucceeded: Bool
    var onRestore: (Wallet) -> Void

    var body: some View {
        Group {
            if setupSelection.isRestoreFlow, !restoreSeed.isEmpty {
                RestoreViewV2(seed: restoreSeed, restoreInProgress: $restoreInProgress) { wallet in
                    onRestore(wallet)
                }
            } else if !generatedSeed.isEmpty {
                SeedPage(seed: generatedSeed)
                    .padding()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct SuccessPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.5))

            Text("Your wallet is ready")
                .font(.title2.bold())

            Text("Tap Finish to start using the app.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

@available(iOS 18.0, *)
#Preview("Onboarding") {
    OnboardingCanvas(onComplete: { wallet in
        print("Onboarding complete, wallet ID: \(wallet.walletID)")
    })
}
