#!/usr/bin/env python3
"""
aloha_ld_r_repack.py — re-pack libvlc-full-static.a so consumer apps that link
their own FFmpeg.framework don't collide with VLC's bundled FFmpeg internals.

Why this exists:
  - VLCKit ships a static archive containing libvlc + all enabled plugins +
    all contribs (incl. an FFmpeg snapshot used by libavcodec_plugin).
  - VLC plugin .o files (libavcodec_plugin_la-video.o, …) reference
    `_avcodec_send_packet`, `_av_frame_alloc`, … as Mach-O `(undefined)
    external` imports.
  - Consumer apps (Aloha iOS) link Apple ld with both VLCKit.a AND a
    separate `Modules/FFmpeg/libavcodec.xcframework`. ld resolves VLC's
    extern undef refs to the consumer's FFmpeg dylib (which loads first
    in command order) rather than to VLC's bundled FFmpeg static .o
    members. The two FFmpegs are different versions → AVCodecContext
    layout mismatch → indirect branch through garbage struct field →
    EXC_BAD_ACCESS (PC = 0x200000002) on first decoded frame.
  - -fvisibility=hidden in VLCKit's apple/build.sh + contrib/ffmpeg
    rules.mak ALREADY makes FFmpeg internal DEFINITIONS hidden (private
    external). It does NOT make plugin .o REFERENCES private — Mach-O
    has no "(undefined) private external" encoding, and clang's
    `-fvisibility` flag is documented to affect definitions only.
  - The only way to resolve the cross-archive references INTERNALLY is
    a partial link (`ld -r`) of the whole archive AT PACKAGING TIME.
    After `ld -r`, plugin refs that previously were `(undefined)
    external` become `non-external (was a private external)` — bound to
    VLC's bundled FFmpeg locally and invisible to consumers.

What this script does (run after `libtool -static -o libvlc-full-static.a`):
  1. Parses the BSD archive byte-by-byte (Python — handles BSD `#1/NN`
     extended-name members AND `name~N` duplicate-name members which
     Apple's `ar t` shows as the same name but treats as separate
     members).
  2. Extracts every .o member to a temp directory with a UNIQUE filename
     even when the macOS host filesystem is case-insensitive (APFS).
     Live555's `Base64.o` (C++ base64Decode) and FFmpeg's `base64.o`
     (`_av_base64_decode`) would otherwise overwrite each other on disk.
  3. Excludes a hard-coded set of members that produce duplicate-SYMBOL
     errors at `ld -r` time (different .o, same symbol — typically
     libtool generating both a plain and a libfoo_la-prefixed copy of
     the same source). For each known pair we drop the one that is
     redundant for the static-link consumer.
  4. Runs `xcrun ld -r` with all surviving .o files → one big .o where
     VLC's plugin → FFmpeg / libvlc / contrib references are
     statically resolved.
  5. Re-wraps the single .o in a fresh archive via `xcrun ar -rcs`,
     overwriting the input path.

Usage:
    aloha_ld_r_repack.py <input-archive> <arch> <platform> <min-os> <max-os>

    <platform> is one of: ios, ios-simulator, tvos, tvos-simulator, macosx,
                          xros, xros-simulator, watchos, watchos-simulator
    <arch>     is one of: arm64, x86_64
    <min-os>, <max-os>: e.g. "16.0", "26.2"

Side effect: rewrites the input archive in place.

Verification post-run:
    nm -arch <arch> <archive> | grep -cE ' T _(av|avcodec|avformat|avutil|swscale|swresample|avfilter)_'
    # expected: 0 — every FFmpeg-prefix T symbol should now be either
    #            non-external (local) or "was a private external" after
    #            ld -r's symbol-scope collapse.

    nm -arch <arch> -u <archive> | grep -cE '^_(av|avcodec|avformat|avutil)_'
    # expected: 0 — no plugin .o still has an undef external FFmpeg ref.

Plan ref: CU-86eq9n2ta, docs/superpowers/qa/2026-05-15-vlckit-aloha03-findings.md
"""

from __future__ import annotations
import os
import re
import shutil
import subprocess
import sys
import tempfile

