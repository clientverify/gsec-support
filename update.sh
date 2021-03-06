#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

#WRAPPER="`readlink -f "$0"`"
#HERE="`dirname "$WRAPPER"`"
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ERROR_EXIT=1

# Include gsec_common
. $HERE/build_configs/gsec_common

# Command line options
FORCE_CLEAN=0
FORCE_COMPILATION=0
FORCE_CONFIGURE=0
INSTALL_PACKAGES=0
BUILD_DEBUG=0
BUILD_DEBUG_ALL=0
BUILD_LOCAL=0 # build local code, don't checkout from git
SELECTIVE_BUILD=0
SELECTIVE_BUILD_TARGET=""
SKIP_INSTALL_ERRORS=1
SKIP_TESTS=0
INSTALL_CLANG_BIN=1
USE_LLVM29=0
VERBOSE_OUTPUT=0
MAKE_THREADS=$(max_threads)
ROOT_DIR="`pwd`"

get_file()
{
  # usage: get_file [file] [remote-path] [local-dest]
  if [[ $# -lt 3 ]]; then
    echo "[Error getting file] "
    exit
  fi

  local FILE=$1
  local REMOTE_PATH=$2
  local LOCAL_DEST=$3

  mkdir -p $LOCAL_DEST

  if [[ $(expr match $REMOTE_PATH "http") -gt 0 ]]; then
    leval wget $REMOTE_PATH/$FILE -O $LOCAL_DEST/$FILE
  else
    leval scp -r $REMOTE_PATH/$FILE $LOCAL_DEST/
  fi
}

get_package()
{
  # usage: get_package [package] [remote-path] [local-dest]
  if [[ $# -lt 3 ]]; then
    echo "[Error getting package] "
    exit
  fi

  local PACKAGE=$1
  local REMOTE_PATH=$2
  local LOCAL_DEST=$3
  local PACKAGE_TYPE=${PACKAGE##*.}

  TAR_OPTIONS="--strip-components=1"

  mkdir -p $LOCAL_DEST

  necho "[Downloading] "
  get_file $PACKAGE $REMOTE_PATH $LOCAL_DEST

  necho "[Extracting] "
  if [ $PACKAGE_TYPE == "gz" ] || [ $PACKAGE_TYPE == "tgz" ]; then
    leval tar $TAR_OPTIONS -xvzf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST 
  elif [ $PACKAGE_TYPE == "bz2" ]; then
    leval tar $TAR_OPTIONS -xvjf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST 
  elif [ $PACKAGE_TYPE == "xz" ]; then
    leval tar $TAR_OPTIONS -xvf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST
  else
    echo "[Error invalid package type] "
    rm $LOCAL_DEST/$PACKAGE
    exit
  fi

  rm $LOCAL_DEST/$PACKAGE
}

check_dirs()
{
  if [ -e $ROOT_DIR/src/$1 ] ||
     [ -e $ROOT_DIR/build/$1 ] ||
     [ -e $1 ] ; then
    if [ $SKIP_INSTALL_ERRORS -eq 1 ]; then
      echo "[Skipping] (Already exists, integrity unconfirmed) "
      return 1
    else
      echo "[Error checking dirs] "
      exit
    fi
  fi
}

install_ncurses()
{
  necho "$NCURSES\t\t"
  check_dirs $NCURSES || { return 0; }
  get_package $NCURSES_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$NCURSES"

  mkdir -p $ROOT_DIR/build/$NCURSES
  cd $ROOT_DIR/build/$NCURSES

  NCURSES_CONFIG_OPTIONS="--with-shared --without-ada --without-manpages --prefix=$NCURSES_ROOT --enable-symlinks "
  if test ${ALTCC+defined}; then
    NCURSES_CONFIG_OPTIONS+="CC=$ALTCC LD=$ALTCC "
  fi

  necho "[Configuring] "
  leval $ROOT_DIR/src/$NCURSES/configure $NCURSES_CONFIG_OPTIONS 

  necho "[Compiling] "
  leval make -j $MAKE_THREADS 

  necho "[Installing] "
  mkdir -p $NCURSES_ROOT
  leval make -j $MAKE_THREADS install 

  necho "[Done]\n"
}

install_zlib()
{
  necho "$ZLIB \t\t"
  check_dirs $ZLIB || { return 0; }
  get_package $ZLIB_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$ZLIB"

  cd $ROOT_DIR/src/$ZLIB

  necho "[Configuring] "
  leval $ROOT_DIR/src/$ZLIB/configure --prefix=$ZLIB_ROOT 

  necho "[Compiling] "
  leval make

  necho "[Installing] "
  mkdir -p $ZLIB_ROOT
  leval make install

  necho "[Done]\n"
}

install_waffles()
{
  necho "$WAFFLES\t"
  check_dirs $WAFFLES || { return 0; }
  get_package $WAFFLES_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$WAFFLES"

  cd $ROOT_DIR/src/$WAFFLES/src

  necho "[Patching] "
  get_file $WAFFLES_PATCH_FILE $PATCH_DIR $ROOT_DIR/src/$WAFFLES
  cd $ROOT_DIR/src/$WAFFLES
  leval patch -p1 < $WAFFLES_PATCH_FILE

  cd $ROOT_DIR/src/$WAFFLES/src
  necho "[Compiling] "
  leval make

  necho "[Installing] "
  mkdir -p $WAFFLES_ROOT
  leval make install INSTALL_PREFIX="$WAFFLES_ROOT"

  necho "[Done]\n"
}

install_expat()
{
  necho "$EXPAT\t\t"
  check_dirs $EXPAT || { return 0; }
  get_package $EXPAT_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$EXPAT"
  cd $ROOT_DIR/src/$EXPAT

  necho "[Configuring] "
  leval $ROOT_DIR/src/$EXPAT/configure --prefix=$EXPAT_ROOT 

  necho "[Compiling] "
  leval make -j $MAKE_THREADS 

  necho "[Installing] "
  mkdir -p $EXPAT_ROOT
  leval make -j $MAKE_THREADS install 

  necho "[Done]\n"
}

install_boost()
{
  necho "$BOOST\t\t"

  check_dirs $BOOST || { return 0; }

  get_package $BOOST_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$BOOST/"

  mkdir -p $ROOT_DIR/build/$BOOST
  cd $ROOT_DIR/src/$BOOST

  #BJAM_OPTIONS=" --without-regex -j$MAKE_THREADS"
  #BJAM_OPTIONS="--build-type=complete --build-dir=$ROOT_DIR/build/$BOOST -j$MAKE_THREADS"
  BJAM_OPTIONS=" --without-python --build-dir=$ROOT_DIR/build/$BOOST -j$MAKE_THREADS debug-symbols=on "

  if test ${ALTCC+defined}; then
    echo "using gcc : $ALTCCVERSION : /usr/bin/$ALTCC ; " >> $ROOT_DIR/src/$BOOST/tools/build/user-config.jam
    BJAM_OPTIONS+=" --toolset=$ALTCC "
  fi

  necho "[Configuring] "
  leval ./bootstrap.sh --prefix=$BOOST_ROOT 

  necho "[Compiling] "
  leval ./b2 $BJAM_OPTIONS install

  necho "[Installing] "

  necho "[Done]\n"
}

install_libunwind()
{
  necho "$LIBUNWIND\t\t"
  check_dirs $LIBUNWIND || { return 0; }
  get_package $LIBUNWIND_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$LIBUNWIND"

  mkdir -p $ROOT_DIR/build/$LIBUNWIND
  cd $ROOT_DIR/build/$LIBUNWIND

  necho "[Configuring] "
  leval $ROOT_DIR/src/$LIBUNWIND/configure CFLAGS=\"-U_FORTIFY_SOURCE\" --prefix=$LIBUNWIND_ROOT 

  necho "[Compiling] "
  leval make -j $MAKE_THREADS

  necho "[Installing] "
  mkdir -p $LIBUNWIND_ROOT
  leval make -j $MAKE_THREADS install 

  necho "[Done]\n"
}

install_sparsehash()
{
  necho "$SPARSEHASH\t"
  check_dirs $SPARSEHASH || { return 0; }
  get_package $SPARSEHASH_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$SPARSEHASH"

  mkdir -p $ROOT_DIR/build/$SPARSEHASH
  cd $ROOT_DIR/build/$SPARSEHASH

  necho "[Configuring] "
  leval $ROOT_DIR/src/$SPARSEHASH/configure --prefix=$SPARSEHASH_ROOT 

  necho "[Installing] "
  mkdir -p $SPARSEHASH_ROOT
  leval make -j $MAKE_THREADS install 

  necho "[Done]\n"
}

install_ghmm()
{
  necho "$GHMM\t\t\t"
  check_dirs $GHMM || { return 0; }

  necho "[Cloning] "
  leval svn co $GHMM_SVN $ROOT_DIR/src/$GHMM
  cd $ROOT_DIR/src/$GHMM

  necho "[Configuring] "
  leval ./autogen.sh
  GHMM_CONFIG_OPTIONS="--prefix=$GHMM_ROOT --without-python "

  GHMM_MAKE_OPTIONS=""
  if test ${ALTCC+defined}; then
    GHMM_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
    GHMM_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  leval $ROOT_DIR/src/$GHMM/configure $GHMM_CONFIG_OPTIONS

  necho "[Compiling] "
  leval make -j $MAKE_THREADS $GHMM_MAKE_OPTIONS

  necho "[Installing] "
  leval make $GHMM_MAKE_OPTIONS install

  necho "[Done]\n"
}

install_google_perftools()
{
  necho "$GOOGLE_PERFTOOLS\t\t"
  check_dirs $GOOGLE_PERFTOOLS || { return 0; }

  necho "[Cloning] "
  leval git clone $GOOGLE_PERFTOOLS_GIT $ROOT_DIR/src/$GOOGLE_PERFTOOLS
  cd $ROOT_DIR/src/$GOOGLE_PERFTOOLS
  leval git checkout tags/$GOOGLE_PERFTOOLS_TAG -b $GOOGLE_PERFTOOLS_TAG
  leval ./autogen.sh

  mkdir -p $ROOT_DIR/build/$GOOGLE_PERFTOOLS
  cd $ROOT_DIR/build/$GOOGLE_PERFTOOLS

  necho "[Configuring] "
  GOOGLE_PERFTOOLS_CONFIG_OPTIONS="--prefix=$GOOGLE_PERFTOOLS_ROOT "

  if [ "$(uname)" != "Darwin" ] ; then
    GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="LDFLAGS=-L$LIBUNWIND_ROOT/lib/ "
    GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="CPPFLAGS=-I$LIBUNWIND_ROOT/include/ "
    GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="LIBS=-lunwind-x86_64 "
  fi

  GOOGLE_PERFTOOLS_CONFIG_COMMAND="$ROOT_DIR/src/$GOOGLE_PERFTOOLS/configure $GOOGLE_PERFTOOLS_CONFIG_OPTIONS"

  # google-perf-tools requires libunwind libraries on x86_64, so we provide
  # the libunwind directory to the compiler for static libraries, and add the libunwind directory
  # to LD_LIBRARY_PATH for shared libraries
  GOOGLE_PERFTOOLS_LD_LIBRARY_PATH=""
  if [ "$(uname)" != "Darwin" ] ; then
    if test ${LD_LIBRARY_PATH+defined}; then
      GOOGLE_PERFTOOLS_LD_LIBRARY_PATH+="$LD_LIBRARY_PATH:$LIBUNWIND_ROOT/lib" 
    else
      GOOGLE_PERFTOOLS_LD_LIBRARY_PATH+="$LIBUNWIND_ROOT/lib" 
    fi
  fi

  GOOGLE_PERFTOOLS_MAKE_OPTIONS=""
  if test ${ALTCC+defined}; then
    GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
    GOOGLE_PERFTOOLS_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  leval LD_LIBRARY_PATH=$GOOGLE_PERFTOOLS_LD_LIBRARY_PATH $GOOGLE_PERFTOOLS_CONFIG_COMMAND 

  necho "[Compiling] "
  leval make -j $MAKE_THREADS $GOOGLE_PERFTOOLS_MAKE_OPTIONS

  necho "[Installing] "
  mkdir -p $GOOGLE_PERFTOOLS_ROOT
  leval make -j $MAKE_THREADS $GOOGLE_PERFTOOLS_MAKE_OPTIONS install 

  necho "[Done]\n"
}


install_uclibc()
{
  necho "$UCLIBC\t"
  check_dirs $UCLIBC || { return 0; }
  get_package $UCLIBC_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$UCLIBC"

  cd $ROOT_DIR/src/$UCLIBC

  necho "[Configuring] "
  leval ./configure --with-llvm=$ROOT_DIR/build/$LLVM 

  necho "[Compiling] "
  leval make 

  necho "[Done]\n"
} 

install_uclibc_git()
{
  necho "$UCLIBC\t\t"
  check_dirs $UCLIBC|| { return 0; }
  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone --branch $UCLIBC_BRANCH $UCLIBC_GIT

  cd $ROOT_DIR/src/$UCLIBC

  necho "[Configuring] "
  leval ./configure --with-llvm-config=$LLVM_ROOT/bin/llvm-config --with-cc=$CLANG_ROOT/bin/$LLVM_CC --make-llvm-lib

  necho "[Compiling] "
  leval make 

  necho "[Done]\n"
}

# Facebook C++ Library
install_folly()
{
  necho "$FOLLY\t\t\t"
  check_dirs $FOLLY|| { return 0; }
  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone  $FOLLY_GIT
  cd $ROOT_DIR/src/$FOLLY
  leval git checkout tags/$FOLLY_TAG -b $FOLLY_TAG

  necho "[Configuring] "
  cd $ROOT_DIR/src/$FOLLY/folly
  leval autoreconf -ivf
  leval LD_LIBRARY_PATH='$OPENSSL_ROOT/lib' CPPFLAGS='-I$OPENSSL_ROOT/include' LDFLAGS='-L$OPENSSL_ROOT/lib' ./configure --prefix=$FOLLY_ROOT

  necho "[Compiling] "
  leval LD_LIBRARY_PATH='$OPENSSL_ROOT/lib' CPPFLAGS='-I$OPENSSL_ROOT/include' LDFLAGS='-L$OPENSSL_ROOT/lib' make -j $MAKE_THREADS

  necho "[Installing] "
  mkdir -p $FOLLY_ROOT
  leval LD_LIBRARY_PATH='$OPENSSL_ROOT/lib' CPPFLAGS='-I$OPENSSL_ROOT/include' LDFLAGS='-L$OPENSSL_ROOT/lib' make install

  necho "[Done]\n"
}

install_clang_bin()
{
  necho "$CLANG_BIN\t"
  check_dirs "$CLANG_ROOT/bin/$LLVM_CC" || { return 0; }
  get_package $CLANG_BIN_PACKAGE $PACKAGE_DIR $CLANG_ROOT
  necho "[Done]\n"
}

install_clang_from_source()
{
  necho "$CLANG\t"
  necho "Installation from source not supported\n"
  exit 2
}

update_wllvm()
{
  necho "$WLLVM\t"

  if [ ! -e "$ROOT_DIR/src/$WLLVM/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$WLLVM

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$WLLVM_BRANCH" ]; then
      echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    fi
    necho "[Checking] "
    leval git remote update
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      necho "[Pulling] "
      leval git pull --all
    fi

    # No build step necessary (just python wrapper)
  fi

  necho "[Done]\n"
}

install_wllvm()
{
  necho "$WLLVM\t"

  check_dirs $WLLVM || { return 0; }
  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone $WLLVM_GIT $WLLVM

  WLLVM_SRC_DIR=$ROOT_DIR"/src/$WLLVM"
  cd $WLLVM_SRC_DIR

  leval git checkout $WLLVM_BRANCH

  # No build step necessary (just python wrapper)

  necho "[Installing] "
  mkdir -p ${WLLVM_ROOT}/bin
  cd ${WLLVM_ROOT}/bin
  cp -a $WLLVM_SRC_DIR/wllvm .
  cp -a $WLLVM_SRC_DIR/wllvm++ .
  cp -a $WLLVM_SRC_DIR/extract-bc .
  cp -a $WLLVM_SRC_DIR/driver .

  necho "[Done]\n"
}

config_llvm ()
{ 
  mkdir -p $ROOT_DIR/build/$LLVM
  cd $ROOT_DIR"/build/$LLVM"

  LLVM_CONFIG_OPTIONS="--prefix=$LLVM_ROOT "
  LLVM_CONFIG_OPTIONS+="--enable-shared --enable-pic --enable-libffi "

  # Note: the LLVM debug build is slow and very large (400 MB)
  if [ $BUILD_DEBUG_ALL -eq 1 ]; then
    LLVM_CONFIG_OPTIONS+="--enable-debug-symbols --disable-optimized "
  else
    LLVM_CONFIG_OPTIONS+="--enable-optimized --disable-assertions "
  fi

  if test ${ALTCC+defined}; then
    LLVM_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  leval $ROOT_DIR/src/$LLVM/configure $LLVM_CONFIG_OPTIONS 
}

build_llvm ()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then TARGET=$1; fi

  mkdir -p $ROOT_DIR/build/$LLVM
  cd $ROOT_DIR"/build/$LLVM"

  LLVM_MAKE_OPTIONS=" -j $MAKE_THREADS REQUIRES_RTTI=1 DEBUG_SYMBOLS=1 "

  leval make $LLVM_MAKE_OPTIONS $TARGET 
}

update_llvm()
{
  necho "$LLVM\t\t\t"

  if [ ! -e "$ROOT_DIR/src/$LLVM/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$LLVM

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$LLVM_BRANCH" ]; then
      echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    fi

    necho "[Checking] "
    leval git remote update
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      necho "[Pulling] "
      leval git pull --all
    fi

    if [ $FORCE_CONFIGURE -eq 1 ]; then
      necho "[Configuring] "
      config_llvm
    fi

    if [ $FORCE_CLEAN -eq 1 ]; then
      necho "[Cleaning] "
      build_llvm clean
    fi

    if [ $BUILD_DEBUG -eq 1 ]; then
      necho "[Compiling Debug] "
      build_llvm "ENABLE_OPTIMIZED=0 DISABLE_ASSERTIONS=0 "

      necho "[Installing Debug] "
      mkdir -p $LLVM_ROOT
      build_llvm "ENABLE_OPTIMIZED=0 DISABLE_ASSERTIONS=0 install"
    else
      necho "[Compiling Release] "
      build_llvm "ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=1 "

      necho "[Installing Release] "
      mkdir -p $LLVM_ROOT
      build_llvm "ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=1 install"
    fi
  fi
  necho "[Done]\n"
}

install_llvm()
{
  necho "$LLVM\t\t\t"
  check_dirs $LLVM || { return 0; }
  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone $LLVM_GIT

  cd $ROOT_DIR"/src/$LLVM"

  leval git checkout $LLVM_BRANCH

  if test ${GIT_TAG+defined}; then
    necho "[Fetching $GIT_TAG] "
    leval git checkout $GIT_TAG
  fi

  necho "[Configuring] "
  config_llvm

  if [ $BUILD_DEBUG -eq 1 ]; then
    necho "[Compiling Debug] "
    build_llvm "ENABLE_OPTIMIZED=0 DISABLE_ASSERTIONS=0 "

    necho "[Installing Debug] "
    mkdir -p $LLVM_ROOT
    build_llvm "ENABLE_OPTIMIZED=0 DISABLE_ASSERTIONS=0 install"
  else
    necho "[Compiling Release] "
    build_llvm "ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=0 "

    necho "[Installing Release] "
    mkdir -p $LLVM_ROOT
    build_llvm "ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=0 install"
  fi

  necho "[Done]\n"
}

install_minisat()
{
  necho "$MINISAT\t\t\t"
  check_dirs $MINISAT || { return 0; }

  necho "[Cloning] "
  cd $ROOT_DIR"/src"
  leval git clone --branch $MINISAT_BRANCH $MINISAT_GIT

  necho "[Compiling] "
  mkdir -p $ROOT_DIR/build/$MINISAT
  cd $ROOT_DIR/build/$MINISAT
  leval cmake -DCMAKE_INSTALL_PREFIX:PATH=$MINISAT_ROOT $ROOT_DIR/src/$MINISAT
  leval make VERBOSE=1 -j $MAKE_THREADS

  necho "[Installing] "
  leval make install

  necho "[Done]\n"
}

install_stp_git()
{
  necho "$STP\t\t\t"
  check_dirs $STP || { return 0; }

  necho "[Cloning] "
  cd $ROOT_DIR"/src"
  leval git clone --branch $STP_BRANCH $STP_GIT

  necho "[Compiling] "
  mkdir -p $ROOT_DIR/build/$STP
  cd $ROOT_DIR/build/$STP
  leval cmake \
      -DCMAKE_INSTALL_PREFIX:PATH=$STP_ROOT \
      -DBUILD_SHARED_LIBS:BOOL=OFF \
      -DENABLE_PYTHON_INTERFACE:BOOL=OFF \
      $ROOT_DIR/src/$STP
  leval make VERBOSE=1 -j $MAKE_THREADS

  necho "[Installing] "
  leval make install

  necho "[Done]\n"
}

install_stp()
{
  necho "$STP\t\t\t"
  check_dirs $STP || { return 0; }
  get_package $STP_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$STP"

  cd $ROOT_DIR/src/$STP 

  #### HACK to fix compilation with old version of flex on redhat, only needed for rev 940, fixed in rev 1139 ####
  local OLD_FLEX=$(flex --version | awk -F '[ .]' '{ print ($$(NF-2) < 2 || $$(NF-2) == 2 && ($$(NF-1) < 5 || $$(NF-1) == 5 && $$NF < 20)) }')
  if [ $OLD_FLEX -eq 0 ]; then
    necho "[Patching] "
    get_file $STP_PATCH_FILE $PATCH_DIR $ROOT_DIR/src/$STP
    leval patch -p0 < $STP_PATCH_FILE
  fi

  necho "[Patching] "
  get_file $STP_BISON_PATCH_FILE $PATCH_DIR $ROOT_DIR/src/$STP
  leval patch -p1 < $STP_BISON_PATCH_FILE

  necho "[Patching] "
  get_file $STP_THREAD_PATCH_FILE $PATCH_DIR $ROOT_DIR/src/$STP
  leval patch -p1 < $STP_THREAD_PATCH_FILE

  if test ${ALTCC+defined}; then
    STP_COMPILER_OPTIONS="CC=$ALTCC CXX=$ALTCXX "
  else
    STP_COMPILER_OPTIONS=""
  fi

  necho "[Configuring] "
  local STP_CONFIG_FLAGS="--with-prefix=$STP_ROOT --with-cryptominisat2 "
  leval ${STP_COMPILER_OPTIONS} ./scripts/configure $STP_CONFIG_FLAGS

  # Building with multiple threads causes errors
  local STP_MAKE_FLAGS=" ${STP_COMPILER_OPTIONS} OPTIMIZE=-O2 CFLAGS_M32=\" -g -fPIC \" VERBOSE=1 "

  necho "[Compiling] "
  leval make $STP_MAKE_FLAGS

  necho "[Installing] "
  leval make $STP_MAKE_FLAGS install
  
  necho "[Done]\n"
}

install_z3()
{
  necho "$Z3\t\t\t"
  check_dirs $Z3 || { return 0; }

  necho "[Cloning] "
  cd $ROOT_DIR"/src"
  leval git clone $Z3_GIT
  cd $ROOT_DIR"/src/z3"
  leval git checkout $Z3_BRANCH

  leval python scripts/mk_make.py  --prefix=$ROOT_DIR/local

  necho "[Compiling] "
  cd $ROOT_DIR"/src/z3/build"
  leval make VERBOSE=1 -j $MAKE_THREADS

  necho "[Installing] "
  leval make install

  necho "[Done]\n"
  cd $ROOT_DIR
}

config_klee()
{
  mkdir -p $ROOT_DIR/build/$KLEE
  cd $ROOT_DIR/build/$KLEE

  KLEE_CONFIG_OPTIONS="--prefix=$KLEE_ROOT -libdir=$KLEE_ROOT/lib/$KLEE "

  KLEE_CONFIG_OPTIONS+="--with-llvmsrc=$ROOT_DIR/src/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-llvmobj=$ROOT_DIR/build/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-llvmcc=$CLANG_ROOT/bin/$LLVM_CC "
  KLEE_CONFIG_OPTIONS+="--with-llvmcxx=$CLANG_ROOT/bin/$LLVM_CXX "

  if [ $USE_LLVM29 -eq 0 ]; then
    KLEE_CONFIG_OPTIONS+="--enable-cxx11 "
  fi

  if [ $KLEE_SMT_SOLVER == $Z3 ]; then
    KLEE_CONFIG_OPTIONS+="--with-z3=$Z3_ROOT "
  else
    KLEE_CONFIG_OPTIONS+="--with-stp=$STP_ROOT "
  fi

  KLEE_CONFIG_OPTIONS+="--with-uclibc=$UCLIBC_ROOT --enable-posix-runtime "

  if test ${ALTCC+defined}; then
   KLEE_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  if [ $BUILD_DEBUG -eq 1 ]; then
   KLEE_CONFIG_OPTIONS+="--with-runtime=Debug+Asserts"
  else
   KLEE_CONFIG_OPTIONS+="--with-runtime=Release"
  fi


  leval $ROOT_DIR/src/$KLEE/configure $KLEE_CONFIG_OPTIONS 
}

make_klee()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then TARGET=$1; fi

  mkdir -p $ROOT_DIR/build/$KLEE
  cd $ROOT_DIR/build/$KLEE

  local make_options=""
  local env_options=""

  make_options+="-j $MAKE_THREADS "
  make_options+="ENABLE_GOOGLE_PROFILER=1 "
  make_options+="ENABLE_BOOST_GRAPHVIZ=1 "

  if test ${ALTCC+defined}; then
   make_options+="CC=$ALTCC CXX=$ALTCXX "
  fi

  local klee_ldflags="-L$BOOST_ROOT/lib -L$GOOGLE_PERFTOOLS_ROOT/lib -Wl,-rpath=${BOOST_ROOT}/lib "
  local klee_cxxflags="-I$OPENSSL_ROOT/include -I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include "
  #local klee_cxxflags="-I$OPENSSL_ROOT/include -I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include -I${GLIBC_INCLUDE_PATH} "
  #local klee_cppflags="-I$OPENSSL_ROOT/include -I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include "
  local klee_cflags="-I${GLIBC_INCLUDE_PATH} -I$OPENSSL_ROOT/include "

  if [ $USE_LLVM29 -eq 0 ]; then
    # compile with pretty colors!
    klee_cxxflags+="-fdiagnostics-color=always "
    # don't warn about unused typedefs and functions in boost
    klee_cxxflags+="-Wno-unused-functions -Wno-unused-local-typedefs "
  else
    klee_cxxflags+="-std=c++0x "
  fi
  if [ $KLEE_SMT_SOLVER == $Z3 ]; then
    local klee_libs=" -ldl -lz3 -lz -lboost_serialization -lboost_system -lboost_thread -lboost_regex -lfolly -lcap -lutil -lglog -lprofiler -ltcmalloc -lpthread -ltinfo "
    env_options+=" LIBS=\"${klee_libs}\" "
  fi

  env_options+="LDFLAGS=\"${klee_ldflags}\" CXXFLAGS=\"${klee_cxxflags}\" CFLAGS=\"${klee_cflags}\" "

  ### HACK ### need to remove libraries from install location so that
  # old klee/cliver libs are not used before recently compiled libs
  #leval make $make_options uninstall

  leval make $env_options $make_options $TARGET
}

build_klee_helper()
{
  local klee="klee"
  local options=$1
  local tag=$2

  if [ $FORCE_CLEAN -eq 1 ]; then 
    necho "[Cleaning$tag] "
    make_klee "$options clean"
  fi

  necho "[Compiling$tag] "
  make_klee "$options"

  if [ $SKIP_TESTS -eq 0 ]; then

    # skipping tests for asan and tsan versions because of memory leaks and thread errors
    if [[ $options != *SANITIZER* ]]; then
      necho "[Testing$tag] "
      cd $ROOT_DIR"/build/$KLEE/test"
      # need to force remake of lit.site.cfg
      # make test will overwrite results from previous build configurations
      leval make --always-make "$options" VERBOSE=1 lit.site.cfg
      leval make "$options" VERBOSE=1 
      cd $ROOT_DIR"/build/$KLEE/"
    else
      necho "[Testing$tag (skipped)] "
    fi

    # skipping unittests for sanitizer versions because of linking errors
    if [[ $options != *SANITIZER* ]]; then
      necho "[Unittesting$tag] "
      make_klee "LD_LIBRARY_PATH=${BOOST_ROOT}/lib ${options} ENABLE_SHARED=0 unittests "
    else
      necho "[Unittesting$tag (skipped)] "
    fi
  fi

  necho "[Installing$tag] "
  make_klee "$options install"

  if [ ${#tag} -gt 0 ]; then
    leval cp "$KLEE_ROOT/bin/$klee" "$KLEE_ROOT/bin/$klee$tag"
  fi
}

build_klee()
{
  mkdir -p $KLEE_ROOT

  local release_build_options="ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=1 DISABLE_TIMER_STATS=1 DEBUG_SYMBOLS=1 "
  local release_tag=""

  local debug_build_options="ENABLE_OPTIMIZED=0 DISABLE_ASSERTIONS=0 DISABLE_TIMER_STATS=0 "
  local debug_tag=""

  local single_thread_build_options="DISABLE_THREADS=1 "
  local single_thread_tag="-st"

  if [ $BUILD_DEBUG -eq 1 ]; then
    build_klee_helper "$debug_build_options ENABLE_ADDRESS_SANITIZER=1" "${debug_tag}-asan"
    build_klee_helper "$debug_build_options ENABLE_THREAD_SANITIZER=1" "${debug_tag}-tsan"

    # ThreadSanitizer and AddressSanitizer don't work with tcmalloc, enable here
    debug_build_options+="ENABLE_TCMALLOC=1 "

    build_klee_helper "$debug_build_options$single_thread_build_options" "$debug_tag$single_thread_tag"
    build_klee_helper "$debug_build_options" "$debug_tag"
  else
    build_klee_helper "$release_build_options ENABLE_ADDRESS_SANITIZER=1" "${release_tag}-asan"
    build_klee_helper "$release_build_options ENABLE_THREAD_SANITIZER=1" "${release_tag}-tsan"

    # ThreadSanitizer and AddressSanitizer don't work with tcmalloc, enable here
    release_build_options+="ENABLE_TCMALLOC=1 "

    build_klee_helper "$release_build_options$single_thread_build_options" "$release_tag$single_thread_tag"
    build_klee_helper "$release_build_options" "$release_tag"
  fi
}

install_klee()
{
  necho "$KLEE\t\t\t"

  check_dirs $KLEE || { return 0; }

  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone $KLEE_GIT 

  cd $ROOT_DIR"/src/$KLEE"

  leval git checkout $KLEE_BRANCH
  
  necho "[Configuring] "
  config_klee

  build_klee

  necho "[Done]\n"
}

update_klee()
{
  necho "$KLEE\t\t\t"

  if [ ! -e "$ROOT_DIR/src/$KLEE/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$KLEE

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$KLEE_BRANCH" ]; then
      echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    fi

    necho "[Checking] "
    leval git remote update 
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      necho "[Pulling] "
      leval git pull --all 
    fi

    if [ $FORCE_CONFIGURE -eq 1 ]; then 
      necho "[Configuring] "
      config_klee
    fi

    build_klee

  fi

  necho "[Done]\n"
}

build_tetrinet()
{
  TETRINET_MAKE_OPTIONS="NCURSES_DIR=${NCURSES_ROOT} "
  TETRINET_MAKE_OPTIONS+="PREFIX=${TETRINET_ROOT} "
  TETRINET_MAKE_OPTIONS+="LLVMCOMPILER=\"${CLANG_ROOT}/bin/${LLVM_CC}\" "
  TETRINET_MAKE_OPTIONS+="LLVMCOMPILER_FLAGS=\"-I${GLIBC_INCLUDE_PATH}\" "
  TETRINET_MAKE_OPTIONS+="LLVMLINKER=\"${LLVM_ROOT}/bin/${LLVM_LD}\" "

  if test ${ALTCC+defined}; then
    TETRINET_MAKE_OPTIONS+="CC=$ALTCC LD=$ALTCC "
  fi

  necho "[Compiling] "
  leval make $TETRINET_MAKE_OPTIONS install

  necho "[Installing] "
  mkdir -p $TETRINET_ROOT
  leval make $TETRINET_MAKE_OPTIONS install 
}

update_tetrinet()
{
  necho "$TETRINET\t\t"

  if [ ! -e "$ROOT_DIR/src/$TETRINET/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$TETRINET

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$TETRINET_BRANCH" ]; then
      echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    fi
    
    necho "[Checking] "
    leval git remote update 
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      necho "[Pulling] "
      leval git pull --all 
    fi

    if [ $FORCE_CLEAN -eq 1 ]; then 
      necho "[Cleaning] "
      leval make clean 
    fi

    build_tetrinet

  fi

  necho "[Done]\n"
}

install_tetrinet()
{
  necho "$TETRINET\t\t"

  check_dirs $TETRINET|| { return 0; }

  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone $TETRINET_GIT 

  cd $ROOT_DIR"/src/$TETRINET"

  if [ "$TETRINET_BRANCH" != "master" ]; then
    leval git checkout $TETRINET_BRANCH
  fi

  build_tetrinet

  necho "[Done]\n"
}

config_and_build_xpilot_with_wllvm()
{
  local llvm_compiler_options=$1
  local tag=$2

  local xpilot_config_options=""
  xpilot_config_options+="--disable-sdl-client --disable-sdl-gameloop "
  xpilot_config_options+="--disable-sdltest --disable-xp-mapedit "
  xpilot_config_options+="--disable-replay --disable-sound "
  xpilot_config_options+="--enable-select-sched --prefix=$XPILOT_ROOT "
  xpilot_config_options+="--program-suffix=${tag} "

  local make_options=""
  make_options+="CC=wllvm "
  make_options+="C_INCLUDE_PATH=${GLIBC_INCLUDE_PATH} "
  make_options+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "

  export LLVM_COMPILER=${LLVM_CC}
  export LLVM_COMPILER_FLAGS="-fno-slp-vectorize -fno-slp-vectorize-aggressive -fno-vectorize -I${GLIBC_INCLUDE_PATH} -B${GLIBC_LIBRARY_PATH} -DXLIB_ILLEGAL_ACCESS -D__GNUC__ ${llvm_compiler_options} "
  PATH_ORIGINAL="${PATH}"
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  necho "[Configuring-for${tag}] "
  leval $ROOT_DIR/src/$XPILOT/configure $xpilot_config_options $make_options

  necho "[Compiling-for${tag}] "
  leval make $make_options

  necho "[Installing-for${tag}] "
  mkdir -p $XPILOT_ROOT
  leval make $make_options install
  leval extract-bc $XPILOT_ROOT/bin/xpilot-ng-x11${tag}

  necho "[Optimizing-for${tag}] "
  local opt_passes="-O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
  if [ $BUILD_DEBUG_ALL -eq 0 ]; then
    opt_passes="-strip-debug ${opt_passes}"
  fi
  leval ${LLVM_ROOT}/bin/opt -load=${KLEE_ROOT}/lib/libkleePasses.so ${opt_passes} --time-passes -o ${XPILOT_ROOT}/bin/xpilot-ng-x11${tag}-opt.bc ${XPILOT_ROOT}/bin/xpilot-ng-x11${tag}.bc

  export PATH="${PATH_ORIGINAL}"
}

update_xpilot_with_wllvm()
{
  necho "$XPILOT\t\t\t"

  if [ ! -e "$ROOT_DIR/src/$XPILOT/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$XPILOT

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$XPILOT_BRANCH" ]; then
      echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    fi

    necho "[Checking] "
    leval git remote update
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      necho "[Pulling] "
      leval git pull --all
    fi

    # Build two versions of xpilot, to support cliver and lli
    config_and_build_xpilot_with_wllvm "-DNUKLEAR" "-klee"
    config_and_build_xpilot_with_wllvm " " "-run"
  fi

  necho "[Done]\n"
}

install_xpilot_with_wllvm()
{
  necho "$XPILOT\t\t\t"

  check_dirs $XPILOT || { return 0; }
  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone $XPILOT_GIT $XPILOT

  cd $ROOT_DIR"/src/$XPILOT"

  if [ "$XPILOT_BRANCH" != "master" ]; then
    leval git checkout $XPILOT_BRANCH
  fi

  # Build two versions of xpilot, to support cliver and lli
  config_and_build_xpilot_with_wllvm "-DNUKLEAR" "-klee"
  config_and_build_xpilot_with_wllvm " " "-run"

  necho "[Done]\n"
}

config_and_build_openssl()
{
  local llvm_compiler_options=$1
  local tag=$2

  local openssl_config_options=""
  openssl_config_options+="--prefix=${OPENSSL_ROOT} "
  openssl_config_options+="no-asm no-threads no-shared -DPURIFY "
  openssl_config_options+="-DCLIVER "
  openssl_config_options+="-DOPENSSL_NO_LOCKING "
  openssl_config_options+="-DOPENSSL_NO_ERR "

  if [ $BUILD_DEBUG_ALL -eq 1 ]; then
    # Warning: this adds not only debug symbols to OpenSSL, but also extra
    # debug code like a custom malloc(). Cliver will be much slower.
    openssl_config_options+="-d " # compile with debugging symbols
  fi

  local make_options=""
  make_options+="CC=wllvm "
  make_options+="C_INCLUDE_PATH=${GLIBC_INCLUDE_PATH} "
  make_options+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "

  export LLVM_COMPILER=${LLVM_CC}
  export LLVM_COMPILER_FLAGS="-fno-slp-vectorize -fno-slp-vectorize-aggressive -fno-vectorize -I${GLIBC_INCLUDE_PATH} -B${GLIBC_LIBRARY_PATH} ${llvm_compiler_options} "
  PATH_ORIGINAL="${PATH}"
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  # Create 'makedepend' replacement
  MAKEDEPEND="${ROOT_DIR}/local/bin/makedepend"
  echo "#!/bin/bash" > "${MAKEDEPEND}"
  echo 'exec '"${LLVM_COMPILER}"' -M "$@"' >> "${MAKEDEPEND}"
  chmod +x "${MAKEDEPEND}"

  necho "[Configuring-for${tag}] "
  leval $ROOT_DIR/src/$OPENSSL/config $openssl_config_options

  necho "[Compiling-for${tag}] "
  leval make $make_options depend
  leval make $make_options

  if [ $SKIP_TESTS -eq 1 ]; then
    necho "[Testing-for${tag} (skipped)] "
  else
    necho "[Testing-for${tag}] "
    leval make $make_options test
  fi

  necho "[Installing-for${tag}] "
  mkdir -p $OPENSSL_ROOT
  leval make install_sw
  leval extract-bc $OPENSSL_ROOT/bin/openssl
  leval cp $OPENSSL_ROOT/bin/openssl.bc $OPENSSL_ROOT/bin/openssl${tag}.bc

  export PATH="${PATH_ORIGINAL}"
}

config_and_build_openssl_shared()
{
  local tag="-shared"

  local openssl_config_options=""
  openssl_config_options+="--prefix=${OPENSSL_ROOT} "
  openssl_config_options+="no-asm no-threads shared -DPURIFY "
  #openssl_config_options+="-DCLIVER "
  openssl_config_options+="-DOPENSSL_NO_LOCKING "
  openssl_config_options+="-DOPENSSL_NO_ERR "
  openssl_config_options+="-L${OPENSSL_ROOT}/lib "

  local make_options=""

  PATH_ORIGINAL="${PATH}"
  export PATH="${ROOT_DIR}/local/bin:${PATH}"

  # Create 'makedepend' replacement
  if test ${ALTCC+defined}; then
    CC=${ALTCC}
  else
    CC=gcc
  fi
  MAKEDEPEND="${ROOT_DIR}/local/bin/makedepend"
  echo "#!/bin/bash" > "${MAKEDEPEND}"
  echo 'exec '"${CC}"' -M "$@"' >> "${MAKEDEPEND}"
  chmod +x "${MAKEDEPEND}"

  necho "[Configuring-for${tag}] "
  leval $ROOT_DIR/src/$OPENSSL/config $openssl_config_options

  necho "[Compiling-for${tag}] "
  leval make $make_options depend
  leval make $make_options

  necho "[Installing-for${tag}] "
  mkdir -p $OPENSSL_ROOT
  leval make install_sw

  # Clean afterwards so that future builds don't get confused
  necho "[Cleaning] "
  leval make clean

  export PATH="${PATH_ORIGINAL}"
}

build_optimized_openssl_bitcode()
{
  local tag=$1

  necho "[Optimizing-for${tag}] "
  local opt_passes="-O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
  if [ $BUILD_DEBUG_ALL -eq 0 ]; then
    opt_passes="-strip-debug ${opt_passes}"
  fi
  leval ${LLVM_ROOT}/bin/opt -load=${KLEE_ROOT}/lib/libkleePasses.so ${opt_passes} --time-passes -o ${OPENSSL_ROOT}/bin/openssl-opt${tag}.bc ${OPENSSL_ROOT}/bin/openssl${tag}.bc
}
 
manage_openssl()
{
  necho "$OPENSSL  \t\t"
  case $1 in
    install)
      check_dirs $OPENSSL || { return 0; }

      cd $ROOT_DIR"/src"

      necho "[Cloning] "
      leval git clone $OPENSSL_GIT $OPENSSL

      cd $ROOT_DIR"/src/$OPENSSL"

      leval git checkout $OPENSSL_BRANCH

      # Build native shared library (.so) for linking with other libraries
      config_and_build_openssl_shared

      # Build two versions of openssl, to support cliver and lli
      config_and_build_openssl "-DKLEE" "-klee"
      config_and_build_openssl " " "-run"
      ;;

    update)
      if [ ! -e "$ROOT_DIR/src/$OPENSSL/.git" ]; then
        echo "[Error] (git directory missing) "; exit;
      fi

      cd $ROOT_DIR/src/$OPENSSL

      if [ $BUILD_LOCAL -eq 0 ]; then
        if [ "$(git_current_branch)" != "$OPENSSL_BRANCH" ]; then
          echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
        fi
        necho "[Checking] "
        leval git remote update
      fi

      if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

        if [ $BUILD_LOCAL -eq 0 ]; then
          necho "[Pulling] "
          leval git pull --all
        fi

        if [ $FORCE_CLEAN -eq 1 ]; then
          necho "[Cleaning] "
          leval make clean
        fi

        # Build native shared library (.so) for linking with other libraries
        config_and_build_openssl_shared

        # Build two versions of openssl, to support cliver and lli
        config_and_build_openssl "-DKLEE" "-klee"
        config_and_build_openssl " " "-run"

        # run opt on two versions of openssl, to support cliver and lli
        build_optimized_openssl_bitcode "-klee"
        build_optimized_openssl_bitcode "-run"
      fi
      ;;
    opt*)
      # run opt on two versions of openssl, to support cliver and lli
      build_optimized_openssl_bitcode "-klee"
      build_optimized_openssl_bitcode "-run"
      ;;

  esac
  necho "[Done]\n"
}

###############################################################################

manage_testclientserver()
{
  necho "$TESTCLIENTSERVER \t"
  case $1 in
    install)
      check_dirs $TESTCLIENTSERVER || { return 0; }

      cd $ROOT_DIR"/src"
      leval mkdir $TESTCLIENTSERVER

      ## KLEE needs to be installed
      necho "[Copying] "
      leval cp ./$KLEE/test/Cliver/ClientServer.c ./$TESTCLIENTSERVER
      leval cp ./$KLEE/test/Cliver/KTestSocket.inc ./$TESTCLIENTSERVER
      leval cp ./$KLEE/lib/Basic/KTest.cpp ./$TESTCLIENTSERVER

      cd $ROOT_DIR"/src/$TESTCLIENTSERVER"
      local srcfile="ClientServer.c"
      local native_compile_flags="-B/usr/lib/x86_64-linux-gnu KTest.cpp $srcfile -DKTEST=\"\\\"./$TESTCLIENTSERVER.ktest\\\"\" -I$ROOT_DIR\"/src/klee/include\" "
      local bc_compile_flags=" $srcfile -I$ROOT_DIR\"/src/klee/include\" -DKLEE -DCLIENT -emit-llvm -c "

      local TESTCC=gcc
      if test ${ALTCC+defined}; then
        TESTCC=$ALTCC
      fi

      necho "[Compiling] "
      leval ${CLANG_ROOT}/bin/${LLVM_CC} -g ${bc_compile_flags} -o $TESTCLIENTSERVER.bc
      leval ${TESTCC} $native_compile_flags -g -o $TESTCLIENTSERVER

      necho "[Installing] "
      leval cp $TESTCLIENTSERVER $ROOT_DIR/local/bin/
      leval cp $TESTCLIENTSERVER.bc $ROOT_DIR/local/bin/
      ;;

    update)
      ;;

  esac
  necho "[Done]\n"
}

###############################################################################


config_and_build_openssh()
{
  local llvm_compiler_options=$1
  local tag=$2
  mkdir -p ${LOCAL_ROOT}/var/empty

  local openssh_config_options=""
  openssh_config_options+="--prefix=${OPENSSH_ROOT} "
  #openssh_config_options+="--with-ssl-dir=${OPENSSL_ROOT} "
  openssh_config_options+="--without-openssl "
  openssh_config_options+="--without-pie "
  openssh_config_options+="--disable-strip "
  openssh_config_options+="--with-privsep-path=${LOCAL_ROOT}/var/empty "

  local config_env=""
  config_env+="CC=wllvm "
  local cflags_for_config=""
  cflags_for_config="-DCLIVER "
  cflags_for_config+="-DWITH_KTEST "

  if [ $BUILD_DEBUG_ALL -eq 1 ]; then
    cflags_for_config+="-g " # compile with debugging symbols
  fi

  cflags_for_config+=""
  config_env+="CFLAGS=\"${cflags_for_config}\" "

  #llvm_compiler_options+="-DOPENSSL_PRNG_ONLY " # don't gather entropy locally

  local make_options=""
  make_options+="-j $MAKE_THREADS " # parallel build
  #make_options+="CC=wllvm "
  #make_options+="C_INCLUDE_PATH=${GLIBC_INCLUDE_PATH} "
  #make_options+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "

  export LLVM_COMPILER=${LLVM_CC}
  export LLVM_COMPILER_FLAGS="-fno-slp-vectorize -fno-slp-vectorize-aggressive -fno-vectorize -I${GLIBC_INCLUDE_PATH} -B${GLIBC_LIBRARY_PATH} ${llvm_compiler_options} "
  PATH_ORIGINAL="${PATH}"
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  if [ $FORCE_CLEAN -eq 1 ]; then
    necho "[Cleaning] "
    leval make clean
  fi

  necho "[Configuring-for${tag}] "
  leval autoreconf -i
  leval $config_env $ROOT_DIR/src/$OPENSSH/configure $openssh_config_options

  necho "[Compiling-for${tag}] "
  leval make $make_options

  # Note: this takes forever, and uses specific hard-coded ports.  Therefore,
  # only one instance of OpenSSH "make tests" can be run on the machine at any
  # point in time.
  # Unfortunately, "make tests" breaks when built --without-openssl.  We
  # therefore disable the tests for now.
  necho "[Testing disabled] "
  #if [ $SKIP_TESTS -eq 0 ]; then
  #  necho "[Testing] "
  #  local RETRY=180 # keep retrying for about 3 hours (6 builds)
  #  leval lockfile-create --use-pid --retry $RETRY --lock-name $OPENSSH_LOCKFILE
  #  leval make tests
  #  leval lockfile-remove --lock-name $OPENSSH_LOCKFILE
  #fi

  necho "[Installing-for${tag}] "
  mkdir -p $OPENSSH_ROOT
  leval make install-nokeys
  leval extract-bc $OPENSSH_ROOT/bin/ssh
  leval cp $OPENSSH_ROOT/bin/ssh.bc $OPENSSH_ROOT/bin/ssh${tag}.bc

  leval extract-bc $OPENSSH_ROOT/sbin/sshd
  leval cp $OPENSSH_ROOT/sbin/sshd.bc $OPENSSH_ROOT/sbin/sshd${tag}.bc

  export PATH="${PATH_ORIGINAL}"
}

build_optimized_openssh_bitcode()
{
  local tag=$1

  necho "[Optimizing-for${tag}] "
  local opt_passes="-O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
  if [ $BUILD_DEBUG_ALL -eq 0 ]; then
    opt_passes="-strip-debug ${opt_passes}"
  fi
  leval ${LLVM_ROOT}/bin/opt -load=${KLEE_ROOT}/lib/libkleePasses.so ${opt_passes} --time-passes -o ${OPENSSH_ROOT}/bin/ssh-opt${tag}.bc ${OPENSSH_ROOT}/bin/ssh${tag}.bc
}

manage_openssh()
{
  necho "$OPENSSH  \t\t"
  case $1 in
    install)
      check_dirs $OPENSSH || { return 0; }

      cd $ROOT_DIR"/src"

      necho "[Cloning] "
      leval git clone $OPENSSH_GIT $OPENSSH

      cd $ROOT_DIR"/src/$OPENSSH"

      leval git checkout $OPENSSH_BRANCH

      # Build only one version. Later we might need 2 versions in order to
      # support cliver and lli, like OpenSSL.
      config_and_build_openssh "-DKLEE " "-klee"
      #config_and_build_openssh " " "-run"
      ;;

    update)
      if [ ! -e "$ROOT_DIR/src/$OPENSSH/.git" ]; then
        echo "[Error] (git directory missing) "; exit;
      fi

      cd $ROOT_DIR/src/$OPENSSH

      if [ $BUILD_LOCAL -eq 0 ]; then
        if [ "$(git_current_branch)" != "$OPENSSH_BRANCH" ]; then
          echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
        fi
        necho "[Checking] "
        leval git remote update
      fi

      if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

        if [ $BUILD_LOCAL -eq 0 ]; then
          necho "[Pulling] "
          leval git pull --all
        fi

        # Build only one version. Later we might need 2 versions in order to
        # support cliver and lli, like OpenSSL.
        config_and_build_openssh "-DKLEE " "-klee"
        #config_and_build_openssh " " "-run"
      fi
      ;;

    opt*)
      # Run LLVM optimizer (opt) on only one version. Later we might need 2
      # versions in order to support cliver and lli, like OpenSSL.
      build_optimized_openssh_bitcode "-klee"
      #build_optimized_openssh_bitcode "-run"
      ;;
  esac
  necho "[Done]\n"
}

###############################################################################
config_and_build_boringssl()
{
  local llvm_compiler_options=$1
  local tag=$2
  local save_directory="$(pwd)"
  local boringssl_build_directory="$ROOT_DIR/build/$BORINGSSL"

  local boringssl_config_options=""
  boringssl_config_options+="-DCMAKE_INSTALL_PREFIX=${BORINGSSL_ROOT} "

  if [ $BUILD_DEBUG_ALL -eq 0 ]; then
    # The default BoringSSL build is debug, compiled with -ggdb
    boringssl_config_options+="-DCMAKE_BUILD_TYPE=Release "
  fi

  local make_options=""
  make_options+="CC=wllvm "
  make_options+="CXX=wllvm++ "
  make_options+="C_INCLUDE_PATH=${GLIBC_INCLUDE_PATH} "
  make_options+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "
  local cflags_options=""
  cflags_options+="-DOPENSSL_NO_ASM "
  cflags_options+="-DOPENSSL_NO_THREADS "
  cflags_options+="-DCLIVER "
  make_options+="CFLAGS='${cflags_options}' "
  local cxxflags_options=""
  cxxflags_options+="${cflags_options} "
  make_options+="CXXFLAGS='${cxxflags_options}' "

  export LLVM_COMPILER=${LLVM_CC}
  LLVM_COMPILER_FLAGS=""
  LLVM_COMPILER_FLAGS+="-fno-slp-vectorize "
  LLVM_COMPILER_FLAGS+="-fno-slp-vectorize-aggressive "
  LLVM_COMPILER_FLAGS+="-fno-vectorize "
  LLVM_COMPILER_FLAGS+="-I${GLIBC_INCLUDE_PATH} -B${GLIBC_LIBRARY_PATH} "
  LLVM_COMPILER_FLAGS+="${llvm_compiler_options} "
  export LLVM_COMPILER_FLAGS
  PATH_ORIGINAL="${PATH}"
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  necho "[Configuring-for${tag}] "
  leval mkdir -p "$boringssl_build_directory"
  leval cd "$boringssl_build_directory"
  leval rm -f CMakeCache.txt
  leval $make_options cmake -GNinja \
      $boringssl_config_options \
      $ROOT_DIR/src/$BORINGSSL

  necho "[Cleaning-for${tag}] "
  leval ninja clean

  necho "[Compiling-for${tag}] "
  leval ninja

  if [ $SKIP_TESTS -eq 0 ]; then
    necho "[Testing-for${tag}] "
    # Do we need to use a system-wide lockfile here?
    leval ninja run_tests
  fi

  necho "[Installing-for${tag}] "
  leval mkdir -p $BORINGSSL_ROOT
  leval cp tool/bssl $BORINGSSL_ROOT/bin/
  leval extract-bc $BORINGSSL_ROOT/bin/bssl
  leval cp $BORINGSSL_ROOT/bin/bssl.bc $BORINGSSL_ROOT/bin/bssl${tag}.bc

  export PATH="${PATH_ORIGINAL}"

  cd $save_directory
}

build_optimized_boringssl_bitcode()
{
  local tag=$1

  necho "[Optimizing-for${tag}] "
  local opt_passes="-O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
  if [ $BUILD_DEBUG_ALL -eq 0 ]; then
    opt_passes="-strip-debug ${opt_passes}"
  fi
  leval ${LLVM_ROOT}/bin/opt -load=${KLEE_ROOT}/lib/libkleePasses.so ${opt_passes} --time-passes -o ${BORINGSSL_ROOT}/bin/bssl-opt${tag}.bc ${BORINGSSL_ROOT}/bin/bssl${tag}.bc
}

manage_boringssl()
{
  local boringssl_build_directory="$ROOT_DIR/build/$BORINGSSL"

  necho "$BORINGSSL  \t\t"
  case $1 in
    install)
      check_dirs $BORINGSSL || { return 0; }

      cd $ROOT_DIR"/src"

      necho "[Cloning] "
      leval git clone $BORINGSSL_GIT $BORINGSSL

      cd $ROOT_DIR"/src/$BORINGSSL"

      leval git checkout $BORINGSSL_BRANCH

      # Build two versions of boringssl, to support cliver and lli
      config_and_build_boringssl "-DKLEE" "-klee"
      config_and_build_boringssl " " "-run"
      ;;

    update)
      if [ ! -e "$ROOT_DIR/src/$BORINGSSL/.git" ]; then
        echo "[Error] (git directory missing) "; exit;
      fi

      cd $ROOT_DIR/src/$BORINGSSL

      if [ $BUILD_LOCAL -eq 0 ]; then
        if [ "$(git_current_branch)" != "$BORINGSSL_BRANCH" ]; then
          echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
        fi
        necho "[Checking] "
        leval git remote update
      fi

      if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

        if [ $BUILD_LOCAL -eq 0 ]; then
          necho "[Pulling] "
          leval git pull --all
        fi

        if [ $FORCE_CLEAN -eq 1 ]; then
          necho "[Cleaning] "
          leval cd $boringssl_build_directory
          leval ninja clean
          leval cd -
        fi

        # Build two versions of boringssl, to support cliver and lli
        config_and_build_boringssl "-DKLEE" "-klee"
        config_and_build_boringssl " " "-run"

        # run opt on two versions of boringssl, to support cliver and lli
        build_optimized_boringssl_bitcode "-klee"
        build_optimized_boringssl_bitcode "-run"
      fi
      ;;
    opt*)
      # run opt on two versions of boringssl, to support cliver and lli
      build_optimized_boringssl_bitcode "-klee"
      build_optimized_boringssl_bitcode "-run"
      ;;

  esac
  necho "[Done]\n"
}

