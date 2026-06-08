project('ppm',
    ['c'],
    license : 'PPM',
    version : '1.2.0',
    meson_version : '>= 0.56',
)

cc = meson.get_compiler('c')

wrap_mode = get_option('wrap_mode')
force_all_fallbacks = wrap_mode == 'forcefallback'

use_static_deps = force_all_fallbacks

zlib_dep = dependency('zlib', static: use_static_deps, fallback: ['zlib', 'zlib_dep'])
lzma_dep = dependency('liblzma', static: use_static_deps, fallback: ['liblzma', 'lzma_dep'])
lua_dep = dependency('lua', static: use_static_deps, fallback: ['lua', 'lua_dep'])
mbedtls_dep = [
    dependency('mbedtls', static: use_static_deps, fallback: ['mbedtls', 'mbedtls_dep']),
    dependency('mbedx509', static: use_static_deps, fallback: ['mbedtls', 'mbedx509_dep']),
    dependency('mbedcrypto', static: use_static_deps, fallback: ['mbedtls', 'tfpsacrypto_dep']),
]
libgit2_dep = dependency('libgit2', static: use_static_deps, fallback: ['libgit2', 'libgit2_dep'])
libzip_dep = dependency('libzip', static: use_static_deps, fallback: ['libzip', 'zip_dep'])

microtar_lib = static_library('microtar', files('lib/microtar/src/microtar.c'))
microtar_dep = declare_dependency(
    link_whole: [microtar_lib],
    include_directories: ['lib/microtar/src']
)

ppm_source = files('src/ppm.c')
cflags = []
ppm_release_version = get_option('release_version')
ppm_full_version = get_option('full_version')
ppm_target_arch = get_option('target_arch')
ppm_binary_name = get_option('binary_name')

if ppm_release_version == ''
    ppm_release_version = meson.project_version()
endif

if ppm_full_version == ''
    ppm_full_version = ppm_release_version
endif

ppm_version = ppm_full_version
if ppm_target_arch != ''
    ppm_version += '-' + ppm_target_arch
endif

if ppm_binary_name == ''
    ppm_binary_name = 'ppm'
endif

cflags += '-DPPM_VERSION="@0@"'.format(ppm_version)

if get_option('static')
    python = import('python').find_installation()

    ppm_source += configure_file(
        capture: false,
        command: [
            python,
            files('tools/embed_lua_source.py'),
            '@INPUT0@',
            '@OUTPUT0@'
        ],
        input: files('src/ppm.lua'),
        output: 'ppm.lua.c'
    )
    cflags += '-DPPM_STATIC'
endif

ppm_exe = executable(ppm_binary_name,
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