# Regex matching FFmpeg-prefix symbols. Used to identify which .o files
# carry FFmpeg internals (either as definitions or as references). Only
# those .o get merged via `ld -r`; everything else stays as a separate
# archive member.
#
# CRITICAL: a broad `ld -r` of the entire archive (initial version of
# this script) breaks C++ RTTI / weak-coalesced symbols in unrelated
# contribs — most visibly protobuf typeinfo. Apps using those at dyld
# initialization time crash with `CODESIGNING / Invalid Page` because
# `ld -r`'s relocation / chained-fixup output is not page-hash-compatible
# with the consumer dylib link step. Restricting the merge to FFmpeg-
# related .o files only is the empirical fix.
FFMPEG_SYMBOL_RE = re.compile(
    rb"^_(av|avcodec|avformat|avutil|swscale|swresample|swr|avfilter|postproc"
    rb"|avdevice|ff|avpriv)_",
    re.MULTILINE,
)
# CRITICAL: anchored at line start (re.MULTILINE) — must match a SYMBOL
# starting with the FFmpeg prefix, not the prefix as a substring inside
# some other symbol's name.
#
# Without the `^` anchor, files like `static-module-list.o` (VLC's
# generated plugin registry, 253 `_vlc_entry__codec_avcodec_*`,
# `_vlc_entry__demux_avformat_*`, … strings) and `VLCLibrary.o` would
# get mis-flagged as FFmpeg-related — `_avcodec_` is a substring of
# `_vlc_entry__codec_avcodec_libavcodec`. Pulling those into the
# merge set then triggers a duplicate-symbol error at `ld -r` for
# `_vlc_static_modules`, which is defined as a stub in VLCLibrary.o
# (8-byte placeholder, external) AND as the real plugin table in
# static-module-list.o (~18 KB, private external).
# Notes on what each prefix catches:
#   av_/avcodec_/avformat_/avutil_/swscale_/swresample_/avfilter_/avdevice_/
#   postproc_  — FFmpeg PUBLIC API symbols
#   swr_       — libswresample's shortcut prefix
#   ff_        — FFmpeg INTERNAL cross-file symbols (library-private but
#                marked external for inter-.o linkage). EVERY .c inside
#                libavcodec/libavformat/libavutil/libswscale/libswresample/
#                libavfilter that exposes anything to its sibling .c's uses
#                this prefix (mathtables.o defines `_ff_crop_tab`,
#                cavsdsp.o references it, etc.). MUST be in the merge
#                set or `ld -r` produces a partial-link with dangling
#                refs.
#   avpriv_    — FFmpeg internal cross-library helpers (rarer than ff_).

# Filenames that are obviously VLC's FFmpeg plugin wrappers. These reference
# FFmpeg API even when they don't define any `_av_*` symbol themselves, so
# we want them in the merged set so their cross-archive references resolve
# locally. Matched against the .o member name AFTER stripping any libtool
# `_la-` segment.
FFMPEG_PLUGIN_NAME_RE = re.compile(
    r"^(libav[a-z]*_plugin_la-|libpostproc_plugin_la-|libavcodec_common_la-|"
    r"libswscale_plugin_la-|libswresample_plugin_la-)"
)

