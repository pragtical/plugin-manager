# Pragtical Plugin Manager (ppm)

![Pragtical Plugin Manager](screenshots/plugin-manager.png)

`ppm` manages Pragtical plugins, colors, fonts, and editor installations. It
includes the Plugin Manager UI for searching, filtering, and managing addons.

Both are bundled with official Pragtical releases. Open **Plugin Manager: Show**
from the command palette (`Ctrl+Shift+P`) to use the UI.

The UI plugin requires Pragtical 3.10.0 or later.

Release builds use the manifest from this repository's `latest` branch by default.
See the [changelog](CHANGELOG.md) for release history.

## Installation

Download binaries for your platform from the
[latest release](https://github.com/pragtical/plugin-manager/releases/tag/latest)
or the [continuous build](https://github.com/pragtical/plugin-manager/releases/tag/continuous).

### Windows

Run in PowerShell:

```powershell
Invoke-WebRequest -Uri "https://github.com/pragtical/plugin-manager/releases/download/latest/ppm.x86_64-windows.exe" -OutFile "ppm.exe"
.\ppm.exe install plugin_manager --assume-yes
```

Alternatively, install the standalone binary with Scoop:

```powershell
scoop install https://raw.githubusercontent.com/pragtical/plugin-manager/refs/heads/master/pragtical-plugin-manager.json
```

### Linux And macOS

For Linux x86_64:

```sh
curl -fL https://github.com/pragtical/plugin-manager/releases/download/latest/ppm.x86_64-linux -o ppm
chmod +x ppm
./ppm install plugin_manager --assume-yes
```

For macOS, replace the asset name with `ppm.x86_64-darwin` or
`ppm.aarch64-darwin`. Use `ppm.aarch64-linux` for Linux ARM64.

Restart Pragtical after installing the UI plugin.

## Usage

```sh
ppm list
ppm install editorconfig
ppm uninstall editorconfig
ppm update
ppm upgrade
ppm --help
```

Use `pragtical pm` in place of `ppm` to invoke the editor's bundled binary.
For automated installation, pass `--assume-yes` and `--userdir=<directory>`.

On Linux and macOS, downloads run directly in Plugin Manager. Its status
strip shows bytes received, plus the total and percentage when the server
provides a file size. With no reported size, the bar animates instead.

On Windows to prevent file lock issues, the UI saves your selection and shows
**Pending restart**. Checking or unchecking a pending action does not fetch
repositories, resolve dependencies, or download files. Filter by
**Pending restart** to see your selections, or use **Cancel Pending Changes**
to clear them.

On the next full launch, ppm resolves dependencies, downloads what it needs,
and prepares the whole batch before replacing live plugins. A soft restart
does not apply changes. **Upgrade All** checks repositories at startup;
**Check for Updates** still checks immediately. If preparation fails, the
selection remains editable and live plugins are unchanged.
The startup window shows bytes received during downloads. When the server
provides a file size, it also shows the total and percentage; otherwise
the bar stays animated until the transfer finishes.
If Windows reports that another process is using a
file, the startup window names it and keeps the update queued when safe.
Close the program holding the file (often another editor or language server),
quit all Pragtical instances, and reopen the editor to retry automatically.
On older editors without startup transactions, close Pragtical
and run standalone ppm instead. Plugin Manager itself is not upgraded this way.

### Installed Addons

**Check for Updates** refreshes repository metadata without installing anything.
Known outdated copies appear as **upgradable**, with their installed and available
versions. **Upgrade All** upgrades those copies but skips protected installations:

- **Orphaned**: the installed addon has no matching configured repository.
- **Modified**: files from a tracked installation have been changed locally.
- **Local**: a repository has the addon, but the installed copy cannot be verified.

Use the status filter to find these copies. **Replace** explicitly replaces a
protected copy with the repository version after confirmation. From the CLI, use
`ppm reinstall <id>`. Uninstall remains available for user-owned copies.

Installation versions, sources, and file hashes are stored in
`~/.config/ppm/installations.json` (or `--configdir`), keyed by installation path
so profiles and bottles remain independent. Cache purges do not erase this file.
Older installations are identified from matching payloads or cached Git history,
without fetching history or changing repository checkouts. Unverifiable versions
are shown as `unknown`; JSON output omits `version` and `installed_version` rather
than inventing a version. Extra runtime-generated files are not treated as edits
to the tracked payload.

## Building

Requires a C compiler, Python 3, Meson, Ninja, and Git. Meson uses system
libraries when available and downloads missing dependencies through wraps.

```sh
git clone https://github.com/pragtical/plugin-manager.git
cd plugin-manager
meson setup build --buildtype=release -Dstatic=true
meson compile -C build
./build/ppm --help
```

On Windows, the executable is `build/ppm.exe`. The `static` option embeds the
Lua program so ppm can run without the source tree; it does not make the
executable fully statically linked.

To stage a stripped release binary, enable Meson's install-time stripping:

```sh
meson configure build -Dstrip=true -Dprefix="$PWD/build/install"
meson install -C build
```

The stripped copy is `build/install/bin/ppm` (`ppm.exe` on Windows). The
build-tree executable remains unstripped.

Dependencies are Lua, mbedTLS 4/TF-PSA-Crypto, libgit2, zlib, liblzma, and libzip.
The `microtar` sources are vendored in `lib/microtar/`. No Git submodule checkout
or CMake build is needed.

### Static Dependencies

Build dependencies from the supplied wraps, as CI does:

```sh
meson setup build-fallback --buildtype=release --wrap-mode=forcefallback \
  -Dstatic=true
meson compile -C build-fallback
```

Linux release builds also use `-Dfully_static=true` and a musl compiler to
avoid requiring a dynamic loader on the target system.

### Cross-Compilation

For Windows from Linux, install MinGW-w64 and run:

```sh
meson setup build-windows --buildtype=release --wrap-mode=forcefallback \
  --cross-file=cross/x86_64-w64-mingw32.ini -Dstatic=true
meson compile -C build-windows
```

The output is `build-windows/ppm.exe`. Additional files in `cross/` cover Linux
aarch64/riscv64 musl and Android targets. Put the matching toolchain on `PATH`
before configuring.

## Platforms

| Platform | Architectures |
| --- | --- |
| Windows | x86_64 |
| Linux | x86_64, aarch64, riscv64 (experimental) |
| macOS | x86_64, aarch64 |
| Android 8.0+ | x86_64, x86, aarch64, armv7a |

## Tests

The suites use Pragtical's `core.test` framework. Build ppm, then run them with
a Pragtical build that includes the current Plugin Manager:

```sh
pragtical test tests
```

With the sibling Pragtical checkout, use its isolated local runner:

```sh
cd ../pragtical
SDL_VIDEO_DRIVER=dummy SDL_AUDIO_DRIVER=dummy \
  ./scripts/run-local build test ../plugin-manager/tests
```

Integration fixtures use temporary local repositories and isolated ppm
cache/config directories. Set `PPM_BINARY` to an absolute path to test another
binary; otherwise the suite uses `build/ppm` or the packaged binary. Remote-stub
fixtures require Git, and the multi-architecture symlink test is skipped on
Windows.

## Manifest

See [SPEC.md](SPEC.md) for the manifest format.
`addons.files.extra.chmod_executable` lists files to mark as executable after
download or extraction.

## Bug Reports

Include your operating system, `ppm --version` output, and the commands needed
to reproduce the issue, preferably with a fresh `--userdir`.
