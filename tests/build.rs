use std::env;

fn main() {
    // w2c2 defines its own `bool`, a keyword in C23 (GCC 15+'s default), so compile its output as C17.
    let cflags = env::var("CFLAGS").unwrap_or_default();
    env::set_var("CFLAGS", format!("{cflags} -std=gnu17"));

    rust_witness::transpile::transpile_wasm("./test-vectors".to_string());
}
