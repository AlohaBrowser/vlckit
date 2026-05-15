#!/usr/bin/env bash
#
# Build the VLCKit iOS XCFramework, upload it to doloto (Aloha Maven),
# regenerate Package.swift with the new binaryTarget, then commit, tag and push.
#
# Mirrors the workflow used in ~/projects/outline-apps/scripts/publish_release.zsh
# (tun2socks release pipeline).
#
# Output layout:
#   - XCFramework slices:  ios-arm64 (device)  +  ios-arm64-simulator (Apple Silicon sim)
#   - Each slice is THIN — single arch, no lipo'd fat binaries.
#   - Linkage:             STATIC (MACH_O_TYPE=staticlib), so the consuming app
#                          links the resulting .a-style binary directly. No dylib
#                          is emitted, and no @rpath dance at runtime.
#
# Requirements:
#   - bash 4+, Xcode, mvn (with alohaMaven creds in ~/.m2/settings.xml), git, zip, shasum
#   - The libvlc submodule must be initialised (see Modules/VLC after a `git submodule update --init --recursive`)
#
# Usage:
#   Packaging/publish_release.sh                       # full release (build + upload + push)
#   Packaging/publish_release.sh --version 4.0.0-a16-aloha02
#   Packaging/publish_release.sh --skip-build          # reuse the existing build/iOS/VLCKit.xcframework
#   Packaging/publish_release.sh --skip-upload         # build + Package.swift only, no maven push, no git push
#   Packaging/publish_release.sh --dry-run             # build only; no upload, no Package.swift bump, no git
#   Packaging/publish_release.sh --no-git              # do everything except commit/tag/push
#

set -euo pipefail

# ---------- configuration ----------
ARTIFACT_ID="vlckit-ios"
GROUP_ID="com.alohamobile"
CLASSIFIER="vlckit-ios"
TARGET_NAME="VLCKit"
MAVEN_URL="https://doloto.alohabrowser.com/repository/maven-releases/"
MAVEN_REPO_ID="alohaMaven"
RELEASE_BRANCH="aloha"
# ----------------------------------

GROUP_PATH=${GROUP_ID//./\/}

SKIP_BUILD=no
SKIP_UPLOAD=no
DO_GIT=yes
DRY_RUN=no
VERSION=""
ASSUME_YES=no

# ---------- helpers ----------
color_green="\033[1;32m"
color_orange="\033[1;91m"
color_red="\033[1;31m"
color_reset="\033[0m"

log() {
    local level="$1"; shift
    local color="$color_green"
    case "$level" in
        Warning) color="$color_orange" ;;
        Error)   color="$color_red" ;;
    esac
    printf "[${color}%s${color_reset}] %s\n" "$level" "$*"
}

die() { log Error "$*"; exit 1; }

confirm() {
    if [ "$ASSUME_YES" = "yes" ]; then return 0; fi
    local prompt="$1"
    read -r -p "$prompt [y/N]: " ans
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

usage() {
cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --version X.Y.Z       Use this artifact version instead of auto-deriving it
                        from git tags.
  --skip-build          Skip the libvlc + xcframework build; reuse the existing
                        build/iOS/VLCKit.xcframework.
  --skip-upload         Skip the mvn deploy step. Still bumps Package.swift
                        unless --no-git is also passed.
  --no-git              Don't commit, tag or push. Useful for local smoke tests.
  --dry-run             Build only — no upload, no Package.swift, no git push.
  --yes                 Skip interactive confirmations.
  -h | --help           This message.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)      VERSION="$2"; shift 2 ;;
        --skip-build)   SKIP_BUILD=yes; shift ;;
        --skip-upload)  SKIP_UPLOAD=yes; shift ;;
        --no-git)       DO_GIT=no; shift ;;
        --dry-run)      DRY_RUN=yes; SKIP_UPLOAD=yes; DO_GIT=no; shift ;;
        --yes|-y)       ASSUME_YES=yes; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

