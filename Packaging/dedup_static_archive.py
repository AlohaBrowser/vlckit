#!/usr/bin/env python3
"""
Deduplicate `.o` members in a BSD-style ar archive (macOS static library).

Why this exists: VLC's per-plugin static libraries each compile shared helper
TUs (libplacebo utils, OpenGLES helpers, h264_nal, vt_utils, …) into their own
.o. When all those plugin .a files are merged into VLCKit's final static
archive via `libtool -static`, the same .o ends up packaged 4-8 times. The
duplicates make the consuming iOS app trip over `-Wl,-load_hidden` / `-force_load`
with "duplicate symbol" errors.

Two kinds of "same-named" members live in the archive:

  1. Truly identical members. The exact same .o (same content, same symbols)
     packaged into N different per-plugin .a files. Safe — and necessary — to
     drop down to one.

  2. Same basename but DIFFERENT content. Most often `list.c.o`, `utils.c.o`,
     `file.c.o` — every contrib library brings its own `list.c.o`, and they
     define completely different symbols (libupnp's `list.c.o` carries
     `_UpnpListBegin`, libxml2's `list.c.o` carries `_xmlList*`, etc.).
     Dropping all-but-the-first by name silently strips functionality.

Strategy used here:

    Use a sha256 of the member content as the dedup key. Truly identical
    members collapse; differently-content same-named members are all kept.

    For the surviving same-name-different-content members, rename the second,
    third, … occurrence by appending `~2`, `~3`, … to the display name. This
    satisfies a strict `ar t | sort | uniq -d` check (the spec's done-definition
    written in 2026-05-15-vlckit-rebuild-fixes-needed.md) without losing any
    real translation unit.

After rewriting the file, the caller MUST run `ranlib` to regenerate the
archive symbol table — member offsets shift after deduplication.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

ARCH_MAGIC = b"!<arch>\n"
HEADER_LEN = 60


def parse_header(hdr: bytes) -> tuple[str, int]:
    """Return (raw_name_field, data_size_bytes)."""
    if len(hdr) != HEADER_LEN:
        raise ValueError(f"truncated header, got {len(hdr)} bytes")
    name = hdr[0:16].decode("ascii", errors="replace").rstrip()
    size_str = hdr[48:58].decode("ascii").strip()
    size = int(size_str)
    return name, size


def member_display_name(raw_name: str, data: bytes) -> tuple[str, int]:
    """Return (resolved_display_name, extended_name_length_in_data_bytes).

    BSD ar stores names longer than 16 chars as `#1/NNN` in the header, followed
    by NNN bytes of the actual name at the start of the data area. For those
    members, the visible content (object file bytes) starts NNN bytes in.
    """
    if raw_name.startswith("#1/"):
        n = int(raw_name[3:])
        return data[:n].rstrip(b"\x00").decode("ascii", errors="replace"), n
    return raw_name.rstrip("/"), 0


def build_header(name: str, data: bytes) -> bytes:
    """Build a 60-byte BSD ar header for a renamed member.

    The data bytes here are the FULL member payload as it will be written into
    the archive (i.e. for a BSD-extended name, this must already include the
    name prefix at the start; we don't re-add the prefix). We always emit the
    BSD `#1/NNN` extended form to keep the rename path simple and uniform.
    """
    name_bytes = name.encode("ascii")
    n = len(name_bytes)
    # Pad name to even byte boundary inside the data area.
    if n % 2:
        name_bytes += b"\x00"
        n += 1
    raw_name = f"#1/{n}"
    size = n + len(data)
    header = (
        f"{raw_name:<16}"     # name (16 bytes, space-padded)
        f"{'0':<12}"          # mtime
        f"{'0':<6}"           # uid
        f"{'0':<6}"           # gid
        f"{'644':<8}"         # mode
        f"{str(size):<10}"    # size
        f"\x60\n"             # end marker
    ).encode("ascii")
    assert len(header) == HEADER_LEN, len(header)
    return header + name_bytes + data


def dedup(src: Path, dst: Path) -> tuple[int, int, int]:
    """Write a deduplicated copy of `src` to `dst`.

    Returns (kept, dropped, renamed)."""
    blob = src.read_bytes()
    if not blob.startswith(ARCH_MAGIC):
        raise SystemExit(f"{src}: not a BSD/SysV ar archive (missing !<arch>\\n)")

    out = bytearray(ARCH_MAGIC)
    seen_hashes: set[bytes] = set()
    name_counts: dict[str, int] = {}
    kept = dropped = renamed = 0

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

        display_name, ext_name_len = member_display_name(raw_name, member_data)
        # The actual object-file bytes (excluding any extended-name prefix).
        object_bytes = member_data[ext_name_len:]

        # Special members (symbol table "/", "//", "__.SYMDEF", etc.) are kept
        # unconditionally — they are not user object files and never duplicate
        # in a meaningful sense.
        is_special = (
            raw_name in ("/", "//")
            or display_name.startswith("__.SYMDEF")
            or display_name == ""
        )

        if is_special:
            out.extend(blob[pos:end])
            kept += 1
            pos = end
            continue

        # Dedup by SHA256 of the actual object payload (ignoring the
        # extended-name prefix and trailing padding inside the data area).
        content_hash = hashlib.sha256(object_bytes).digest()
        if content_hash in seen_hashes:
            dropped += 1
            pos = end
            continue
        seen_hashes.add(content_hash)

        # Rename if a previous DIFFERENT-content member already used this
        # display name — `list.c.o` from libupnp vs `list.c.o` from libxml2,
        # for example. Suffix with `~N` so `ar t | sort | uniq -d` returns
        # zero on the resulting archive.
        n = name_counts.get(display_name, 0) + 1
        name_counts[display_name] = n
        if n == 1:
            # First time we see this name — keep the original header.
            out.extend(blob[pos:end])
            kept += 1
        else:
            new_name = f"{display_name}~{n}"
            new_member = build_header(new_name, object_bytes)
            # Pad to even byte boundary in the output stream.
            if len(new_member) % 2:
                new_member += b"\n"
            out.extend(new_member)
            kept += 1
            renamed += 1

        pos = end

    dst.write_bytes(bytes(out))
    return kept, dropped, renamed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", type=Path, help="Input ar archive")
    ap.add_argument("output", type=Path, help="Deduplicated archive output path")
    ap.add_argument("--quiet", action="store_true", help="Don't print summary")
    args = ap.parse_args()

    kept, dropped, renamed = dedup(args.input, args.output)
    if not args.quiet:
        total = kept + dropped
        print(
            f"dedup_static_archive: {args.input.name} → "
            f"kept {kept} (of which {renamed} renamed to break name "
            f"collisions) / dropped {dropped} truly-identical duplicates "
            f"({total} total members)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
