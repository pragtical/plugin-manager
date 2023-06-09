# 1.0.5

* Marked `lpm` for `plugin_manager` as optional.
* Made `--help` and `help` output on `stdout`, rather than `stderr`, following convention.
* Removed system configuration search paths for `git`.
* Removed `xxd` as a build dependency.
* Colorized some extra messages.
* Made repository fetching atomic.
* Made sure that `common.path` checked for executability and non-folderness.
* Added in meson as a build system (thank you @Jan200101).

# 1.0.4

* Added in metapackage support into manifest and SPEC.
* Fixed issue with system lite-xls not being detected correctly.
* Colorized output by default.
* Added in NO_COLOR standard.
* Updated SPEC and fixed a few spelling/grammatical errors.

# 1.0.3

* Fixed a major issue with windows that causes a crash.
* Ensured that the simplified releases are pointing to the right place.

# 1.0.2

* Suppresses the progress bar by default if we're not on a TTY.
* Added `url` as a field to `SPEC.md`.
* Modified `run` so that it'll use the system version if you don't specify one.
* Added the ability to specify a repo url as part of `run`, so you can easily test new plugin branches and their plugins without actually modifying your ppm state.
* Fixed a few typos.
* Fixed issue with `run` not handling cases where plugins were either orphaned or core plugins, which would cause the bottle to be incorrectly constructed.
* Fixed issue where you could add non-numeric pragtical versions.
* Fixed issue where tables generated with ppm didn't annotate non-remote url plugins with \*.
* Fixed a memory leak.
* Added in warning to let people know when stubs are mismatching versions.
* Added in warning when we cannot acquire an ppm global lock, and also made it so we do not lock upon running something.
* Better error handling for invalid manifests, specifically when paths for plugins don't exist.
* Fixed issue with permissions not being recorded correctly when extracting from a zip file.
* Added in --reinstall flag.


# 1.0.1

* Fixed an issue with --no-install-optional being non-functional.
* Modified fopen calls to use `_wfopen` where appropriate to improve UTF-8 support on windows.
* Fixed some defaults around specifiying explicit binaries and datadirs for certain pathways.
* Added this CHANGELOG.md.

# 1.0.0

Initial release of `ppm`.

