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

//struct Onboarding: View {
//    @State private var seedPhraseWrittenDown = false
//    @State private var tosAcknowledged = false
//    
//    @State private var currentPage: Int = 0
//    
//    var seedPhrase: [String]
//    var onClose: () -> Void
//    
//    private var doneButtonDisabled: Bool {
//        if currentPage == 3 && tosAcknowledged {
//            return false
//        } else if tosAcknowledged && seedPhraseWrittenDown {
//            return false
//        } else {
//            return true
//        }
//    }
//    
//    var body: some View {
//        ZStack(alignment: .bottomTrailing) {
//            
//            Group {
//                RadialGradient(
//                    gradient: Gradient(colors: [Color(white: 0.1), .black]),
//                    center: .leading,
//                    startRadius: 100,
//                    endRadius: 1000
//                )
//                RadialGradient(
//                    gradient: Gradient(colors: [Color(white: 0.08), .clear]),
//                    center: .bottomTrailing,
//                    startRadius: 100,
//                    endRadius: 400
//                )
//            }
//            
//            Group {
//                TabView(selection: $currentPage) {
//                    WelcomePage().tag(0)
//                    DisclaimerPage().tag(1)
//                    SeedPhrasePage(seedPhraseWrittenDown: $seedPhraseWrittenDown, phrase: seedPhrase).tag(2)
//                    TOSPage(tosAcknoledged: $tosAcknowledged).tag(3)
//                }
//                .tabViewStyle(.page)
//                .indexViewStyle(.page(backgroundDisplayMode: .always))
//        
//                HStack {
//                    Spacer()
//                    Button(action: {
//                        if !seedPhraseWrittenDown {
//                            withAnimation {
//                                currentPage = 2
//                            }
//                        } else {
//                            onClose()
//                        }
//                    }) {
//                        Text("Done")
//                    }
//                    .padding()
//                    .disabled(doneButtonDisabled)
//                    .buttonStyle(.bordered)
//                }
//            }
//        }
//        .background(Color.gray.opacity(0.15))
//        .ignoresSafeArea()
//    }
//}
//
//struct OnboardingPageLayout<Content: View>: View {
//    @ScaledMetric(relativeTo: .body) private var scaleMetric: CGFloat = 20
//    
//    private var sidePadding: CGFloat {
//        max(0, 50-scaleMetric)
//    }
//    
//    var title: String
//    var content: () -> Content
//    
//    var body: some View {
//        VStack(alignment: .leading) {
//            Spacer().frame(maxHeight: 50)
//            Text(title)
//                .fontWeight(.semibold)
//                .font(.largeTitle)
//            Spacer().frame(maxHeight: 30)
//            content()
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
//        .padding(EdgeInsets(top: 0, leading: sidePadding, bottom: 70, trailing: sidePadding))
//    }
//}
//
//struct WelcomePage: View {
//    var body: some View {
//        OnboardingPageLayout(title: String(localized: "Hi there!")) {
//            Markdown(String(localized: """
//                     You are using **macadamia**, the first fully native \
//                     ecash wallet for the Cashu protocol on iOS. \n
//                     Digital payments should be as natural as handing over cash in person. \
//                     Cashu brings simplicity back to online and real-life payments. \
//                     Tap [here](https://cashu.space) to learn more. \n
//                     The code for this project is **open-source** allowing anyone to view it or contribute. \
//                     You can find it on [Github](https://github.com/zeugmaster/macadamia). \n
//                     This app does not collect any usage data or analytics. \n
//                     Thank you for trying the future of payments! \n\n\n
//                     # 🥜🌰
//                     """))
//            .markdownTextStyle(\.link, textStyle: {
//                    UnderlineStyle(.single)
//            })
//        }
//    }
//}
//
//struct DisclaimerPage: View {
//    var body: some View {
//        OnboardingPageLayout(title: String(localized: "⚠️ Warning")) {
//            Markdown(String(localized: """
//                     This wallet and the Cashu protocol are in active development. \
//                     Be cautious when using this software and follow best practices:
//                     
//                     - Mint only as much as you are ready to lose
//                     
//                     - Only use mints you trust
//                     
//                     - Back up your wallet
//                     
//                     If you experience any issues, don't hesitate to send a request for \
//                     support or feedback to [support@macadamia.cash](mailto:support@macadamia.cash) \
//                     or open an Issue on [Github](https://github.com/zeugmaster/macadamia/issues).
//                     """))
//            .markdownTextStyle(\.link, textStyle: {
//                UnderlineStyle(.single)
//            })
//        }
//    }
//}
//
//struct SeedPhrasePage: View {
//    @State private var copied = false
//    @Binding var seedPhraseWrittenDown: Bool
//    let phrase: [String]
//    
//    var body: some View {
//        OnboardingPageLayout(title: String(localized: "Wallet Backup")) {
//            VStack {
//                Markdown(String(localized: """
//                         This is your newly generated **seed phrase** backup. \
//                         Write these twelve words down or save them in a password \ 
//                         manager and use them to restore ecash from the mints known to this wallet (write those down, too). \n 
//                         """))
//                Spacer()
//                if phrase.count == 12 {
//                    HStack {
//                        VStack(alignment: .leading, spacing: 10) {
//                            ForEach(phrase.indices.dropLast(6), id: \.self) { index in
//                                HStack {
//                                    Text(String(index + 1) + ".")
//                                        .frame(minWidth: 30)
//                                    Text(phrase[index]).bold()
//                                }
//                            }
//                        }
//                        .padding()
//                        VStack(alignment: .leading, spacing: 10) {
//                            ForEach(phrase.indices.dropFirst(6), id: \.self) { index in
//                                HStack {
//                                    Text(String(index + 1) + ".")
//                                        .frame(minWidth: 30)
//                                    Text(phrase[index]).bold()
//                                }
//                            }
//                        }
//                        .padding()
//                    }
//                } else {
//                    Text("Not a valid mnemonic.")
//                }
//                Button {
//                    withAnimation {
//                        copied = true
//                    }
//                    UIPasteboard.general.string = phrase.joined(separator: " ")
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                        withAnimation {
//                            copied = false
//                        }
//                    }
//                } label: {
//                    if copied {
//                        Text("Copied \(Image(systemName: "list.clipboard"))")
//                    } else {
//                        Text("Copy \(Image(systemName: "clipboard"))")
//                    }
//                }
//                .buttonStyle(.bordered)
//                .controlSize(.small)
//                Spacer()
//                Toggle(isOn: $seedPhraseWrittenDown) {
//                    Text("I have written down the seed phrase")
//                }.toggleStyle(CheckboxToggleStyle())
//            }
//        }
//    }
//}
//
//struct TOSPage: View {
//    @Binding var tosAcknoledged: Bool
//    
//    var body: some View {
//        OnboardingPageLayout(title: String(localized: "Terms")) {
//            VStack {
//                ScrollView {
//                    Text(tos_rev1)
//                }
//                .font(.footnote)
//                .contentMargins(.vertical, 20, for: .scrollContent)
//                .mask {
//                    VStack(spacing: 0) {
//                            // Top fade: transparent → opaque
//                            LinearGradient(
//                                colors: [.clear, .black],
//                                startPoint: .top,
//                                endPoint: .bottom
//                            )
//                            .frame(height: 20)
//
//                            // Middle: fully visible
//                            Rectangle().fill(Color.black)
//
//                            // Bottom fade: opaque → transparent
//                            LinearGradient(
//                                colors: [.black, .clear],
//                                startPoint: .top,
//                                endPoint: .bottom
//                            )
//                            .frame(height: 20)
//                        }
//                }
//                Spacer(minLength: 20)
//                Toggle(isOn: $tosAcknoledged) {
//                    Text("I agree to the terms.")
//                }.toggleStyle(CheckboxToggleStyle())
//            }
//        }
//    }
//}
//
//struct CheckboxToggleStyle: ToggleStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        HStack {
//            RoundedRectangle(cornerRadius: 5.0)
//                .stroke(lineWidth: 2)
//                .frame(width: 22, height: 22)
//                .cornerRadius(5.0)
//                .overlay {
//                    if configuration.isOn {
//                        Image(systemName: "checkmark")
//                            .bold()
//                    }
//                }
//            configuration.label
//        }
//        .onTapGesture {
//            configuration.isOn.toggle()
//        }
//    }
//}
//
//
//#Preview {
//    Onboarding(seedPhrase: dummySeed) {
//        print("onClose closure executed")
//    }
//}
//
//@available(iOS 18.0, *)
//struct AppearTextRenderer: TextRenderer, Animatable {
//    var elapsedTime: Double
//    var totalDuration: Double = 0.6
//
//    var animatableData: Double {
//        get { elapsedTime }
//        set { elapsedTime = newValue }
//    }
//
//    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
//        let allSlices = layout.flatMap { line in
//            line.flatMap { run in
//                run.map { $0 }
//            }
//        }
//        let count = allSlices.count
//        guard count > 0 else { return }
//
//        for (index, slice) in allSlices.enumerated() {
//            let staggerDelay = Double(index) / Double(count) * totalDuration * 0.5
//            let progress = max(0, min(1, (elapsedTime - staggerDelay) / (totalDuration * 0.5)))
//
//            var copy = ctx
//            copy.opacity = progress
//            copy.translateBy(x: 0, y: (1 - progress) * -10)
//            copy.addFilter(.blur(radius: (1 - progress) * 3))
//            copy.draw(slice, options: .init())
//        }
//    }
//}
//
//struct OnboardingCanvas: View {
//    @State private var page = 0
//    @State private var textAnimation: Double = 0
//
//    private let pageCount = 2
//    private let parallaxFactor: CGFloat = 0.2
//
//    private var headerText: String {
//        switch page {
//        case 0: "Hi there!"
//        case 1: "Warning"
//        default: "Empty"
//        }
//    }
//
//    var body: some View {
//        VStack(alignment: .leading) {
//            // header
//            Group {
//                if #available(iOS 18.0, *) {
//                    Text(headerText)
//                        .id(page)
//                        .textRenderer(AppearTextRenderer(elapsedTime: textAnimation))
//                        .onAppear {
//                            withAnimation(.easeOut(duration: 0.6)) {
//                                textAnimation = 1
//                            }
//                        }
//                        .onChange(of: page) {
//                            textAnimation = 0
//                            withAnimation(.easeOut(duration: 0.6)) {
//                                textAnimation = 1
//                            }
//                        }
//                } else {
//                    Text(headerText)
//                        .contentTransition(.numericText())
//                }
//            }
//            .font(.largeTitle)
//            .bold()
//            .fontWidth(.expanded)
//            .padding()
//            .zIndex(1)
//            // content
//            if #available(iOS 18.0, *) {
//                ScrollView(.horizontal) {
//                    LazyHStack(spacing: 0) {
//                        ForEach(0..<pageCount, id: \.self) { index in
//                            ZStack {
////                                Text(index == 0 ? "subheadline" : "two")
//                                TOSPage(tosAcknoledged: .constant(false))
//                            }
//                            .containerRelativeFrame(.horizontal)
//                        }
//                    }
//                    .scrollTargetLayout()
//                    .background {
//                        GeometryReader { geo in
//                            let scrollOffset = geo.frame(in: .named("onboardingScroll")).minX
//                            let containerWidth = geo.size.width / CGFloat(pageCount)
//                            let fraction = containerWidth > 0
//                                ? min(max(-scrollOffset / containerWidth, 0), 1)
//                                : 0
//                            let globalFrame = geo.frame(in: .global)
//                            let screen = UIScreen.main.bounds
//                            let parallaxRange = screen.height - screen.width
//
//                            MeshBackground()
//                                .frame(width: screen.width, height: screen.height)
//                                .offset(
//                                    x: -globalFrame.minX - fraction * parallaxRange * parallaxFactor,
//                                    y: -globalFrame.minY
//                                )
//                        }
//                    }
//                }
//                .scrollClipDisabled()
//                .coordinateSpace(name: "onboardingScroll")
//                .scrollTargetBehavior(.paging)
//                .scrollIndicators(.hidden)
//                .onScrollGeometryChange(for: Int.self) { geo in
//                    let maxOffset = geo.contentSize.width - geo.containerSize.width
//                    guard maxOffset > 0 else { return 0 }
//                    let fraction = geo.contentOffset.x / maxOffset
//                    return Int((min(max(fraction, 0), 1) * CGFloat(pageCount - 1)).rounded())
//                } action: { _, newPage in
//                    if newPage != page {
//                        page = newPage
//                    }
//                }
//            } else {
//                TabView(selection: Binding(get: { page }, set: { newValue in
//                    withAnimation {
//                        page = newValue
//                    }
//                })) {
//                    VStack(alignment: .leading) {
//                        Text("Subheadline")
//                        
//                    }.tag(0)
//                    Text("two").tag(1)
//                }
//                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
//            }
//            // footer
//        }
//        .background {
//            if #available(iOS 18.0, *) {
//                Color.clear
//            } else {
//                GeometryReader { _ in
//                    MeshBackground()
//                }
//                .ignoresSafeArea()
//            }
//        }
//    }
//}
//
///*
// header
//    scrollview
//        welcome page | WarningPage | ToSPage | Seed Selection Page | Success Page
// footer
//    
// 
//*/
//
//#Preview {
//    OnboardingCanvas()
//}

// MARK: - Master View

enum OnboardingPage: Equatable {
    case welcome, warning, terms, setup, seed, restore, success
}

@available(iOS 18.0, *)
struct OnboardingCanvas: View {
    var onComplete: () -> Void

    // -- navigation --
    /// Which phase is visible: 1 = intro (pages 0-2), 2 = wallet setup (pages 0-2 mapped to 3-5)
    @State private var phase = 1
    @State private var phase1Page: Int? = 0
    @State private var phase2Page: Int? = 0
    @State private var scrollOffset: CGFloat = 0

    // -- phase 1 state --
    @State private var termsAccepted = false

    // -- phase 2 state --
    @State private var setupSelection: SetupSelectionState = .none
    @State private var seedPhraseConfirmed = false
    @State private var restoreInProgress = false
    @State private var restoreSucceeded = false

    // -- stub --
    @State private var generatedSeed = "abandon ability able about above absent absorb abstract absurd abuse access accident"

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

    private var headerTitle: String {
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
            // Must have made a selection (and for restore, seed must be valid)
            switch setupSelection {
            case .none, .pendingInput, .invalidInput: false
            case .createNew, .validSeedPhrase: true
            }
        case .seed: seedPhraseConfirmed
        case .restore: !restoreInProgress && restoreSucceeded
        default: true
        }
    }

    private var previousEnabled: Bool {
        switch currentPage {
        case .welcome, .setup: false
        case .restore: !restoreInProgress
        default: true
        }
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
                OnboardingHeader(title: headerTitle)

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
                                generatedSeed: generatedSeed,
                                seedPhraseConfirmed: $seedPhraseConfirmed,
                                restoreInProgress: $restoreInProgress,
                                restoreSucceeded: $restoreSucceeded
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
                // Navigate within phase 1
                withAnimation(anim) { phase1Page = p1 + 1 }
            } else {
                // Transition from phase 1 to phase 2
                phase2Page = 0
                withAnimation(.easeInOut(duration: 0.45)) { phase = 2 }
            }
        } else {
            let p2 = phase2Page ?? 0
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
        // TODO: persist wallet to ModelContext
        onComplete()
    }
}

