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

get_package()
{
  echo -n "[Extracting] "
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
  echo -ne "$NCURSES\t\t"
  check_dirs $NCURSES || { return 0; }
  get_package $NCURSES_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$NCURSES"

  mkdir -p $ROOT_DIR/build/$NCURSES
  cd $ROOT_DIR/build/$NCURSES

  NCURSES_CONFIG_OPTIONS="--with-shared --without-ada --without-manpages --prefix=$NCURSES_ROOT "
  if test ${ALTCC+defined}; then
    NCURSES_CONFIG_OPTIONS+="CC=$ALTCC LD=$ALTCC "
  fi

  echo -n "[Configuring] "
  leval $ROOT_DIR/src/$NCURSES/configure $NCURSES_CONFIG_OPTIONS 

  echo -n "[Compiling] "
  leval make -j $MAKE_THREADS 

  echo -n "[Installing] "
  mkdir -p $NCURSES_ROOT
  leval make -j $MAKE_THREADS install 

  echo "[Done]"
}

install_zlib()
{
  echo -ne "$ZLIB \t\t"
  check_dirs $ZLIB || { return 0; }
  get_package $ZLIB_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$ZLIB"

  cd $ROOT_DIR/src/$ZLIB

  echo -n "[Configuring] "
  leval $ROOT_DIR/src/$ZLIB/configure --prefix=$ZLIB_ROOT 

  echo -n "[Compiling] "
  leval make -j $MAKE_THREADS 

  echo -n "[Installing] "
  mkdir -p $ZLIB_ROOT
  leval make -j $MAKE_THREADS install 

  echo "[Done]"
}

install_zlib_llvm()
{
  echo -ne "$ZLIB (llvm) \t"
  check_dirs $ZLIB-llvm || { return 0; }
  get_package $ZLIB_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$ZLIB-llvm"

  cd $ROOT_DIR/src/$ZLIB-llvm

  echo -n "[Configuring] "
  ZLIB_LLVM_OPTIONS="CC=$LLVMGCC_ROOT/bin/llvm-gcc AR=$LLVM_ROOT/bin/llvm-ar CFLAGS=-emit-llvm"
  leval $ZLIB_LLVM_OPTIONS $ROOT_DIR/src/$ZLIB-llvm/configure --static --prefix=$ZLIB_ROOT 

  echo -n "[Compiling] "
  leval make libz.a 

  echo -n "[Installing] "
  mkdir -p $ZLIB_ROOT
  leval cp -p libz.a $ZLIB_ROOT/lib/libz-llvm.a

  echo "[Done]"
}

install_expat()
{
  echo -ne "$EXPAT\t\t"
  check_dirs $EXPAT || { return 0; }
  get_package $EXPAT_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$EXPAT"
  cd $ROOT_DIR/src/$EXPAT

  echo -n "[Configuring] "
  leval $ROOT_DIR/src/$EXPAT/configure --prefix=$EXPAT_ROOT 

  echo -n "[Compiling] "
  leval make -j $MAKE_THREADS 

  echo -n "[Installing] "
  mkdir -p $EXPAT_ROOT
  leval make -j $MAKE_THREADS install 

  echo "[Done]"
}

install_boost()
{
  echo -ne "$BOOST\t\t"

  check_dirs $BOOST || { return 0; }

  get_package $BOOST_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$BOOST"

  cd $ROOT_DIR/src/$BOOST

  BJAM_OPTIONS="--without-mpi --without-python --without-regex -j$MAKE_THREADS"

  echo -n "[Compiling] "
  leval ./bootstrap.sh --prefix=$BOOST_ROOT 
  leval ./bjam $BJAM_OPTIONS 

  echo -n "[Installing] "
  leval ./bjam $BJAM_OPTIONS install 

  echo "[Done]"
}

install_libunwind()
{
  echo -ne "$LIBUNWIND\t\t"
  check_dirs $LIBUNWIND || { return 0; }
  get_package $LIBUNWIND_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$LIBUNWIND"

  mkdir -p $ROOT_DIR/build/$LIBUNWIND
  cd $ROOT_DIR/build/$LIBUNWIND

  echo -n "[Configuring] "
  leval $ROOT_DIR/src/$LIBUNWIND/configure CFLAGS=\"-U_FORTIFY_SOURCE\" --prefix=$LIBUNWIND_ROOT 

  echo -n "[Compiling] "
  leval make -j $MAKE_THREADS 

  echo -n "[Installing] "
  mkdir -p $LIBUNWIND_ROOT
  leval make -j $MAKE_THREADS install 

  echo "[Done]"
}