# Always run from the repo root regardless of how the script is invoked.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

XCFRAMEWORK_DIR="$ROOT_DIR/build/iOS"
XCFRAMEWORK_PATH="$XCFRAMEWORK_DIR/${TARGET_NAME}.xcframework"
DEVICE_ARCHIVE="$ROOT_DIR/build/${TARGET_NAME}-iphoneos-arm64.xcarchive"
SIM_ARCHIVE="$ROOT_DIR/build/${TARGET_NAME}-iphonesimulator-arm64.xcarchive"

# ---------- step 1: branch sanity ----------
ensure_branch() {
    local current
    current=$(git rev-parse --abbrev-ref HEAD)

    if [ "$current" = "master" ]; then
        # Auto-switch onto / create the release branch.
        if git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}"; then
            log Info "On master — switching to existing '${RELEASE_BRANCH}'."
            git checkout "${RELEASE_BRANCH}"
        elif git show-ref --verify --quiet "refs/remotes/origin/${RELEASE_BRANCH}"; then
            log Info "On master — checking out origin/${RELEASE_BRANCH}."
            git checkout -b "${RELEASE_BRANCH}" "origin/${RELEASE_BRANCH}"
        else
            log Warning "On master and '${RELEASE_BRANCH}' does not exist locally or on origin."
            confirm "Create '${RELEASE_BRANCH}' from current HEAD ($(git rev-parse --short HEAD))?" \
                || die "Aborted — release branch not created."
            git checkout -b "${RELEASE_BRANCH}"
        fi
        current="${RELEASE_BRANCH}"
    fi

    if [ "$current" != "$RELEASE_BRANCH" ]; then
        log Warning "Current branch is '$current', not '$RELEASE_BRANCH'. The release will land on '$current'."
        confirm "Continue on '$current'?" || die "Aborted by user."
    fi
    if [ -n "$(git status --porcelain)" ]; then
        log Warning "Working tree has uncommitted changes."
        confirm "Continue anyway?" || die "Aborted by user."
    fi
}