###############################################################################
config_and_build_libmodbus()
{
  local llvm_compiler_options=$1
  local tag=$2
  local save_directory="$(pwd)"
  # Unfortunately, libmodbus doesn't support out-of-source-dir builds,
  # so libmodbus_build_dir == libmodbus_src_dir
  local libmodbus_build_dir="$ROOT_DIR/src/$LIBMODBUS"

  local config_options=""
  config_options+="--prefix=${LIBMODBUS_ROOT} "
  config_options+="--enable-static "
  config_options+="CC=wllvm "
  local cflags_options=""
  if [ $BUILD_DEBUG_ALL -eq 1 ]; then
    cflags_options+="-g -O0 "
  fi
  cflags_options+="-DCLIVER "
  config_options+="CFLAGS='${cflags_options}' "

  local make_options=""
  make_options+="C_INCLUDE_PATH=${GLIBC_INCLUDE_PATH} "
  make_options+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "

  export LLVM_COMPILER=${LLVM_CC}
  LLVM_COMPILER_FLAGS=""
  LLVM_COMPILER_FLAGS+="-fno-slp-vectorize "
  LLVM_COMPILER_FLAGS+="-fno-slp-vectorize-aggressive "
  LLVM_COMPILER_FLAGS+="-fno-vectorize "
  LLVM_COMPILER_FLAGS+="-I${GLIBC_INCLUDE_PATH} -B${GLIBC_LIBRARY_PATH} "
  LLVM_COMPILER_FLAGS+="${llvm_compiler_options} "
  export LLVM_COMPILER_FLAGS
  PATH_ORIGINAL="${PATH}"
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  necho "[Configuring-for${tag}] "
  #leval mkdir -p "$libmodbus_build_dir"
  leval cd "$libmodbus_build_dir"
  leval ./autogen.sh
  leval ./configure ${config_options}

  necho "[Cleaning-for${tag}] "
  leval make clean

  necho "[Compiling-for${tag}] "
  leval make V=1

  # libmodbus "make check" is a no-op; tests must be run manually

  # if [ $SKIP_TESTS -eq 0 ]; then
  #   necho "[Testing-for${tag}] "
  #   # Do we need to use a system-wide lockfile here?
  #   leval make check
  # fi

  necho "[Installing-for${tag}] "
  leval mkdir -p "${LIBMODBUS_ROOT}/bin"
  leval make install
  leval cp tests/unit-test-server \
        "${LIBMODBUS_ROOT}"/bin/libmodbus-unit-test-server
  local clientpath="${LIBMODBUS_ROOT}"/bin/libmodbus-unit-test-client
  leval cp tests/unit-test-client "${clientpath}"
  leval extract-bc "${clientpath}"
  leval cp "${clientpath}.bc" "${clientpath}${tag}.bc"

  export PATH="${PATH_ORIGINAL}"

  cd $save_directory
}

