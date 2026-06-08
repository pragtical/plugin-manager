project('ppm',
    ['c'],
    license : 'PPM',
    version : '1.2.0',
    meson_version : '>= 0.56',
)

cc = meson.get_compiler('c')
cmake = import('cmake')

wrap_mode = get_option('wrap_mode')
force_fallback_for = get_option('force_fallback_for')
force_all_fallbacks = wrap_mode == 'forcefallback'

use_static_deps = force_all_fallbacks

subprojects_source_root = meson.project_source_root() / 'subprojects'
subprojects_build_root = meson.project_build_root() / 'subprojects'
zlib_source_dir = subprojects_source_root / 'zlib-1.3.2'
zlib_build_dir = subprojects_build_root / 'zlib-1.3.2'
lzma_source_dir = subprojects_source_root / 'xz-5.2.12'
lzma_build_dir = subprojects_build_root / 'xz-5.2.12'
mbedtls_source_dir = subprojects_source_root / 'mbedtls-4.1.0'
mbedtls_build_dir = subprojects_build_root / 'mbedtls-4.1.0'

zlib_dep = dependency('zlib', static: use_static_deps, fallback: ['zlib', 'zlib_dep'])
lzma_dep = dependency('liblzma', static: use_static_deps, fallback: ['liblzma', 'lzma_dep'])
lua_dep = dependency('lua', static: use_static_deps, fallback: ['lua', 'lua_dep'])
mbedtls_dep = [
    dependency('mbedtls', static: use_static_deps, fallback: ['mbedtls', 'mbedtls_dep']),
    dependency('mbedx509', static: use_static_deps, fallback: ['mbedtls', 'mbedx509_dep']),
    dependency('mbedcrypto', static: use_static_deps, fallback: ['mbedtls', 'tfpsacrypto_dep']),
]

use_libgit2_fallback = force_all_fallbacks or 'libgit2' in force_fallback_for
libgit2_dep = disabler()
if not use_libgit2_fallback
    libgit2_dep = dependency('libgit2', static: use_static_deps, required: false)
endif
if use_libgit2_fallback or not libgit2_dep.found()
    libgit2_opts = cmake.subproject_options()
    libgit2_opts.add_cmake_defines({
        'BUILD_SHARED_LIBS': 'OFF',
        'BUILD_TESTS': 'OFF',
        'BUILD_CLI': 'OFF',
        'BUILD_EXAMPLES': 'OFF',
        'BUILD_FUZZERS': 'OFF',
        'BUILD_REFTABLE': 'OFF',
        'REGEX_BACKEND': 'builtin',
        'USE_HTTPS': 'mbedTLS',
        'USE_NTLMCLIENT': 'OFF',
        'USE_SHA1': 'CollisionDetection',
        'USE_SHA256': 'builtin',
        'USE_SSH': 'OFF',
        'USE_HTTP_PARSER': 'builtin',
    })
    libgit2_cflags = []
    if force_all_fallbacks or 'mbedtls' in force_fallback_for or 'mbedx509' in force_fallback_for or 'mbedcrypto' in force_fallback_for
        libgit2_cflags += [
            '-I' + mbedtls_source_dir / 'include',
            '-I' + mbedtls_source_dir / 'tf-psa-crypto' / 'include',
            '-I' + mbedtls_source_dir / 'tf-psa-crypto' / 'drivers' / 'builtin' / 'include',
        ]
        libgit2_opts.add_cmake_defines({
            'MBEDTLS_INCLUDE_DIR': mbedtls_source_dir / 'include',
            'MBEDTLS_EXTRA_INCLUDE_DIRS': ';'.join([
                mbedtls_source_dir / 'tf-psa-crypto' / 'include',
                mbedtls_source_dir / 'tf-psa-crypto' / 'drivers' / 'builtin' / 'include',
            ]),
            'MBEDTLS_LIBRARY': mbedtls_build_dir / 'libmbedtls.a',
            'MBEDX509_LIBRARY': mbedtls_build_dir / 'libmbedx509.a',
            'MBEDCRYPTO_LIBRARY': mbedtls_build_dir / 'libtfpsacrypto.a',
        })
    endif
    if force_all_fallbacks or 'zlib' in force_fallback_for
        libgit2_cflags += ['-I' + zlib_source_dir]
        libgit2_opts.add_cmake_defines({
            'ZLIB_INCLUDE_DIR': zlib_source_dir,
            'ZLIB_LIBRARY': zlib_build_dir / 'libz.a',
        })
    endif
    if libgit2_cflags.length() > 0
        libgit2_opts.add_cmake_defines({
            'CMAKE_C_FLAGS': ' '.join(libgit2_cflags),
        })
    endif
    libgit2_proj = cmake.subproject('libgit2', options: libgit2_opts)
    libgit2_dep = libgit2_proj.dependency('libgit2package')
