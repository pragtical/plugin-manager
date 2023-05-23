project('ppm',
    ['c'],
    license : 'PPM',
    version : '1.2.0',
    meson_version : '>= 0.56',
)

cc = meson.get_compiler('c')

zlib_dep = dependency('zlib')
mbedtls_dep = dependency('mbedtls', version: '<3', required: false)
libgit2_dep = dependency('libgit2')
libzip_dep = dependency('libzip')
lua_dep = dependency('lua')

if not mbedtls_dep.found()
    # Using has_headers to distinguish between mbedtls2 and mbedtls3
    _mbedtls_dep = cc.find_library('mbedtls', has_headers: 'mbedtls/net.h', required: false)
    if _mbedtls_dep.found()
        mbedtls_dep = [
            _mbedtls_dep,
            cc.find_library('mbedx509'),
            cc.find_library('mbedcrypto'),
        ]
    else
        # In some cases we need to manually specify where to find mbedtls2
        message('Using fallback mbedtls definition')
        mbedtls_dep = declare_dependency(
            include_directories: ['/usr/include/mbedtls2/'],
            link_args: ['-L/usr/lib/mbedtls2', '-lmbedtls', '-lmbedx509', '-lmbedcrypto']
        )
    endif
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
        command: [lua_exe, '-e', 'f = string.dump(assert(loadfile("@INPUT0@"))) io.open("@OUTPUT0@", "wb"):write("unsigned char ppm_luac[] = \"" .. f:gsub(".", function (c) return string.format("\\\x%02X",string.byte(c)) end) .. "\";unsigned int ppm_luac_len = " .. #f .. ";")'],
        input: files('src/ppm.lua'),
        output: 'ppm.lua.c'
    )
    cflags += '-DPPM_STATIC'
endif

executable('ppm', ppm_source, dependencies: [zlib_dep, mbedtls_dep, libgit2_dep, libzip_dep, lua_dep, microtar_dep], c_args: cflags)