build_optimized_libmodbus_bitcode()
{
  local tag=$1
  local clientpath="${LIBMODBUS_ROOT}"/bin/libmodbus-unit-test-client

  necho "[Optimizing-for${tag}] "
  local opt_passes="-O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
  if [ $BUILD_DEBUG_ALL -eq 0 ]; then
    opt_passes="-strip-debug ${opt_passes}"
  fi
  leval ${LLVM_ROOT}/bin/opt -load=${KLEE_ROOT}/lib/libkleePasses.so \
        ${opt_passes} --time-passes -o "${clientpath}-opt${tag}.bc" \
        "${clientpath}${tag}.bc"
}

manage_libmodbus()
{
  # Unfortunately, libmodbus doesn't support out-of-source-dir builds,
  # so libmodbus_build_dir == libmodbus_src_dir
  local libmodbus_build_dir="$ROOT_DIR/src/$LIBMODBUS"
  local libmodbus_src_dir="$ROOT_DIR/src/$LIBMODBUS"

  necho "$LIBMODBUS  \t\t"
  case $1 in
    install)
      check_dirs $LIBMODBUS || { return 0; }

      cd $ROOT_DIR"/src"

      necho "[Cloning] "
      leval git clone $LIBMODBUS_GIT $LIBMODBUS

      cd "$libmodbus_src_dir"

      leval git checkout $LIBMODBUS_BRANCH

      # Build two versions of libmodbus, to support cliver and lli
      config_and_build_libmodbus "-DKLEE" "-klee"
      config_and_build_libmodbus " " "-run"
      ;;

    update)
      if [ ! -e "$ROOT_DIR/src/$LIBMODBUS/.git" ]; then
        echo "[Error] (git directory missing) "; exit;
      fi

      cd $ROOT_DIR/src/$LIBMODBUS

      if [ $BUILD_LOCAL -eq 0 ]; then
        if [ "$(git_current_branch)" != "$LIBMODBUS_BRANCH" ]; then
          echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
        fi
        necho "[Checking] "
        leval git remote update
      fi

      if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind
      then

        if [ $BUILD_LOCAL -eq 0 ]; then
          necho "[Pulling] "
          leval git pull --all
        fi

        if [ $FORCE_CLEAN -eq 1 ]; then
          necho "[Cleaning] "
          leval cd $libmodbus_build_dir
          leval make clean
          leval cd -
        fi

        # Build two versions of libmodbus, to support cliver and lli
        config_and_build_libmodbus "-DKLEE" "-klee"
        config_and_build_libmodbus " " "-run"

        # run opt on two versions of libmodbus, to support cliver and lli
        build_optimized_libmodbus_bitcode "-klee"
        build_optimized_libmodbus_bitcode "-run"
      fi
      ;;
    opt*)
      # run opt on two versions of libmodbus, to support cliver and lli
      build_optimized_libmodbus_bitcode "-klee"
      build_optimized_libmodbus_bitcode "-run"
      ;;

  esac
  necho "[Done]\n"
}

