#----------------------------------------------------------------
# Generated CMake target import file.
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "epoll-shim::epoll-shim" for configuration ""
set_property(TARGET epoll-shim::epoll-shim APPEND PROPERTY IMPORTED_CONFIGURATIONS NOCONFIG)
set_target_properties(epoll-shim::epoll-shim PROPERTIES
  IMPORTED_LOCATION_NOCONFIG "${_IMPORT_PREFIX}/lib/libepoll-shim.0.dylib"
  IMPORTED_SONAME_NOCONFIG "@rpath/libepoll-shim.0.dylib"
  )

list(APPEND _cmake_import_check_targets epoll-shim::epoll-shim )
list(APPEND _cmake_import_check_files_for_epoll-shim::epoll-shim "${_IMPORT_PREFIX}/lib/libepoll-shim.0.dylib" )

# Import target "epoll-shim::epoll-shim-interpose" for configuration ""
set_property(TARGET epoll-shim::epoll-shim-interpose APPEND PROPERTY IMPORTED_CONFIGURATIONS NOCONFIG)
set_target_properties(epoll-shim::epoll-shim-interpose PROPERTIES
  IMPORTED_LOCATION_NOCONFIG "${_IMPORT_PREFIX}/lib/libepoll-shim-interpose.0.dylib"
  IMPORTED_SONAME_NOCONFIG "@rpath/libepoll-shim-interpose.0.dylib"
  )

list(APPEND _cmake_import_check_targets epoll-shim::epoll-shim-interpose )
list(APPEND _cmake_import_check_files_for_epoll-shim::epoll-shim-interpose "${_IMPORT_PREFIX}/lib/libepoll-shim-interpose.0.dylib" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