```
Usage: ppm COMMAND [...ARGUMENTS] [--json] [--userdir=directory]
  [--cachedir=directory] [--quiet] [--version] [--help] [--remotes]
  [--ssl-certs=directory/file] [--force] [--arch=x86_64-linux]
  [--assume-yes] [--no-install-optional] [--verbose] [--mod-version=3]
  [--datadir=directory] [--binary=path] [--symlink] [--post]

PPM is a package manager for `pragtical`, written in C (and packed-in lua).

It's designed to install packages from our central github repository (and
affiliated repositories), directly into your pragtical user directory. It can
be called independently, for from the pragtical `addon_manager` addon.

PPM will always use https://github.com/pragtical/plugin-manager as its base
repository, if none are present, and the cache directory does't exist,
but others can be added, and this base one can be removed.

It has the following commands:

  ppm init [repo 1] [repo 2] [...]         Implicitly called before all commands
                                           if necessary, but can be called
                                           independently to save time later, or
                                           to set things up differently.

                                           Adds the built in repository to your
                                           repository list, and all `remotes`.

                                           If repo 1 ... is specified, uses that
                                           list of repositories as the base instead.

                                           If "none" is specified, initializes
                                           an empty repository list.

  ppm repo list                            List all extant repos.
  ppm [repo] add <repository remote>       Add a source repository.
    [...<repository remote>]
  ppm [repo] rm <repository remote>        Remove a source repository.
    [...<repository remote>]
  ppm [repo] update [<repository remote>]  Update all/the specified repos.
    [...<repository remote>]
  ppm [plugin|library|color] install       Install specific addons.
    <addon id>[:<version>]                 If installed, upgrades.
    [...<addon id>:<version>]
  ppm [plugin|library|color] uninstall     Uninstall the specific addon.
    <addon id> [...<addon id>]
  ppm [plugin|library|color] reinstall     Uninstall and installs the specific addon.
   <addon id> [...<addon id>]

  ppm [plugin|library|color] list          List all/associated addons.
   <remote> [...<remote>]

  ppm upgrade                              Upgrades all installed addons
                                           to new version if applicable.
  ppm [pragtical] install <version>          Installs pragtical. Infers the
    [binary] [datadir]                     paths on your system if not
                                           supplied. Automatically
                                           switches to be your system default
                                           if path auto inferred.
  ppm pragtical add <version> <path>         Adds a local version of pragtical to
                                           the managed list, allowing it to be
                                           easily bottled.
  ppm pragtical remove <path>                Removes a local version of pragtical
                                           from the managed list.
  ppm [pragtical] switch <version> [<path>]  Sets the active version of pragtical
                                           to be the specified version. Auto-detects
                                           current install of pragtical; if none found
                                           path can be specified.
  ppm pragtical list [name pattern]          Lists all installed versions of
     [...filters]                          pragtical. Can specify the flags listed
                                           in the filtering seciton.
  ppm run <version> [...addons]            Sets up a "bottle" to run the specified
                                           pragtical version, with the specified addons
                                           and then opens it.
  ppm describe [bottle]                    Describes the bottle specified in the form
                                           of a list of commands, that allow someone
                                           else to run your configuration.
  ppm table <manifest path> [readme path]  Formats a markdown table of all specified
                                           addons. Dumps to stdout normally, but if
                                           supplied a readme, will remove all tables
                                           from the readme, and append the new one.

  ppm purge                                Completely purge all state for PPM.
  ppm -                                    Read these commands from stdin in
                                           an interactive print-eval loop.
  ppm help                                 Displays this help text.


Flags have the following effects:

  --json                   Performs all communication in JSON.
  --userdir=directory      Sets the pragtical userdir manually.
                           If omitted, uses the normal pragtical logic.
  --cachedir=directory     Sets the directory to store all repositories.
  --tmpdir=directory       During install, sets the staging area.
  --datadir=directory      Sets the data directory where core addons are located
                           for the system pragtical.
  --binary=path            Sets the pragtical binary path for the system pragtical.
  --verbose                Spits out more information, including intermediate
                           steps to install and whatnot.
  --quiet                  Outputs nothing but explicit responses.
  --mod-version=version    Sets the mod version of pragtical to install addons.
  --version                Returns version information.
  --help                   Displays this help text.
  --ssl-certs              Sets the SSL certificate store. Can be a directory,
                           or path to a certificate bundle.
  --arch=architecture      Sets the architecture (default: x86_64-linux).
  --assume-yes             Ignores any prompts, and automatically answers yes
                           to all.
  --no-install-optional    On install, anything marked as optional
                           won't prompt.
  --trace                  Dumps to STDERR useful debugging information, in
                           particular information relating to SSL connections,
                           and other network activity.
  --progress               For JSON mode, lines of progress as JSON objects.
                           By default, JSON does not emit progress lines.
  --symlink                Use symlinks where possible when installing modules.
                           If a repository contains a file of the same name as a
                           `files` download in the primary directory, will also
                           symlink that, rather than downloading.

The following flags are useful when listing plugins, or generating the plugin
table. Putting a ! infront of the string will invert the filter. Multiple
filters of the same type can be specified to create an OR relationship.

  --author=author          Only display addons by the specified author.
  --tag=tag                Only display addons with the specified tag.
  --stub=git/file/false    Only display the specified stubs.
  --dependency=dep         Only display addons that have a dependency on the
                           specified addon.
  --status=status          Only display addons that have the specified status.
  --type=type              Only display addons on the specified type.
  --name=name              Only display addons that have a name which matches the
                           specified filter.

There also several flags which are classified as "risky", and are never enabled
in any circumstance unless explicitly supplied.

  --force                  Ignores checksum inconsistencies.
  --post                   Run post-install build steps. Must be explicitly enabled.
                           Official repositories must function without this
                           flag being needed; generally they must provide
                           binaries if there is a native compilation step.
  --remotes                Automatically adds any specified remotes in the
                           repository to the end of the resolution list.
  --ssl-certs=noverify     Ignores SSL certificate validation. Opens you up to
                           man-in-the-middle attacks.

There exist also other debug commands that are potentially useful, but are
not commonly used publically.

  ppm test [test file]               Runs the specified test suite.
  ppm table <manifest> [...filters]  Generates markdown table for the given
                                     manifest. Used by repositories to build
                                     READMEs.
  ppm download <url> [target]        Downloads the specified URL to stdout,
                                     or to the specified target file.
  ppm extract <file.[tar.gz|zip]>    Extracts the specified archive at
    [target]                         target, or the current working directory.
```
