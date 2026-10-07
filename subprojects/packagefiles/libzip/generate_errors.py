#!/usr/bin/env python3
import json
from pathlib import Path
import re
import sys


def error_table(path, prefix, types, name):
    pattern = re.compile(
        r'^#define ' + prefix + r'[A-Z0-9_]+\s+(\d+)\s+/\*\s+(['
        + types + r'])\s+(.+?)\s*\*/$', re.MULTILINE
    )
    entries = pattern.findall(Path(path).read_text(encoding="utf-8"))
    if not entries or [int(entry[0]) for entry in entries] != list(range(len(entries))):
        raise ValueError(f"{path}: expected contiguous {prefix} error definitions")
    rows = [f'    {{ {kind}, {json.dumps(message)} }},' for _, kind, message in entries]
    return (
        f"const struct _zip_err_info {name}[] = {{\n"
        + "\n".join(rows)
        + f"\n}};\n\nconst int {name}_count = sizeof({name}) / sizeof({name}[0]);\n"
    )


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: generate_errors.py zip.h zipint.h output.c")
    contents = (
        '/* Generated from zip.h and zipint.h by Meson. */\n\n#include "zipint.h"\n\n'
        '#define L ZIP_ET_LIBZIP\n#define N ZIP_ET_NONE\n'
        '#define S ZIP_ET_SYS\n#define Z ZIP_ET_ZLIB\n'
        '#define E ZIP_DETAIL_ET_ENTRY\n#define G ZIP_DETAIL_ET_GLOBAL\n\n'
        + error_table(sys.argv[1], "ZIP_ER_", "LNSZ", "_zip_err_str") + "\n"
        + error_table(sys.argv[2], "ZIP_ER_DETAIL_", "EG", "_zip_err_details")
    )
    Path(sys.argv[3]).write_text(contents, encoding="ascii")


if __name__ == "__main__":
    main()
