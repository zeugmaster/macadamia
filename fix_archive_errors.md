# Fix for Archive Build Errors in Messages Extension

## The Problem(s)
1. **Missing Swift Package Dependencies**: Your Messages extension is missing critical package dependencies
2. **Xcode File Location Quirk**: After moving files to work around an Xcode quirk, the project file needs path updates
3. **Wrong Assets Catalog**: Messages extension was referencing the main app's Assets.xcassets instead of its own
4. **Missing Custom Colors**: Custom colors (successGreen, failureRed) were not available in Messages extension

## Root Cause (UPDATED)
While the shared files have their target membership set correctly, the Messages extension is **missing critical Swift Package dependencies**:

**Main app has these packages:**
- CashuSwift ✅ (Messages extension has this)
- BIP39 ❌ (MISSING in Messages extension!)
- secp256k1 ❌ (MISSING - required by PersistentModelV1.swift)
- BigNumber (might be needed)
- Other packages (MarkdownUI, Popovers, etc.)

**Messages extension only has:**
- CashuSwift

**The shared code requires:**
- `import secp256k1` (used in PersistentModelV1.swift for cryptographic operations)
- `import BIP39` (used in Operations/restore.swift if included)

This causes "missing symbol" errors during Archive builds because the packages aren't linked to the extension.

## Solution: Add Missing Swift Package Dependencies

### Step 1: Add Package Dependencies to Messages Extension

Since your files already have target membership set, you need to add the missing Swift Package dependencies:

1. **Open your project in Xcode**
2. **Select the `macadamiaMessages` target**
3. Go to the **"General"** tab
4. Scroll to **"Frameworks and Libraries"** section
5. Click the **"+"** button
6. Add these specific package products:
   - **secp256k1** (from swift-secp256k1 package - required by PersistentModelV1.swift)
   - **BIP39** (from BIP39 package - required if restore.swift is included)
   - **BigInt** (from Swift-BigInt package - if your code uses BigNumber)

### Alternative Method via Build Phases:
1. Select the Messages extension target
2. Go to **"Build Phases"** tab  
3. Expand **"Link Binary With Libraries"**
4. Click **"+"** and add the missing package products

### Step 2: Verify Dependencies

Check that these imports work in your Messages extension:
- `import secp256k1` (required by PersistentModelV1.swift)
- `import BIP39` (if using restore functionality)

### Step 3: Fix File Paths and Assets (if you moved files)

If you moved the Messages extension files to `macadamia/macadamiaMessages/`:

**The project.pbxproj has been updated with:**
- INFOPLIST_FILE paths: `macadamia/macadamiaMessages/Info.plist`
- Synchronized root group path: `macadamiaMessages` (relative to parent group)
- Removed incorrect Assets.xcassets reference (was pointing to main app's assets)

**Assets Catalog Fix:**
- The Messages extension was incorrectly using the main app's Assets.xcassets
- This caused "iMessage App Icon" not found errors
- Now uses its own Assets.xcassets from `macadamia/macadamiaMessages/Assets.xcassets`
- The synchronized root group automatically includes the correct assets

### Step 4: Fix Custom Colors

The Messages extension needs its own copy of custom colors used by shared code:

**Custom colors copied to Messages extension:**
- `successGreen.colorset` - Green color for success states
- `failureRed.colorset` - Red color for error/warning states

These colors are now in `macadamia/macadamiaMessages/Assets.xcassets/` and will be included automatically.

### Step 5: Clean and Archive

1. Clean Build Folder: Product > Clean Build Folder (⇧⌘K)
2. Try archiving again: Product > Archive

## Alternative Solution: Adjust Build Settings

If adding files causes other issues, try this temporary fix:

1. Select the `macadamiaMessages` target
2. Go to Build Settings tab
3. Search for "Swift Compilation Mode"
4. Change from "Whole Module" to "Incremental" for Release configuration
5. This is less optimal but can help identify remaining issues

## Why This Happens

- **Debug builds** often work because they use incremental compilation and don't optimize as aggressively
- **Archive/Release builds** use whole module optimization which strips symbols not explicitly part of the target
- The Messages extension is a separate binary that needs its own copy of the code it uses

## Long-term Best Practice

Consider creating a shared framework:
1. Create a new Framework target called "MacadamiaCore"
2. Move all shared code to this framework
3. Link both the main app and Messages extension to this framework
4. This ensures code is shared properly and reduces app size

## Verification

After making changes, verify:
1. Build succeeds for Debug configuration
2. Archive succeeds for Release configuration
3. Messages extension works correctly when installed

## Summary of All Fixes Applied

1. ✅ **Swift Package Dependencies** - Add secp256k1 and BIP39 to Messages extension
2. ✅ **Info.plist Path** - Updated to `macadamia/macadamiaMessages/Info.plist`
3. ✅ **Assets Catalog Path** - Fixed to use extension's own Assets.xcassets
4. ✅ **Custom Colors** - Copied successGreen and failureRed colorsets to extension

## Common Pitfalls to Avoid

- Don't use `@testable import` in production code
- Ensure all dependencies of added files are also included
- Check that the App Group is properly configured for data sharing
- Verify entitlements match between app and extension
- Remember that extensions need their own copies of custom colors/assets
