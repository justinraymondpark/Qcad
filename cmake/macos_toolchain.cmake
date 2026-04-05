# CMake Toolchain File for building QCAD on macOS 11 (Big Sur) and later
#
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=cmake/macos_toolchain.cmake ..
#
# This toolchain file configures the build to target macOS 11.0+
# with support for both Intel (x86_64) and Apple Silicon (arm64).

set(CMAKE_SYSTEM_NAME Darwin)

# Minimum macOS deployment target: macOS 11.0 Big Sur
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS deployment target" FORCE)

# Build universal binary (Intel + Apple Silicon) by default
# Override with -DCMAKE_OSX_ARCHITECTURES="arm64" for single-arch builds
if(NOT DEFINED CMAKE_OSX_ARCHITECTURES OR CMAKE_OSX_ARCHITECTURES STREQUAL "")
    set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "Build architectures for macOS" FORCE)
endif()

# Use the latest available macOS SDK
set(CMAKE_OSX_SYSROOT "macosx" CACHE STRING "macOS SDK" FORCE)

# Use Clang (default on macOS)
set(CMAKE_C_COMPILER "clang")
set(CMAKE_CXX_COMPILER "clang++")

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Ensure proper RPATH handling for macOS bundles
set(CMAKE_MACOSX_RPATH ON)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "@executable_path/../Frameworks;@executable_path/../lib")

# Compiler flags for macOS 11 compatibility
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mmacosx-version-min=11.0")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mmacosx-version-min=11.0")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -mmacosx-version-min=11.0")
set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -mmacosx-version-min=11.0")

# Linker flags
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -mmacosx-version-min=11.0")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -mmacosx-version-min=11.0")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -mmacosx-version-min=11.0")
