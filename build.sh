#!/bin/bash
# GCC Build Script for OpenHarmony (OHOS) Target
# Based on Alpine Linux APKBUILD
# Copyright (C) 2024 OpenHarmony Project

set -e

# CRITICAL FIX: Disable shell aliases/functions for diff and use absolute path
# Some shell configurations define diff() with --color which breaks
# autoconf's config.status script that uses diff for file comparison
# Also ensure we use /bin/diff, not any custom diff in PATH
unset -f diff
alias diff='/bin/diff'
export DIFF='/bin/diff'
export PATH="/bin:/usr/bin:/usr/local/bin:${PATH}"

# ============================================================================
# Configuration Variables
# ============================================================================

# GCC Version
GCC_VERSION="15.2.0"
GCC_MAJOR_VERSION="${GCC_VERSION%%.*}"

# Build directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/gcc-${GCC_VERSION}"
BUILD_DIR="${SCRIPT_DIR}/build-ohos"
INSTALL_PREFIX="${INSTALL_PREFIX:-${SCRIPT_DIR}/install}"
SYSROOT="${SYSROOT:-}"

# Binutils configuration
BINUTILS_VERSION="${BINUTILS_VERSION:-2.43}"
BINUTILS_SOURCE_DIR="${SCRIPT_DIR}/binutils-${BINUTILS_VERSION}"
BINUTILS_BUILD_DIR="${SCRIPT_DIR}/build-binutils"
# BINUTILS_INSTALL_PREFIX is set after command line parsing to use the correct INSTALL_PREFIX

# Stage 2 (Canadian Cross) configuration
# When building native OHOS toolchain, we need a stage 1 cross-compiler
# STAGE1_PREFIX points to the previously built cross-compiler
STAGE1_PREFIX="${STAGE1_PREFIX:-}"

# Stage 3 (Native bootstrap) configuration
# When building on OHOS itself, we need a stage 2 native compiler
# STAGE2_PREFIX points to the previously built native OHOS compiler
STAGE2_PREFIX="${STAGE2_PREFIX:-}"

# NDK configuration
NDK_URL="${NDK_URL:-https://cidownload.openharmony.cn/version/Daily_Version/LLVM-19/20260114_061434/version-Daily_Version-LLVM-19-20260114_061434-LLVM-19.tar.gz}"
NDK_DIR="${SCRIPT_DIR}/ndk"
NDK_SYSROOT_DIR="${NDK_DIR}/sysroot"

# Target configuration
DEFAULT_CBUILD="$(gcc -dumpmachine)"
CBUILD="${CBUILD:-${DEFAULT_CBUILD}}"
CHOST="${CHOST:-}"
CTARGET="${CTARGET:-aarch64-linux-ohos}"

# Function to setup target-specific configuration
# This is called after command line parsing to ensure --target is respected
setup_target_config() {
    # Extract architecture from target triplet
    case "${CTARGET}" in
        aarch64-*)
            CTARGET_ARCH="aarch64"
            ARCH_CONFIGURE="--with-arch=armv8-a --with-abi=lp64"
            ;;
        arm*hf-*)
            CTARGET_ARCH="armv7"
            ARCH_CONFIGURE="--with-arch=armv7-a --with-tune=generic-armv7-a --with-fpu=vfpv3-d16 --with-float=hard --with-abi=aapcs-linux --with-mode=thumb"
            ;;
        arm*-*)
            CTARGET_ARCH="arm"
            ARCH_CONFIGURE="--with-arch=armv5te --with-tune=arm926ej-s --with-float=soft --with-abi=aapcs-linux"
            ;;
        x86_64-*)
            CTARGET_ARCH="x86_64"
            ARCH_CONFIGURE=""
            SANITIZER_CONFIGURE="--enable-libsanitizer"
            ;;
        i?86-*)
            CTARGET_ARCH="x86"
            ARCH_CONFIGURE="--with-arch=i486 --with-tune=generic --enable-cld"
            ;;
        riscv64-*)
            CTARGET_ARCH="riscv64"
            ARCH_CONFIGURE="--with-arch=rv64gc --with-abi=lp64d --enable-autolink-libatomic"
            ;;
        mips64el-*)
            CTARGET_ARCH="mips64el"
            ARCH_CONFIGURE="--with-arch=mips3 --with-tune=mips64 --with-mips-plt --with-float=soft --with-abi=64"
            ;;
        mips64-*)
            CTARGET_ARCH="mips64"
            ARCH_CONFIGURE="--with-arch=mips3 --with-tune=mips64 --with-mips-plt --with-float=soft --with-abi=64"
            ;;
        mipsel-*)
            CTARGET_ARCH="mipsel"
            ARCH_CONFIGURE="--with-arch=mips32 --with-mips-plt --with-float=soft --with-abi=32"
            ;;
        mips-*)
            CTARGET_ARCH="mips"
            ARCH_CONFIGURE="--with-arch=mips32 --with-mips-plt --with-float=soft --with-abi=32"
            ;;
        *)
            echo "Error: Unsupported target architecture: ${CTARGET}"
            exit 1
            ;;
    esac

    # Default sanitizer config (disabled for most architectures)
    SANITIZER_CONFIGURE="${SANITIZER_CONFIGURE:---disable-libsanitizer}"

    # Hash style configuration
    case "${CTARGET_ARCH}" in
        mips*) HASH_STYLE_CONFIGURE="--with-linker-hash-style=sysv" ;;
        *)     HASH_STYLE_CONFIGURE="--with-linker-hash-style=gnu" ;;
    esac

    # Disable libitm for certain architectures
    case "${CTARGET_ARCH}" in
        arm*|mips*|riscv64) LIBITM="no" ;;
    esac

    # Quadmath support (x86/x86_64/ppc64le only) - disabled for cross-compilation
    case "${CTARGET_ARCH}" in
        x86|x86_64|ppc64le) LIBQUADMATH="no" ;;
    esac

    # Rebuild BOOTSTRAP_CONFIGURE with updated library settings
    BOOTSTRAP_CONFIGURE="--enable-shared --enable-threads --enable-tls"
    [ "${LIBGOMP}" = "no" ] && BOOTSTRAP_CONFIGURE="${BOOTSTRAP_CONFIGURE} --disable-libgomp"
    [ "${LIBATOMIC}" = "no" ] && BOOTSTRAP_CONFIGURE="${BOOTSTRAP_CONFIGURE} --disable-libatomic"
    [ "${LIBITM}" = "no" ] && BOOTSTRAP_CONFIGURE="${BOOTSTRAP_CONFIGURE} --disable-libitm"
    [ "${LIBQUADMATH}" = "no" ] && ARCH_CONFIGURE="${ARCH_CONFIGURE} --disable-libquadmath"
}

# Language support
LANG_CXX="${LANG_CXX:-yes}"
LANG_D="${LANG_D:-no}"
LANG_OBJC="${LANG_OBJC:-no}"
LANG_GO="${LANG_GO:-no}"
LANG_FORTRAN="${LANG_FORTRAN:-no}"
LANG_ADA="${LANG_ADA:-no}"
LANG_JIT="${LANG_JIT:-no}"

