/// @author     Shawn <shawn@zilliqa.com>
/// @date       2026-08-07
/// 
/// Prerequisites:
/// - Install rustup targets [aarch64-linux-android, x86_64-linux-android, x86_64-unknown-linux-gnu, aarch64-apple-ios, ...]
/// - Run `cargo install mopro-cli` to install the mopro CLI tool.
/// 
/// - Install flutter https://docs.flutter.dev/install
/// - Run `flutter pub get` in the `flutter` directory to install the Flutter dependencies.
///
/// - Download the `circuit_final.zkey` and `circuit.wasm` files from https://checkpoints.zq2-testnet.zilliqa.com/
/// 
/// How to build and run the Flutter app:
/// 1. Copy the `circuit.wasm` file to the `test-vectors/circom/ledger.wasm` file.
/// 2. Copy the `circuit_final.zkey` file to the `test-vectors/circom/ledger_final.zkey` file.
/// 3. Run `mopro build` to build the Rust library bindings for flutter.
/// 4. Run `cargo test -- --no-capture circom_test` to run the self-test; it should pass.
/// 5. Run `flutter run -d <xxx>` in the `flutter` directory to run the Flutter app.
/// 6. Do not forget to run `mopro build` again if you change the circuit; and recompile it with circom.

fn main() {
    // CIRCOM_TEMPLATE

    rust_witness::transpile::transpile_wasm("./test-vectors/circom".to_string());
    
    // GNARK_TEMPLATE
}
