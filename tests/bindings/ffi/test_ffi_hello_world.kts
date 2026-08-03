import uniffi.ledger_mopro_app.*

var helloWorld = moproHelloWorld()
assert(helloWorld == "Hello, World!") { "Test string mismatch" }
