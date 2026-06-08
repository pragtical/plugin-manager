#!/usr/bin/env python3
import sys


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: embed_lua_source.py input output")

    with open(sys.argv[1], "rb") as source_file:
        source = source_file.read()

    with open(sys.argv[2], "w", encoding="ascii") as output_file:
        output_file.write("const char ppm_luac[] = {\n")
        for index in range(0, len(source), 16):
            chunk = source[index:index + 16]
            values = ", ".join(str(byte) for byte in chunk)
            output_file.write("  " + values + ",\n")
        output_file.write("  0\n")
        output_file.write("};\n")
        output_file.write("unsigned int ppm_luac_len = sizeof(ppm_luac) - 1;\n")


if __name__ == "__main__":
    main()
