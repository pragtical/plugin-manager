# SPDX-License-Identifier: 0BSD
project('liblzma', 'c', version: '5.8.4', license: '0BSD',
  meson_version: '>=0.56.0', default_options: ['c_std=c99'])

cc = meson.get_compiler('c')
is_windows = host_machine.system() == 'windows'
feature_args = cc.get_supported_arguments('-D_GNU_SOURCE')
config = configuration_data()

foreach header : ['stdint.h', 'inttypes.h', 'stdbool.h', 'sys/param.h', 'byteswap.h']
  config.set('HAVE_' + header.underscorify().to_upper(), cc.has_header(header))
endforeach
config.set('HAVE__BOOL', cc.has_type('_Bool'))
config.set('HAVE_UINTPTR_T', cc.has_type('uintptr_t', prefix: '#include <stdint.h>'))
config.set('SIZEOF_SIZE_T', cc.sizeof('size_t', prefix: '#include <stddef.h>'))
config.set('HAVE_VISIBILITY', cc.has_function_attribute('visibility') ? 1 : 0)
if host_machine.endian() == 'big'
  config.set('WORDS_BIGENDIAN', 1)
endif
foreach bits : ['16', '32', '64']
  if cc.has_header_symbol('byteswap.h', 'bswap_' + bits)
    config.set('HAVE_BSWAP_' + bits, 1)
  endif
endforeach
if cc.has_function('__builtin_bswap16') and cc.has_function('__builtin_bswap32') and cc.has_function('__builtin_bswap64')
  config.set('HAVE___BUILTIN_BSWAPXX', 1)
endif
if cc.has_function('__builtin_assume_aligned')
  config.set('HAVE___BUILTIN_ASSUME_ALIGNED', 1)
endif

foreach check : ['crc32', 'crc64', 'sha256']
  config.set('HAVE_CHECK_' + check.to_upper(), 1)
endforeach
config.set('HAVE_ENCODERS', 1)
config.set('HAVE_DECODERS', 1)
foreach filter : ['lzma1', 'lzma2', 'delta', 'x86', 'arm', 'armthumb', 'arm64', 'powerpc', 'ia64', 'sparc', 'riscv']
  config.set('HAVE_ENCODER_' + filter.to_upper(), 1)
  config.set('HAVE_DECODER_' + filter.to_upper(), 1)
endforeach
foreach finder : ['hc3', 'hc4', 'bt2', 'bt3', 'bt4']
  config.set('HAVE_MF_' + finder.to_upper(), 1)
endforeach
config.set('HAVE_MICROLZMA_ENCODER', 1)
config.set('HAVE_MICROLZMA_DECODER', 1)
config.set('HAVE_LZIP_DECODER', 1)

platform_deps = []
if is_windows
  config.set('MYTHREAD_VISTA', 1)
else
  thread_dep = dependency('threads')
  platform_deps += thread_dep
  config.set('MYTHREAD_POSIX', 1)
  has_clock_gettime = cc.has_function('clock_gettime', prefix: '#include <time.h>', args: feature_args)
  if not has_clock_gettime
    rt_dep = cc.find_library('rt', required: false)
    if rt_dep.found() and cc.has_function('clock_gettime', prefix: '#include <time.h>', args: feature_args, dependencies: rt_dep)
      platform_deps += rt_dep
      has_clock_gettime = true
    endif
  endif
  if has_clock_gettime
    config.set('HAVE_CLOCK_GETTIME', 1)
    if cc.has_header_symbol('time.h', 'CLOCK_MONOTONIC', args: feature_args)
      config.set('HAVE_CLOCK_MONOTONIC', 1)
    endif
  endif
  if cc.has_function('pthread_condattr_setclock', prefix: '#include <pthread.h>', args: feature_args, dependencies: thread_dep)
    config.set('HAVE_PTHREAD_CONDATTR_SETCLOCK', 1)
  endif

  if cc.has_function('sched_getaffinity', args: feature_args) and cc.has_header_symbol('sched.h', 'CPU_COUNT', args: feature_args)
    config.set('TUKLIB_CPUCORES_SCHED_GETAFFINITY', 1)
  elif cc.has_header_symbol('unistd.h', '_SC_NPROCESSORS_ONLN')
    config.set('TUKLIB_CPUCORES_SYSCONF', 1)
  elif cc.has_header_symbol('sys/sysctl.h', 'HW_NCPU', prefix: '#include <sys/types.h>')
    config.set('TUKLIB_CPUCORES_SYSCTL', 1)
  endif
  if cc.has_header_symbol('unistd.h', '_SC_PHYS_PAGES') and cc.has_header_symbol('unistd.h', '_SC_PAGESIZE')
    config.set('TUKLIB_PHYSMEM_SYSCONF', 1)
  elif cc.has_header_symbol('sys/sysctl.h', 'HW_PHYSMEM', prefix: '#include <sys/types.h>')
    config.set('TUKLIB_PHYSMEM_SYSCTL', 1)
  endif
endif

configure_file(output: 'config.h', configuration: config)