install_google_perftools()
{
  echo -ne "$GOOGLE_PERFTOOLS\t"
  check_dirs $GOOGLE_PERFTOOLS || { return 0; }
  get_package $GOOGLE_PERFTOOLS_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$GOOGLE_PERFTOOLS"

  mkdir -p $ROOT_DIR/build/$GOOGLE_PERFTOOLS
  cd $ROOT_DIR/build/$GOOGLE_PERFTOOLS

  echo -n "[Configuring] "
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

  echo -n "[Compiling] "
  leval make -j $MAKE_THREADS 

  echo -n "[Installing] "
  mkdir -p $GOOGLE_PERFTOOLS_ROOT
  leval make -j $MAKE_THREADS install 

  echo "[Done]"
}


install_uclibc()
{
  echo -ne "$UCLIBC\t"
  check_dirs $UCLIBC || { return 0; }
  get_package $UCLIBC_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$UCLIBC"

  cd $ROOT_DIR/src/$UCLIBC

  echo -n "[Configuring] "
  leval ./configure --with-llvm=$ROOT_DIR/build/$LLVM 

  echo -n "[Compiling] "
  leval make 

  echo "[Done]"
} 

install_llvmgcc_bin()
{
  echo -ne "$LLVMGCC\t"
  check_dirs $LLVMGCC || { return 0; }
  get_package $LLVMGCC_BIN_PACKAGE $PACKAGE_DIR $LLVMGCC_ROOT 
  echo "[Done]"
}

install_llvmgcc_from_source()
{
  echo -ne "$LLVMGCC\t"
  check_dirs $LLVMGCC || { return 0; }
  get_package $LLVMGCC_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$LLVMGCC"

  mkdir -p $ROOT_DIR/build/$LLVMGCC
  cd $ROOT_DIR/build/$LLVMGCC

  LLVMGCC_CONFIG_OPTIONS="--prefix=$LLVMGCC_ROOT --disable-multilib --program-prefix=llvm- "
  LLVMGCC_CONFIG_OPTIONS+="--enable-llvm=$LLVM_ROOT --enable-languages=c,c++,fortran "

  echo -n "[Configuring] "
  leval $ROOT_DIR/src/$LLVMGCC/configure $LLVMGCC_CONFIG_OPTIONS 

  LLVMGCC_MAKE_OPTIONS=""

  if test ${ALTCC+defined}; then
    LLVMGCC_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi
  if test ${GXX_INCLUDE_DIR+defined}; then
    LLVMGCC_MAKE_OPTIONS+="--with-gxx-include-dir=$GXX_INCLUDE_DIR "
  fi

  echo -n "[Compiling] "
  leval make $LLVMGCC_MAKE_OPTIONS -j $MAKE_THREADS 

  echo -n "[Installing] "
  mkdir -p $LLVMGCC_ROOT
  leval make $LLVMGCC_MAKE_OPTIONS install 

  echo "[Done]"
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
  echo -ne "$LLVM\t\t"

  if [ ! -e "$ROOT_DIR/src/$LLVM/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$LLVM

  if [ $BUILD_LOCAL -eq 0 ]; then
    #if [ "$(git_current_branch)" != "$LLVM_BRANCH" ]; then
    #  echo "[Error] (unknown git branch "$(git_current_branch)") "; exit;
    #fi

    echo -n "[Checking] "
    leval git remote update
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      echo -n "[Pulling] "
      leval git pull --all 
    fi

    if [ $FORCE_CONFIGURE -eq 1 ]; then 
      echo -n "[Configuring] "
      config_llvm 
    fi

    if [ $FORCE_CLEAN -eq 1 ]; then 
      echo -n "[Cleaning] "
      build_llvm clean
    fi

    echo -n "[Compiling] "
    build_llvm

    echo -n "[Installing] "
    mkdir -p $LLVM_ROOT
    build_llvm install

  fi

  echo "[Done]"
}

install_llvm()
{
  echo -ne "$LLVM\t\t"
  check_dirs $LLVM || { return 0; }
  cd $ROOT_DIR"/src"

  echo -n "[Cloning] "
  leval git clone $LLVM_GIT 

  echo -n "[Configuring] "
  config_llvm 

  echo -n "[Compiling] "
  build_llvm

  echo -n "[Installing] "
  mkdir -p $LLVM_ROOT
  build_llvm install

  echo "[Done]"
}

config_klee()
{
  cd $ROOT_DIR/src/$KLEE
  KLEE_CONFIG_OPTIONS="--prefix=$KLEE_ROOT -libdir=$KLEE_ROOT/lib/$KLEE "
  KLEE_CONFIG_OPTIONS+="--with-llvmsrc=$ROOT_DIR/src/$LLVM --with-llvmobj=$ROOT_DIR/build/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-uclibc=$UCLIBC_ROOT --enable-posix-runtime "

  KLEE_CONFIG_OPTIONS+="LDFLAGS=\"-L$BOOST_ROOT/lib -L$GOOGLE_PERFTOOLS_ROOT/lib\" "
  KLEE_CONFIG_OPTIONS+="CPPFLAGS=\"-I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include\" "
  KLEE_CONFIG_OPTIONS+="CXXFLAGS=\"-I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include\" "

  if test ${ALTCC+defined}; then
   KLEE_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  leval $ROOT_DIR/src/$KLEE/configure $KLEE_CONFIG_OPTIONS 
}

build_klee()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then TARGET=$1; fi

  cd $ROOT_DIR/src/klee
  KLEE_MAKE_OPTIONS="NO_WEXTRA=1 RUNTIME_ENABLE_OPTIMIZED=1 REQUIRES_RTTI=1 -j $MAKE_THREADS "

  if test ${ALTCC+defined}; then
   KLEE_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX VERBOSE=1 "
  fi

  if [ $BUILD_DEBUG -eq 1 ]; then
    KLEE_MAKE_OPTIONS+="ENABLE_OPTIMIZED=0 "
  else
    KLEE_MAKE_OPTIONS+="ENABLE_OPTIMIZED=1 "
  fi

  ### HACK ### need to remove libraries from install location so that
  # old klee/cliver libs are not used before recently compiled libs
  leval make $KLEE_MAKE_OPTIONS uninstall

  leval make $KLEE_MAKE_OPTIONS $TARGET 
}

