**Warning:** This repository could be regularly rebased

# Pragtical Plugin Manager (ppm)

![image](https://user-images.githubusercontent.com/1034518/216748882-3ae8c8d4-a767-4d97-acc4-c1cde7e3e331.png)

A standalone binary that provides an easy way of installing, and uninstalling
plugins from pragtical, as well as different version of pragtical.

Can be used by a package manager plugin that works from inside the editor
and calls this binary.

Also contains a `plugin_manager.lua` plugin to integrate the binary with pragtical in
the form of an easy-to-use GUI.

By default in releases, `ppm` will automatically consume the `manifest.json`
in the `latest` branch of this repository, which corresponds to the most
recent versioned release.

Conforms to [SCPS3](https://github.com/adamharrison/straightforward-c-project-standard#SCPS3).

## Status

`ppm` 1.0 has been just released, and so may still contain bugs, but is generally feature-complete.

## Specification

For details about the `manifest.json` files that `ppm` consumes,
[see here](SPEC.md).

## Quickstart

The fastest way to get started with ppm is to simply pull a release.

```
wget https://github.com/pragtical/plugin-manager/releases/download/latest/ppm.x86_64-linux -O ppm && chmod +x ppm
```

If you want to get the GUI version installed with pragtical, you can tell `ppm` to install `plugin_manager`, which will allow
you to access `Plugin Manager: Show` in the command palette in `pragtical`.

```
./ppm install plugin_manager --assume-yes
```

### Compilation

If you have a C compiler, and `git`, and want to compile from scratch,
you can do:

```
git clone https://github.com/pragtical/plugin-manager.git \
  --shallow-submodules --recurse-submodules && cd plugin-manager &&\
  ./build.sh -DPPM_STATIC && ./ppm
````

If you want to build it quickly, and have the right modules installed, you can
do:

```
./build.sh -lgit2 -lzip -llua -lm -lmbedtls -lmbedx509 -lmbedcrypto -lz -DPPM_STATIC
```

OR

```
gcc src/ppm.c lib/microtar/src/microtar.c -Ilib/microtar/src -lz -lgit2 \
  -lzip -llua -lm -lmbedtls -lmbedx509 -lmbedcrypto -o ppm
```

CI is enabled on this repository, so you can grab Windows and Linux builds from the
`continuous` [release page](https://github.com/pragtical/plugin-manager/releases/tag/continuous),
which is a nightly, or the `latest` [release page](https://github.com/pragtical/plugin-manager/releases/tag/latest),
which holds the most recent released version.

There are also tagged releases, for specified versions.

You can get a feel for how to use `ppm` by typing `./ppm --help`.

You can also use `scoop` to grab `ppm`, courtesy of @cvladan:

```
scoop install https://gist.githubusercontent.com/cvladan/416c1945c9e446a6fc64ba766d6ee4ef/raw/plugin-manager.json
```

## Supporting Libraries / Dependencies

As seen in the `lib` folder, the following external libraries are used to
build `ppm` as git submodules:

* `lua` (core program written in)
* `mbedtls` (https/SSL support)
* `libgit2` (accessing git repositories directly)
* `libz` (supporting library for everything)
* `libzip` (for unpacking .zip files)
* `libmicrotar` (for unpacking .tar.gz files)

To build, `ppm` only requires a C compiler. To run the underlying build process
for `mbedtls` and `libgit2`, `cmake` is also required.

## Supported Platforms

`ppm` should work on all platforms `pragtical` works on; but releases are offered for the following:

* Windows x86_64
* Linux x86_64
* Linux aarch64
* MacOS x86_64
* MacOS aarch64
* Android 8.0+ x86_64
* Android 8.0+ x86
* Android 8.0+ aarch64
* Android 8.0+ armv7a

Experimental support (i.e. doesn't work) exists for the following platforms:

* Linux riscv64

## Use in CI

To make pre-fab pragtical builds, you can easily use `ppm` in CI. If you had a linux build container, you could do something like:

```sh
curl https://github.com/pragtical/plugin-manager/releases/download/v0.1/ppm.x86_64-linux > ppm
export PRAGTICAL_USERDIR=pragtical/data && export PPM_CACHE=/tmp/cache
./ppm add https://github.com/pragtical/plugin-manager && ./ppm install plugin_manager lsp
```

## Usage

```sh
ppm install aligncarets
ppm uninstall aligncarets
```

```sh
ppm --help
```

## Building & Running

### Linux & MacOS & Windows MSYS

```
./build.sh clean && ./build.sh -DPPM_STATIC && ./ppm
```

### Linux -> Windows

```
./build.sh clean && CC=x86_64-w64-mingw32-gcc AR=x86_64-w64-mingw32-gcc-ar WINDRES=x86_64-w64-mingw32-windres \
CMAKE_DEFAULT_FLAGS="-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER\ -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=NEVER -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_INCLUDE_PATH=/usr/share/mingw-w64/include"\
  GIT2_CONFIGURE="-DDLLTOOL=x86_64-w64-mingw32-dlltool" ./build.sh -DPPM_STATIC -DPPM_VERSION='"'$VERSION-x86_64-windows-`git rev-parse --short HEAD`'"'
```

## Tests

To run the test suite, you can use `ppm` to execute the test by doing `./ppm test t/run.lua`. use `FAST=1 ./ppm test t/run.lua` to avoid the costs of tearing down and building up suites each time.

## Extra Features

### Bottles

### Extra Fields

* `addons.files.extra.chmod_executable`

An array of files to be marked as executable (after extraction, if applicable).

## Bugs

If you find a bug, please create an issue with the following information:

* Your operating system.
* The commit or version of PPM you're using (`ppm --version` for releases).
* The exact steps to reproduce in PPM invocations, if possible from a fresh PPM install (targeting an empty folder with `--userdir`).
