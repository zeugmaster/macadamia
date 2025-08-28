# 🌐 Cashu URI Interoperability Guide

## 📱 Message Behavior Scenarios

### **Scenario 1: Sender taps their own message**
- **Behavior**: Opens in main Macadamia app (not extension)
- **Reason**: `extensionContext?.open()` forces main app opening
- **Result**: Token redemption flow in main Macadamia app

### **Scenario 2: Recipient has Macadamia installed**
- **First tap**: Opens in main Macadamia app
- **Alternative**: Long press → "Open With" → Choose app
- **Result**: Standard Cashu token redemption

### **Scenario 3: Recipient has OTHER Cashu wallet (no Macadamia)**
- **System prompt**: "Open with [WalletName]?"
- **Behavior**: Opens in their preferred Cashu wallet
- **Result**: Universal token redemption ✅

### **Scenario 4: Recipient has MULTIPLE Cashu wallets**
- **System prompt**: Lists all compatible apps
- **User choice**: Can pick any Cashu-compatible wallet
- **Result**: Full interoperability ✅

## 🔗 **URL Format Examples**

### **Basic Token:**
```
cashu:cashuAeyJ0eXAiOiJQMkVKgkyNTEyU...
```

### **With Metadata:**
```
cashu:cashuAeyJ0eXAiOiJQMkVKgkyNTEyU...?memo=Coffee&source=imessage
```

## ✅ **Interoperability Benefits**

### **For Senders (Macadamia users):**
- Send from familiar Macadamia interface
- Recipients can use ANY Cashu wallet
- No vendor lock-in for recipients

### **For Recipients:**
- **Freedom of choice**: Use preferred wallet
- **No installation required**: Can use existing Cashu apps
- **Standard protocol**: Guaranteed compatibility

### **For Ecosystem:**
- **Open standard**: Promotes Cashu adoption
- **Network effects**: More wallets = more users
- **Innovation**: Encourages wallet competition

## 🛠️ **Technical Implementation**

### **Extension Side:**
```swift
// Creates standard Cashu URI
components.scheme = "cashu"
components.path = token

// Forces opening in main app when sender taps
extensionContext?.open(url) { success in 
    // Opens main Macadamia app
}
```

### **System Behavior:**
1. **iOS checks**: Which apps handle `cashu:` URLs
2. **Multiple apps**: Shows picker
3. **One app**: Opens directly
4. **No apps**: Shows error

## 🔄 **Flow Diagram**

```
Message Tapped
      ↓
┌─────────────────┐
│ Sender's Device │ → Opens main Macadamia app
└─────────────────┘

┌─────────────────┐
│ Recipient's     │ → System checks cashu: handlers
│ Device          │   ↓
└─────────────────┘   ┌─ Macadamia only → Opens Macadamia
                      ├─ Other wallet only → Opens that wallet  
                      ├─ Multiple wallets → User chooses
                      └─ No wallets → Error message
```

## 🎯 **Best Practices**

### **✅ What We Did Right:**
- Used standard `cashu:` scheme
- Maintained token in path (not query)
- Added optional metadata in query params
- Forced main app opening for sender

### **🔮 Future Considerations:**
- **Fallback URLs**: Could add web fallback
- **Deep linking**: Enhanced app routing
- **Metadata standards**: Community-agreed parameters

## 🚀 **Testing Interoperability**

### **Test 1: Self-testing**
1. Send message from extension
2. Tap message → Should open main app
3. Verify redemption works

### **Test 2: Cross-wallet (if available)**
1. Send to device with another Cashu wallet
2. Verify system shows app picker
3. Test redemption in other wallet

### **Test 3: No Cashu wallet**
1. Send to device without Cashu apps
2. Should show "No app available" error
3. Could offer App Store search

---

**🌐 Result: True interoperability while maintaining Macadamia's great UX!**
