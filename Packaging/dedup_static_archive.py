#!/usr/bin/env python3
"""
Deduplicate `.o` members in a BSD-style ar archive (macOS static library).

Why this exists: VLC's per-plugin static libraries each compile shared helper
TUs (libplacebo utils, OpenGLES helpers, h264_nal, vt_utils, …) into their own
.o. When all those plugin .a files are merged into VLCKit's final static
archive via `libtool -static`, the same .o ends up packaged 4-8 times. The
duplicates make the consuming iOS app trip over `-Wl,-load_hidden` / `-force_load`
with "duplicate symbol" errors, blocking the local FFmpeg-visibility workaround.

Per the 2026-05-15 spec, the final archive must satisfy
    `ar t VLCKit | sort | uniq -d`  → empty.

Strategy:
    Walk the archive sequentially, keep the FIRST occurrence of each member
    name (by the human-readable name surfaced by `ar t`, which is the BSD
    extended `#1/NNN` long name for typical .o entries), drop the rest.
    Bytes-level rewrite — no extraction, no re-libtool.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ARCH_MAGIC = b"!<arch>\n"
HEADER_LEN = 60


def parse_header(hdr: bytes) -> tuple[str, int]:
    """Return (raw_name_field, data_size_bytes). Raw name is the 16-byte field
    as stored on disk — for BSD extended names it'll be like '#1/123'."""
    if len(hdr) != HEADER_LEN:
        raise ValueError(f"truncated header, got {len(hdr)} bytes")
    name = hdr[0:16].decode("ascii", errors="replace").rstrip()
    size_str = hdr[48:58].decode("ascii").strip()
    size = int(size_str)
    return name, size


def member_display_name(raw_name: str, data: bytes) -> str:
    """Resolve the BSD '#1/NNN' extended name from member data, or return
    the raw name (trimmed of the trailing '/' GNU uses for non-extended)."""
    if raw_name.startswith("#1/"):
        n = int(raw_name[3:])
        return data[:n].rstrip(b"\x00").decode("ascii", errors="replace")
    return raw_name.rstrip("/")


def dedup(src: Path, dst: Path) -> tuple[int, int]:
    """Write a deduplicated copy of `src` to `dst`. Returns (kept, dropped)."""
    blob = src.read_bytes()
    if not blob.startswith(ARCH_MAGIC):
        raise SystemExit(f"{src}: not a BSD/SysV ar archive (missing !<arch>\\n)")

    out = bytearray(ARCH_MAGIC)
    seen: set[str] = set()
    kept = dropped = 0

    pos = len(ARCH_MAGIC)
    while pos < len(blob):
        if pos + HEADER_LEN > len(blob):
            raise SystemExit(f"{src}: truncated header at offset {pos}")
        hdr = blob[pos : pos + HEADER_LEN]
        raw_name, size = parse_header(hdr)

        data_start = pos + HEADER_LEN
        data_end = data_start + size
        if data_end > len(blob):
            raise SystemExit(f"{src}: truncated member at offset {pos}")
        member_data = blob[data_start:data_end]

        # Members are padded to an even byte boundary.
        boundary = data_end + (data_end & 1)
        end = min(boundary, len(blob))

        name = member_display_name(raw_name, member_data)

        # Special members (symbol table "/", "//", "__.SYMDEF", etc.) are kept
        # unconditionally — they are not user object files and never duplicate.
        is_special = (
            raw_name in ("/", "//")
            or name.startswith("__.SYMDEF")
            or name == ""
        )

        if is_special or name not in seen:
            out.extend(blob[pos:end])
            if not is_special:
                seen.add(name)
            kept += 1
        else:
            dropped += 1

        pos = end

    dst.write_bytes(bytes(out))
    return kept, dropped


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", type=Path, help="Input ar archive")
    ap.add_argument("output", type=Path, help="Deduplicated archive output path")
    ap.add_argument("--quiet", action="store_true", help="Don't print summary")
    args = ap.parse_args()

    kept, dropped = dedup(args.input, args.output)
    if not args.quiet:
        total = kept + dropped
        print(
            f"dedup_static_archive: {args.input.name} → "
            f"kept {kept} / dropped {dropped} duplicates "
            f"({total} total members)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
