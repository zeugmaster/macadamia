# macadamia for iOS

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

### WARNING: 
This project is in the very early beta stages and propably contains bugs that can lead to a loss of funds. Please only experiment with amounts of sats you are ready to lose!

## Next Steps:
- clean up codebase
- write unit tests
- UI improvements
- inter-mint-swap
- improve robustness
- move to proper SwiftData database
- add support for mint API v1
- preparation for advanced cashu features like P2PK and DLEQs

## Goal:
Really polished UI that hides all unnecessary complexity from casual users, but still provides advanced features to power users