install_klee()
{
  echo -ne "$KLEE\t\t\t"

  check_dirs $KLEE || { return 0; }

  cd $ROOT_DIR"/src"

  echo -n "[Cloning] "
  leval git clone $KLEE_GIT 

  cd $ROOT_DIR"/src/$KLEE"

  leval git checkout -b $KLEE_BRANCH origin/$KLEE_BRANCH 

  echo -n "[Configuring] "
  config_klee

  echo -n "[Compiling] "
  build_klee

  echo -n "[Installing] "
  mkdir -p $KLEE_ROOT
  build_klee install

  echo "[Done]"
}

update_klee()
{
  echo -ne "$KLEE\t\t\t"

  if [ ! -e "$ROOT_DIR/src/$KLEE/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$KLEE

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$KLEE_BRANCH" ]; then
      echo "[Error] (unkown git branch "$(git_current_branch)") "; exit;
    fi

    echo -n "[Checking] "
    leval git remote update 
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      echo -n "[Pulling] "
      leval git pull --all 
    fi

    if [ $FORCE_CONFIGURE -eq 1 ]; then 
      echo -n "[Configuring] "
      config_klee
    fi

    if [ $FORCE_CLEAN -eq 1 ]; then 
      echo -n "[Cleaning] "
      build_klee clean
    fi

    echo -n "[Compiling] "
    build_klee

    echo -n "[Installing] "
    mkdir -p $KLEE_ROOT
    build_klee install
  fi

  echo "[Done]"
}

build_tetrinet()
{
  TETRINET_MAKE_OPTIONS="NCURSES_DIR=$NCURSES_ROOT LLVM_BIN_DIR=$LLVM_ROOT/bin "
  TETRINET_MAKE_OPTIONS+="LLVMGCC_BIN_DIR=$LLVMGCC_ROOT/bin PREFIX=$TETRINET_ROOT "

  if test ${ALTCC+defined}; then
    TETRINET_MAKE_OPTIONS+="CC=$ALTCC LD=$ALTCC "
  fi

  echo -n "[Compiling] "
  leval make $TETRINET_MAKE_OPTIONS 

  echo -n "[Installing] "
  mkdir -p $TETRINET_ROOT
  leval make $TETRINET_MAKE_OPTIONS install 
}

update_tetrinet()
{
  echo -ne "$TETRINET\t\t"

  if [ ! -e "$ROOT_DIR/src/$TETRINET/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$TETRINET

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$TETRINET_BRANCH" ]; then
      echo "[Error] (unkown git branch "$(git_current_branch)") "; exit;
    fi
    
    echo -n "[Checking] "
    leval git remote update 
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      echo -n "[Pulling] "
      leval git pull --all 
    fi

    if [ $FORCE_CLEAN -eq 1 ]; then 
      echo -n "[Cleaning] "
      leval make clean 
    fi

    build_tetrinet

  fi

  echo "[Done]"
}

install_tetrinet()
{
  echo -ne "$TETRINET\t\t"

  check_dirs $TETRINET|| { return 0; }

  cd $ROOT_DIR"/src"

  echo -n "[Cloning] "
  leval git clone $TETRINET_GIT 

  cd $ROOT_DIR"/src/$TETRINET"

  leval git checkout -b $TETRINET_BRANCH origin/$TETRINET_BRANCH 

  build_tetrinet

  echo "[Done]"
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

  echo -n "[Configuring] "
  leval $ROOT_DIR/src/$xpilot_opt/configure $xpilot_config_options 

  echo -n "[Compiling] "
  leval make $xpilot_make_options 

  echo -n "[Installing] "
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
  echo -ne "$xpilot_opt\t\t"

  if [ ! -e "$ROOT_DIR/src/$xpilot_opt/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$xpilot_opt

  if [ $BUILD_LOCAL -eq 0 ]; then
    if [ "$(git_current_branch)" != "$XPILOT_BRANCH" ]; then
      echo "[Error] (unkown git branch "$(git_current_branch)") "; exit;
    fi
    
    echo -n "[Checking] "
    leval git remote update
  fi

  if [ $FORCE_COMPILATION -eq 1 ] || git status -uno | grep -q behind ; then

    if [ $BUILD_LOCAL -eq 0 ]; then
      echo -n "[Pulling] "
      leval git pull --all
    fi

    config_and_build_xpilot $1
  fi

  echo "[Done]"
}

install_xpilot()
{
  if [[ $# -ne 1 ]]; then echo "[Error] "; exit; fi

  local xpilot_opt=$XPILOT-$1
  echo -ne "$xpilot_opt \t\t"

  check_dirs $xpilot_opt || { return 0; }
  cd $ROOT_DIR"/src"

  echo -n "[Cloning] "
  leval git clone $XPILOT_GIT $xpilot_opt

  cd $ROOT_DIR"/src/$xpilot_opt"

  leval git checkout -b $XPILOT_BRANCH origin/$XPILOT_BRANCH

  config_and_build_xpilot $1

  echo "[Done]"
}

main() 
{
  while getopts ":afkcivs:br:j:dl" opt; do
    case $opt in
      a)
        # Use alternative GCC
        ;;
  
      f)
        FORCE_COMPILATION=1
        ;;
   
      d)
        BUILD_DEBUG=1
        ;;
 
      l)
        BUILD_LOCAL=1
        FORCE_COMPILATION=1
        ;;

      k)
        FORCE_CLEAN=1
        ;;
  
      c)
        FORCE_CONFIGURE=1
        ;;
  
      i)
        INSTALL_PACKAGES=1
        ;;
  
      v)
        VERBOSE_OUTPUT=1
        ;;
  
      s)
        SELECTIVE_BUILD=1
        SELECTIVE_BUILD_TARGET="$OPTARG"
        ;;
  
      b)
        INSTALL_LLVMGCC_BIN=1
        ;;
  
      r)
        echo "Setting root dir to $OPTARG"
        ROOT_DIR="$OPTARG"
        ;;
  
      j)
        MAKE_THREADS=$OPTARG
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
    echo "Installing all packages" 
  
    install_llvm
  
    if [ $INSTALL_LLVMGCC_BIN -eq 1 ]; then
      install_llvmgcc_bin
    else
      install_llvmgcc_from_source
    fi
  
    install_libunwind
    install_google_perftools
    install_boost
    install_uclibc
    install_ncurses
    install_zlib
    install_expat
    install_klee
    install_tetrinet
    install_xpilot llvm
    install_xpilot x86
  
  elif [ $SELECTIVE_BUILD -eq 1 ]; then
    case $SELECTIVE_BUILD_TARGET in 
      *llvm*)
        update_llvm
        ;;
      *klee*)
        update_klee
        ;;
      *tetrinet*)
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
  
  echo "Elapsed time: $(elapsed_time $start_time)"
}

# Run main
main "$@"