# Members to exclude because another member in the archive provides the same
# symbol. Picking which side of each duplicate pair to drop was determined
# empirically (the kept member is the one whose symbols are actually used at
# runtime; the dropped one is the redundant libtool-generated sibling).
KNOWN_DUPLICATE_DROPS = {
    # IMPORTANT: with the SELECTIVE `ld -r` strategy (FFmpeg-related .o
    # only — see `is_ffmpeg_related`), most duplicate-symbol pairs that
    # used to need explicit drops are now harmless: both members stay
    # as separate kept archive entries, and Apple ld's demand-load at
    # consumer-side full link picks one. The only drops we still need
    # are for duplicates BOTH of which end up in the FFmpeg MERGE set,
    # because `ld -r` strictly rejects duplicate symbols (unlike
    # consumer-side full link which handles archive demand-loading
    # gracefully).
    #
    # HISTORY: -aloha04..-aloha06 dropped a wider set
    # (static-module-list.o, avaudiosession_common.o, strverscmp.o,
    # compat_clock_gettime.c.o, md5.c.o, contrib_mdx_md5.c.o,
    # libvlccore_la-revision.o). Those were needed for the broken
    # whole-archive `ld -r` of -aloha04 because everything funneled
    # through one giant ld -r where any duplicate aborted the link.
    #
    # The static-module-list.o drop was CATASTROPHIC: it removed VLC's
    # generated plugin registry, leaving only VLCLibrary.o's stub
    # `_vlc_static_modules` placeholder. libvlc then thought no
    # plugins were registered. User-visible symptoms on iPhone 15
    # with -aloha06:
    #   (a) thumbnail generation silently fails for non-mp4 files
    #       (no demuxer plugins reachable at runtime — TSThumbnailGenerator
    #       fallback kicks in but only produces audio-artwork-style
    #       placeholders, not real frame snapshots)
    #   (b) Chromecast TLS handshake throws
    #       std::runtime_error("Failed to create client session")
    #       from cast.cpp because vlc_tls_ClientSessionCreate returns
    #       NULL — the SecureTransport plugin
    #       (_vlc_entry__misc_libsecuretransport) exists in the
    #       archive but is unreachable through the (stub) static
    #       module registry. Crash log:
    #       /Users/artes/Library/Developer/Xcode/DeviceLogs/iPhone\ 15-*/
    #       AlohaBrowserApp-2026-05-18-*.ips
    #
    # Fix: with selective `ld -r`, static-module-list.o never enters
    # the merge set (it has zero FFmpeg-prefix symbols). So it stays
    # as a separate archive member alongside VLCLibrary.o's
    # placeholder, and Apple ld at consumer-side full link picks the
    # real definition via standard demand-load resolution — same as
    # the original VLCKit archives prior to any of our repack work.
    # The same logic applies to all the other non-FFmpeg drops; only
    # the FFmpeg-internal half2float pair actually needs dropping at
    # the `ld -r` stage.

    # _ff_init_half2float_tables — FFmpeg's half-float lookup table
    # built twice in libtool (likely libavutil + libswscale variants).
    # BOTH copies match the FFmpeg-prefix regex (ff_) so both land in
    # the merge set, where `ld -r` strictly rejects the duplicate
    # symbol. The two copies are functionally equivalent; drop the
    # `__cidup1` sibling.
    "half2float__cidup1.o",
}

# Members that are not real .o files (BSD ar's symbol index, empty
# entries, etc.) — silently skip.
ARCHIVE_METADATA_NAMES = {"__.SYMDEF", "__.SYMDEF SORTED", ""}


def parse_bsd_archive(path: str):
    """Yield (member_index, real_name, data_bytes) for every member."""
    idx = 0
    with open(path, "rb") as f:
        magic = f.read(8)
        if magic != b"!<arch>\n":
            raise SystemExit(f"Not a BSD archive: {path!r} (magic={magic!r})")
        while True:
            header = f.read(60)
            if not header or len(header) < 60:
                return
            raw_name = header[:16].decode("ascii", errors="replace").rstrip()
            size_str = header[48:58].decode("ascii").strip()
            size = int(size_str)
            if raw_name.startswith("#1/"):
                # BSD extended name: actual filename in first NN bytes of data
                namelen = int(raw_name[3:])
                real_name = (
                    f.read(namelen).decode("ascii", errors="replace").rstrip("\x00")
                )
                data_size = size - namelen
            else:
                real_name = raw_name
                data_size = size
            data = f.read(data_size)
            # BSD ar pads to even byte
            if size % 2 == 1:
                f.read(1)
            idx += 1
            yield idx, real_name, data


