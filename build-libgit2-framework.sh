#!/bin/bash
# Build libgit2 XCFramework
#
# This script assumes that
#  1. it is run at the root of the repo
#  2. the required tools (wget, ninja, cmake, autotools) are installed either globally via homebrew or locally in tools/bin using our other script build_tools.sh
#

export REPO_ROOT=`pwd`
export PATH=$PATH:$REPO_ROOT/tools/bin

# Version configurations
LIBGIT2_VERSION="1.3.1"
PCRE_VERSION="8.45"
OPENSSL_VERSION="3.0.4"
LIBSSH2_VERSION="1.10.0"

# List of platforms-architecture that we support
# Note that there are limitations in `xcodebuild` command that disallows `maccatalyst` and `macosx` (native macOS lib) in the same xcframework.
AVAILABLE_PLATFORMS=(iphoneos iphonesimulator iphonesimulator-arm64 maccatalyst maccatalyst-arm64) # maccatalyst maccatalyst-arm64

# List of frameworks included in the XCFramework (= AVAILABLE_PLATFORMS without architecture specifications)
XCFRAMEWORK_PLATFORMS=(iphoneos iphonesimulator maccatalyst)

# List of platforms that need to be merged using lipo due to presence of multiple architectures
LIPO_PLATFORMS=(iphonesimulator maccatalyst)

# Create downloads directory if it doesn't exist
mkdir -p downloads

### Setup common environment variables to run CMake for a given platform
### Usage:      setup_variables PLATFORM
### where PLATFORM is the platform to build for and should be one of
###    iphoneos  (implicitly arm64)
###    iphonesimulator, iphonesimulator-arm64
###    maccatalyst, maccatalyst-arm64
###    macosx, macosx-arm64
###
### After this function is executed, the variables
###    $PLATFORM
###    $ARCH
###    $SYSROOT
###    $CMAKE_ARGS
### providing basic/common CMake options will be set.
function setup_variables() {
	cd $REPO_ROOT
	PLATFORM=$1

	CMAKE_ARGS=(-DBUILD_SHARED_LIBS=NO \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER_WORKS=ON \
		-DCMAKE_CXX_COMPILER_WORKS=ON \
		-DCMAKE_INSTALL_PREFIX=$REPO_ROOT/install/$PLATFORM)

	case $PLATFORM in
		"iphoneos")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk iphoneos Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH \
				-DCMAKE_OSX_SYSROOT=$SYSROOT);;

		"iphonesimulator")
			ARCH=x86_64
			SYSROOT=`xcodebuild -version -sdk iphonesimulator Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_SYSROOT=$SYSROOT);;

		"iphonesimulator-arm64")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk iphonesimulator Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_SYSROOT=$SYSROOT);;

		"maccatalyst")
			ARCH=x86_64
			SYSROOT=`xcodebuild -version -sdk macosx Path`
			CMAKE_ARGS+=(-DCMAKE_C_FLAGS=-target\ $ARCH-apple-ios14.1-macabi);;

		"maccatalyst-arm64")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk macosx Path`
			CMAKE_ARGS+=(-DCMAKE_C_FLAGS=-target\ $ARCH-apple-ios14.1-macabi);;

		"macosx")
			ARCH=x86_64
			SYSROOT=`xcodebuild -version -sdk macosx Path`;;

		"macosx-arm64")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk macosx Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH);;

		*)
			echo "Unsupported or missing platform! Must be one of" ${AVAILABLE_PLATFORMS[@]}
			exit 1;;
	esac
}

### Build libpcre for a given platform
function build_libpcre() {
	setup_variables $1

	if [ ! -d "downloads/pcre-$PCRE_VERSION" ]; then
		git clone https://github.com/light-tech/PCRE.git downloads/pcre-$PCRE_VERSION
	fi

	mkdir -p build/$PLATFORM/pcre-$PCRE_VERSION
	cd build/$PLATFORM/pcre-$PCRE_VERSION

	CMAKE_ARGS+=(-DPCRE_BUILD_PCRECPP=NO \
		-DPCRE_BUILD_PCREGREP=NO \
		-DPCRE_BUILD_TESTS=NO \
		-DPCRE_SUPPORT_LIBBZ2=NO)

	cmake "${CMAKE_ARGS[@]}" $REPO_ROOT/downloads/pcre-$PCRE_VERSION >/dev/null 2>/dev/null

	cmake --build . --target install
}

### Build openssl for a given platform
function build_openssl() {
	setup_variables $1

	# It is better to remove and redownload the source since building make the source code directory dirty!
	test -f downloads/openssl-$OPENSSL_VERSION.tar.gz || wget -q https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz -P downloads

	mkdir -p build/$PLATFORM/openssl-$OPENSSL_VERSION
	tar xzf downloads/openssl-$OPENSSL_VERSION.tar.gz -C build/$PLATFORM/openssl-$OPENSSL_VERSION
	cd build/$PLATFORM/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION

	case $PLATFORM in
		"iphoneos")
			TARGET_OS=ios64-cross
			export CFLAGS="-isysroot $SYSROOT -arch $ARCH";;

		"iphonesimulator"|"iphonesimulator-arm64")
			TARGET_OS=iossimulator-xcrun
			export CFLAGS="-isysroot $SYSROOT -arch $ARCH";;

		"maccatalyst"|"maccatalyst-arm64")
			TARGET_OS=darwin64-$ARCH-cc
			export CFLAGS="-isysroot $SYSROOT -target $ARCH-apple-ios14.1-macabi";;

		"macosx"|"macosx-arm64")
			TARGET_OS=darwin64-$ARCH-cc
			export CFLAGS="-isysroot $SYSROOT";;

		*)
			echo "Unsupported or missing platform!";;
	esac

	# See https://wiki.openssl.org/index.php/Compilation_and_Installation
	./Configure --prefix=$REPO_ROOT/install/$PLATFORM \
		--openssldir=$REPO_ROOT/install/$PLATFORM \
		$TARGET_OS no-shared no-dso no-hw no-engine >/dev/null 2>/dev/null

	make 
	make install_sw install_ssldirs >/dev/null 2>/dev/null
	export -n CFLAGS
}

