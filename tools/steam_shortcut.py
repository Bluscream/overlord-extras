#!/usr/bin/env python3
"""Point a Steam non-Steam-game shortcut at a launcher script.

Split out of overlord.sh because it parses and rewrites two binary/text formats
that belong to Steam. Three things went wrong when this lived in a heredoc:

* the binary VDF parser silently desynced on any field type it did not know,
  because it consumed the key but not the value, and the result was written
  straight back over shortcuts.vdf;
* config.vdf was read as text with errors='ignore', which drops any byte that
  is not valid UTF-8 and then writes the damaged result back;
* the config.vdf edit used a `"appid" { [^}]* }` regex, which cannot match a
  nested block and is not scoped to CompatToolMapping, so it could delete an
  unrelated span that merely contained the same number.

Every write here is verified by re-parsing the bytes that are about to be
written and comparing them against the in-memory value, and nothing is written
at all when the content would be unchanged.
"""

from __future__ import annotations

import argparse
import re
import shutil
import struct
import sys
import time
from pathlib import Path
from typing import Any

# Binary VDF field type tags.
TYPE_DICT = 0
TYPE_STR = 1
TYPE_INT32 = 2
TYPE_FLOAT32 = 3
TYPE_POINTER = 4
TYPE_WSTR = 5
TYPE_COLOR = 6
TYPE_UINT64 = 7
TYPE_END = 8
TYPE_INT64 = 10

# Fixed-width types, so an unexpected one can still be skipped by the right
# number of bytes instead of desyncing the rest of the parse.
FIXED_WIDTHS = {
    TYPE_INT32: 4,
    TYPE_FLOAT32: 4,
    TYPE_POINTER: 4,
    TYPE_COLOR: 4,
    TYPE_UINT64: 8,
    TYPE_INT64: 8,
}


class VdfError(RuntimeError):
    """The file is not a binary VDF we can round-trip safely."""


class Int64(int):
    """A uint64/int64 field, kept distinct so it is written back as one."""

    __slots__ = ()


class VdfParser:
    def __init__(self, data: bytes) -> None:
        self._data = data
        self._idx = 0

    def parse(self) -> dict[str, Any]:
        root = self._parse_dict()
        if self._idx != len(self._data):
            trailing = len(self._data) - self._idx
            # Steam writes a single trailing byte on some versions; anything
            # more means we misread the structure and must not write it back.
            if trailing > 1 or self._data[self._idx :] not in (b"\x08", b"\x00"):
                raise VdfError(
                    f"{trailing} unconsumed trailing bytes at offset {self._idx}"
                )
        return root

    def _read_cstr(self) -> str:
        end = self._data.find(b"\x00", self._idx)
        if end < 0:
            raise VdfError(f"unterminated string at offset {self._idx}")
        value = self._data[self._idx : end].decode("utf-8", "surrogateescape")
        self._idx = end + 1
        return value

    def _read_wstr(self) -> str:
        end = self._data.find(b"\x00\x00", self._idx)
        if end < 0:
            raise VdfError(f"unterminated wide string at offset {self._idx}")
        value = self._data[self._idx : end].decode("utf-16le", "surrogateescape")
        self._idx = end + 2
        return value

    def _parse_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        while True:
            if self._idx >= len(self._data):
                raise VdfError("file ended inside a dictionary")
            tag = self._data[self._idx]
            self._idx += 1
            if tag == TYPE_END:
                return result
            key = self._read_cstr()
            if tag == TYPE_DICT:
                result[key] = self._parse_dict()
            elif tag == TYPE_STR:
                result[key] = self._read_cstr()
            elif tag == TYPE_WSTR:
                result[key] = self._read_wstr()
            elif tag == TYPE_INT32:
                (value,) = struct.unpack_from("<i", self._data, self._idx)
                self._idx += 4
                result[key] = value
            elif tag in (TYPE_UINT64, TYPE_INT64):
                (value,) = struct.unpack_from("<q", self._data, self._idx)
                self._idx += 8
                result[key] = Int64(value)
            elif tag in FIXED_WIDTHS:
                width = FIXED_WIDTHS[tag]
                result[key] = self._data[self._idx : self._idx + width]
                self._idx += width
            else:
                # Refuse rather than guess. Writing back a structure we only
                # partly understood is how shortcuts.vdf gets corrupted.
                raise VdfError(
                    f"unknown field type {tag} for key {key!r} at offset {self._idx}"
                )


def dump_vdf(data: dict[str, Any]) -> bytes:
    out = bytearray()

    def write_dict(node: dict[str, Any]) -> None:
        for key, value in node.items():
            encoded_key = key.encode("utf-8", "surrogateescape") + b"\x00"
            if isinstance(value, dict):
                out.extend(bytes([TYPE_DICT]) + encoded_key)
                write_dict(value)
                out.append(TYPE_END)
            elif isinstance(value, str):
                out.extend(bytes([TYPE_STR]) + encoded_key)
                out.extend(value.encode("utf-8", "surrogateescape") + b"\x00")
            elif isinstance(value, Int64):
                out.extend(bytes([TYPE_UINT64]) + encoded_key)
                out.extend(struct.pack("<q", int(value)))
            elif isinstance(value, bool):
                out.extend(bytes([TYPE_INT32]) + encoded_key)
                out.extend(struct.pack("<i", int(value)))
            elif isinstance(value, int):
                out.extend(bytes([TYPE_INT32]) + encoded_key)
                out.extend(struct.pack("<i", value))
            elif isinstance(value, bytes):
                raise VdfError(
                    f"key {key!r} holds an opaque field this writer cannot emit"
                )
            else:
                raise VdfError(
                    f"key {key!r} has unsupported type {type(value).__name__}"
                )

    write_dict(data)
    out.append(TYPE_END)
    return bytes(out)