# Mirror the library sources enabled by upstream CMake's default configuration.
lzma_sources = files(
  'src/common/tuklib_cpucores.c',
  'src/common/tuklib_physmem.c',
  'src/liblzma/check/check.c',
  'src/liblzma/check/crc32_fast.c',
  'src/liblzma/check/crc64_fast.c',
  'src/liblzma/check/sha256.c',
  'src/liblzma/common/alone_decoder.c',
  'src/liblzma/common/alone_encoder.c',
  'src/liblzma/common/auto_decoder.c',
  'src/liblzma/common/block_buffer_decoder.c',
  'src/liblzma/common/block_buffer_encoder.c',
  'src/liblzma/common/block_decoder.c',
  'src/liblzma/common/block_encoder.c',
  'src/liblzma/common/block_header_decoder.c',
  'src/liblzma/common/block_header_encoder.c',
  'src/liblzma/common/block_util.c',
  'src/liblzma/common/common.c',
  'src/liblzma/common/easy_buffer_encoder.c',
  'src/liblzma/common/easy_decoder_memusage.c',
  'src/liblzma/common/easy_encoder.c',
  'src/liblzma/common/easy_encoder_memusage.c',
  'src/liblzma/common/easy_preset.c',
  'src/liblzma/common/file_info.c',
  'src/liblzma/common/filter_buffer_decoder.c',
  'src/liblzma/common/filter_buffer_encoder.c',
  'src/liblzma/common/filter_common.c',
  'src/liblzma/common/filter_decoder.c',
  'src/liblzma/common/filter_encoder.c',
  'src/liblzma/common/filter_flags_decoder.c',
  'src/liblzma/common/filter_flags_encoder.c',
  'src/liblzma/common/hardware_cputhreads.c',
  'src/liblzma/common/hardware_physmem.c',
  'src/liblzma/common/index.c',
  'src/liblzma/common/index_decoder.c',
  'src/liblzma/common/index_encoder.c',
  'src/liblzma/common/index_hash.c',
  'src/liblzma/common/lzip_decoder.c',
  'src/liblzma/common/microlzma_decoder.c',
  'src/liblzma/common/microlzma_encoder.c',
  'src/liblzma/common/outqueue.c',
  'src/liblzma/common/stream_buffer_decoder.c',
  'src/liblzma/common/stream_buffer_encoder.c',
  'src/liblzma/common/stream_decoder.c',
  'src/liblzma/common/stream_decoder_mt.c',
  'src/liblzma/common/stream_encoder.c',
  'src/liblzma/common/stream_encoder_mt.c',
  'src/liblzma/common/stream_flags_common.c',
  'src/liblzma/common/stream_flags_decoder.c',
  'src/liblzma/common/stream_flags_encoder.c',
  'src/liblzma/common/string_conversion.c',
  'src/liblzma/common/vli_decoder.c',
  'src/liblzma/common/vli_encoder.c',
  'src/liblzma/common/vli_size.c',
  'src/liblzma/delta/delta_common.c',
  'src/liblzma/delta/delta_decoder.c',
  'src/liblzma/delta/delta_encoder.c',
  'src/liblzma/lz/lz_decoder.c',
  'src/liblzma/lz/lz_encoder.c',
  'src/liblzma/lz/lz_encoder_mf.c',
  'src/liblzma/lzma/fastpos_table.c',
  'src/liblzma/lzma/lzma2_decoder.c',
  'src/liblzma/lzma/lzma2_encoder.c',
  'src/liblzma/lzma/lzma_decoder.c',
  'src/liblzma/lzma/lzma_encoder.c',
  'src/liblzma/lzma/lzma_encoder_optimum_fast.c',
  'src/liblzma/lzma/lzma_encoder_optimum_normal.c',
  'src/liblzma/lzma/lzma_encoder_presets.c',
  'src/liblzma/rangecoder/price_table.c',
  'src/liblzma/simple/arm.c',
  'src/liblzma/simple/arm64.c',
  'src/liblzma/simple/armthumb.c',
  'src/liblzma/simple/ia64.c',
  'src/liblzma/simple/powerpc.c',
  'src/liblzma/simple/riscv.c',
  'src/liblzma/simple/simple_coder.c',
  'src/liblzma/simple/simple_decoder.c',
  'src/liblzma/simple/simple_encoder.c',
  'src/liblzma/simple/sparc.c',
  'src/liblzma/simple/x86.c',
)

lzma_inc = include_directories('.', 'src/common', 'src/liblzma/api',
  'src/liblzma/common', 'src/liblzma/check', 'src/liblzma/lz',
  'src/liblzma/rangecoder', 'src/liblzma/lzma', 'src/liblzma/delta',
  'src/liblzma/simple')
api_args = is_windows ? ['-DLZMA_API_STATIC'] : []
liblzma = static_library('lzma', lzma_sources,
  include_directories: lzma_inc,
  c_args: feature_args + api_args + ['-DHAVE_CONFIG_H', '-DTUKLIB_SYMBOL_PREFIX=lzma_'],
  dependencies: platform_deps,
  gnu_symbol_visibility: 'hidden',
  install: false,
)
lzma_dep = declare_dependency(link_with: liblzma,
  include_directories: include_directories('src/liblzma/api'),
  compile_args: api_args, dependencies: platform_deps)
meson.override_dependency('liblzma', lzma_dep)
