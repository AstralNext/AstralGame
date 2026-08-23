# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(astral_game LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "astral_game")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# VPN / TUN 运行时 DLL（与 exe 同目录）；本地 flutter run / CI flutter build 均会 install。
set(ASTRAL_DLL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../dlls")
file(GLOB ASTRAL_RUNTIME_DLLS CONFIGURE_DEPENDS "${ASTRAL_DLL_DIR}/*.dll")
if(NOT ASTRAL_RUNTIME_DLLS)
  message(FATAL_ERROR
    "Windows runtime DLLs missing in ${ASTRAL_DLL_DIR} (expected wintun.dll, Packet.dll).")
endif()
install(FILES ${ASTRAL_RUNTIME_DLLS}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# 共用 Unity/Mono 注入器（exe 旁 native/inject/）；各游戏插件在 native/<id>/。
set(ASTRAL_MONO_INJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/mono_inject")
set(ASTRAL_MONO_INJECT "${ASTRAL_MONO_INJECT_DIR}/target/release/astral_mono_inject.exe")
set(ASTRAL_MONO_INJECT_FALLBACK "${ASTRAL_MONO_INJECT_DIR}/bin/astral_mono_inject.exe")
if(EXISTS "${ASTRAL_MONO_INJECT}")
  install(FILES "${ASTRAL_MONO_INJECT}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/inject"
    COMPONENT Runtime)
elseif(EXISTS "${ASTRAL_MONO_INJECT_FALLBACK}")
  install(FILES "${ASTRAL_MONO_INJECT_FALLBACK}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/inject"
    COMPONENT Runtime)
else()
  message(WARNING "Mono injector missing (${ASTRAL_MONO_INJECT}); auto-inject disabled")
endif()

set(ASTRAL_RAFT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/raft_astral_net")
set(ASTRAL_RAFT_PLUGIN "${ASTRAL_RAFT_DIR}/dist/AstralRaftNet.dll")
if(NOT EXISTS "${ASTRAL_RAFT_PLUGIN}")
  set(ASTRAL_RAFT_PLUGIN "${ASTRAL_RAFT_DIR}/bin/plugin/AstralRaftNet.dll")
endif()
if(EXISTS "${ASTRAL_RAFT_PLUGIN}")
  install(FILES "${ASTRAL_RAFT_PLUGIN}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/raft"
    COMPONENT Runtime)
else()
  message(WARNING "Raft plugin missing (${ASTRAL_RAFT_PLUGIN}); Raft auto-inject disabled")
endif()

set(ASTRAL_VALHEIM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/valheim_astral_net")
set(ASTRAL_VALHEIM_PLUGIN "${ASTRAL_VALHEIM_DIR}/dist/AstralValheimNet.dll")
if(NOT EXISTS "${ASTRAL_VALHEIM_PLUGIN}")
  set(ASTRAL_VALHEIM_PLUGIN "${ASTRAL_VALHEIM_DIR}/bin/plugin/AstralValheimNet.dll")
endif()
if(EXISTS "${ASTRAL_VALHEIM_PLUGIN}")
  install(FILES "${ASTRAL_VALHEIM_PLUGIN}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/valheim"
    COMPONENT Runtime)
else()
  message(WARNING "Valheim plugin missing (${ASTRAL_VALHEIM_PLUGIN}); Valheim auto-inject disabled")
endif()

# 网络优化：SmartDNS + auto_dns_binder（仅 Windows 打包）。
set(ASTRAL_DNS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/auto_dns_binder")
set(ASTRAL_DNS_BINDER "${ASTRAL_DNS_DIR}/target/release/auto_dns_binder.exe")
set(ASTRAL_DNS_BINDER_FALLBACK "${ASTRAL_DNS_DIR}/bin/auto_dns_binder.exe")
if(EXISTS "${ASTRAL_DNS_BINDER}")
  install(FILES "${ASTRAL_DNS_BINDER}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/dns"
    COMPONENT Runtime)
elseif(EXISTS "${ASTRAL_DNS_BINDER_FALLBACK}")
  install(FILES "${ASTRAL_DNS_BINDER_FALLBACK}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/dns"
    COMPONENT Runtime)
else()
  message(WARNING "auto_dns_binder missing (${ASTRAL_DNS_BINDER}); 网络优化服务不可用")
endif()

set(ASTRAL_SMARTDNS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/smartdns")
set(ASTRAL_SMARTDNS_EXE "${ASTRAL_SMARTDNS_DIR}/smartdns.exe")
set(ASTRAL_SMARTDNS_CONF "${ASTRAL_SMARTDNS_DIR}/smartdns.conf")
if(EXISTS "${ASTRAL_SMARTDNS_EXE}" AND EXISTS "${ASTRAL_SMARTDNS_CONF}")
  install(FILES "${ASTRAL_SMARTDNS_EXE}" "${ASTRAL_SMARTDNS_CONF}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/native/dns/smartdns"
    COMPONENT Runtime)
else()
  message(WARNING "smartdns missing in ${ASTRAL_SMARTDNS_DIR}; 网络优化服务不可用")
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