// MARK: - Header

struct OnboardingHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .fontWidth(.expanded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.4), value: title)
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
//            Text("Welcome to YourApp")
//                .font(.title2.bold())
            Text("This short setup will get your wallet ready in a few steps. You'll review some important safety information, accept the terms, and configure your wallet.")
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
            Text(String(localized: """
                                   This wallet and the Cashu protocol are in active development. \
                                   Be cautious when using this software and follow best practices:
                                   
                                   - Mint only as much as you are ready to lose
                                   
                                   - Only use mints you trust
                                   
                                   - Back up your wallet
                                   
                                   If you experience any issues, don't hesitate to send a request for \
                                   support or feedback to [support@macadamia.cash](mailto:support@macadamia.cash) \
                                   or open an Issue on [Github](https://github.com/zeugmaster/macadamia/issues).
                                   """))
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
                    Text("Create new")
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
                                        .fill(.primary.opacity(0.1))
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
                                    .fill(.primary.opacity(0.1)))
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

#Preview {
    @Previewable @State var selection: SetupSelectionState = .none
    SetupSelectionPage(state: $selection)
}

struct WalletSetupPage: View {
    let setupSelection: SetupSelectionState
    let generatedSeed: String
    @Binding var seedPhraseConfirmed: Bool
    @Binding var restoreInProgress: Bool
    @Binding var restoreSucceeded: Bool

    var body: some View {
        Group {
            if setupSelection.isRestoreFlow {
                restoreContent
            } else {
                SeedPage(seed: dummySeed)
                    .padding()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var seedDisplayContent: some View {
        VStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Write down your seed phrase")
                    .font(.title2.bold())

                Text("Store this somewhere safe. It is the only way to recover your wallet.")
                    .foregroundStyle(.secondary)

            }
            Spacer(minLength: 10)
                .frame(maxHeight: 50)
            SeedView(seed: dummySeed)
        }
        .padding()
    }

    private var restoreContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restoring wallet…")
                .font(.title2.bold())

            if restoreInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking mints for ecash…")
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            if restoreSucceeded {
                Label("Wallet restored successfully",
                      systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.3), value: restoreInProgress)
        .animation(.easeInOut(duration: 0.3), value: restoreSucceeded)
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
#Preview("Onboarding Test") {
    OnboardingCanvas(onComplete: {
        print("✅ Onboarding complete")
    })
}
