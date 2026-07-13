//! Build script.
//!
//! Fixes FRB issue #1719: Android x86_64 emulator crashes with
//! `dlopen failed: cannot locate symbol "__extenddftf2"` when the Rust lib
//! links bundled C code (e.g. SQLite via `rusqlite/bundled`). The fix is to
//! explicitly link `clang_rt.builtins-x86_64-android` for that target only.
//! Real arm/arm64 devices are unaffected.

use std::path::{Path, PathBuf};

fn main() {
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    if target_arch == "x86_64" && target_os == "android" {
        link_clang_rt_builtins_x86_64_android();
    }
}

fn link_clang_rt_builtins_x86_64_android() {
    println!("cargo:rerun-if-env-changed=ANDROID_NDK_HOME");
    println!("cargo:rerun-if-env-changed=ANDROID_HOME");
    println!("cargo:rerun-if-env-changed=ANDROID_SDK_ROOT");

    let ndk_home = std::env::var("ANDROID_NDK_HOME")
        .or_else(|_| std::env::var("ANDROID_HOME"))
        .or_else(|_| std::env::var("ANDROID_SDK_ROOT"));

    let ndk_home = match ndk_home {
        Ok(path) => path,
        Err(_) => {
            println!(
                "cargo:warning=ANDROID_NDK_HOME/ANDROID_HOME/ANDROID_SDK_ROOT not set; \
                 skipping clang_rt.builtins link for android x86_64 \
                 (emulator builds may crash — see FRB #1719)"
            );
            return;
        }
    };

    // The builtins library lives at:
    //   <ndk>/toolchains/llvm/prebuilt/<host-tag>/lib/clang/<version>/lib/linux/
    // The <host-tag> and <version> directories vary by NDK release, so walk them.
    let prebuilt = PathBuf::from(&ndk_home).join("toolchains/llvm/prebuilt");

    for host_tag in read_subdirs(&prebuilt) {
        let clang_dir = prebuilt.join(&host_tag).join("lib/clang");
        for version in read_subdirs(&clang_dir) {
            let linux_dir = clang_dir.join(&version).join("lib/linux");
            let lib_file = linux_dir.join("libclang_rt.builtins-x86_64-android.a");
            if lib_file.exists() {
                println!("cargo:rustc-link-search={}", linux_dir.display());
                println!("cargo:rustc-link-lib=static=clang_rt.builtins-x86_64-android");
                println!(
                    "cargo:warning=Linked clang_rt.builtins-x86_64-android from {}",
                    linux_dir.display()
                );
                return;
            }
        }
    }

    println!(
        "cargo:warning=libclang_rt.builtins-x86_64-android.a not found under {ndk_home}; \
         android x86_64 emulator builds may crash with __extenddftf2 (FRB #1719)"
    );
}

/// Returns the names of immediate subdirectories of `path` (non-recursive).
fn read_subdirs(path: &Path) -> Vec<String> {
    std::fs::read_dir(path)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            if entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                entry.file_name().to_str().map(String::from)
            } else {
                None
            }
        })
        .collect()
}