def extract_members(archive_path: str, out_dir: str) -> list[str]:
    """
    Extract every .o member to out_dir. Handle name collisions both at
    case-sensitive level (`name~2` BSD duplicate suffix) and at
    case-insensitive level (`Base64.o` vs `base64.o` on APFS).

    Before writing to disk, deduplicate by SHA256 of member content —
    libtool -static concatenates contrib .a files blindly, so the same
    translation unit (e.g. protobuf's arena.cc.o, glslang's doc.cpp.o)
    appears multiple times byte-for-byte when several contribs each
    bundle a copy. Keeping all of them blows up `ld -r` with thousands
    of "duplicate symbol" errors. Byte-identical members carry the same
    symbols, so dropping all but one is always safe.

    Returns the list of filenames written (relative to out_dir).
    """
    import hashlib

    written: list[str] = []
    # case-insensitive lookup: lower(basename) → next dedup index
    seen_ci: dict[str, int] = {}
    # content-hash dedup: sha256(data) → first written filename
    seen_content: dict[bytes, str] = {}
    content_dups = 0

    name_re = re.compile(r"^(.+\.o)(~\d+)?$")

    for idx, real_name, data in parse_bsd_archive(archive_path):
        if real_name in ARCHIVE_METADATA_NAMES:
            continue
        m = name_re.match(real_name)
        if not m:
            # Not a recognized .o name pattern (e.g. some BSD metadata) → skip.
            continue
        if len(data) == 0:
            continue

        content_hash = hashlib.sha256(data).digest()
        if content_hash in seen_content:
            content_dups += 1
            continue

        basename = m.group(1)
        tilde_suffix = m.group(2) or ""

        if tilde_suffix:
            # `name~N` BSD duplicate-name member → always gets a unique
            # disk name; case-sensitivity is moot because the suffix
            # differentiates the dedup index.
            stem = basename.rsplit(".o", 1)[0]
            outname = f"{stem}__dup{tilde_suffix.lstrip('~')}.o"
        else:
            ci_key = basename.lower()
            count = seen_ci.get(ci_key, 0)
            seen_ci[ci_key] = count + 1
            if count == 0:
                outname = basename
            else:
                stem = basename.rsplit(".o", 1)[0]
                outname = f"{stem}__cidup{count}.o"

        with open(os.path.join(out_dir, outname), "wb") as g:
            g.write(data)
        written.append(outname)
        seen_content[content_hash] = outname

    if content_dups:
        print(f"[aloha_ld_r_repack] dropped {content_dups} byte-identical duplicate members during extraction")

    return written


def is_ffmpeg_related(out_dir: str, filename: str) -> bool:
    """
    Return True if this .o either defines OR references at least one
    FFmpeg-prefix symbol, OR if its filename matches a VLC FFmpeg-plugin
    wrapper pattern. These are the only .o files we want to merge via
    `ld -r` — merging anything else can corrupt C++ RTTI / weak-coalesced
    symbols in protobuf, harfbuzz, libplacebo etc.

    Implementation: scan the .o for the FFmpeg symbol prefix in its
    symbol table. Doing this in pure Python (parsing Mach-O directly)
    is overkill; we just run `xcrun nm` and grep.
    """
    if FFMPEG_PLUGIN_NAME_RE.match(filename):
        return True
    path = os.path.join(out_dir, filename)
    try:
        # `nm -j` outputs just symbol names (no addresses or types),
        # one per line. Faster than parsing full nm output. Captures
        # both defined symbols (T/D/B) and undefined refs (U).
        out = subprocess.run(
            ["xcrun", "nm", "-j", path],
            capture_output=True, check=True,
        ).stdout
        return bool(FFMPEG_SYMBOL_RE.search(out))
    except subprocess.CalledProcessError:
        return False


def select_for_relink(out_dir: str, filenames: list[str]) -> tuple[list[str], list[str]]:
    """
    Partition extracted .o filenames into:
      * to_merge — FFmpeg-related .o files that go into `ld -r`
      * to_keep  — everything else; stays as separate archive members

    Also drops members in KNOWN_DUPLICATE_DROPS from both sets — those
    cause duplicate-symbol errors at `ld -r` time when paired with
    their libtool-prefixed siblings.
    """
    to_merge = []
    to_keep = []
    for n in filenames:
        if n in KNOWN_DUPLICATE_DROPS:
            # Skip entirely — the surviving member of each duplicate pair
            # is already in either to_merge or to_keep (we keep the
            # plugin-prefixed sibling).
            continue
        if is_ffmpeg_related(out_dir, n):
            to_merge.append(n)
        else:
            to_keep.append(n)
    return to_merge, to_keep


