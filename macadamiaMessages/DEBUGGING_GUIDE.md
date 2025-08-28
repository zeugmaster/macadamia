# 🐛 Extension Debugging Guide

## 📱 **How to View Extension Logs**

### **Method 1: Xcode Console (Recommended)**
1. **Run the app** from Xcode on device/simulator
2. **Open Messages app** (keep Xcode open)
3. **Use the extension** and trigger the send action
4. **Watch Xcode console** for `print()` statements with prefixes:
   - `📝 Extension:` - General info
   - `✅ Extension:` - Success messages  
   - `❌ Extension Error:` - Error messages
   - `📊 Extension:` - Data/metrics
   - `📨 Extension:` - Message operations

### **Method 2: Device Console App (macOS)**
1. **Open Console app** on Mac
2. **Connect your device** 
3. **Filter by process**: `macadamiaMessages`
4. **Watch for OSLog** messages from extension

### **Method 3: iPhone Analytics (On Device)**
1. **Settings** → **Privacy & Security** → **Analytics & Improvements**
2. **Analytics Data** → Look for crash logs
3. **Search for**: `macadamiaMessages` or `Macadamia`

## 🔍 **Common Debugging Steps**

### **Step 1: Check Basic Flow**
Look for these messages in sequence:
```
📝 Extension: Starting token generation for 100 sats
✅ Extension: Token generation successful, length: 1234
📱 Extension: Calling createMessage...
📊 Extension: Data URL length: 5678 characters
📨 Extension: Attempting to insert message...
✅ Extension: Successfully inserted ecash message
```

### **Step 2: Identify Where It Fails**
- **No "Starting token generation"** → Button not calling function
- **No "Token generation successful"** → Wallet/mint issue
- **No "Calling createMessage"** → Delegate not set
- **No "Data URL length"** → HTML creation failed
- **No "Attempting to insert"** → URL creation failed
- **"Failed to insert message"** → iMessage API issue

### **Step 3: Check Data URL Size**
If you see data URL length > 10,000 characters:
- **Too large for iMessage** → Need to compress further
- **Satellite warning** → Size limit exceeded

## 🚨 **Common Issues & Solutions**

### **Issue 1: "No mint selected"**
```
❌ Extension: No mint selected
```
**Solution**: Ensure wallet has mints configured in main app

### **Issue 2: "Token generation failed"**
```
❌ Extension: Token generation failed: Insufficient balance
```
**Solution**: Check wallet balance in main app

### **Issue 3: "Failed to insert message"**
```
❌ Extension Error: Failed to insert message: Message too large
```
**Solution**: HTML/token too big for iMessage - need compression

### **Issue 4: "Failed to create data URL"**
```
❌ Extension Error: Failed to create data URL from string of length 15000
```
**Solution**: URL too long - reduce HTML size further

### **Issue 5: Extension doesn't appear**
- **Check**: App Groups capability enabled
- **Check**: Extension target builds successfully
- **Try**: Restart Messages app
- **Try**: Restart device

## 🔧 **Manual Testing Commands**

Add these to your test flow:

### **Test 1: Print Available Mints**
Add to `ExpandedView.onAppear`:
```swift
print("🏦 Available mints: \(availableMints.count)")
for mint in availableMints {
    print("  - \(mint.nickName ?? "Unknown"): \(mint.balance()) sats")
}
```

### **Test 2: Print Token Details**
Add to token generation success:
```swift
print("🎫 Token preview: \(String(tokenString.prefix(50)))...")
print("🎫 Token length: \(tokenString.count) characters")
```

### **Test 3: Test HTML Creation**
Add to `createTokenHTML`:
```swift
let html = createTokenHTML(token: "test", amount: 100, memo: "test")
print("📄 HTML length: \(html.count) characters")
```

## 🎯 **Quick Debug Checklist**

- [ ] Extension appears in Messages app
- [ ] Can tap to expand extension
- [ ] Shows available balance > 0
- [ ] Can enter amount and memo
- [ ] Send button becomes enabled
- [ ] Can tap send button
- [ ] See "Starting token generation" log
- [ ] See "Token generation successful" log
- [ ] See "Data URL length" log
- [ ] See "Successfully inserted" log
- [ ] Message appears in conversation

## 📊 **Size Limits to Watch**

- **Data URL**: < 2MB (browser limit)
- **iMessage**: < 100KB (satellite limit)
- **Current HTML**: ~1.5KB (good)
- **Typical token**: 500-2000 chars
- **Total URL**: Should be < 10KB

---

**💡 Tip: Use `print()` statements liberally - they're the easiest way to debug extensions!**