### Build libssh2 for a given platform (assume openssl was built)
function build_libssh2() {
	setup_variables $1

	mkdir -p build/$PLATFORM/libssh2-$LIBSSH2_VERSION
	tar xzf downloads/libssh2-$LIBSSH2_VERSION.tar.gz -C build/$PLATFORM/libssh2-$LIBSSH2_VERSION
	cd build/$PLATFORM/libssh2-$LIBSSH2_VERSION/libssh2-$LIBSSH2_VERSION

	CMAKE_ARGS+=(-DCRYPTO_BACKEND=OpenSSL \
		-DOPENSSL_ROOT_DIR=$REPO_ROOT/install/$PLATFORM \
		-DBUILD_EXAMPLES=OFF \
		-DBUILD_TESTING=OFF)

	cmake "${CMAKE_ARGS[@]}" $REPO_ROOT/build/$PLATFORM/libssh2-$LIBSSH2_VERSION/libssh2-$LIBSSH2_VERSION >/dev/null 2>/dev/null

	cmake --build . --target install
}

### Build libgit2 for a single platform (given as the first and only argument)
### See @setup_variables for the list of available platform names
### Assume openssl and libssh2 was built
function build_libgit2() {
    setup_variables $1

    test -f downloads/v$LIBGIT2_VERSION.zip || wget -q https://github.com/libgit2/libgit2/archive/refs/tags/v$LIBGIT2_VERSION.zip -P downloads

	mkdir -p build/$PLATFORM/libgit2-$LIBGIT2_VERSION
	cd build/$PLATFORM/libgit2-$LIBGIT2_VERSION

	ditto -V -x -k --sequesterRsrc --rsrc $REPO_ROOT/downloads/v$LIBGIT2_VERSION.zip ./ >/dev/null 2>/dev/null
	rm -rf build && mkdir build && cd build

    CMAKE_ARGS+=(-DBUILD_CLAR=NO)

    # See libgit2/cmake/FindPkgLibraries.cmake to understand how libgit2 looks for libssh2
    # Basically, setting LIBSSH2_FOUND forces SSH support and since we are building static library,
    # we only need the headers.
    CMAKE_ARGS+=(-DOPENSSL_ROOT_DIR=$REPO_ROOT/install/$PLATFORM \
        -DUSE_SSH=ON \
        -DLIBSSH2_FOUND=YES \
        -DLIBSSH2_INCLUDE_DIRS=$REPO_ROOT/install/$PLATFORM/include)

    cmake "${CMAKE_ARGS[@]}" ../libgit2-$LIBGIT2_VERSION >/dev/null 2>/dev/null

    cmake --build . --target install
}

### Create xcframework for a given library
function build_xcframework() {
	local FWNAME=$1
	shift
	local PLATFORMS=( "$@" )
	local FRAMEWORKS_ARGS=()

	echo "Building" $FWNAME "XCFramework containing" ${PLATFORMS[@]}

	for p in ${PLATFORMS[@]}; do
		FRAMEWORKS_ARGS+=("-library" "install/$p/$FWNAME.a" "-headers" "install/$p/include")
	done

	cd $REPO_ROOT
	xcodebuild -create-xcframework ${FRAMEWORKS_ARGS[@]} -output $FWNAME.xcframework
}

### Copy SwiftGit2's module.modulemap to libgit2.xcframework/*/Headers
### so that we can use libgit2 C API in Swift (e.g. via SwiftGit2)
function copy_modulemap() {
    local FWDIRS=$(find Clibgit2.xcframework -mindepth 1 -maxdepth 1 -type d)
    for d in ${FWDIRS[@]}; do
        echo $d
        cp Clibgit2_modulemap $d/Headers/module.modulemap
    done
}

### Build libgit2 and Clibgit2 frameworks for all available platforms

for p in ${AVAILABLE_PLATFORMS[@]}; do
	echo "Build libraries for $p"
	build_libpcre $p
	build_openssl $p
	build_libssh2 $p
	build_libgit2 $p

	# Merge all static libs as libgit2.a since xcodebuild doesn't allow specifying multiple .a
	cd $REPO_ROOT/install/$p
	libtool -static -o libgit2.a lib/*.a
done

# Merge the libgit2.a for iphonesimulator & iphonesimulator-arm64 as well as maccatalyst & maccatalyst-arm64 using lipo
for p in ${LIPO_PLATFORMS[@]}; do
    cd $REPO_ROOT/install/$p
    lipo libgit2.a ../$p-arm64/libgit2.a -output libgit2_all_archs.a -create
    test -f libgit2_all_archs.a && rm libgit2.a && mv libgit2_all_archs.a libgit2.a
done

# Build raw libgit2 XCFramework for Objective-C usage
build_xcframework libgit2 ${XCFRAMEWORK_PLATFORMS[@]}
zip -r libgit2.xcframework.zip libgit2.xcframework/

# Build Clibgit2 XCFramework for use with SwiftGit2
mv libgit2.xcframework Clibgit2.xcframework
copy_modulemap
zip -r Clibgit2.xcframework.zip Clibgit2.xcframework/