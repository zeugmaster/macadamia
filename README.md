# macadamia Wallet for iOS <img align="left" width="40" height="40" src="https://cypherbase.cc/images/logo_w256.png" alt="logo">


This is __macadamia__, a native iOS client for [cashu](https://github.com/cashubtc).
cashu is a Chaumian eCash system designed for near perfect privacy.

macadamia support standard cashu operations such as:
- __Minting__ of tokens
- __Sending__ and 
- __Receiving__
- __Melting__ tokens (using them to pay a Lightning Network invoice) 
- Restoring your wallet balance using a 12 word mnemonic __seed phrase backup__


You can test it using [Testflight](https://testflight.apple.com/join/RMU6PaRu)

Come join the discussion in the [Telegram channel](https://t.me/macadamiawallet)

### WARNING: 
This project is in the very early beta stages and propably contains bugs that can lead to a loss of funds. 
Please only experiment with amounts of sats you are ready to lose!

### Network privacy

The default connection mode supports public HTTPS/WSS endpoints directly and v3
onion endpoints through embedded Tor. Settings → Privacy → **Tor only** routes all
wallet connections through Tor and fails closed if Tor is unavailable. New installs
start in Automatic mode; Tor only is available in Settings. Public HTTP,
cross-origin redirects, and local destinations in Tor only mode are rejected.
Links opened in another app use that app's settings.

The wallet owns routing, ephemeral URLSessions and the lifecycle of
[Tor.framework](https://github.com/iCepa/Tor.framework), pinned to CTor 409.17.1.
CashuSwift receives a normal URLSession on each operation; it has no Tor dependency
or global networking configuration. NostrSDK uses the same injected sessions for
WebSockets, including reconnects. Images, LNURL callbacks, mint discovery, backups,
exchange rates and block explorers follow the wallet's connection policy too.

Messages uses the shared preference and opens the main app for operations requiring
Tor. Exact unlocked token sends remain available offline in either app.

Sends requiring a swap save their recovery context, reserve inputs and advance
derivation counters before contacting the mint. An interrupted send stays pending
in History, where **Recover send** restores the saved outputs using NUT-09. An empty
restore response keeps the funds reserved; it does not prove the swap was rejected.
Pending recovery records cannot be deleted from History. Keep the app's local data:
random P2PK output secrets cannot be reconstructed from the seed alone.

### Networking checks

`NetworkRoutingTests`, `SOCKSRoutingTests` and `SendRecoveryTests` run without public
services. SOCKS tests inspect the actual HTTP/WebSocket destination sent to a local
proxy and detect loopback bypass. CashuSwift's session tests use independent caller
sessions and cover nested mint, receive, restore and payment-delivery operations.

`TorSmokeTests` is opt-in: set `MACADAMIA_TOR_SMOKE=1` in the **test runner's**
environment in Xcode. It checks Tor Project HTTPS and onion services plus foreground
recovery; it never contacts a mint. The existing mint integration tests require a
local test mint. Before release, exercise background/foreground changes, network
loss, Messages handoff and DNS routing on a physical device, including the oldest
supported iOS version. New privacy and recovery copy currently has English strings;
the string catalog contains entries for translation.