# ---------- step 2: version ----------
compute_version() {
    if [ -n "$VERSION" ]; then
        log Info "Using user-supplied version: $VERSION"
        return
    fi

    # Latest upstream-style VLCKit tag, e.g. 4.0.0-a16
    local upstream_tag
    upstream_tag=$(git tag --list '[0-9]*.[0-9]*.[0-9]*-a[0-9]*' --sort=-v:refname \
                   | grep -v -- '-aloha' \
                   | head -n1 || true)
    [ -z "$upstream_tag" ] && die "No upstream-style tag (e.g. 4.0.0-a16) found in repo history."

    # Latest aloha-suffixed tag for that upstream tag
    local aloha_latest
    aloha_latest=$(git tag --list "${upstream_tag}-aloha*" --sort=-v:refname | head -n1 || true)

    local next_num=01
    if [ -n "$aloha_latest" ]; then
        local suffix="${aloha_latest##*-aloha}"
        if [[ "$suffix" =~ ^[0-9]+$ ]]; then
            next_num=$(printf "%02d" $((10#$suffix + 1)))
        fi
    fi

    local proposed="${upstream_tag}-aloha${next_num}"
    if [ "$ASSUME_YES" = "yes" ]; then
        VERSION="$proposed"
    else
        echo
        echo "Latest upstream tag:   $upstream_tag"
        [ -n "$aloha_latest" ] && echo "Latest aloha tag:      $aloha_latest"
        echo "Proposed next version: $proposed"
        read -r -p "Use this version? Press <enter> to accept, or type a different version: " ans
        VERSION="${ans:-$proposed}"
    fi

    if git rev-parse --verify --quiet "refs/tags/${VERSION}" >/dev/null; then
        die "Tag '${VERSION}' already exists. Pick a different version."
    fi
    log Info "Releasing version: $VERSION"
}

# ---------- step 3: build ----------
#
# Strategy:
#   - Build libvlc + dependencies for arm64 device via compileAndBuildVLCKit.sh
#     WITHOUT the `-f` flag (so the script stops after libvlc and skips its own
#     framework archive step, which would otherwise produce a *dynamic* framework).
#   - Build libvlc for arm64 simulator manually by invoking libvlc's own
#     extras/package/apple/build.sh — the VLCKit script's `-a aarch64` flag
#     pins the platform to iphoneos and has no flag for "arm64 simulator".
#   - Patch the iphone simulator static-lib + module list header into the
#     locations VLCKit.xcodeproj expects (mirrors build_simulator_static_lib).
#   - Run xcodebuild archive ourselves for each slice with MACH_O_TYPE=staticlib
#     to emit a static .framework binary (no dylib), thin to a single arch each.
#   - xcodebuild -create-xcframework glues the two slices into a static
#     xcframework consumable via SPM .binaryTarget.
#
# Dedupe `.o` members in the static archive that xcodebuild just wrote into
# the .xcarchive. VLC's per-plugin static libs each carry the same helper
# .o (vt_utils, libvlc_opengles_la-*, h264_nal, libplacebo_utils, …) and
# `libtool -static` blindly concatenates without de-duplicating. Untouched,
# the resulting archive trips `-Wl,-load_hidden` / `-force_load` with
# hundreds of "duplicate symbol" errors and breaks any consumer-side
# visibility workaround. After dedup, ranlib regenerates the symbol table.
dedup_archive_in_xcarchive() {
    local xcarchive="$1"
    local label="$2"
    local bin="$xcarchive/Products/Library/Frameworks/${TARGET_NAME}.framework/${TARGET_NAME}"

    [ -f "$bin" ] || die "Static binary missing in $xcarchive (expected at $bin)"

    local before_members before_dups
    before_members=$(ar t "$bin" | wc -l | tr -d ' ')
    before_dups=$(ar t "$bin" | sort | uniq -d | wc -l | tr -d ' ')
    log Info "  dedup $label: $before_members members, $before_dups duplicate names"

    local tmp="$bin.dedup.tmp"
    python3 "$ROOT_DIR/Packaging/dedup_static_archive.py" --quiet "$bin" "$tmp"
    mv "$tmp" "$bin"
    ranlib "$bin"

    local after_members after_dups
    after_members=$(ar t "$bin" | wc -l | tr -d ' ')
    after_dups=$(ar t "$bin" | sort | uniq -d | wc -l | tr -d ' ')
    log Info "  dedup $label: $after_members members after, $after_dups duplicate names after"
    [ "$after_dups" -eq 0 ] \
        || die "Dedup of $label left $after_dups duplicate members in archive."
}

do_xcodebuild_archive() {
    local sdk="$1"
    local destination="$2"
    local archive_path="$3"
    log Info "  xcodebuild archive: sdk=$sdk arch=arm64 MACH_O_TYPE=staticlib → $(basename "$archive_path")"
    rm -rf "$archive_path"
    xcodebuild archive \
        -project "${TARGET_NAME}.xcodeproj" \
        -scheme "${TARGET_NAME}" \
        -sdk "$sdk" \
        -configuration Release \
        -destination "$destination" \
        -archivePath "$archive_path" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO \
        EXCLUDED_ARCHS=x86_64 \
        MACH_O_TYPE=staticlib \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        DEFINES_MODULE=YES \
        IPHONEOS_DEPLOYMENT_TARGET=11.0 \
        BITCODE_GENERATION_MODE=none \
        ENABLE_BITCODE=NO \
        SKIP_INSTALL=NO
    [ -d "$archive_path" ] || die "xcarchive not produced at $archive_path."
}

build_simulator_libvlc_arm64() {
    local sdk_version
    sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
    local vlc_root="$ROOT_DIR/libvlc/vlc"
    local build_dir="$vlc_root/build-iphonesimulator-arm64"

    log Info "Building libvlc for arm64 iphonesimulator (SDK $sdk_version)"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    (
        cd "$build_dir"
        ../extras/package/apple/build.sh \
            --arch=aarch64 \
            --sdk=iphonesimulator${sdk_version} \
            --disable-debug
    )
    [ -f "$build_dir/static-lib/libvlc-full-static.a" ] \
        || die "libvlc simulator static lib missing at $build_dir/static-lib/libvlc-full-static.a"

    # Mirror compileAndBuildVLCKit.sh's build_simulator_static_lib for VLCKit.xcodeproj.
    log Info "Patching simulator static lib + module-list header into expected locations"
    mkdir -p "$vlc_root/install-iphone-simulator"
    cp "$build_dir/static-lib/libvlc-full-static.a" \
       "$vlc_root/install-iphone-simulator/libvlc-simulator-static.a"

    mkdir -p "$ROOT_DIR/Headers/Internal"
    cp "$build_dir/static-lib/static-module-list.c" \
       "$ROOT_DIR/Headers/Internal/vlc-plugins-iphone-simulator-arm64.h"
    : > "$ROOT_DIR/Headers/Internal/vlc-plugins-iphone-simulator.h"
}

build_xcframework() {
    [ "$SKIP_BUILD" = "yes" ] && { log Info "--skip-build: reusing existing $XCFRAMEWORK_PATH"; return; }

    # Xcode 26 vs old VLC contribs workaround is applied via
    # libvlc/patches/0013-apple-build.sh-disable-libcpp-assertions-define.patch
    # which compileAndBuildVLCKit.sh `git am`s onto the libvlc tree on every
    # invocation (lines 529 / 540). The patch appends
    # `-U_LIBCPP_ENABLE_ASSERTIONS -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_NONE`
    # to the flags written into contrib config.mak so the
    # harfbuzz->ragel-6.10 and libplacebo meson subprojects (which hardcode
    # -D_LIBCPP_ENABLE_ASSERTIONS=1 in their meson.build) can still compile
    # against Xcode 26's libc++.

    # Note: compileAndBuildVLCKit.sh clones libvlc into libvlc/vlc on first run,
    # so we deliberately do NOT pre-check that directory here.

    # Clean any stale simulator libvlc build dirs from a previous interrupted
    # run. compileAndBuildVLCKit.sh's `check_lipo` blindly trusts that a present
    # build-iphonesimulator-* dir contains a finished `static-module-list.c`
    # and `set -e`s out if it doesn't, killing the device build that follows.
    if [ -d libvlc/vlc ]; then
        rm -rf libvlc/vlc/build-iphonesimulator-arm64 \
               libvlc/vlc/build-iphonesimulator-x86_64
    fi

    log Info "Pass 1/2: building libvlc + contribs for arm64 device (no framework archive yet)"
    # No -n: we need network access on a cold build for libvlc clone + contrib downloads.
    ./compileAndBuildVLCKit.sh -a aarch64

    log Info "Pass 2/2: building libvlc for arm64 simulator (Apple Silicon only)"
    build_simulator_libvlc_arm64

    log Info "Archiving VLCKit.framework as STATIC (MACH_O_TYPE=staticlib) for arm64 device"
    do_xcodebuild_archive iphoneos          "generic/platform=iOS"           "$DEVICE_ARCHIVE"
    dedup_archive_in_xcarchive "$DEVICE_ARCHIVE" "ios-arm64"

    log Info "Archiving VLCKit.framework as STATIC (MACH_O_TYPE=staticlib) for arm64 simulator"
    do_xcodebuild_archive iphonesimulator   "generic/platform=iOS Simulator" "$SIM_ARCHIVE"
    dedup_archive_in_xcarchive "$SIM_ARCHIVE" "ios-arm64-simulator"

    log Info "Composing static XCFramework (ios-arm64 + ios-arm64-simulator)"
    rm -rf "$XCFRAMEWORK_PATH"
    mkdir -p "$XCFRAMEWORK_DIR"
    # NOTE: -debug-symbols intentionally omitted. With MACH_O_TYPE=staticlib
    # xcodebuild does not emit a separate dSYM (debug info is in the .o files
    # inside the static archive), and passing a missing dSYM path would fail.
    xcodebuild -create-xcframework \
        -framework "$DEVICE_ARCHIVE/Products/Library/Frameworks/${TARGET_NAME}.framework" \
        -framework "$SIM_ARCHIVE/Products/Library/Frameworks/${TARGET_NAME}.framework" \
        -output    "$XCFRAMEWORK_PATH"
}

# ---------- step 4: package ----------
ZIP_NAME=""
ZIP_PATH=""
CHECKSUM=""

package_zip() {
    [ -d "$XCFRAMEWORK_PATH" ] || die "$XCFRAMEWORK_PATH does not exist; can't package."

    log Info "Verifying XCFramework slices..."
    local slices
    slices=$(ls "$XCFRAMEWORK_PATH" | grep -v '^Info.plist$' || true)
    echo "$slices" | sed 's/^/    /'
    for slice in $slices; do
        local bin="$XCFRAMEWORK_PATH/$slice/${TARGET_NAME}.framework/${TARGET_NAME}"
        [ -f "$bin" ] || continue

        local archs filetype
        archs=$(lipo -archs "$bin" 2>/dev/null || echo "?")
        # `file` reports "current ar archive" for staticlib, "Mach-O ... dynamically linked shared library" for dylib.
        filetype=$(file -b "$bin" | head -n1)
        log Info "  $slice → archs: $archs"
        log Info "    type:  $filetype"

        if [[ "$archs" == *" "* ]]; then
            log Warning "  Slice $slice contains multiple architectures ($archs) — not strictly thin."
        fi
        if [[ "$filetype" == *"dynamically linked"* || "$filetype" == *"dynamic library"* ]]; then
            die "Slice $slice is a DYNAMIC library ($filetype) — expected a static archive. Check MACH_O_TYPE=staticlib."
        fi

        # 2026-05-15 spec acceptance: `ar t VLCKit | sort | uniq -d` must be empty.
        local dup_count
        dup_count=$(ar t "$bin" | sort | uniq -d | wc -l | tr -d ' ')
        if [ "$dup_count" -gt 0 ]; then
            log Error "  $slice has $dup_count duplicate .o members; top offenders:"
            ar t "$bin" | sort | uniq -c | sort -rn | awk '$1>1' | head -10 | sed 's/^/      /'
            die "Archive dedup invariant violated for $slice."
        fi
        log Info "    ar dedup: 0 duplicate members"

        # 2026-05-15 spec acceptance: no public FFmpeg internals.
        # Regex matches symbols of the form _av_*, _avcodec_*, _avformat_*,
        # _avutil_*, _swscale_*, _swresample_*, _avfilter_*, _postproc_*,
        # _avdevice_* — same shape as VLC's avformat wrappers, so the check
        # also catches `_avformat_OpenDemux`-style leaks from libvlc itself.
        local nm_arch="$archs"
        # If multi-arch (shouldn't be, but just in case), pick the first.
        nm_arch="${nm_arch%% *}"
        local ffmpeg_leak
        ffmpeg_leak=$(nm -arch "$nm_arch" "$bin" 2>/dev/null \
            | grep -cE " T _(av|avcodec|avformat|avutil|swscale|swresample|avfilter|postproc|avdevice)_" || true)
        if [ "$ffmpeg_leak" -gt 0 ]; then
            log Error "  $slice exports $ffmpeg_leak FFmpeg public symbols (must be 0); first 10:"
            nm -arch "$nm_arch" "$bin" 2>/dev/null \
                | grep -E " T _(av|avcodec|avformat|avutil|swscale|swresample|avfilter|postproc|avdevice)_" \
                | head -10 | sed 's/^/      /'
            die "FFmpeg visibility invariant violated for $slice."
        fi
        log Info "    FFmpeg symbols: 0 public"
    done

    ZIP_NAME="${ARTIFACT_ID}-${VERSION}-${CLASSIFIER}.zip"
    ZIP_PATH="${XCFRAMEWORK_DIR}/${ZIP_NAME}"
    rm -f "$ZIP_PATH"

    log Info "Zipping ${TARGET_NAME}.xcframework → $ZIP_NAME"
    ( cd "$XCFRAMEWORK_DIR" && zip -FSry "$ZIP_NAME" "${TARGET_NAME}.xcframework" >/dev/null )

    CHECKSUM=$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)
    log Info "Artifact: $ZIP_PATH"
    log Info "sha256:   $CHECKSUM"
}

# ---------- step 5: upload to Maven ----------
upload_maven() {
    [ "$SKIP_UPLOAD" = "yes" ] && { log Info "--skip-upload: not deploying to maven."; return; }
    command -v mvn >/dev/null || die "mvn not found in PATH. Install Maven (brew install maven)."

    log Info "Deploying to ${MAVEN_URL} as ${GROUP_ID}:${ARTIFACT_ID}:${VERSION}"
    mvn deploy:deploy-file \
        -Dfile="$ZIP_PATH" \
        -DgroupId="$GROUP_ID" \
        -DartifactId="$ARTIFACT_ID" \
        -Dversion="$VERSION" \
        -Dpackaging=zip \
        -Dclassifier="$CLASSIFIER" \
        -DrepositoryId="$MAVEN_REPO_ID" \
        -Durl="$MAVEN_URL"

    local artifact_url
    artifact_url="${MAVEN_URL}${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/${ZIP_NAME}"
    log Info "Verifying remote artifact: $artifact_url"
    if ! curl -fsSI "$artifact_url" >/dev/null; then
        die "Remote artifact not reachable. Did the maven deploy actually succeed?"
    fi
    log Info "Upload OK."
}

# ---------- step 6: Package.swift ----------
write_package_swift() {
    local artifact_url
    artifact_url="${MAVEN_URL}${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/${ARTIFACT_ID}-${VERSION}-${CLASSIFIER}.zip"

    cat > Package.swift <<EOF
// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "${TARGET_NAME}",
    products: [
        .library(
            name: "${TARGET_NAME}",
            targets: [
              "${TARGET_NAME}",
            ]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(name: "${TARGET_NAME}",
                      url: "${artifact_url}",
                      checksum: "${CHECKSUM}"),
    ]
)
EOF
    log Info "Package.swift regenerated for ${VERSION}"
}

# ---------- step 7: git commit / tag / push ----------
git_release() {
    [ "$DO_GIT" = "no" ] && { log Info "--no-git: skipping commit/tag/push."; return; }

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)

    git add Package.swift
    git commit -m "Release ${VERSION}"
    git tag -a "${VERSION}" -m "Release ${VERSION}"

    log Info "Pushing branch '$branch' and tag '${VERSION}' to origin"
    git push origin "$branch"
    git push origin "${VERSION}"
}

# ---------- main ----------
log Info "VLCKit iOS release pipeline"
log Info "  repo:     $ROOT_DIR"
log Info "  maven:    $MAVEN_URL"
log Info "  group:    $GROUP_ID"
log Info "  artifact: $ARTIFACT_ID  classifier=$CLASSIFIER"

if [ "$DO_GIT" = "yes" ]; then
    ensure_branch
fi

compute_version
build_xcframework
package_zip

if [ "$DRY_RUN" = "yes" ]; then
    log Info "Dry run finished — built and zipped only. No upload, no Package.swift bump, no git push."
    exit 0
fi

upload_maven
write_package_swift
git_release

log Info "Done. ${ARTIFACT_ID} ${VERSION} is live at:"
log Info "  ${MAVEN_URL}${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/${ARTIFACT_ID}-${VERSION}-${CLASSIFIER}.zip"
log Info "  checksum: ${CHECKSUM}"