###############################################################################

on_exit()
{
  if [ $ERROR_EXIT -eq 1 ]; then
    lecho "Error"
    lockfile-remove --lock-name $OPENSSH_LOCKFILE > /dev/null 2>&1
    if ! [ $VERBOSE_OUTPUT -eq 1 ]; then
      if test ${LOG_FILE+defined}; then
        necho "\n\n"
        grep "error: " ${LOG_FILE} | tail -n 20
        necho "\n"
      fi
    fi
  fi
  if [ $ERROR_EXIT -eq 0 ]; then
    lecho "Success! Elapsed time: $(elapsed_time $start_time)"
  fi
}

###############################################################################

main() 
{
  echo
  echo "====--configuration--===="
  while getopts ":ae:fkcivsb:r:j:dDltn" opt; do
    case $opt in

      e) # variables supplementing or overriding gsec_common
        EXTRA_BUILD_CONFIG=$OPTARG
        source ${EXTRA_BUILD_CONFIG}
        ;;

      f)
        lecho "Forcing compilation"
        FORCE_COMPILATION=1
        ;;
   
      d)
        lecho "Building (mostly) debug version"
        BUILD_DEBUG=1
        ;;

      D)
        lecho "Building completely debug version"
        BUILD_DEBUG=1
        BUILD_DEBUG_ALL=1
        ;;
 
      l)
        lecho "Compiling with local changes"
        BUILD_LOCAL=1
        FORCE_COMPILATION=1
        ;;

      k)
        lecho "Forcing make clean"
        FORCE_CLEAN=1
        ;;
  
      c)
        lecho "Forcing configure"
        FORCE_CONFIGURE=1
        ;;
  
      i)
        INSTALL_PACKAGES=1
        ;;
  
      v)
        lecho "Verbose output"
        VERBOSE_OUTPUT=1
        ;;
  
      b)
        lecho "Only building $OPTARG"
        SELECTIVE_BUILD=1
        SELECTIVE_BUILD_TARGET="$OPTARG"
        ;;
  
      s)
        lecho "\"Speedy build\" skipping tests"
        SKIP_TESTS=1
        ;;
  
      r)
        lecho "Setting root dir to $OPTARG"
        ROOT_DIR="$OPTARG"
        ;;
  
      j)
        lecho "Using $OPTARG threads"
        MAKE_THREADS=$OPTARG
        ;;

      :)
        echo "Option -$OPTARG requires an argument"
        exit
        ;;

       n)
        lecho "Using LLVM 2.9 and llvm-gcc-4.2"
        lecho "NOT SUPPORTED" ; exit
        #USE_LLVM29=1
        #LLVM="llvm-2.9"
        #LLVM_PACKAGE="$LLVM.tgz"
        #LLVMGCC_BIN="llvm-gcc4.2-2.9"
        #LLVMGCC_BIN_PACKAGE="$LLVMGCC_BIN-x86_64-linux.tar.bz2"
        #LLVM_CC="llvm-gcc"
        #LLVM_LD="llvm-ld"
        ;;


    esac
  done

  if [ $USE_LLVM29 -eq 1 ]; then
    lecho "Using LLVM 2.9 and llvm-gcc-4.2"
    lecho "NOT SUPPORTED" ; exit
  fi  
  
  # force usage of gcc-5
  set_alternate_gcc

  if [ $KLEE_SMT_SOLVER == $Z3 ]; then
    lecho "Building with Z3"
  elif [ $USE_STP_NEW -eq 1 ]; then
    lecho "Building with newer STP + minisat"
  else
    lecho "Building with older STP + cryptominisat2"
  fi

  lecho "Compiling with $(max_threads) threads"

  initialize_root_directories

  initialize_logging $@


  if [ $INSTALL_PACKAGES -eq 1 ]; then
    echo
    echo "====--installation--===="
  
    mkdir -p $ROOT_DIR/{src,local,build}

    if [ $INSTALL_CLANG_BIN -eq 1 ]; then
      install_clang_bin
    else
      install_clang_from_source
    fi

    install_llvm
  
    # google perftools requires libunwind on x86_64
    if [ "$(uname)" != "Darwin" ] ; then
      install_libunwind
    fi

    install_wllvm
    install_google_perftools
    # Boost is still required, but we can use the system version
    #install_boost
    install_uclibc_git
    install_ncurses
    if [ $KLEE_SMT_SOLVER == $Z3 ]; then
        install_z3
    elif [ $USE_STP_NEW -eq 1 ]; then
      install_minisat
      install_stp_git
    else
      install_stp
    fi
    #install_ghmm
    manage_openssl install
    manage_openssh install # NOTE: SSH depends on OpenSSL
    manage_boringssl install
    manage_libmodbus install
    install_folly
    install_klee
    manage_openssl opt # 'opt' requires klee to be installed
    manage_openssh opt
    manage_boringssl opt # 'opt' requires klee to be installed
    manage_libmodbus opt
    manage_testclientserver install
    #install_zlib # zlib is still required, but we can use the system version
    install_expat
    install_tetrinet
    install_xpilot_with_wllvm
  
  elif [ $SELECTIVE_BUILD -eq 1 ]; then
    echo
    echo "====--update--===="
    case $SELECTIVE_BUILD_TARGET in 
      klee*)
        update_klee
        ;;
      tetrinet*)
        update_tetrinet
        ;;
      xpilot)
        update_xpilot_with_wllvm
        ;;
      openssl)
        manage_openssl update
        ;;
      openssh)
        manage_openssh update
        manage_openssh opt
        ;;
      boringssl)
        manage_boringssl update
        ;;
      libmodbus)
        manage_libmodbus update
        ;;
      llvm)
        update_llvm
        ;;
      *)
       echo "${SELECTIVE_BUILD_TARGET} selective build recipe not found!"; exit
        ;;
    esac

  else
    echo
    echo "====--update--===="
    # update all
    update_wllvm
    manage_openssl update
    manage_openssh update # Note: SSH depends on OpenSSL
    manage_boringssl update
    manage_libmodbus update
    update_klee
    manage_openssl opt
    manage_openssh opt
    manage_boringssl opt
    manage_libmodbus opt
    update_tetrinet
    update_xpilot_with_wllvm
  fi

  echo
}

# set up exit handler
trap on_exit EXIT

# record start time
start_time=$(elapsed_time)

# Run main
main "$@"
ERROR_EXIT=0

