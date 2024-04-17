# Version {{VERSION}}
## Build {{BUILD}}

This build of macadamia contains **important changes to cryptographic functions** as well as bug fixes:

⚠️ Important: Due to necessary changes in the underlying cryptography, this build **breaks backwards compatibility** when using the `Restore from Seedphrase` feature.  

To avoid loss of funds, please consider performing one full `Drain` and subsequent `Redeem` back into your wallet. 

This will ensure using `Restore` works properly going forward.

For more information check out macadamia on [GitHub](https://github.com/zeugmaster/macadamia).
