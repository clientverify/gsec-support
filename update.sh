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
. $HERE/gsec_common

# Command line options
FORCE_CLEAN=0
FORCE_COMPILATION=0
FORCE_CONFIGURE=0
INSTALL_PACKAGES=0
BUILD_DEBUG=0
BUILD_LOCAL=0 # build local code, don't checkout from git
SELECTIVE_BUILD=0
SELECTIVE_BUILD_TARGET=""
SKIP_INSTALL_ERRORS=1
SKIP_TESTS=0
INSTALL_CLANG_BIN=1
USE_LLVM29=0
USE_TSAN=0
USE_ASAN=0
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

install_zlib_llvm()
{
  necho "$ZLIB (llvm) \t"
  check_dirs $ZLIB-llvm || { return 0; }
  get_package $ZLIB_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$ZLIB-llvm"

  cd $ROOT_DIR/src/$ZLIB-llvm

  necho "[Configuring] "
  ZLIB_LLVM_OPTIONS="CC=$CLANG_ROOT/bin/llvm-gcc AR=$LLVM_ROOT/bin/llvm-ar CFLAGS=-emit-llvm"
  leval $ZLIB_LLVM_OPTIONS $ROOT_DIR/src/$ZLIB-llvm/configure --static --prefix=$ZLIB_ROOT 

  necho "[Compiling] "
  leval make libz.a 

  necho "[Installing] "
  mkdir -p $ZLIB_ROOT
  leval cp -p libz.a $ZLIB_ROOT/lib/libz-llvm.a

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
  BJAM_OPTIONS=" --without-python --build-dir=$ROOT_DIR/build/$BOOST -j$MAKE_THREADS"

  if test ${ALTCC+defined}; then
    echo "using gcc : $ALTCCVERSION : /usr/bin/$ALTCC ; " >> $ROOT_DIR/src/$BOOST/tools/build/v2/user-config.jam
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
  get_package $GOOGLE_PERFTOOLS_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$GOOGLE_PERFTOOLS"

  #necho "[Cloning] "
  #leval svn co $GOOGLE_PERFTOOLS_SVN $ROOT_DIR/src/$GOOGLE_PERFTOOLS
  #cd $ROOT_DIR/src/$GOOGLE_PERFTOOLS
  #leval ./autogen.sh

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

install_clang_bin()
{
  necho "$CLANG_VERSION\t"
  check_dirs "$CLANG_ROOT/bin/$LLVM_CC" || { return 0; }
  get_package $CLANG_BIN_PACKAGE $PACKAGE_DIR $CLANG_ROOT
  necho "[Done]\n"
}

install_llvmgcc_from_source()
{
  necho "$LLVMGCC\t"
  check_dirs $LLVMGCC || { return 0; }
  get_package $LLVMGCC_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$LLVMGCC"

  mkdir -p $ROOT_DIR/build/$LLVMGCC
  cd $ROOT_DIR/build/$LLVMGCC

  LLVMGCC_CONFIG_OPTIONS="--prefix=$LLVMGCC_ROOT --disable-multilib --program-prefix=llvm- "
  LLVMGCC_CONFIG_OPTIONS+="--enable-llvm=$LLVM_ROOT --enable-languages=c,c++ "

  LLVMGCC_CONFIG_ENV_OPTIONS=""

  if test ${ALTCC+defined}; then
    LLVMGCC_CONFIG_ENV_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  necho "[Configuring] "
  leval $LLVMGCC_CONFIG_ENV_OPTIONS $ROOT_DIR/src/$LLVMGCC/configure $LLVMGCC_CONFIG_OPTIONS 

  LLVMGCC_MAKE_OPTIONS=""

  if test ${ALTCC+defined}; then
    # HACK for LLVM 2.7 + GCC 4.2 support: needs path to crti.o
    LLVMGCC_MAKE_OPTIONS+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "
  fi

  necho "[Compiling] "
  leval make $LLVMGCC_MAKE_OPTIONS -j $MAKE_THREADS 

  necho "[Installing] "
  mkdir -p $LLVMGCC_ROOT
  leval make $LLVMGCC_MAKE_OPTIONS install 

  necho "[Done]\n"
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
  LLVM_CONFIG_OPTIONS+="--enable-optimized --disable-assertions --enable-shared --enable-pic --enable-libffi "

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

  LLVM_MAKE_OPTIONS=" -j $MAKE_THREADS REQUIRES_RTTI=1 "

  #if [ $BUILD_DEBUG -eq 1 ]; then
  #  LLVM_MAKE_OPTIONS+="ENABLE_OPTIMIZED=0 "
  #else
  #  LLVM_MAKE_OPTIONS+="ENABLE_OPTIMIZED=1 "
  #fi

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
      build_llvm "ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=0 "

      necho "[Installing Release] "
      mkdir -p $LLVM_ROOT
      build_llvm "ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=0 install"
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

  leval git checkout -b $LLVM_BRANCH origin/$LLVM_BRANCH

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

config_klee()
{
  cd $ROOT_DIR/src/$KLEE
  KLEE_CONFIG_OPTIONS="--prefix=$KLEE_ROOT -libdir=$KLEE_ROOT/lib/$KLEE "

  KLEE_CONFIG_OPTIONS+="--with-llvmsrc=$ROOT_DIR/src/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-llvmobj=$ROOT_DIR/build/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-llvmcc=$CLANG_ROOT/bin/$LLVM_CC "
  KLEE_CONFIG_OPTIONS+="--with-llvmcxx=$CLANG_ROOT/bin/$LLVM_CXX "

  if [ $USE_LLVM29 -eq 0 ]; then
    KLEE_CONFIG_OPTIONS+="--enable-cxx11 "
  fi

  KLEE_CONFIG_OPTIONS+="--with-stp=$STP_ROOT "

  KLEE_CONFIG_OPTIONS+="--with-uclibc=$UCLIBC_ROOT --enable-posix-runtime "

  if test ${ALTCC+defined}; then
   KLEE_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  leval $ROOT_DIR/src/$KLEE/configure $KLEE_CONFIG_OPTIONS 
}

make_klee()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then TARGET=$1; fi

  cd $ROOT_DIR/src/klee

  local make_options=""
  local env_options=""

  make_options+="-j $MAKE_THREADS "
  make_options+="ENABLE_GOOGLE_PROFILER=1 "
  make_options+="VERBOSE=1 "

  if test ${ALTCC+defined}; then
   make_options+="CC=$ALTCC CXX=$ALTCXX "
  fi

  if [ $USE_TSAN -eq 1 ]; then
     make_options+=" ENABLE_THREAD_SANITIZER=1 "
  elif [ $USE_ASAN -eq 1 ]; then
     make_options+=" ENABLE_ADDRESS_SANITIZER=1 "
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
    cd $ROOT_DIR/src/klee

    necho "[Testing$tag] "
    if [ $USE_TSAN -eq 1 ]; then
      leval make "$options" VERBOSE=1 ENABLE_THREAD_SANITIZER=1 test
    elif [ $USE_ASAN -eq 1 ]; then
      leval make "$options" VERBOSE=1 ENABLE_ADDRESS_SANITIZER=1 test
    else
      leval make "$options" VERBOSE=1 test
    fi

    necho "[Unittesting$tag] "
    make_klee "LD_LIBRARY_PATH=${BOOST_ROOT}/lib ${options} ENABLE_SHARED=0 unittests "
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

  local release_build_options="ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=1 DISABLE_TIMER_STATS=1 DISABLE_THREADS=1 "
  local release_tag=""

  local debug_build_options="ENABLE_OPTIMIZED=0 DISABLE_ASSERTIONS=0 DISABLE_TIMER_STATS=0 DISABLE_THREADS=1 "
  local debug_tag=""

  #local optimized_build_options=" ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=1 ENABLE_TCMALLOC=1 DISABLE_TIMER_STATS=1 "
  #local optimized_tag="-opt"

  #build_klee_helper "$optimized_build_options" "$optimized_tag"

  # ThreadSanitizer and AddressSanitizer don't work with tcmalloc
  if [ $USE_TSAN -eq 0 ] && [ $USE_ASAN -eq 0 ]; then
    release_build_options+="ENABLE_TCMALLOC=1 "
    debug_build_options+="ENABLE_TCMALLOC=1 "
  fi

  if [ $BUILD_DEBUG -eq 1 ]; then
    build_klee_helper "$debug_build_options" "$debug_tag"
  else
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
    leval git checkout -b $TETRINET_BRANCH origin/$TETRINET_BRANCH 
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
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  necho "[Configuring${tag}] "
  leval $ROOT_DIR/src/$XPILOT/configure $xpilot_config_options $make_options

  necho "[Compiling${tag}] "
  leval make $make_options

  necho "[Installing${tag}] "
  mkdir -p $XPILOT_ROOT
  leval make $make_options install
  leval extract-bc $XPILOT_ROOT/bin/xpilot-ng-x11${tag}

  necho "[Optimizing${tag}] "
  local opt_passes="-strip-debug -O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
  leval ${LLVM_ROOT}/bin/opt -load=${KLEE_ROOT}/lib/libkleePasses.so ${opt_passes} --time-passes -o ${XPILOT_ROOT}/bin/xpilot-ng-x11${tag}-opt.bc ${XPILOT_ROOT}/bin/xpilot-ng-x11${tag}.bc
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
    leval git checkout -b $XPILOT_BRANCH origin/$XPILOT_BRANCH
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
  #openssl_config_options+="-d " # compile with debugging symbols

  local make_options=""
  make_options+="CC=wllvm "
  make_options+="C_INCLUDE_PATH=${GLIBC_INCLUDE_PATH} "
  make_options+="LIBRARY_PATH=${GLIBC_LIBRARY_PATH} "

  export LLVM_COMPILER=${LLVM_CC}
  export LLVM_COMPILER_FLAGS="-fno-slp-vectorize -fno-slp-vectorize-aggressive -fno-vectorize -I${GLIBC_INCLUDE_PATH} -B${GLIBC_LIBRARY_PATH} ${llvm_compiler_options} "
  export PATH="${ROOT_DIR}/local/bin:${LLVM_ROOT}/bin:${CLANG_ROOT}/bin/:${PATH}"

  # Create 'makedepend' replacement
  MAKEDEPEND="${ROOT_DIR}/local/bin/makedepend"
  echo "#!/bin/bash" > "${MAKEDEPEND}"
  echo 'exec '"${LLVM_COMPILER}"' -M "$@"' >> "${MAKEDEPEND}"
  chmod +x "${MAKEDEPEND}"

  necho "[Configuring${tag}] "
  leval $ROOT_DIR/src/$OPENSSL/config $openssl_config_options

  necho "[Compiling${tag}] "
  leval make $make_options depend
  leval make $make_options

  if [ $SKIP_TESTS -eq 0 ]; then
    necho "[Testing] "
    leval make $make_options test
  fi

  necho "[Installing${tag}] "
  mkdir -p $OPENSSL_ROOT
  leval make install_sw
  leval extract-bc $OPENSSL_ROOT/bin/openssl
  leval cp $OPENSSL_ROOT/bin/openssl.bc $OPENSSL_ROOT/bin/openssl${tag}.bc

}

build_optimized_openssl_bitcode()
{
  local tag=$1

  necho "[Optimizing${tag}] "
  local opt_passes="-strip-debug -O3 -disable-loop-vectorization -disable-slp-vectorization -lowerswitch -intrinsiccleaner -phicleaner"
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

      leval git checkout -b $OPENSSL_BRANCH origin/$OPENSSL_BRANCH

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

        # Build two versions of openssl, to support cliver and lli
        config_and_build_openssl "-DKLEE" "-klee"
        config_and_build_openssl " " "-run"
      fi
      ;;

    opt*)
      # runt opt on two versions of openssl, to support cliver and lli
      build_optimized_openssl_bitcode "-klee"
      build_optimized_openssl_bitcode "-run"
      ;;
  esac
  necho "[Done]\n"
}


