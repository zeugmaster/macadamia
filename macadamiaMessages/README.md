# 📱 Macadamia iMessage Extension

A clean, simple iMessage app extension that allows users to send ecash directly from within Messages with beautiful formatting and seamless integration.

## ✨ Features

- **💰 Quick Send**: Generate and send ecash tokens directly from iMessage
- **🎨 Beautiful Messages**: Custom message bubbles with amount display  
- **🔗 Interoperable**: Uses standard `cashu:` URIs, works with any Cashu wallet
- **📊 Live Balance**: Shows available balance and mint count
- **🏦 Smart Selection**: Auto-selects best available mint
- **🔒 Secure**: Shared app group for secure wallet data access

## 🎯 Simple User Flow

### **1. Compact View** (Collapsed)
```
┌─────────────────────────────┐
│ 🪙 Macadamia                │
│ Send ecash instantly        │
│                             │
│ Available Balance           │
│ 1,234 sats    [↗ Send]     │
└─────────────────────────────┘
```

### **2. Expanded View** (Full Interface)  
```
┌─────────────────────────────┐
│ 🪙 Send Ecash          Done │
│                             │
│ Amount: [_______] sats      │
│ Mint: [Testmint ↓]         │
│ Memo: [_______] (optional)  │
│                             │
│     [Send Ecash]            │
└─────────────────────────────┘
```

### **3. Message Sent**
```
┌─────────────────────────────┐
│ 🪙 💰 100 sats             │
│ Coffee money                │
│ Tap to claim Cashu ecash   │
│                      Cashu │
└─────────────────────────────┘
```

## 🛠️ Technical Overview

### **Clean Architecture**
- **CompactView**: Balance display + send button
- **ExpandedView**: Amount input + mint picker + send
- **MessagesViewController**: Handles view transitions
- **MacadamiaCore**: Shared wallet logic

### **Shared Data Access**
```swift
// Same SwiftData container as main app
@Query var wallets: [Wallet]
@Query var mints: [Mint] 

// Live balance calculation
let totalBalance = wallets.reduce(0) { $0 + $1.totalBalance() }
```

### **Standard Cashu URIs**
```swift
// Creates interoperable Cashu URIs
var components = URLComponents()
components.scheme = "cashu"           // Standard Cashu protocol
components.path = tokenString         // Raw token data
components.queryItems = [             // Optional metadata
    URLQueryItem(name: "memo", value: memo)
]
// Result: cashu:cashuAeyJ0eXAiOiJQMk...?memo=Coffee
```

## 📋 Setup Checklist

- [x] **Extension target**: `macadamiaMessages` created
- [x] **App Groups**: `group.com.cypherbase.macadamia` enabled  
- [x] **Dependencies**: Messages.framework, SwiftData.framework added
- [x] **Bundle ID**: `com.cypherbase.macadamia.macadamiaMessages`
- [x] **Standard Protocol**: Uses `cashu:` URIs for interoperability

## 🔧 Files Structure

```
macadamiaMessages/
├── MessagesViewController.swift     # Main controller
├── Views/
│   ├── CompactView.swift           # Balance + send button
│   └── ExpandedView.swift          # Full send interface  
├── UI/
│   ├── ExtensionActionButton.swift # Styled button component
│   ├── ExtensionColors.swift       # Extension color theme
│   └── ExtensionAlerts.swift       # Error handling
├── Shared/
│   └── MacadamiaCore.swift         # Wallet operations
└── Info.plist                     # Extension configuration
```

## 🎨 Design Principles

- **Minimal Dependencies**: Standalone UI components
- **Dark Theme**: Optimized for iMessage environment  
- **Brand Consistent**: Macadamia orange accents
- **State Management**: Loading/success/error states
- **Accessibility**: Semantic colors and labels

## 🚀 Usage

1. **Build and install** on device
2. **Open Messages** app
3. **Start conversation**  
4. **Tap app store icon** → Find Macadamia
5. **Enter amount** and **send ecash** 💰

## ✅ Working Features

- ✅ App group container access
- ✅ Live wallet/mint data sync
- ✅ Token generation and sending
- ✅ Beautiful message formatting
- ✅ Standard `cashu:` URI protocol
- ✅ Interoperable with other Cashu wallets
- ✅ Error handling and validation

---

**Clean, simple ecash sending directly from Messages! 🚀💰**