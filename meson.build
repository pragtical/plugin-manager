project('ppm',
    ['c'],
    license : 'PPM',
    version : '1.2.0',
    meson_version : '>= 0.56',
)

cc = meson.get_compiler('c')

zlib_dep = dependency('zlib')
lzma_dep = dependency('liblzma')
libgit2_dep = dependency('libgit2')
libzip_dep = dependency('libzip')
lua_dep = dependency('lua')
mbedtls_dep = [
    dependency('mbedtls'),
    dependency('mbedx509'),
    dependency('mbedcrypto'),
]

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
