# macadamia Wallet for iOS <img align="left" width="40" height="40" src="https://macadamia.cash/images/Artboard%201@1024x-8.png" alt="logo">


This is __macadamia__, a native iOS client for [cashu](https://github.com/cashubtc).
cashu is a Chaumian eCash system designed for near perfect privacy.

macadamia support standard cashu operations such as:
- __Minting__ of tokens
- __Sending__ and 
- __Receiving__
- __Melting__ tokens (using them to pay a Lightning Network invoice) 
- Restoring your wallet balance using a 12 word mnemonic __seed phrase backup__

Additionally, macadamia supports sending and receiving/redeeming tokens sent over the __Nostr__ protocol!

You can test it using [Testflight](https://testflight.apple.com/join/FteRYrAZ)

Come join the discussion in the [Telegram channel](https://t.me/macadamiawallet)

### WARNING: 
This project is in the very early beta stages and propably contains bugs that can lead to a loss of funds. Please only experiment with amounts of sats you are ready to lose!

## Project Timeline:

#### Phase 0 - Native Swift and SwiftUI Wallet Alpha Release and PoC
**Complete**

#### Phase 1 - Library Segregation, Late Stage Beta Testing and App Store Release

| Task                                                                                                                                                                                      | State |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| Completion and Release of `Cashu-swift` as a standalone library for cashu API v1 written in Swift; Support for all mandatory NUTs as well as `NUT-07`, `NUT-09` and `NUT-13` initially    |       |
| Test coverage on critical library functions (e.g. cryptography)                                                                                                                           |       |
| Documentation and annotation on all public library functions                                                                                                                              |       |
| Migration to Apple Developer Account for  and transfer of Testflight App                                                                                                                  |       |
| Wallet release with full Wallet-Library separation                                                                                                                                        |       |
| Wallet Database migration to SwiftData                                                                                                                                                    |       |
| Mint Swap Feature                                                                                                                                                                         |       |
| Mint Info UI                                                                                                                                                                              |       |
| Deployment of reliable, high-availabilty demo mint.                                                                                                                                       |       |
| Rewrite of websocket related logic for nostr relay communication                                                                                                                          |       |
| Website update                                                                                                                                                                            |       |
| App Store Release of first stable version with following features: Mint, Melt, Send, Receive, Restore from Seedphrase, Simple mint management, Mint Swap, sending and receiving via Nostr |       |
#### Phase 2 - Advanced Wallet Functionality and UI Improvements

| Detail                                                                                                                                | State   |
| ------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| V4 Token support                                                                                                                      |         |
| Auto-Swap feature to let users automatically make a mint swap from the unknown mint to a trusted one via Lightning                    |         |
| Animated QR-Codes                                                                                                                     | In Beta |
| Advanced mint selection: Allow users to set a default mint and enable automatic mint selection based on current balance, availability |         |
| Multi-mint token sending: Enable the selective creation of a token containing proofs for multiple mints                               |         |
| Implementation of spending conditions in library (`NUT-10`)                                                                           |         |
| Support for P2PK spending condition (`NUT-11`)                                                                                        |         |
| Support for DLEQ Proofs for receiver-offline payments                                                                                 |         |
| Wallet support for receiving offline payments                                                                                         |         |
| Enable device biometric security for wallet protection, e.g. FaceID                                                                   |         |
| Encrypted iCloud backup for wallet database                                                                                           |         |
| iMessage App Prototype to allow for sending and receiving of payments                                                                 |         |

#### Phase 3 - Novel/Experimental Wallet Features and User Interface Design Exploration

| Task                                                                                                                                                                                   | State |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| Multipart Cashu payments: Lets the wallet instruct multiple mints to collectively pay the sum of a single Lightning invoice                                                            |       |
| Mint Watch: Notify users of any issues with their trusted mints such as disproportionally large balances or reliability problems                                                       |       |
| Mint Balancing: Provide the option to have the wallet balance funds across trusted, reliable mints                                                                                     |       |
| AirNut: Simple and reliable sharing of tokens using Bluetooth Low Energy as an alternative to the very restricted APIs for NFC on Apple devices; Relying on library support for NUT-11 |       |
| watchOS Demo                                                                                                                                                                           |       |
| NFC payments on iPhone feasibility testing                                                                                                                                             |       |


## Goal:
Really polished UI that hides all unnecessary complexity from casual users, but still provides advanced features to power users