# Build languages list
LANGUAGES="c"
[ "${LANG_CXX}" = "yes" ] && LANGUAGES="${LANGUAGES},c++"
[ "${LANG_D}" = "yes" ] && LANGUAGES="${LANGUAGES},d"
[ "${LANG_OBJC}" = "yes" ] && LANGUAGES="${LANGUAGES},objc"
[ "${LANG_GO}" = "yes" ] && LANGUAGES="${LANGUAGES},go"
[ "${LANG_FORTRAN}" = "yes" ] && LANGUAGES="${LANGUAGES},fortran"
[ "${LANG_ADA}" = "yes" ] && LANGUAGES="${LANGUAGES},ada"
[ "${LANG_JIT}" = "yes" ] && LANGUAGES="${LANGUAGES},jit"

# Library features
# Note: In cross-compilation, these libraries require link tests which fail early
# when GCC is not fully bootstrapped. Disable them by default for OHOS.
LIBGOMP="${LIBGOMP:-no}"
LIBATOMIC="${LIBATOMIC:-no}"
LIBITM="${LIBITM:-no}"
LIBQUADMATH="${LIBQUADMATH:-no}"

# Cross-compilation configuration will be resolved during configure phase
# Build types:
#   Stage 1 (cross):     CBUILD=host, CHOST=host,   CTARGET=ohos  (cross-compiler)
#   Stage 2 (Canadian):  CBUILD=host, CHOST=ohos,   CTARGET=ohos  (native compiler)
# Stage 2 requires STAGE1_PREFIX pointing to a working stage 1 cross-compiler

# Parallel build
JOBS="${JOBS:-$(nproc)}"

# ============================================================================
# Helper Functions
# ============================================================================

