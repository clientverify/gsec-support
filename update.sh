#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

WRAPPER="`readlink -f "$0"`"
HERE="`dirname "$WRAPPER"`"

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
INSTALL_LLVMGCC_BIN=0
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

  leval scp $REMOTE_PATH/$FILE $LOCAL_DEST/ 
}

get_package()
{
  necho "[Extracting] "
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

  leval scp $REMOTE_PATH/$PACKAGE $LOCAL_DEST/ 

  if [ $PACKAGE_TYPE == "gz" ] || [ $PACKAGE_TYPE == "tgz" ]; then
    leval tar $TAR_OPTIONS -xvzf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST 
  elif [ $PACKAGE_TYPE == "bz2" ]; then
    leval tar $TAR_OPTIONS -xvjf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST 
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
     [ -e $ROOT_DIR/build/$1 ]; then
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

  NCURSES_CONFIG_OPTIONS="--with-shared --without-ada --without-manpages --prefix=$NCURSES_ROOT "
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
  leval make -j $MAKE_THREADS 

  necho "[Installing] "
  mkdir -p $ZLIB_ROOT
  leval make -j $MAKE_THREADS install 

  necho "[Done]\n"
}

install_waffles()
{
  necho "$WAFFLES\t"
  check_dirs $WAFFLES || { return 0; }
  get_package $WAFFLES_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$WAFFLES"

  cd $ROOT_DIR/src/$WAFFLES/src

  #necho "[Configuring] "
  #leval $ROOT_DIR/src/$WAFFLES/configure --prefix=$WAFFLES_ROOT 

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
  ZLIB_LLVM_OPTIONS="CC=$LLVMGCC_ROOT/bin/llvm-gcc AR=$LLVM_ROOT/bin/llvm-ar CFLAGS=-emit-llvm"
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

  #get_package $BOOST_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$BOOST"
  get_package $BOOST_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/"

  cd $ROOT_DIR/src/$BOOST

  BJAM_OPTIONS="--without-mpi --without-python --without-regex -j$MAKE_THREADS"

  necho "[Compiling] "
  leval ./bootstrap.sh --prefix=$BOOST_ROOT 
  leval ./bjam $BJAM_OPTIONS 

  necho "[Installing] "
  leval ./bjam $BJAM_OPTIONS install 

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

install_google_perftools()
{
  necho "$GOOGLE_PERFTOOLS\t\t"
  check_dirs $GOOGLE_PERFTOOLS || { return 0; }
  get_package $GOOGLE_PERFTOOLS_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$GOOGLE_PERFTOOLS"

  mkdir -p $ROOT_DIR/build/$GOOGLE_PERFTOOLS
  cd $ROOT_DIR/build/$GOOGLE_PERFTOOLS

  necho "[Configuring] "
  GOOGLE_PERFTOOLS_CONFIG_OPTIONS="LDFLAGS=-L$LIBUNWIND_ROOT/lib/ "
  GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="CPPFLAGS=-I$LIBUNWIND_ROOT/include/ "
  GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="LIBS=-lunwind-x86_64 "
  GOOGLE_PERFTOOLS_CONFIG_OPTIONS+="--prefix=$GOOGLE_PERFTOOLS_ROOT "

  GOOGLE_PERFTOOLS_CONFIG_COMMAND="$ROOT_DIR/src/$GOOGLE_PERFTOOLS/configure $GOOGLE_PERFTOOLS_CONFIG_OPTIONS"

  # google-perf-tools requires libunwind libraries on x86_64, so we provide
  # the libunwind directory to the compiler for static libraries, and add the libunwind directory
  # to LD_LIBRARY_PATH for shared libraries
  if test ${LD_LIBRARY_PATH+defined}; then
    GOOGLE_PERFTOOLS_LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$LIBUNWIND_ROOT/lib" 
  else
    GOOGLE_PERFTOOLS_LD_LIBRARY_PATH="$LIBUNWIND_ROOT/lib" 
  fi

  leval LD_LIBRARY_PATH=$GOOGLE_PERFTOOLS_LD_LIBRARY_PATH $GOOGLE_PERFTOOLS_CONFIG_COMMAND 

  necho "[Compiling] "
  leval make -j $MAKE_THREADS 

  necho "[Installing] "
  mkdir -p $GOOGLE_PERFTOOLS_ROOT
  leval make -j $MAKE_THREADS install 

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

install_llvmgcc_bin()
{
  necho "$LLVMGCC\t"
  check_dirs $LLVMGCC || { return 0; }
  get_package $LLVMGCC_BIN_PACKAGE $PACKAGE_DIR $LLVMGCC_ROOT 
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
    LLVMGCC_MAKE_OPTIONS+="LIBRARY_PATH=/usr/lib/x86_64-linux-gnu "
  fi

  necho "[Compiling] "
  leval make $LLVMGCC_MAKE_OPTIONS -j $MAKE_THREADS 

  necho "[Installing] "
  mkdir -p $LLVMGCC_ROOT
  leval make $LLVMGCC_MAKE_OPTIONS install 

  necho "[Done]\n"
}

config_llvm ()
{ 
  mkdir -p $ROOT_DIR/build/$LLVM
  cd $ROOT_DIR"/build/$LLVM"

  LLVM_CONFIG_OPTIONS="--enable-optimized --with-llvmgccdir=$LLVMGCC_ROOT --prefix=$LLVM_ROOT "

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

  LLVM_MAKE_OPTIONS=" -j $MAKE_THREADS "

  if [ $BUILD_DEBUG -eq 1 ]; then
    LLVM_MAKE_OPTIONS+="ENABLE_OPTIMIZED=0 "
  else
    LLVM_MAKE_OPTIONS+="ENABLE_OPTIMIZED=1 "
  fi

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
    #if [ "$(git_current_branch)" != "$LLVM_BRANCH" ]; then
    #  echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    #fi

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

    necho "[Compiling] "
    build_llvm "DISABLE_ASSERTIONS=1 "
    build_llvm 

    necho "[Installing] "
    mkdir -p $LLVM_ROOT
    build_llvm install

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

  necho "[Compiling] "
  build_llvm "DISABLE_ASSERTIONS=1 "
  build_llvm 

  necho "[Installing] "
  mkdir -p $LLVM_ROOT
  build_llvm install

  necho "[Done]\n"
}

install_stp()
{
  necho "$STP\t\t\t"
  check_dirs $STP || { return 0; }
  get_package $STP_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$STP"

  #necho "[Cloning] "
  #leval svn co -r $STP_REV $STP_SVN $STP

  cd $ROOT_DIR/src/$STP 

  #### HACK to fix compilation with old version of flex on redhat, only needed for rev 940, fixed in rev 1139 ####
  local OLD_FLEX=$(flex --version | awk -F '[ .]' '{ print ($$(NF-2) < 2 || $$(NF-2) == 2 && ($$(NF-1) < 5 || $$(NF-1) == 5 && $$NF < 20)) }')
  if [ $OLD_FLEX -eq 0 ]; then
    necho "[Patching] "
    get_file $STP_PATCH_FILE $PACKAGE_DIR $ROOT_DIR/src/$STP
    leval patch -p0 < $STP_PATCH_FILE
  fi

  necho "[Configuring] "
  local STP_CONFIG_FLAGS="--with-prefix=$STP_ROOT --with-cryptominisat2"
  leval ./scripts/configure $STP_CONFIG_FLAGS

  local STP_MAKE_FLAGS="-j $MAKE_THREADS OPTIMIZE=-O2 CFLAGS_M32= "

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
  KLEE_CONFIG_OPTIONS+="--with-llvmsrc=$ROOT_DIR/src/$LLVM --with-llvmobj=$ROOT_DIR/build/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-stp=$STP_ROOT "
  KLEE_CONFIG_OPTIONS+="--with-uclibc=$UCLIBC_ROOT --enable-posix-runtime "

  KLEE_CONFIG_OPTIONS+="LDFLAGS=\"-L$BOOST_ROOT/lib -L$GOOGLE_PERFTOOLS_ROOT/lib\" "
  KLEE_CONFIG_OPTIONS+="CPPFLAGS=\"-I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include\" "
  KLEE_CONFIG_OPTIONS+="CXXFLAGS=\"-I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include\" "

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
  KLEE_MAKE_OPTIONS="NO_PEDANTIC=1 NO_WEXTRA=1 RUNTIME_ENABLE_OPTIMIZED=1 REQUIRES_RTTI=1 -j $MAKE_THREADS "

  if test ${ALTCC+defined}; then
   KLEE_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX VERBOSE=1 "
  fi

  ### HACK ### need to remove libraries from install location so that
  # old klee/cliver libs are not used before recently compiled libs
  leval make $KLEE_MAKE_OPTIONS uninstall

  leval make $KLEE_MAKE_OPTIONS $TARGET 
}

build_klee_helper()
{
  local klee="cliver"
  local options=$1
  local tag=$2

  if [ $FORCE_CLEAN -eq 1 ]; then 
    necho "[Cleaning$tag] "
    make_klee "$options clean"
  fi

  necho "[Compiling$tag] "
  make_klee $options

  necho "[Installing$tag] "
  make_klee "$options install"

  if [ ${#tag} -gt 0 ]; then
    leval cp "$KLEE_ROOT/bin/$klee" "$KLEE_ROOT/bin/$klee$tag"
    leval cp "$KLEE_ROOT/bin/$klee-bin" "$KLEE_ROOT/bin/$klee$tag-bin"
  fi
}

build_klee()
{
  mkdir -p $KLEE_ROOT

  local release_build_options="ENABLE_OPTIMIZED=1 "
  local release_tag=""

  local debug_build_options="ENABLE_OPTIMIZED=0 "
  local debug_tag=""

  local optimized_build_options="ENABLE_OPTIMIZED=1 DISABLE_ASSERTIONS=1 DISABLE_TIMER_STATS=1 "
  local optimized_tag="-opt"

  build_klee_helper "$optimized_build_options" "$optimized_tag"

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

  leval git checkout -b $KLEE_BRANCH origin/$KLEE_BRANCH 

  if test ${GIT_TAG+defined}; then
    necho "[Fetching $GIT_TAG] "
    leval git checkout $GIT_TAG
  fi

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
      echo "[Error] (unkown git branch "$(git_current_branch)") "; exit;
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
  TETRINET_MAKE_OPTIONS="NCURSES_DIR=$NCURSES_ROOT LLVM_BIN_DIR=$LLVM_ROOT/bin "
  TETRINET_MAKE_OPTIONS+="LLVMGCC_BIN_DIR=$LLVMGCC_ROOT/bin PREFIX=$TETRINET_ROOT "

  if test ${ALTCC+defined}; then
    TETRINET_MAKE_OPTIONS+="CC=$ALTCC LD=$ALTCC "
  fi

  necho "[Compiling] "
  leval make $TETRINET_MAKE_OPTIONS 

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
      echo "[Error] (unkown git branch "$(git_current_branch)") "; exit;
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

  leval git checkout -b $TETRINET_BRANCH origin/$TETRINET_BRANCH 

  if test ${GIT_TAG+defined}; then
    necho "[Fetching $GIT_TAG] "
    leval git checkout $GIT_TAG
  fi

  build_tetrinet

  necho "[Done]\n"
}

config_and_build_xpilot()
{
  if [[ $# -ne 1 ]]; then echo "[Error] "; exit; fi

  local xpilot_config_options=""
  xpilot_config_options+="--disable-sdl-client --disable-sdl-gameloop "
  xpilot_config_options+="--disable-sdltest --disable-xp-mapedit "
  xpilot_config_options+="--disable-replay --disable-sound "
  xpilot_config_options+="--enable-select-sched --prefix=$XPILOT_ROOT "
  xpilot_config_options+="--program-suffix=-$1 "

  local xpilot_llvm_options=""
  xpilot_llvm_options+="LLVMINTERP=$LLVM_ROOT/bin/lli UCLIBC_ROOT=$UCLIBC_ROOT LLVM_ROOT=$LLVM_ROOT "
  xpilot_llvm_options+="LLVMGCC_ROOT=$LLVMGCC_ROOT CC=$ROOT_DIR/src/$XPILOT-$1/llvm_gcc_script.py "

  local xpilot_make_options=""
  if [ "$1" == "llvm" ]; then
    xpilot_config_options+="$xpilot_llvm_options"
    xpilot_make_options+="$xpilot_llvm_options "
  fi

  necho "[Configuring] "
  leval $ROOT_DIR/src/$xpilot_opt/configure $xpilot_config_options 

  necho "[Compiling] "
  leval make $xpilot_make_options 

  necho "[Installing] "
  mkdir -p $XPILOT_ROOT
  leval make $xpilot_make_options install 

  if [ "$1" == "llvm" ]; then
    leval cp -u $ROOT_DIR/src/$XPILOT-$1/src/client/x11/xpilot-ng-x11.bc $XPILOT_ROOT/bin/
    leval cp -u $ROOT_DIR/src/$XPILOT-$1/src/server/xpilot-ng-server.bc $XPILOT_ROOT/bin/
  fi
}

update_xpilot()
{
  if [[ $# -ne 1 ]]; then echo "[Error] "; exit; fi

  local xpilot_opt=$XPILOT-$1
  necho "$xpilot_opt\t\t"

  if [ ! -e "$ROOT_DIR/src/$xpilot_opt/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$xpilot_opt

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$XPILOT_BRANCH" ]; then
      echo "[Error] (unkown git branch "$(git_current_branch)") "; exit;
    fi
    
    necho "[Checking] "
    leval git remote update
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      necho "[Pulling] "
      leval git pull --all
    fi

    config_and_build_xpilot $1
  fi

  necho "[Done]\n"
}

install_xpilot()
{
  if [[ $# -ne 1 ]]; then echo "[Error] "; exit; fi

  local xpilot_opt=$XPILOT-$1
  necho "$xpilot_opt \t\t"

  check_dirs $xpilot_opt || { return 0; }
  cd $ROOT_DIR"/src"

  necho "[Cloning] "
  leval git clone $XPILOT_GIT $xpilot_opt

  cd $ROOT_DIR"/src/$xpilot_opt"

  leval git checkout -b $XPILOT_BRANCH origin/$XPILOT_BRANCH

  if test ${GIT_TAG+defined}; then
    necho "[Fetching $GIT_TAG] "
    leval git checkout $GIT_TAG
  fi

  config_and_build_xpilot $1

  necho "[Done]\n"
}

main() 
{
  while getopts ":afkcivs:br:j:dlt:" opt; do
    case $opt in
      a)
        lecho "Forcing alternative gcc"
        set_alternative_gcc
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
        lecho "Installing packages"
        INSTALL_PACKAGES=1
        ;;
  
      v)
        lecho "Verbose output"
        VERBOSE_OUTPUT=1
        ;;
  
      s)
        lecho "Selective update"
        SELECTIVE_BUILD=1
        SELECTIVE_BUILD_TARGET="$OPTARG"
        ;;
  
      b)
        lecho "Installing llvm-gcc binaries"
        INSTALL_LLVMGCC_BIN=1
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
        lecho "Installing versions tagged with $OPTARG"
        GIT_TAG="$OPTARG"
        ;;

      :)
        echo "Option -$OPTARG requires an argument"
        exit
        ;;
  
    esac
  done

  initialize_root_directories

  initialize_logging $@

  check_gcc_version

  # record start time
  start_time=$(elapsed_time)
  
  if [ $INSTALL_PACKAGES -eq 1 ]; then
  
    mkdir -p $ROOT_DIR/{src,local,build}
  
    install_llvm
  
    if [ $INSTALL_LLVMGCC_BIN -eq 1 ]; then
      install_llvmgcc_bin
    else
      install_llvmgcc_from_source
    fi
  
    install_libunwind
    install_sparsehash
    install_google_perftools
    install_boost
    install_uclibc
    install_ncurses
    install_zlib
    install_waffles
    install_expat
    install_stp
    install_klee
    install_tetrinet
    install_xpilot llvm
    install_xpilot x86
  
  elif [ $SELECTIVE_BUILD -eq 1 ]; then
    case $SELECTIVE_BUILD_TARGET in 
      llvm*)
        update_llvm
        ;;
      klee*)
        update_klee
        ;;
      tetrinet*)
        update_tetrinet
        ;;
      xpilot)
        update_xpilot llvm
        update_xpilot x86
        ;;
      xpilot-llvm)
        update_xpilot llvm
        ;;
      xpilot-x86)
        update_xpilot x86 
        ;;
    esac

  else
    # update all
    update_llvm
    update_klee
    update_tetrinet
    update_xpilot llvm
    update_xpilot x86
  
  fi
  
  lecho "Elapsed time: $(elapsed_time $start_time)"
}

# Run main
main "$@"