endif

use_libzip_fallback = force_all_fallbacks or 'libzip' in force_fallback_for
libzip_dep = disabler()
if not use_libzip_fallback
    libzip_dep = dependency('libzip', static: use_static_deps, required: false)
endif
if use_libzip_fallback or not libzip_dep.found()
    libzip_opts = cmake.subproject_options()
    libzip_opts.add_cmake_defines({
        'BUILD_SHARED_LIBS': 'OFF',
        'BUILD_TOOLS': 'OFF',
        'BUILD_REGRESS': 'OFF',
        'BUILD_EXAMPLES': 'OFF',
        'BUILD_DOC': 'OFF',
        'LIBZIP_DO_INSTALL': 'OFF',
        'ENABLE_COMMONCRYPTO': 'OFF',
        'ENABLE_GNUTLS': 'OFF',
        'ENABLE_MBEDTLS': 'OFF',
        'ENABLE_OPENSSL': 'OFF',
        'ENABLE_WINDOWS_CRYPTO': 'OFF',
        'ENABLE_BZIP2': 'OFF',
        'ENABLE_LZMA': 'OFF',
        'ENABLE_ZSTD': 'OFF',
    })
    libzip_cflags = []
    if force_all_fallbacks or 'zlib' in force_fallback_for
        libzip_cflags += ['-I' + zlib_source_dir]
        libzip_opts.add_cmake_defines({
            'ZLIB_INCLUDE_DIR': zlib_source_dir,
            'ZLIB_LIBRARY': zlib_build_dir / 'libz.a',
        })
    endif
    if libzip_cflags.length() > 0
        libzip_opts.add_cmake_defines({
            'CMAKE_C_FLAGS': ' '.join(libzip_cflags),
        })
    endif
    libzip_proj = cmake.subproject('libzip', options: libzip_opts)
    libzip_dep = libzip_proj.dependency('zip')
endif

microtar_lib = static_library('microtar', files('lib/microtar/src/microtar.c'))
microtar_dep = declare_dependency(
    link_whole: [microtar_lib],
    include_directories: ['lib/microtar/src']
)

ppm_source = files('src/ppm.c')
cflags = []
if get_option('static')
    lua_exe = find_program('lua')

    ppm_source += configure_file(
        capture: false,
        command: [lua_exe, '-e', 'f = string.dump(assert(load(io.lines("@INPUT0@", "L"), "=ppm.lua"))) io.open("@OUTPUT0@", "wb"):write("unsigned char ppm_luac[] = \"" .. f:gsub(".", function (c) return string.format("\\\x%02X",string.byte(c)) end) .. "\";unsigned int ppm_luac_len = " .. #f .. ";")'],
        input: files('src/ppm.lua'),
        output: 'ppm.lua.c'
    )
    cflags += '-DPPM_STATIC'
endif

ppm_exe = executable('ppm',
    ppm_source,
    dependencies: [
        zlib_dep,
        lzma_dep,
        mbedtls_dep,
        libgit2_dep,
        libzip_dep,
        lua_dep,
        microtar_dep
    ],
    c_args: cflags,
    install: true,
)

if (get_option('install_plugin'))
    pragtical_datadir = get_option('pragtical_datadir')
    if pragtical_datadir == ''
        # No path given, assume a default
        pragtical_datadir = get_option('datadir') + '/pragtical'
    endif

    install_subdir('plugins', install_dir : pragtical_datadir)
endif