###############################################################################

on_exit()
{
  if [ $ERROR_EXIT -eq 1 ]; then
    lecho "Error"
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
  while getopts ":afkcivsb:r:j:dltn" opt; do
    case $opt in
      a)
        #lecho "Forcing alternative gcc"
        #set_alternate_gcc
        lecho "Building klee with AddressSanitizer"
        USE_ASAN=1
        ;;
  
      f)
        lecho "Forcing compilation"
        FORCE_COMPILATION=1
        ;;
   
      d)
        lecho "Building debug version"
        BUILD_DEBUG=1
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
   
      t)
        lecho "Building klee with ThreadSanitizer"
        USE_TSAN=1
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

  if [ $USE_LLVM29 -eq 0 ]; then
    check_gcc_version
  else
    check_gcc_version_old
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
      install_llvmgcc_from_source
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
    install_minisat
    #install_stp
    install_stp_git
    #install_ghmm
    manage_openssl install
    install_klee
    manage_openssl opt
    install_zlib
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
        manage_openssl opt
        ;;
      llvm)
        update_llvm
        ;;
      *)
       echo "${SELECTIVE_BUILD_TARGET} not found!"; exit
        ;;
    esac

  else
    echo
    echo "====--update--===="
    # update all
    update_wllvm
    manage_openssl update
    manage_openssl opt
    update_klee
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

