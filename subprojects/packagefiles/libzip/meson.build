project('libzip', 'c', version : '1.10.1')

cc = meson.get_compiler('c')
is_windows = host_machine.system() == 'windows'
zip_feature_args = ['-D__STDC_WANT_LIB_EXT1__=1']
zip_c_args = ['-fvisibility=hidden'] + cc.get_supported_arguments(
  '-Wno-incompatible-pointer-types'
)

zlib_dep = dependency('zlib', fallback : ['zlib', 'zlib_dep'])

zipconf = configuration_data()
zipconf.set('ZIP_STATIC', 1)
configure_file(
  input : 'zipconf.h.in',
  output : 'zipconf.h',
  configuration : zipconf,
)

config = configuration_data()
foreach feature : [
  ['ENABLE_FDOPEN', true],
  ['HAVE___PROGNAME', cc.has_function('__progname')],
  ['HAVE__CLOSE', cc.has_function('_close')],
  ['HAVE__DUP', cc.has_function('_dup')],
  ['HAVE__FDOPEN', cc.has_function('_fdopen')],
  ['HAVE__FILENO', cc.has_function('_fileno')],
  ['HAVE__SETMODE', cc.has_function('_setmode')],
  ['HAVE__SNPRINTF', cc.has_header_symbol('stdio.h', '_snprintf', args : zip_feature_args)],
  ['HAVE__SNPRINTF_S', cc.has_header_symbol('stdio.h', '_snprintf_s', args : zip_feature_args)],
  ['HAVE__SNWPRINTF_S', cc.has_header_symbol('stdio.h', '_snwprintf_s', args : zip_feature_args)],
  ['HAVE__STRDUP', cc.has_function('_strdup')],
  ['HAVE__STRICMP', cc.has_header_symbol('string.h', '_stricmp', args : zip_feature_args)],
  ['HAVE__STRTOI64', cc.has_function('_strtoi64')],
  ['HAVE__STRTOUI64', cc.has_function('_strtoui64')],
  ['HAVE__UNLINK', cc.has_function('_unlink')],
  ['HAVE_ARC4RANDOM', cc.has_function('arc4random')],
  ['HAVE_CLONEFILE', cc.has_function('clonefile')],
  ['HAVE_FICLONERANGE', cc.has_function('ioctl') and cc.has_header('linux/fs.h')],
  ['HAVE_FILENO', cc.has_function('fileno')],
  ['HAVE_FCHMOD', cc.has_function('fchmod')],
  ['HAVE_FSEEKO', cc.has_function('fseeko')],
  ['HAVE_FTELLO', cc.has_function('ftello')],
  ['HAVE_GETPROGNAME', cc.has_function('getprogname')],
  ['HAVE_LOCALTIME_R', cc.has_header_symbol('time.h', 'localtime_r', args : zip_feature_args)],
  ['HAVE_LOCALTIME_S', cc.has_header_symbol('time.h', 'localtime_s', args : zip_feature_args)],
  ['HAVE_MEMCPY_S', cc.has_function('memcpy_s', args : zip_feature_args)],
  ['HAVE_MKSTEMP', cc.has_function('mkstemp')],
  ['HAVE_SETMODE', cc.has_function('setmode')],
  ['HAVE_SNPRINTF', cc.has_header_symbol('stdio.h', 'snprintf', args : zip_feature_args)],
  ['HAVE_SNPRINTF_S', cc.has_header_symbol('stdio.h', 'snprintf_s', args : zip_feature_args)],
  ['HAVE_STRCASECMP', cc.has_header_symbol('strings.h', 'strcasecmp', args : zip_feature_args)],
  ['HAVE_STRDUP', cc.has_function('strdup')],
  ['HAVE_STRERROR_S', cc.has_function('strerror_s')],
  ['HAVE_STRERRORLEN_S', cc.has_function('strerrorlen_s')],
  ['HAVE_STRICMP', cc.has_function('stricmp')],
  ['HAVE_STRNCPY_S', cc.has_function('strncpy_s', args : zip_feature_args)],
  ['HAVE_STRTOLL', cc.has_function('strtoll')],
  ['HAVE_STRTOULL', cc.has_function('strtoull')],
  ['HAVE_STDBOOL_H', cc.has_header('stdbool.h')],
  ['HAVE_STRINGS_H', cc.has_header('strings.h')],
  ['HAVE_UNISTD_H', cc.has_header('unistd.h')],
  ['HAVE_WINDOWS_CRYPTO', false],
]
  if feature[1]
    config.set(feature[0], 1)
  endif
endforeach
config.set('SIZEOF_OFF_T', cc.sizeof('off_t', prefix : '#include <sys/types.h>'))
config.set('SIZEOF_SIZE_T', cc.sizeof('size_t', prefix : '#include <stddef.h>'))
foreach feature : [
  ['HAVE_DIRENT_H', cc.has_header('dirent.h')],
  ['HAVE_FTS_H', cc.has_header('fts.h')],
  ['HAVE_NDIR_H', cc.has_header('ndir.h')],
  ['HAVE_SYS_DIR_H', cc.has_header('sys/dir.h')],
  ['HAVE_SYS_NDIR_H', cc.has_header('sys/ndir.h')],
  ['WORDS_BIGENDIAN', host_machine.endian() == 'big'],
]
  if feature[1]
    config.set(feature[0], 1)
  endif
endforeach
configure_file(
  input : 'config.h.in',
  output : 'config.h',
  configuration : config,
)

