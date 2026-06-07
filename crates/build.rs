use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

const RAPIDSNARK_DOWNLOAD_SCRIPT: &str = include_str!("./download_rapidsnark.sh");

fn main() {
    let target = env::var("TARGET").unwrap();
    let out_dir = env::var("OUT_DIR").expect("OUT_DIR not set");
    let arch = target.split('-').next().unwrap();

    // See: https://github.com/zkmopro/chkstk_stub
    chkstk_stub::build();

    // Try to list contents of the target directory
    let rapidsnark_path = Path::new(&out_dir).join(Path::new("rapidsnark"));
    // If the rapidsnark repo is not downloaded, download it
    if !rapidsnark_path.exists() {
        let rapidsnark_script_path = Path::new(&out_dir).join(Path::new("download_rapidsnark.sh"));
        fs::write(&rapidsnark_script_path, RAPIDSNARK_DOWNLOAD_SCRIPT)
            .expect("Failed to write build script");
        let child_process = Command::new("sh")
            .arg(rapidsnark_script_path.to_str().unwrap())
            .spawn();
        if let Err(e) = child_process {
            panic!("Failed to spawn rapidsnark download: {e}");
        }
        let status = child_process.unwrap().wait();
        if let Err(e) = status {
            panic!("Failed to wait for rapidsnark download: {e}");
        } else if !status.unwrap().success() {
            panic!("Failed to wait for rapidsnark download");
        }
    }
    let absolute_lib_path = if rapidsnark_path.join(&target).exists() {
        rapidsnark_path.join(&target)
    } else {
        rapidsnark_path.join(arch)
    };
    let compiler = cc::Build::new().get_compiler();
    let cpp_stdlib = if compiler.is_like_clang() {
        "c++"
    } else {
        "stdc++"
    };

    println!(
        "cargo:rustc-link-search=native={}",
        absolute_lib_path.display()
    );

    // The shared rapidsnark artifact is already linked with its fr/fq/gmp implementation.
    // Linking those helper libraries again is redundant and can accidentally pull static archives
    // into downstream binaries, exporting generic Fr_* / Fq_* symbols that collide with other
    // native ZK libraries.
    //
    // The static rapidsnark archive is different: it leaves Fr_*, Fq_*, and GMP symbols unresolved,
    // so static/mobile builds must link the helper archives.
    if is_static_rapidsnark() || is_mobile_target() {
        println!("cargo:rustc-link-lib=static=rapidsnark");
        println!("cargo:rustc-link-lib=static=fr");
        println!("cargo:rustc-link-lib=static=fq");
        println!("cargo:rustc-link-lib=static=gmp");
    } else {
        println!("cargo:rustc-link-lib=dylib=rapidsnark");
    }

    println!("cargo:rustc-link-lib={cpp_stdlib}");

    // Android bundles pthread into libc
    let thread_lib = if is_android_target() { "c" } else { "pthread" };
    println!("cargo:rustc-link-lib={thread_lib}");

    // glibc >= 2.38 redirects strtoll/strtoull to the C23 interceptor symbols
    // __isoc23_strtoll / __isoc23_strtoull. The prebuilt iden3 rapidsnark archives
    // were compiled against such a glibc, so when they are linked statically on a
    // host with an older glibc (e.g. glibc 2.35) the verifier objects reference
    // __isoc23_* symbols that do not exist there and linking fails. Compile thin
    // forwarders to the classic strtoll/strtoull and link them so the static path
    // resolves regardless of the host glibc version. Only relevant for the static
    // archive on glibc-Linux; the shared library and other targets are unaffected.
    println!("cargo:rerun-if-changed=isoc23_compat.c");
    if is_static_rapidsnark()
        && env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux")
        && env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("gnu")
    {
        cc::Build::new()
            .file("isoc23_compat.c")
            .cargo_metadata(false)
            .compile("isoc23_compat");
        println!("cargo:rustc-link-search=native={out_dir}");
        // whole-archive so the forwarders are included unconditionally, regardless
        // of this archive's position relative to librapidsnark.a on the link line.
        println!("cargo:rustc-link-lib=static:+whole-archive=isoc23_compat");
    }
}

fn is_static_rapidsnark() -> bool {
    env::var_os("CARGO_FEATURE_STATIC_RAPIDSNARK").is_some()
}

fn is_mobile_target() -> bool {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    target_os.contains("ios") || target_os.contains("android")
}

fn is_android_target() -> bool {
    env::var("CARGO_CFG_TARGET_OS").unwrap().contains("android")
}