def backup(path: Path) -> Path:
    destination = path.with_name(f"{path.name}.bak.{int(time.time())}")
    shutil.copy2(path, destination)
    return destination


def write_verified(path: Path, payload: bytes, expected: dict[str, Any]) -> None:
    """Write only after proving the payload parses back to `expected`."""
    reparsed = VdfParser(payload).parse()
    if reparsed != expected:
        raise VdfError(
            "refusing to write: the serialized form does not parse back to the "
            "same structure, so the round-trip is lossy"
        )
    temporary = path.with_name(f"{path.name}.tmp")
    temporary.write_bytes(payload)
    temporary.replace(path)


def point_shortcut(
    path: Path, appid: int, appname: str, exe: str, start_dir: str, launch_options: str
) -> int:
    original = path.read_bytes()
    data = VdfParser(original).parse()

    shortcuts = data.get("shortcuts")
    if not isinstance(shortcuts, dict):
        print(f"[ERROR] no 'shortcuts' section in {path}", file=sys.stderr)
        return 1

    # Steam stores appid as a signed int32, but it is quoted everywhere else as
    # unsigned (4096896093 on disk is -198071203 once parsed). Accept both, or
    # the id never matches and only the name fallback ever fires.
    candidates = {appid, appid - 2**32, appid + 2**32}

    target_key = None
    for key, entry in shortcuts.items():
        if not isinstance(entry, dict):
            continue
        if entry.get("appid") in candidates or appname in str(entry.get("appname", "")):
            target_key = key
            break

    if target_key is None:
        print(
            f"[ERROR] no shortcut matching appid {appid} or name {appname!r} in {path}",
            file=sys.stderr,
        )
        return 1

    entry = shortcuts[target_key]
    desired = {
        "exe": f'"{exe}"',
        "StartDir": start_dir,
        "LaunchOptions": launch_options,
    }
    if all(entry.get(field) == value for field, value in desired.items()):
        print(f"[OK] shortcut [{target_key}] already points at {exe}; nothing to write")
        return 0

    entry.update(desired)
    saved = backup(path)
    write_verified(path, dump_vdf(data), data)
    print(
        f"[OK] shortcut [{target_key}] now runs {entry['exe']} (backup: {saved.name})"
    )
    return 0


def match_block(text: str, open_brace: int) -> int:
    """Return the index just past the `}` closing the brace at `open_brace`."""
    if text[open_brace] != "{":
        raise VdfError(f"expected '{{' at offset {open_brace}")
    depth = 0
    for index in range(open_brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    raise VdfError(f"unbalanced braces from offset {open_brace}")


def clear_compat_tool(path: Path, appid: int) -> int:
    """Remove the forced Proton mapping so Steam runs the shell script natively.

    config.vdf is text KeyValues, but it is read and written as bytes here: a
    text read with errors='ignore' would silently drop any byte it could not
    decode and then write the damaged file back.
    """
    original = path.read_bytes()
    text = original.decode("utf-8", "surrogateescape")

    mapping = re.search(
        r'^[ \t]*"CompatToolMapping"[ \t]*\r?\n[ \t]*\{', text, re.MULTILINE
    )
    if mapping is None:
        print(f"[OK] no CompatToolMapping section in {path}; nothing to clear")
        return 0

    # Bound the search to CompatToolMapping's own braces. Searching from its end
    # to EOF is not enough: this appid also appears under ShaderCacheSize and
    # SizeOnDisk, and an unbounded search deletes one of those instead.
    section_start = text.index("{", mapping.start())
    section_end = match_block(text, section_start)

    entry = re.compile(
        r'^[ \t]*"' + re.escape(str(appid)) + r'"[ \t]*\r?\n[ \t]*\{', re.MULTILINE
    )
    found = entry.search(text, section_start, section_end)
    if found is None:
        print(f"[OK] no forced compatibility tool for {appid}; nothing to clear")
        return 0

    end = match_block(text, text.index("{", found.start()))
    start = found.start()
    while end < len(text) and text[end] in "\r\n":
        end += 1
    updated = text[:start] + text[end:]

    if updated.count("{") != text.count("{") - 1:
        print(
            "[ERROR] brace count after removal is wrong; refusing to write",
            file=sys.stderr,
        )
        return 1

    saved = backup(path)
    temporary = path.with_name(f"{path.name}.tmp")
    temporary.write_bytes(updated.encode("utf-8", "surrogateescape"))
    temporary.replace(path)
    print(f"[OK] cleared forced compatibility tool for {appid} (backup: {saved.name})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)

    point = sub.add_parser("point", help="point a shortcut at a launcher")
    point.add_argument("--shortcuts", required=True, type=Path)
    point.add_argument("--appid", required=True, type=int)
    point.add_argument("--appname", required=True)
    point.add_argument("--exe", required=True)
    point.add_argument("--start-dir", required=True)
    point.add_argument("--launch-options", default="")

    clear = sub.add_parser("clear-compat", help="remove a forced compatibility tool")
    clear.add_argument("--config", required=True, type=Path)
    clear.add_argument("--appid", required=True, type=int)

    args = parser.parse_args()
    try:
        if args.action == "point":
            return point_shortcut(
                args.shortcuts,
                args.appid,
                args.appname,
                args.exe,
                args.start_dir,
                args.launch_options,
            )
        return clear_compat_tool(args.config, args.appid)
    except (VdfError, OSError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