def run_ld_r(out_dir: str, files: list[str], arch: str, platform: str,
             min_os: str, max_os: str, out_o: str) -> None:
    """Invoke `xcrun ld -r` to produce a single relocatable .o."""
    # `ld -r` takes a -filelist for many files; build it.
    filelist = os.path.join(out_dir, "_filelist.txt")
    with open(filelist, "w") as f:
        for name in files:
            f.write(f"./{name}\n")
    # -keep_private_externs is essential. By default `ld -r` demotes every
    # `private external` (hidden visibility) symbol in the inputs to a
    # plain `local`/`non-external` symbol in the output. That kills the
    # archive: VLCKit's ObjC wrapper sources reference `_libvlc_printerr`
    # and the static module list references every `_vlc_entry__*` plugin
    # entry, and both are emitted as `private external` because libvlc /
    # contribs compile with -fvisibility=hidden. After demotion they're
    # no longer in the archive's symbol table, so xcodebuild's final
    # linker stage fails with "Undefined symbols ... _libvlc_printerr,
    # _vlc_entry__codec_avcodec_libavcodec, …".
    #
    # With -keep_private_externs, hidden symbols survive `ld -r` as
    # `private external` — still globally addressable for archive
    # symbol-table lookup (so the static-module-list and VLCKit ObjC code
    # can bind to them), still hidden when the resulting object is later
    # linked into the consumer's dylib (so they don't leak into
    # CoreFiles.framework's export trie). This is exactly the
    # visibility-preserving semantics we want.
    cmd = [
        "xcrun", "ld", "-r",
        "-keep_private_externs",
        "-arch", arch,
        "-platform_version", platform, min_os, max_os,
        "-filelist", filelist,
        "-o", out_o,
    ]
    res = subprocess.run(cmd, cwd=out_dir, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write("ld -r failed:\n")
        sys.stderr.write(res.stderr)
        raise SystemExit(res.returncode)
    # Surface any warnings on stderr so they're visible in the build log.
    if res.stderr.strip():
        sys.stderr.write(res.stderr)


def repack_as_archive(out_dir: str, output_a: str,
                      combined_o: str, kept_files: list[str]) -> None:
    """
    Wrap the merged FFmpeg .o plus all the untouched .o members back into
    a single static archive via `xcrun libtool -static`.

    Using `libtool -static` (not plain `ar -rcs` on one giant .o) so that
    each preserved .o keeps its own Mach-O headers, relocations,
    weak/coalesced attributes, and codedirectory-friendly section
    layout. This is critical for C++ contribs (protobuf, harfbuzz,
    libplacebo) whose RTTI/typeinfo data was getting corrupted by the
    naive single-.o repack.
    """
    if os.path.exists(output_a):
        os.remove(output_a)

    # Write a libtool filelist: one path per line, combined.o first then
    # all the kept .o members.
    filelist = os.path.join(out_dir, "_libtool_filelist.txt")
    with open(filelist, "w") as f:
        f.write(combined_o + "\n")
        for name in kept_files:
            f.write(os.path.join(out_dir, name) + "\n")

    cmd = [
        "xcrun", "libtool", "-static",
        "-no_warning_for_no_symbols",
        "-filelist", filelist,
        "-o", output_a,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write("libtool -static failed:\n")
        sys.stderr.write(res.stderr)
        raise SystemExit(res.returncode)


def main() -> None:
    if len(sys.argv) != 6:
        print(__doc__)
        sys.exit(2)
    archive = sys.argv[1]
    arch = sys.argv[2]
    platform = sys.argv[3]
    min_os = sys.argv[4]
    max_os = sys.argv[5]

    if not os.path.isfile(archive):
        sys.exit(f"Input archive does not exist: {archive}")

    print(f"[aloha_ld_r_repack] arch={arch} platform={platform} target={min_os}-{max_os}")
    print(f"[aloha_ld_r_repack] input: {archive} ({os.path.getsize(archive)} bytes)")

    tmp = tempfile.mkdtemp(prefix="vlckit-aloha-repack-")
    try:
        members = extract_members(archive, tmp)
        print(f"[aloha_ld_r_repack] extracted {len(members)} .o members")

        to_merge, to_keep = select_for_relink(tmp, members)
        dropped = len(members) - len(to_merge) - len(to_keep)
        print(f"[aloha_ld_r_repack] dropped {dropped} known-dup .o; "
              f"merge={len(to_merge)} (FFmpeg-related), "
              f"keep-as-is={len(to_keep)}")

        combined_o = os.path.join(tmp, "vlckit-ffmpeg-merged.o")
        run_ld_r(tmp, to_merge, arch, platform, min_os, max_os, combined_o)
        print(f"[aloha_ld_r_repack] ffmpeg-merged .o: {os.path.getsize(combined_o)} bytes")

        repack_as_archive(tmp, archive, combined_o, to_keep)
        print(f"[aloha_ld_r_repack] repacked archive: "
              f"{os.path.getsize(archive)} bytes — overwrote in place "
              f"(1 merged .o + {len(to_keep)} kept .o = {1 + len(to_keep)} members)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
