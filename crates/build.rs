use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

const RAPIDSNARK_DOWNLOAD_SCRIPT: &str = include_str!("./download_rapidsnark.sh");
const RAPIDSNARK_GIT: &str = "https://github.com/iden3/rapidsnark.git";
const RAPIDSNARK_TAG: &str = "v0.0.8";

fn main() {
    let target = env::var("TARGET").unwrap();
    let out_dir = env::var("OUT_DIR").expect("OUT_DIR not set");
    let arch = target.split('-').next().unwrap();

    // See: https://github.com/zkmopro/chkstk_stub
    chkstk_stub::build();

    // On glibc-Linux with static linking the prebuilt iden3 archives don't work:
    // they are non-PIC (cannot be linked into a downstream cdylib such as the
    // node's C bindings) and are built against a newer glibc (undefined
    // __isoc23_strtoll/ull on older hosts). Build rapidsnark from source with
    // -fPIC against the host toolchain instead, which resolves both problems.
    if build_from_source_applies() {
        build_rapidsnark_from_source(&out_dir);
        return;
    }

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
}

fn build_from_source_applies() -> bool {
    is_static_rapidsnark()
        && env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux")
        && env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("gnu")
}

/// Build rapidsnark's static archives from source with position-independent code.
///
/// Requires `git`, `cmake`, `make`, `nasm`, a C++ compiler, and the GMP/libsodium
/// development headers to be available on the build host. GMP is linked from the
/// system as a (PIC) shared library.
fn build_rapidsnark_from_source(out_dir: &str) {
    let src = Path::new(out_dir).join("rapidsnark-src");
    if !src.join("CMakeLists.txt").exists() {
        // Clean any partial checkout so the clone can succeed.
        let _ = fs::remove_dir_all(&src);
        run(Command::new("git").args([
            "clone",
            "--depth",
            "1",
            "--branch",
            RAPIDSNARK_TAG,
            RAPIDSNARK_GIT,
            src.to_str().unwrap(),
        ]));
    }
    // Only the field-element codegen (ffiasm) and JSON header are needed to build
    // the prover/verifier static libraries.
    run(Command::new("git").current_dir(&src).args([
        "submodule",
        "update",
        "--init",
        "--depth",
        "1",
        "depends/ffiasm",
        "depends/json",
    ]));

    let build = src.join("build_pic");
    fs::create_dir_all(&build).expect("Failed to create rapidsnark build dir");
    run(Command::new("cmake").current_dir(&build).args([
        "..",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
        "-DUSE_ASM=ON",
        "-DUSE_OPENMP=OFF",
        "-DUSE_LOGGER=ON",
    ]));

    let jobs = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .to_string();
    run(Command::new("make").current_dir(&build).args([
        "-j",
        &jobs,
        "rapidsnarkStatic",
        "fr",
        "fq",
    ]));

    let lib_dir = build.join("src");
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=rapidsnark");
    println!("cargo:rustc-link-lib=static=fr");
    println!("cargo:rustc-link-lib=static=fq");
    // GMP is provided by the system as a PIC shared library.
    println!("cargo:rustc-link-lib=dylib=gmp");
    println!("cargo:rustc-link-lib=stdc++");
    println!("cargo:rustc-link-lib=pthread");
}

fn run(cmd: &mut Command) {
    eprintln!("rapidsnark build: running {cmd:?}");
    let status = cmd
        .status()
        .unwrap_or_else(|e| panic!("Failed to spawn {cmd:?}: {e}"));
    assert!(status.success(), "Command failed ({status}): {cmd:?}");
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