zip_dir = include_directories('lib', '.')
zip_sys = include_directories(is_system : true)
zip_inc = [zip_dir, zip_sys]
zip_src = files(
  'lib/zip_add.c',
  'lib/zip_add_dir.c',
  'lib/zip_add_entry.c',
  'lib/zip_algorithm_deflate.c',
  'lib/zip_buffer.c',
  'lib/zip_close.c',
  'lib/zip_delete.c',
  'lib/zip_dir_add.c',
  'lib/zip_dirent.c',
  'lib/zip_discard.c',
  'lib/zip_entry.c',
  'lib/zip_error.c',
  'lib/zip_error_clear.c',
  'lib/zip_error_get.c',
  'lib/zip_error_get_sys_type.c',
  'lib/zip_error_strerror.c',
  'lib/zip_error_to_str.c',
  'lib/zip_extra_field.c',
  'lib/zip_extra_field_api.c',
  'lib/zip_fclose.c',
  'lib/zip_fdopen.c',
  'lib/zip_file_add.c',
  'lib/zip_file_error_clear.c',
  'lib/zip_file_error_get.c',
  'lib/zip_file_get_comment.c',
  'lib/zip_file_get_external_attributes.c',
  'lib/zip_file_get_offset.c',
  'lib/zip_file_rename.c',
  'lib/zip_file_replace.c',
  'lib/zip_file_set_comment.c',
  'lib/zip_file_set_encryption.c',
  'lib/zip_file_set_external_attributes.c',
  'lib/zip_file_set_mtime.c',
  'lib/zip_file_strerror.c',
  'lib/zip_fopen.c',
  'lib/zip_fopen_encrypted.c',
  'lib/zip_fopen_index.c',
  'lib/zip_fopen_index_encrypted.c',
  'lib/zip_fread.c',
  'lib/zip_fseek.c',
  'lib/zip_ftell.c',
  'lib/zip_get_archive_comment.c',
  'lib/zip_get_archive_flag.c',
  'lib/zip_get_encryption_implementation.c',
  'lib/zip_get_file_comment.c',
  'lib/zip_get_name.c',
  'lib/zip_get_num_entries.c',
  'lib/zip_get_num_files.c',
  'lib/zip_hash.c',
  'lib/zip_io_util.c',
  'lib/zip_libzip_version.c',
  'lib/zip_memdup.c',
  'lib/zip_name_locate.c',
  'lib/zip_new.c',
  'lib/zip_open.c',
  'lib/zip_pkware.c',
  'lib/zip_progress.c',
  'lib/zip_rename.c',
  'lib/zip_replace.c',
  'lib/zip_set_archive_comment.c',
  'lib/zip_set_archive_flag.c',
  'lib/zip_set_default_password.c',
  'lib/zip_set_file_comment.c',
  'lib/zip_set_file_compression.c',
  'lib/zip_set_name.c',
  'lib/zip_source_accept_empty.c',
  'lib/zip_source_begin_write.c',
  'lib/zip_source_begin_write_cloning.c',
  'lib/zip_source_buffer.c',
  'lib/zip_source_call.c',
  'lib/zip_source_close.c',
  'lib/zip_source_commit_write.c',
  'lib/zip_source_compress.c',
  'lib/zip_source_crc.c',
  'lib/zip_source_error.c',
  'lib/zip_source_file_common.c',
  'lib/zip_source_file_stdio.c',
  'lib/zip_source_free.c',
  'lib/zip_source_function.c',
  'lib/zip_source_get_file_attributes.c',
  'lib/zip_source_is_deleted.c',
  'lib/zip_source_layered.c',
  'lib/zip_source_open.c',
  'lib/zip_source_pass_to_lower_layer.c',
  'lib/zip_source_pkware_decode.c',
  'lib/zip_source_pkware_encode.c',
  'lib/zip_source_read.c',
  'lib/zip_source_remove.c',
  'lib/zip_source_rollback_write.c',
  'lib/zip_source_seek.c',
  'lib/zip_source_seek_write.c',
  'lib/zip_source_stat.c',
  'lib/zip_source_supports.c',
  'lib/zip_source_tell.c',
  'lib/zip_source_tell_write.c',
  'lib/zip_source_window.c',
  'lib/zip_source_write.c',
  'lib/zip_source_zip.c',
  'lib/zip_source_zip_new.c',
  'lib/zip_stat.c',
  'lib/zip_stat_index.c',
  'lib/zip_stat_init.c',
  'lib/zip_strerror.c',
  'lib/zip_string.c',
  'lib/zip_unchange.c',
  'lib/zip_unchange_all.c',
  'lib/zip_unchange_archive.c',
  'lib/zip_unchange_data.c',
  'lib/zip_utf-8.c',
  'lib/zip_err_str.c'
)
if is_windows
  zip_src += files(
    'lib/zip_random_win32.c',
    'lib/zip_source_file_win32.c',
    'lib/zip_source_file_win32_ansi.c',
    'lib/zip_source_file_win32_named.c',
    'lib/zip_source_file_win32_utf16.c',
    'lib/zip_source_file_win32_utf8.c',
  )
else
  zip_src += files(
    'lib/zip_random_unix.c',
    'lib/zip_source_file_stdio_named.c',
  )
endif
zip = static_library(
  'zip',
  zip_src,
  build_by_default : false,
  link_args : [],
  link_with : [],
  include_directories : zip_inc,
  install : false,
  override_options : [],
  objects : [],
  c_args : zip_c_args,
  dependencies : [zlib_dep],
  pic : false
)
zip_dep = declare_dependency(
  link_with : zip,
  compile_args : [],
  include_directories : zip_inc,
  dependencies : [zlib_dep],
  link_args : []
)