msg() {
    echo "===> $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# Check if this is a Canadian Cross build (stage 2)
is_canadian_cross() {
    [ "${CBUILD}" != "${CHOST}" ] && [ "${CHOST}" = "${CTARGET}" ]
}

# Check if this is a native OHOS build (stage 3)
# All three triplets are the same and are OHOS targets
is_native_ohos_build() {
    [ "${CBUILD}" = "${CHOST}" ] && [ "${CHOST}" = "${CTARGET}" ] && [[ "${CTARGET}" == *-linux-ohos ]]
}

# Verify stage 1 toolchain exists and is functional
check_stage1_toolchain() {
    if [ -z "${STAGE1_PREFIX}" ]; then
        error "STAGE1_PREFIX not set. Stage 2 build requires a stage 1 cross-compiler.
Use --stage1=/path/to/stage1/install to specify it."
    fi

    msg "Checking stage 1 toolchain at ${STAGE1_PREFIX}..."

    local cc="${STAGE1_PREFIX}/bin/${CTARGET}-gcc"
    local cxx="${STAGE1_PREFIX}/bin/${CTARGET}-g++"
    local ar="${STAGE1_PREFIX}/bin/${CTARGET}-ar"
    local as="${STAGE1_PREFIX}/bin/${CTARGET}-as"
    local ld="${STAGE1_PREFIX}/bin/${CTARGET}-ld"

    for tool in "${cc}" "${cxx}" "${ar}" "${as}" "${ld}"; do
        if [ ! -x "${tool}" ]; then
            error "Stage 1 tool not found: ${tool}
Make sure stage 1 cross-compiler is properly installed at ${STAGE1_PREFIX}"
        fi
    done

    msg "Stage 1 toolchain verified: $("${cc}" --version | head -1)"
}

# Verify stage 2 toolchain exists and is functional
check_stage2_toolchain() {
    if [ -z "${STAGE2_PREFIX}" ]; then
        error "STAGE2_PREFIX not set. Stage 3 build requires a stage 2 native compiler.
Use --stage2=/path/to/stage2/install to specify it."
    fi

    msg "Checking stage 2 toolchain at ${STAGE2_PREFIX}..."

    # Stage 2 produces native tools, check for both prefixed and unprefixed names
    local cc="${STAGE2_PREFIX}/bin/gcc"
    local cxx="${STAGE2_PREFIX}/bin/g++"
    local ar="${STAGE2_PREFIX}/bin/ar"
    local as="${STAGE2_PREFIX}/bin/as"
    local ld="${STAGE2_PREFIX}/bin/ld"

    # Fall back to target-prefixed names if unprefixed not found
    [ ! -x "${cc}" ] && cc="${STAGE2_PREFIX}/bin/${CTARGET}-gcc"
    [ ! -x "${cxx}" ] && cxx="${STAGE2_PREFIX}/bin/${CTARGET}-g++"
    [ ! -x "${ar}" ] && ar="${STAGE2_PREFIX}/bin/${CTARGET}-ar"
    [ ! -x "${as}" ] && as="${STAGE2_PREFIX}/bin/${CTARGET}-as"
    [ ! -x "${ld}" ] && ld="${STAGE2_PREFIX}/bin/${CTARGET}-ld"

    for tool in "${cc}" "${cxx}" "${ar}" "${as}" "${ld}"; do
        if [ ! -x "${tool}" ]; then
            error "Stage 2 tool not found: ${tool}
Make sure stage 2 native compiler is properly installed at ${STAGE2_PREFIX}"
        fi
    done

    msg "Stage 2 toolchain verified: $("${cc}" --version | head -1)"
}

# Setup environment for Canadian Cross build (stage 2)
setup_canadian_cross_env() {
    msg "Setting up Canadian Cross (stage 2) build environment..."

    # Add stage 1 toolchain to PATH first, so tools can be found by name
    export PATH="${STAGE1_PREFIX}/bin:${PATH}"

    # Use stage 1 cross-compiler as the host compiler (found via PATH)
    export CC="${CTARGET}-gcc"
    export CXX="${CTARGET}-g++"
    export AR="${CTARGET}-ar"
    export AS="${CTARGET}-as"
    export LD="${CTARGET}-ld"
    export NM="${CTARGET}-nm"
    export RANLIB="${CTARGET}-ranlib"
    export STRIP="${CTARGET}-strip"
    export OBJCOPY="${CTARGET}-objcopy"
    export OBJDUMP="${CTARGET}-objdump"

    # Note: Do NOT set PIE flags here manually. GCC's configure will detect PIE requirements
    # and set PICFLAG/LD_PICFLAG appropriately. For Canadian Cross to OHOS, we use
    # --enable-host-pie in configure_gcc() to build PIE-compatible host tools.
    export CFLAGS="${CFLAGS:--g -O2}"
    export CXXFLAGS="${CXXFLAGS:--g -O2}"
    export LDFLAGS="${LDFLAGS:-}"

    # For Canadian Cross build, target tools must be the stage 1 cross-compiler
    # because it can run on the BUILD machine and generate code for TARGET.
    # The newly built compiler (xgcc) cannot run on BUILD machine.
    export CC_FOR_TARGET="${CC}"
    export CXX_FOR_TARGET="${CXX}"
    export GCC_FOR_TARGET="${CTARGET}-gcc"
    export GXX_FOR_TARGET="${CTARGET}-g++"
    export AR_FOR_TARGET="${CTARGET}-ar"
    export AS_FOR_TARGET="${CTARGET}-as"
    export LD_FOR_TARGET="${CTARGET}-ld"
    export NM_FOR_TARGET="${CTARGET}-nm"
    export RANLIB_FOR_TARGET="${CTARGET}-ranlib"
    export STRIP_FOR_TARGET="${CTARGET}-strip"
    export OBJCOPY_FOR_TARGET="${CTARGET}-objcopy"
    export OBJDUMP_FOR_TARGET="${CTARGET}-objdump"

    # Build tools - must run on the BUILD machine, not the HOST
    # NOTE: We intentionally do NOT export CC_FOR_BUILD/CXX_FOR_BUILD as environment
    # variables. Instead, we pass them on the configure command line in configure_gcc().
    # This ensures the correct build compiler is used without triggering GMP's configure
    # race condition that can occur when CC_FOR_BUILD is exported as an environment
    # variable during parallel configure runs.
    #
    # We set these as shell variables for use in both binutils build and GCC configure.
    # Note: We need to find the native toolchain path to ensure CC_FOR_BUILD can
    # properly link executables. When PATH is modified to include cross tools,
    # the native compiler's collect2 might find the wrong linker.
    local native_bindir="/usr/bin"
    if [[ -x "/usr/bin/${CBUILD}-gcc" ]]; then
        CC_FOR_BUILD="/usr/bin/${CBUILD}-gcc"
        CXX_FOR_BUILD="/usr/bin/${CBUILD}-g++"
    elif [[ -x "/usr/bin/gcc" ]]; then
        CC_FOR_BUILD="/usr/bin/gcc"
        CXX_FOR_BUILD="/usr/bin/g++"
    else
        CC_FOR_BUILD="${CBUILD}-gcc"
        CXX_FOR_BUILD="${CBUILD}-g++"
        if ! command -v "${CC_FOR_BUILD}" >/dev/null 2>&1; then
            CC_FOR_BUILD="gcc"
            CXX_FOR_BUILD="g++"
        fi
    fi
    # Add -B flag to tell the compiler where to find the native binutils (ld, as, etc.)
    # This is critical for Canadian Cross builds where PATH is modified to include
    # cross-compiler tools, which could confuse collect2's linker search.
    CC_FOR_BUILD="${CC_FOR_BUILD} -B${native_bindir}"
    CXX_FOR_BUILD="${CXX_FOR_BUILD} -B${native_bindir}"
    # Only export the flags, not the compiler commands
    export CFLAGS_FOR_BUILD="-g -O2"
    export CXXFLAGS_FOR_BUILD="-g -O2"
    export LDFLAGS_FOR_BUILD=""

    msg "Canadian Cross environment configured:"
    echo "  PATH includes: ${STAGE1_PREFIX}/bin"
    echo "  CC=${CC}"
    echo "  CC_FOR_BUILD=${CC_FOR_BUILD} (not exported, to avoid GMP configure race)"
    echo "  GCC_FOR_TARGET=${GCC_FOR_TARGET}"
    echo "  CFLAGS=${CFLAGS}"
    echo "  LDFLAGS=${LDFLAGS}"
    echo "  CBUILD=${CBUILD}"
    echo "  CHOST=${CHOST}"
    echo "  CTARGET=${CTARGET}"
}

# Setup environment for native OHOS build (stage 3)
setup_native_ohos_env() {
    msg "Setting up native OHOS (stage 3) build environment..."

    # Use stage 2 native compiler as the host/target compiler
    # Try unprefixed first, fall back to prefixed
    if [ -x "${STAGE2_PREFIX}/bin/gcc" ]; then
        export CC="${STAGE2_PREFIX}/bin/gcc"
        export CXX="${STAGE2_PREFIX}/bin/g++"
        export AR="${STAGE2_PREFIX}/bin/ar"
        export AS="${STAGE2_PREFIX}/bin/as"
        export LD="${STAGE2_PREFIX}/bin/ld"
        export NM="${STAGE2_PREFIX}/bin/nm"
        export RANLIB="${STAGE2_PREFIX}/bin/ranlib"
        export STRIP="${STAGE2_PREFIX}/bin/strip"
        export OBJCOPY="${STAGE2_PREFIX}/bin/objcopy"
        export OBJDUMP="${STAGE2_PREFIX}/bin/objdump"
    else
        export CC="${STAGE2_PREFIX}/bin/${CTARGET}-gcc"
        export CXX="${STAGE2_PREFIX}/bin/${CTARGET}-g++"
        export AR="${STAGE2_PREFIX}/bin/${CTARGET}-ar"
        export AS="${STAGE2_PREFIX}/bin/${CTARGET}-as"
        export LD="${STAGE2_PREFIX}/bin/${CTARGET}-ld"
        export NM="${STAGE2_PREFIX}/bin/${CTARGET}-nm"
        export RANLIB="${STAGE2_PREFIX}/bin/${CTARGET}-ranlib"
        export STRIP="${STAGE2_PREFIX}/bin/${CTARGET}-strip"
        export OBJCOPY="${STAGE2_PREFIX}/bin/${CTARGET}-objcopy"
        export OBJDUMP="${STAGE2_PREFIX}/bin/${CTARGET}-objdump"
    fi

    # For native build, all tools are the same
    export CC_FOR_TARGET="${CC}"
    export CXX_FOR_TARGET="${CXX}"
    export AR_FOR_TARGET="${AR}"
    export AS_FOR_TARGET="${AS}"
    export LD_FOR_TARGET="${LD}"
    export NM_FOR_TARGET="${NM}"
    export RANLIB_FOR_TARGET="${RANLIB}"
    export STRIP_FOR_TARGET="${STRIP}"
    export OBJCOPY_FOR_TARGET="${OBJCOPY}"
    export OBJDUMP_FOR_TARGET="${OBJDUMP}"

    # Add stage 2 toolchain to PATH
    export PATH="${STAGE2_PREFIX}/bin:${PATH}"

    msg "Native OHOS environment configured:"
    echo "  CC=${CC}"
    echo "  CBUILD=${CBUILD}"
    echo "  CHOST=${CHOST}"
    echo "  CTARGET=${CTARGET}"
}

# ============================================================================
# Build Steps
# ============================================================================

prepare_ndk() {
    msg "Preparing NDK sysroot..."

    local ndk_tarball="${SCRIPT_DIR}/ndk-llvm.tar.gz"
    local ndk_extract_tmp="${NDK_DIR}/tmp-extract"

    # Check if sysroot already exists for current target
    if [ -d "${NDK_SYSROOT_DIR}/${CTARGET}" ]; then
        msg "NDK sysroot for ${CTARGET} already exists at ${NDK_SYSROOT_DIR}/${CTARGET}"
        return 0
    fi

    mkdir -p "${NDK_DIR}"

    # Download NDK if not present
    if [ ! -f "${ndk_tarball}" ]; then
        msg "Downloading NDK from ${NDK_URL}..."
        wget -O "${ndk_tarball}" "${NDK_URL}" || \
            error "Failed to download NDK"
    fi

    # Extract ohos-sysroot.tar.gz from NDK package
    msg "Extracting ohos-sysroot.tar.gz from NDK package..."
    local sysroot_tarball="${NDK_DIR}/ohos-sysroot.tar.gz"
    tar -xzf "${ndk_tarball}" -C "${NDK_DIR}" 'ohos-sysroot.tar.gz' || \
        error "Failed to extract ohos-sysroot.tar.gz from NDK package"

    if [ ! -f "${sysroot_tarball}" ]; then
        error "ohos-sysroot.tar.gz not found after extraction"
    fi

    # Extract sysroot to temp directory first (it contains sysroot/ subdirectory)
    msg "Extracting sysroot..."
    mkdir -p "${ndk_extract_tmp}"
    tar -xzf "${sysroot_tarball}" -C "${ndk_extract_tmp}" || \
        error "Failed to extract sysroot"

    # Move contents from sysroot/ subdirectory to NDK_SYSROOT_DIR
    # ohos-sysroot.tar.gz structure: sysroot/{aarch64-linux-ohos,arm-linux-ohos,...}
    msg "Moving sysroot to ${NDK_SYSROOT_DIR}..."
    mkdir -p "${NDK_SYSROOT_DIR}"
    if [ -d "${ndk_extract_tmp}/sysroot" ]; then
        mv "${ndk_extract_tmp}/sysroot"/* "${NDK_SYSROOT_DIR}/" || \
            error "Failed to move sysroot contents"
    else
        error "sysroot directory not found in ohos-sysroot.tar.gz"
    fi

    # Clean up
    rm -rf "${ndk_extract_tmp}"
    rm -f "${sysroot_tarball}"

    msg "NDK sysroot prepared at ${NDK_SYSROOT_DIR}"
}

prepare_binutils() {
    msg "Preparing binutils ${BINUTILS_VERSION} source directory..."

    if [ ! -d "${BINUTILS_SOURCE_DIR}" ]; then
        msg "Downloading binutils ${BINUTILS_VERSION}..."
        local tarball="binutils-${BINUTILS_VERSION}.tar.xz"
        if [ ! -f "${tarball}" ]; then
            wget "https://ftp.gnu.org/gnu/binutils/${tarball}" || \
                error "Failed to download binutils source"
        fi

        msg "Extracting binutils source..."
        tar -xf "${tarball}" || error "Failed to extract binutils source"
    fi

    msg "Applying binutils patches..."
    cd "${BINUTILS_SOURCE_DIR}"

    for patch in "${SCRIPT_DIR}"/binutils-patches/*.patch; do
        [ -f "${patch}" ] || continue
        msg "Applying $(basename "${patch}")..."
        patch -p1 -N -i "${patch}" || msg "Patch $(basename "${patch}") already applied or failed"
    done

    cd "${SCRIPT_DIR}"
}

build_binutils() {
    prepare_binutils

    # Setup build environment based on build type
    if is_native_ohos_build && [ -n "${STAGE2_PREFIX}" ]; then
        check_stage2_toolchain
        setup_native_ohos_env
    elif is_canadian_cross; then
        check_stage1_toolchain
        setup_canadian_cross_env
    fi

    msg "Configuring binutils for ${CTARGET}..."
    msg "  CBUILD=${CBUILD}, CHOST=${CHOST}, CTARGET=${CTARGET}"
    mkdir -p "${BINUTILS_BUILD_DIR}"
    cd "${BINUTILS_BUILD_DIR}"

    local configure_args=(
        "${BINUTILS_SOURCE_DIR}/configure"
        "--prefix=${BINUTILS_INSTALL_PREFIX}"
        "--build=${CBUILD}"
        "--host=${CHOST}"
        "--target=${CTARGET}"
        "--disable-nls"
        "--disable-werror"
        "--disable-multilib"
        "--disable-gprofng"
        "--enable-default-hash-style=gnu"
        "--with-pkgversion=OHOS Binutils ${BINUTILS_VERSION}"
    )

    if [ -n "${SYSROOT}" ]; then
        configure_args+=("--with-sysroot=${SYSROOT}")
    fi

    # For Canadian Cross builds, disable plugins to avoid LTO issues
    # where build-time tools might try to load incompatible plugins
    if is_canadian_cross; then
        configure_args+=("--disable-plugins")
    fi

    "${configure_args[@]}" || error "Binutils configuration failed"

    # Pass CC_FOR_BUILD explicitly to make for Canadian Cross
    # Use the exported CC_FOR_BUILD which is set in setup_canadian_cross_env()
    if is_canadian_cross; then
        make -j"${JOBS}" MAKEINFO=true CC_FOR_BUILD="${CC_FOR_BUILD}" CXX_FOR_BUILD="${CXX_FOR_BUILD}" \
            || error "Binutils build failed"
    else
        make -j"${JOBS}" MAKEINFO=true || error "Binutils build failed"
    fi
    make install DESTDIR="${DESTDIR:-}" MAKEINFO=true || error "Binutils install failed"

    cd "${SCRIPT_DIR}"
}

ensure_binutils() {
    local expected_ld="${BINUTILS_INSTALL_PREFIX}/bin/${CTARGET}-ld"
    if [ ! -x "${expected_ld}" ]; then
        msg "Binutils not found at ${expected_ld}; building binutils..."
        build_binutils
    else
        msg "Using existing binutils from ${BINUTILS_INSTALL_PREFIX}"
    fi
}

apply_sysroot_patches() {
    if [ -d "${SCRIPT_DIR}/sysroot-patches" ]; then
        msg "Applying sysroot patches..."
        for patch in "${SCRIPT_DIR}"/sysroot-patches/*.patch; do
            [ -f "${patch}" ] || continue
            msg "Applying $(basename "${patch}")..."
            patch -d "${SYSROOT}" -p0 -N -i "${patch}" || msg "Patch $(basename "${patch}") already applied or failed"
        done
    fi
}

# Download GCC prerequisites (GMP, MPFR, MPC, ISL, gettext)
download_prerequisites() {
    msg "Checking GCC prerequisites..."

    cd "${SOURCE_DIR}"

    # Check if prerequisites already downloaded
    local need_download=0
    for dep in gmp mpfr mpc isl gettext; do
        if [ ! -e "${dep}" ]; then
            need_download=1
            break
        fi
    done

    if [ "${need_download}" -eq 0 ]; then
        msg "Prerequisites already downloaded"
        # Still need to apply patches in case they weren't applied
        apply_prerequisite_patches
        cd "${SCRIPT_DIR}"
        return 0
    fi

    msg "Downloading GCC prerequisites..."

    # Use GCC's contrib script to download prerequisites
    if [ -x "./contrib/download_prerequisites" ]; then
        ./contrib/download_prerequisites || error "Failed to download prerequisites"
    else
        error "download_prerequisites script not found in GCC source"
    fi

    # Apply patches for OHOS support to all prerequisites
    apply_prerequisite_patches

    cd "${SCRIPT_DIR}"
}

# Apply patches to all GCC prerequisites for OHOS support
apply_prerequisite_patches() {
    apply_gmp_patches
    apply_mpfr_patches
    apply_mpc_patches
    apply_isl_patches
    apply_gettext_patches
}

# Apply patches to GMP for OHOS support
apply_gmp_patches() {
    local gmp_dir="${SOURCE_DIR}/gmp"

    if [ ! -d "${gmp_dir}" ]; then
        msg "GMP directory not found, skipping patches"
        return 0
    fi

    local real_gmp_dir
    real_gmp_dir=$(readlink -f "${gmp_dir}")

    if [ ! -d "${SCRIPT_DIR}/gmp-patches" ]; then
        return 0
    fi

    msg "Applying GMP patches for OHOS support..."

    for patch in "${SCRIPT_DIR}"/gmp-patches/*.patch; do
        [ -f "${patch}" ] || continue
        msg "Applying $(basename "${patch}") to GMP..."
        cd "${real_gmp_dir}"
        patch -p0 -N -i "${patch}" 2>/dev/null || msg "Patch $(basename "${patch}") already applied or failed"
        cd "${SCRIPT_DIR}"
    done
}

# Apply patches to MPFR for OHOS support
apply_mpfr_patches() {
    local mpfr_dir="${SOURCE_DIR}/mpfr"

    if [ ! -d "${mpfr_dir}" ]; then
        msg "MPFR directory not found, skipping patches"
        return 0
    fi

    local real_mpfr_dir
    real_mpfr_dir=$(readlink -f "${mpfr_dir}")

    if [ ! -d "${SCRIPT_DIR}/mpfr-patches" ]; then
        return 0
    fi

    msg "Applying MPFR patches for OHOS support..."

    for patch in "${SCRIPT_DIR}"/mpfr-patches/*.patch; do
        [ -f "${patch}" ] || continue
        msg "Applying $(basename "${patch}") to MPFR..."
        cd "${real_mpfr_dir}"
        patch -p0 -N -i "${patch}" 2>/dev/null || msg "Patch $(basename "${patch}") already applied or failed"
        cd "${SCRIPT_DIR}"
    done
}

# Apply patches to MPC for OHOS support
apply_mpc_patches() {
    local mpc_dir="${SOURCE_DIR}/mpc"

    if [ ! -d "${mpc_dir}" ]; then
        msg "MPC directory not found, skipping patches"
        return 0
    fi

    local real_mpc_dir
    real_mpc_dir=$(readlink -f "${mpc_dir}")

    if [ ! -d "${SCRIPT_DIR}/mpc-patches" ]; then
        return 0
    fi

    msg "Applying MPC patches for OHOS support..."

    for patch in "${SCRIPT_DIR}"/mpc-patches/*.patch; do
        [ -f "${patch}" ] || continue
        msg "Applying $(basename "${patch}") to MPC..."
        cd "${real_mpc_dir}"
        patch -p0 -N -i "${patch}" 2>/dev/null || msg "Patch $(basename "${patch}") already applied or failed"
        cd "${SCRIPT_DIR}"
    done
}

# Apply patches to ISL for OHOS support
apply_isl_patches() {
    local isl_dir="${SOURCE_DIR}/isl"

    if [ ! -d "${isl_dir}" ]; then
        msg "ISL directory not found, skipping patches"
        return 0
    fi

    local real_isl_dir
    real_isl_dir=$(readlink -f "${isl_dir}")

    if [ ! -d "${SCRIPT_DIR}/isl-patches" ]; then
        return 0
    fi

    msg "Applying ISL patches for OHOS support..."

    for patch in "${SCRIPT_DIR}"/isl-patches/*.patch; do
        [ -f "${patch}" ] || continue
        msg "Applying $(basename "${patch}") to ISL..."
        cd "${real_isl_dir}"
        patch -p0 -N -i "${patch}" 2>/dev/null || msg "Patch $(basename "${patch}") already applied or failed"
        cd "${SCRIPT_DIR}"
    done
}

# Apply patches to gettext for OHOS support
apply_gettext_patches() {
    local gettext_dir="${SOURCE_DIR}/gettext"

    if [ ! -d "${gettext_dir}" ]; then
        msg "gettext directory not found, skipping patches"
        return 0
    fi

    local real_gettext_dir
    real_gettext_dir=$(readlink -f "${gettext_dir}")

    if [ ! -d "${SCRIPT_DIR}/gettext-patches" ]; then
        return 0
    fi

    msg "Applying gettext patches for OHOS support..."

    for patch in "${SCRIPT_DIR}"/gettext-patches/*.patch; do
        [ -f "${patch}" ] || continue
        msg "Applying $(basename "${patch}") to gettext..."
        cd "${real_gettext_dir}"
        patch -p0 -N -i "${patch}" 2>/dev/null || msg "Patch $(basename "${patch}") already applied or failed"
        cd "${SCRIPT_DIR}"
    done
}

prepare_gcc() {
    msg "Preparing GCC source directory..."

    # Download GCC source if not present
    if [ ! -d "${SOURCE_DIR}" ]; then
        msg "Downloading GCC ${GCC_VERSION}..."
        local tarball="gcc-${GCC_VERSION}.tar.xz"
        if [ ! -f "${tarball}" ]; then
            wget "https://gcc.gnu.org/pub/gcc/releases/gcc-${GCC_VERSION}/${tarball}" || \
                error "Failed to download GCC source"
        fi

        msg "Extracting GCC source..."
        tar -xf "${tarball}" || error "Failed to extract GCC source"
    fi

    # Download prerequisites (GMP, MPFR, MPC, ISL, gettext)
    download_prerequisites

    # Apply patches
    msg "Applying GCC patches..."
    cd "${SOURCE_DIR}"

    # Apply OHOS patch first
    if [ -f "${SCRIPT_DIR}/gcc-patches/0001-Add-OpenHarmony-OHOS-target-support-to-GCC.patch" ]; then
        patch -p1 -N -i "${SCRIPT_DIR}/gcc-patches/0001-Add-OpenHarmony-OHOS-target-support-to-GCC.patch" || \
            msg "OHOS patch already applied or failed"
    fi

    # Apply other patches
    for patch in "${SCRIPT_DIR}"/gcc-patches/*.patch; do
        [ -f "${patch}" ] || continue
        [[ "${patch}" =~ "0001-Add-OpenHarmony-OHOS" ]] && continue

        msg "Applying $(basename "${patch}")..."
        patch -p1 -N -i "${patch}" || msg "Patch $(basename "${patch}") already applied or failed"
    done

    echo "${GCC_VERSION}" > gcc/BASE-VER

    cd "${SCRIPT_DIR}"
}

configure_gcc() {
    ensure_binutils
    apply_sysroot_patches
    prepare_gcc

    # Setup build environment based on build type
    if is_native_ohos_build && [ -n "${STAGE2_PREFIX}" ]; then
        check_stage2_toolchain
        setup_native_ohos_env
    elif is_canadian_cross; then
        check_stage1_toolchain
        setup_canadian_cross_env
    fi

    msg "Configuring GCC ${GCC_VERSION} for ${CTARGET}..."

    if [ -d "${BINUTILS_INSTALL_PREFIX}/bin" ]; then
        export PATH="${BINUTILS_INSTALL_PREFIX}/bin:${PATH}"
    fi

    local extra_binutils_flags=""
    local as_path="${BINUTILS_INSTALL_PREFIX}/bin/${CTARGET}-as"
    local ld_path="${BINUTILS_INSTALL_PREFIX}/bin/${CTARGET}-ld"
    [ -x "${as_path}" ] && extra_binutils_flags+=" --with-as=${as_path}"
    [ -x "${ld_path}" ] && extra_binutils_flags+=" --with-ld=${ld_path}"

    # Create build directory
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    # Set build environment
    export libat_cv_have_ifunc=no
    
    # For cross-compilation to OHOS, we need to provide libtool cache variables
    # to bypass dynamic linker detection tests that require running executables.
    # OHOS uses musl-style dynamic linker paths.
    if [ "${CHOST}" != "${CTARGET}" ]; then
        case "${CTARGET}" in
            *-linux-ohos*)
                # Libtool cache variables for OHOS target
                # These tell configure to skip link tests that require running executables
                export lt_cv_deplibs_check_method='pass_all'
                export lt_cv_file_magic_cmd='$MAGIC_CMD'
                export lt_cv_file_magic_test_file=''
                export lt_cv_ld_reload_flag='-r'
                export lt_cv_nm_interface='BSD nm'
                export lt_cv_objdir='.libs'
                export lt_cv_path_LD="${BINUTILS_INSTALL_PREFIX}/bin/${CTARGET}-ld"
                export lt_cv_path_NM="${BINUTILS_INSTALL_PREFIX}/bin/${CTARGET}-nm"
                export lt_cv_prog_compiler_c_o='yes'
                export lt_cv_prog_compiler_pic='-fPIC -DPIC'
                export lt_cv_prog_compiler_pic_works='yes'
                export lt_cv_prog_compiler_static_works='yes'
                export lt_cv_prog_compiler_wl='-Wl,'
                export lt_cv_prog_gnu_ld='yes'
                export lt_cv_sys_global_symbol_pipe="sed -n -e 's/^.*[	 ]\\([ABCDGIRSTW][ABCDGIRSTW]*\\)[	 ][	 ]*\\([_A-Za-z][_A-Za-z0-9]*\\)\$/\\1 \\2 \\2/p' | sed '/ __gnu_lto/d'"
                export lt_cv_sys_global_symbol_to_c_name_address="sed -n -e 's/^: \\([^ ]*\\) \$/  {\\\"\\1\\\", (void *) 0},/p' -e 's/^[ABCDGIRSTW]* \\([^ ]*\\) \\([^ ]*\\)\$/  {\\\"\\2\\\", (void *) \\&\\2},/p'"
                export lt_cv_sys_global_symbol_to_cdecl="sed -n -e 's/^T .* \\(.*\\)\$/extern int \\1();/p' -e 's/^[ABCDGIRSTW]* .* \\(.*\\)\$/extern char \\1;/p'"
                export lt_cv_sys_max_cmd_len='1572864'
                
                # Dynamic linker path for OHOS (musl-style)
                case "${CTARGET_ARCH}" in
                    x86_64)  export lt_cv_sys_lib_dlsearch_path_spec='/lib /usr/lib' ;;
                    aarch64) export lt_cv_sys_lib_dlsearch_path_spec='/lib /usr/lib' ;;
                    *)       export lt_cv_sys_lib_dlsearch_path_spec='/lib /usr/lib' ;;
                esac
                export lt_cv_sys_lib_search_path_spec='/lib /usr/lib'
                
                # Additional cache variables to help libstdc++ configure
                export glibcxx_cv_BSWAP='yes'
                export ac_cv_func_sched_yield='yes'
                export ac_cv_func_uselocale='yes'
                ;;
        esac
    fi
    
    # For Canadian Cross builds, we need to tell configure that the HOST compiler
    # (stage 1 cross-compiler) supports C++14. Since the cross-compiler produces
    # binaries that can't run on the BUILD machine, configure cannot test this
    # by running a program. We provide cache variables to skip these runtime tests.
    if is_canadian_cross; then
        # Tell configure the HOST (cross) compiler supports C++14
        # These variables bypass runtime tests that would fail for cross-compilation
        export ax_cv_cxx_compile_cxx14='yes'
        export ac_cv_prog_cxx_g='yes'
        export ac_cv_prog_cc_g='yes'
        # GCC's configure checks for C++14 support via compilation test only
        # but some sub-configures may try to run test programs
        export gcc_cv_prog_cxx_stdcxx='cxx14'
        
        # Also set the cache variables for the BUILD compiler (g++)
        # GCC configure also checks if the build system's compiler supports C++14
        # These are separate from the HOST compiler checks above
        export ax_cv_cxx_compile_cxx14_FOR_BUILD='yes'
        export ac_cv_prog_cxx_g_FOR_BUILD='yes'
        
        msg "Canadian Cross: Set C++14 cache variables to bypass runtime tests"
    fi
    
    # Configure flags for different build scenarios
    if is_canadian_cross; then
        # Canadian Cross (stage 2): CBUILD != CHOST = CTARGET
        # Host compiler is the stage 1 cross-compiler, target is native OHOS
        export CFLAGS="${CFLAGS:-} -g0 -O2"
        export CXXFLAGS="${CXXFLAGS:-} -g0 -O2"
        export CFLAGS_FOR_TARGET="${CFLAGS}"
        export CXXFLAGS_FOR_TARGET="${CXXFLAGS}"
        export LDFLAGS_FOR_TARGET="${LDFLAGS:-}"
    elif [ "${CHOST}" != "${CTARGET}" ]; then
        # Stage 1 Cross-compilation: CHOST != CTARGET
        export CFLAGS="${CFLAGS:-} -g0 -O2"
        export CXXFLAGS="${CXXFLAGS:-} -g0 -O2"
        export CFLAGS_FOR_TARGET=" "
        export CXXFLAGS_FOR_TARGET=" "
        export LDFLAGS_FOR_TARGET=" "
    else
        # Native build: CBUILD = CHOST = CTARGET
        export CFLAGS="${CFLAGS:-} -g0 -O2"
        export CXXFLAGS="${CXXFLAGS:-} -g0 -O2"
        export CFLAGS_FOR_TARGET="${CFLAGS}"
        export CXXFLAGS_FOR_TARGET="${CXXFLAGS}"
        export LDFLAGS_FOR_TARGET="${LDFLAGS:-}"
        export BOOT_CFLAGS="${CFLAGS}"
        export BOOT_LDFLAGS="${LDFLAGS:-}"
    fi
    
    # Determine build type string for display
    local build_type="native"
    if is_native_ohos_build && [ -n "${STAGE2_PREFIX}" ]; then
        build_type="native OHOS bootstrap (stage 3)"
    elif is_canadian_cross; then
        build_type="Canadian Cross (stage 2)"
    elif [ "${CHOST}" != "${CTARGET}" ]; then
        build_type="cross-compiler (stage 1)"
    fi

    msg "Build configuration:"
    echo "  Build type: ${build_type}"
    echo "  CBUILD=${CBUILD}"
    echo "  CHOST=${CHOST}"
    echo "  CTARGET=${CTARGET}"
    echo "  CTARGET_ARCH=${CTARGET_ARCH}"
    echo "  LANGUAGES=${LANGUAGES}"
    echo "  INSTALL_PREFIX=${INSTALL_PREFIX}"
    echo "  SYSROOT=${SYSROOT}"
    if is_canadian_cross; then
        echo "  STAGE1_PREFIX=${STAGE1_PREFIX}"
    fi
    if is_native_ohos_build && [ -n "${STAGE2_PREFIX}" ]; then
        echo "  STAGE2_PREFIX=${STAGE2_PREFIX}"
    fi
    echo "  CROSS_COMPILE=${CROSS_COMPILE}"
    echo ""

    if [ -n "${CROSS_COMPILE}" ]; then
        export AR_FOR_TARGET="${AR_FOR_TARGET:-${CROSS_COMPILE}ar}"
        export AS_FOR_TARGET="${AS_FOR_TARGET:-${CROSS_COMPILE}as}"
        export LD_FOR_TARGET="${LD_FOR_TARGET:-${CROSS_COMPILE}ld}"
        export NM_FOR_TARGET="${NM_FOR_TARGET:-${CROSS_COMPILE}nm}"
        export OBJDUMP_FOR_TARGET="${OBJDUMP_FOR_TARGET:-${CROSS_COMPILE}objdump}"
        export OBJCOPY_FOR_TARGET="${OBJCOPY_FOR_TARGET:-${CROSS_COMPILE}objcopy}"
        export RANLIB_FOR_TARGET="${RANLIB_FOR_TARGET:-${CROSS_COMPILE}ranlib}"
        export STRIP_FOR_TARGET="${STRIP_FOR_TARGET:-${CROSS_COMPILE}strip}"
    fi
    
    # Configure GCC
    local cross_configure=()
    local zlib_configure="--with-system-zlib"
    
    if [ "${CBUILD}" != "${CHOST}" ] || [ "${CHOST}" != "${CTARGET}" ]; then
        cross_configure+=("--disable-bootstrap")
        # Note: We keep PIE enabled for cross-compilation because OHOS uses PIE.
        # The t-ohos-crtstuff makefile fragment ensures crtbegin.o is compiled
        # with PIC to be compatible with PIE executables.
    fi
    if [ "${CHOST}" != "${CTARGET}" ] && [ -n "${SYSROOT}" ]; then
        cross_configure+=("--with-sysroot=${SYSROOT}")
    fi
    
    # For Canadian Cross builds, use bundled zlib since OHOS sysroot may not have it
    # Also enable host PIE since OHOS defaults to PIE
    # Use --with-build-time-tools to specify stage 1 tools for running on build machine
    local host_pie_configure=""
    local build_time_tools=""
    if is_canadian_cross; then
        zlib_configure=""
        host_pie_configure="--enable-host-pie"
        # Point to stage 1 tools - these can run on the build machine and produce
        # output for the target. This is essential for Canadian Cross builds where
        # the newly built compiler cannot run on the build machine.
        # Note: --with-build-time-tools still needs absolute path as a configure option
        build_time_tools="--with-build-time-tools=${STAGE1_PREFIX}/bin"
        msg "Canadian Cross: Using bundled zlib, enabling host PIE, and using stage 1 build-time tools"
    fi

    # Run configure - for Canadian Cross, pass CC_FOR_BUILD/CXX_FOR_BUILD explicitly
    # using env command to set them as environment variables for configure only.
    # This avoids exporting them globally (which can cause GMP configure race
    # conditions) while still ensuring the correct build compiler is used.
    local env_prefix=""
    if is_canadian_cross; then
        env_prefix="env CC_FOR_BUILD=${CC_FOR_BUILD} CXX_FOR_BUILD=${CXX_FOR_BUILD}"
    fi
    
    ${env_prefix} "${SOURCE_DIR}/configure" \
        --prefix="${INSTALL_PREFIX}" \
        --mandir="${INSTALL_PREFIX}/share/man" \
        --infodir="${INSTALL_PREFIX}/share/info" \
        --build="${CBUILD}" \
        --host="${CHOST}" \
        --target="${CTARGET}" \
        --with-pkgversion="OHOS GCC ${GCC_VERSION}" \
        --with-bugurl="https://github.com/sanchuanhehe/ohos-gcc" \
        ${zlib_configure} \
        ${host_pie_configure} \
        ${build_time_tools} \
        --enable-checking=release \
        --enable-languages="${LANGUAGES}" \
        --enable-__cxa_atexit \
        --enable-default-pie \
        --enable-default-ssp \
        --enable-linker-build-id \
        --enable-link-serialization=2 \
        --disable-cet \
        --disable-fixed-point \
        --disable-libstdcxx-pch \
        --disable-multilib \
        --disable-nls \
        --disable-werror \
        --disable-symvers \
        --disable-libssp \
        ${ARCH_CONFIGURE} \
        ${SANITIZER_CONFIGURE} \
        "${cross_configure[@]}" \
        ${BOOTSTRAP_CONFIGURE} \
        ${HASH_STYLE_CONFIGURE} \
        ${extra_binutils_flags} \
        ${EXTRA_CONFIGURE_FLAGS:-} \
        || error "Configuration failed"
}

build_gcc() {
    msg "Building GCC..."
    cd "${BUILD_DIR}"
    
    # For Canadian Cross builds, we need to explicitly pass GCC_FOR_TARGET
    # pointing to the stage 1 cross-compiler, because the newly built xgcc
    # is an OHOS binary that cannot run on the Linux build machine.
    # We also need to ensure stage 1 tools are in PATH for sub-configures.
    if is_canadian_cross; then
        PATH="${STAGE1_PREFIX}/bin:${PATH}" make -j"${JOBS}" \
            GCC_FOR_TARGET="${CTARGET}-gcc" \
            || error "Build failed"
    else
        make -j"${JOBS}" || error "Build failed"
    fi
}

install_gcc() {
    msg "Installing GCC to ${INSTALL_PREFIX}..."
    cd "${BUILD_DIR}"
    
    # For Canadian Cross builds, pass GCC_FOR_TARGET to avoid trying to run
    # the newly built OHOS binaries on the Linux build machine.
    # Also ensure stage 1 tools are in PATH.
    if is_canadian_cross; then
        PATH="${STAGE1_PREFIX}/bin:${PATH}" make install DESTDIR="${DESTDIR:-}" \
            GCC_FOR_TARGET="${CTARGET}-gcc" \
            || error "Installation failed"
    else
        make install DESTDIR="${DESTDIR:-}" || error "Installation failed"
    fi
    
    local real_prefix="${DESTDIR:-}${INSTALL_PREFIX}"
    mkdir -p "${real_prefix}/bin"

    # Create convenient compiler symlinks inside install prefix
    if [ "${CHOST}" = "${CTARGET}" ]; then
        ln -sf gcc "${real_prefix}/bin/cc"
    fi
    ln -sf "${CTARGET}-gcc" "${real_prefix}/bin/${CTARGET}-cc"
    
    msg "GCC installation complete"
}

clean() {
    msg "Cleaning build directories..."
    rm -rf "${BUILD_DIR}" "${BINUTILS_BUILD_DIR}"
}

# ============================================================================
# Main Script
# ============================================================================

show_help() {
    cat <<EOF
GCC Build Script for OpenHarmony (OHOS) Target

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    prepare_ndk         Download and setup NDK sysroot only
    prepare             Download NDK/sources and apply patches for binutils and GCC
    download_prereqs    Download GCC prerequisites (GMP, MPFR, MPC, ISL, gettext)
    binutils            Build and install binutils only
    configure           Ensure binutils exist and configure GCC
    build               Build GCC
    install             Install GCC
    all                 Run full pipeline (NDK + binutils + GCC)
    clean               Clean build directories

Options:
  --target=TARGET           Set target triplet (default: aarch64-linux-ohos)
  --host=HOST               Set host triplet (default: auto-detected)
  --build=BUILD             Set build triplet (default: auto-detected)
  --prefix=PREFIX           Set installation prefix (default: ./install)
  --sysroot=SYSROOT         Set sysroot path for cross-compilation
                            (default: ndk/sysroot/CTARGET)
  --stage1=PATH             Stage 1 cross-compiler prefix (for stage 2 builds)
  --stage2=PATH             Stage 2 native compiler prefix (for stage 3 builds)
  --jobs=N                  Number of parallel jobs (default: $(nproc))
  --enable-languages=LIST   Comma-separated language list (default: c,c++)
  --help                    Show this help message

Environment Variables:
  CTARGET                   Target triplet
  CHOST                     Host triplet
  CBUILD                    Build triplet
  INSTALL_PREFIX            Installation prefix
  STAGE1_PREFIX             Stage 1 cross-compiler prefix (for stage 2)
  STAGE2_PREFIX             Stage 2 native compiler prefix (for stage 3)
  BINUTILS_VERSION          Binutils version (default: ${BINUTILS_VERSION})
  BINUTILS_INSTALL_PREFIX   Binutils installation prefix (default: same as INSTALL_PREFIX)
  SYSROOT                   Sysroot path (default: ndk/sysroot/CTARGET)
  NDK_URL                   NDK download URL
  JOBS                      Number of parallel jobs
  CROSS_COMPILE             Cross prefix override (default: target- when cross compiling)
  LANG_*                    Enable/disable specific languages (yes/no)

Build Types:
  Stage 1 (Cross-compiler):
    Builds on host (e.g., x86_64-linux-gnu) to produce a cross-compiler
    that runs on host and targets OHOS.
    CBUILD=CHOST=x86_64-linux-gnu, CTARGET=x86_64-linux-ohos

  Stage 2 (Canadian Cross / Native compiler):
    Uses stage 1 cross-compiler to build a native OHOS compiler.
    The resulting compiler runs on OHOS and produces OHOS binaries.
    CBUILD=x86_64-linux-gnu, CHOST=CTARGET=x86_64-linux-ohos
    Requires --stage1 pointing to stage 1 installation.

  Stage 3 (Native bootstrap):
    Runs on OHOS using stage 2 compiler to rebuild itself.
    Full native build: CBUILD=CHOST=CTARGET=x86_64-linux-ohos
    Requires --stage2 pointing to stage 2 installation.

Examples:
  # Stage 1: Build cross-compiler for x86_64 OHOS
  $0 --target=x86_64-linux-ohos --prefix=/opt/ohos-gcc-stage1

  # Stage 2: Build native OHOS compiler (Canadian Cross)
  $0 --build=x86_64-linux-gnu --host=x86_64-linux-ohos --target=x86_64-linux-ohos --stage1=/opt/ohos-gcc-stage1 --prefix=/opt/ohos-gcc-stage2

  # Stage 3: Native bootstrap on OHOS (run inside OHOS)
  $0 --build=x86_64-linux-ohos --host=x86_64-linux-ohos --target=x86_64-linux-ohos --stage2=/opt/ohos-gcc-stage2 --prefix=/opt/ohos-gcc

  # Build for AArch64 OHOS
  $0 --target=aarch64-linux-ohos --prefix=/opt/ohos-gcc

EOF
}

# Parse command line arguments
COMMAND="all"
while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;
        --target=*)
            CTARGET="${1#*=}"
            ;;
        --host=*)
            CHOST="${1#*=}"
            ;;
        --build=*)
            CBUILD="${1#*=}"
            ;;
        --prefix=*)
            INSTALL_PREFIX="${1#*=}"
            ;;
        --sysroot=*)
            SYSROOT="${1#*=}"
            ;;
        --stage1=*)
            STAGE1_PREFIX="${1#*=}"
            ;;
        --stage2=*)
            STAGE2_PREFIX="${1#*=}"
            ;;
        --jobs=*)
            JOBS="${1#*=}"
            ;;
        --enable-languages=*)
            LANGUAGES="${1#*=}"
            ;;
        prepare_ndk|prepare|binutils|configure|build|install|all|clean|prepare_binutils|download_prereqs)
            COMMAND="$1"
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
    shift
done

# Normalize all path arguments to absolute form
# This allows users to specify relative paths like ./install

# Normalize install prefix to absolute form
if [ -n "${INSTALL_PREFIX}" ]; then
    # For paths that don't exist yet, we need to handle differently
    # Use realpath with -m to allow non-existent paths
    if command -v realpath >/dev/null 2>&1; then
        INSTALL_PREFIX=$(realpath -m "${INSTALL_PREFIX}")
    else
        # Fallback: convert relative to absolute manually
        case "${INSTALL_PREFIX}" in
            /*) ;; # Already absolute
            *)  INSTALL_PREFIX="${PWD}/${INSTALL_PREFIX}" ;;
        esac
    fi
fi

# Also normalize BINUTILS_INSTALL_PREFIX if it was set explicitly
# Otherwise it inherits from INSTALL_PREFIX (set default if not already set)
BINUTILS_INSTALL_PREFIX="${BINUTILS_INSTALL_PREFIX:-${INSTALL_PREFIX}}"
if [ "${BINUTILS_INSTALL_PREFIX}" != "${INSTALL_PREFIX}" ] && [ -n "${BINUTILS_INSTALL_PREFIX}" ]; then
    if command -v realpath >/dev/null 2>&1; then
        BINUTILS_INSTALL_PREFIX=$(realpath -m "${BINUTILS_INSTALL_PREFIX}")
    else
        case "${BINUTILS_INSTALL_PREFIX}" in
            /*) ;;
            *)  BINUTILS_INSTALL_PREFIX="${PWD}/${BINUTILS_INSTALL_PREFIX}" ;;
        esac
    fi
else
    BINUTILS_INSTALL_PREFIX="${INSTALL_PREFIX}"
fi

# Normalize stage1 prefix to absolute form if provided
if [ -n "${STAGE1_PREFIX}" ]; then
    if ! resolved_stage1=$(readlink -f "${STAGE1_PREFIX}"); then
        error "Failed to resolve stage1 path: ${STAGE1_PREFIX}"
    fi
    STAGE1_PREFIX="${resolved_stage1}"
fi

# Normalize stage2 prefix to absolute form if provided
if [ -n "${STAGE2_PREFIX}" ]; then
    if ! resolved_stage2=$(readlink -f "${STAGE2_PREFIX}"); then
        error "Failed to resolve stage2 path: ${STAGE2_PREFIX}"
    fi
    STAGE2_PREFIX="${resolved_stage2}"
fi

# Normalize sysroot path to absolute form if provided
if [ -n "${SYSROOT}" ]; then
    if ! resolved_sysroot=$(readlink -f "${SYSROOT}"); then
        error "Failed to resolve sysroot path: ${SYSROOT}"
    fi
    SYSROOT="${resolved_sysroot}"
fi

# Resolve defaults that depend on parsed values
CHOST="${CHOST:-${CBUILD}}"

# Setup target-specific configuration AFTER parsing command line arguments
# This ensures --target is properly respected
setup_target_config

# Determine cross-compilation context after parsing options
if [ -z "${CROSS_COMPILE:-}" ]; then
    if [ "${CHOST}" != "${CTARGET}" ]; then
        CROSS_COMPILE="${CTARGET}-"
    else
        CROSS_COMPILE=""
    fi
fi
export CROSS_COMPILE

IS_NATIVE_BUILD=0
if [ "${CHOST}" = "${CTARGET}" ]; then
    IS_NATIVE_BUILD=1
fi

# Set default SYSROOT to NDK sysroot if not specified
if [ -z "${SYSROOT}" ]; then
    SYSROOT="${NDK_SYSROOT_DIR}/${CTARGET}"
    msg "Using default sysroot: ${SYSROOT}"
fi

# Execute command
case "${COMMAND}" in
    prepare_ndk)
        prepare_ndk
        apply_sysroot_patches
        ;;
    prepare)
        prepare_ndk
        prepare_binutils
        apply_sysroot_patches
        prepare_gcc
        ;;
    prepare_binutils)
        prepare_binutils
        ;;
    download_prereqs)
        # Ensure GCC source exists before downloading prerequisites
        if [ ! -d "${SOURCE_DIR}" ]; then
            error "GCC source directory not found: ${SOURCE_DIR}
Please run 'prepare' or download GCC source first."
        fi
        download_prerequisites
        ;;
    binutils)
        build_binutils
        ;;
    configure)
        configure_gcc
        ;;
    build)
        build_gcc
        ;;
    install)
        install_gcc
        ;;
    clean)
        clean
        ;;
    all)
        prepare_ndk
        prepare_binutils
        apply_sysroot_patches
        prepare_gcc
        build_binutils
        configure_gcc
        build_gcc
        install_gcc
        ;;
    *)
        error "Unknown command: ${COMMAND}"
        ;;
esac

msg "Done!"