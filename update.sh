#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

# Packages to install
LLVM="llvm-2.7"
LLVMGCC="llvm-gcc-4.2-2.7"
LLVMGCC_BIN="llvm-gcc4.2-2.7-x86_64-linux"
KLEE="klee"
UCLIBC="klee-uclibc-0.01-x64"
BOOST="boost_1_42_0"
GOOGLE_PERFTOOLS="google-perftools-1.8.3"
UDIS86="udis86-1.7"
LIBUNWIND="libunwind-1.0.1"
NCURSES="ncurses-5.7"
TETRINET="tetrinet"
ZLIB="zlib-1.2.5"
EXPAT="expat-2.0.1"
XPILOT="xpilot"
XPILOT_LLVM_PREFIX="llvm-"
XPILOT_NATIVE_PREFIX="x86-"

# Source repositories
GIT_HOST="rac@kudzoo.cs.unc.edu"
GIT_DIR="/afs/cs.unc.edu/home/rac/repos/research"
LLVM_GIT="$GIT_HOST:$GIT_DIR/$LLVM.git"
KLEE_GIT="$GIT_HOST:$GIT_DIR/$KLEE.git"
TETRINET_GIT="$GIT_HOST:$GIT_DIR/$TETRINET.git"
XPILOT_GIT="$GIT_HOST:$GIT_DIR/$XPILOT.git"

# Repository Branches
KLEE_BRANCH="cliver"
TETRINET_BRANCH="enumerate"
XPILOT_BRANCH="nuklear-support"

# Tarball locations
PACKAGE_HOST="rac@kudzoo.cs.unc.edu"
PACKAGE_DIR="$PACKAGE_HOST:/afs/cs.unc.edu/home/rac/public/research/files"
UCLIBC_PACKAGE="$UCLIBC.tgz"
BOOST_PACKAGE="$BOOST.tar.gz"
GOOGLE_PERFTOOLS_PACKAGE="$GOOGLE_PERFTOOLS.tar.gz"
UDIS86_PACKAGE="$UDIS86.tar.gz"
LIBUNWIND_PACKAGE="$LIBUNWIND.tar.gz"
LLVMGCC_PACKAGE="$LLVMGCC.source.tgz"
LLVMGCC_BIN_PACKAGE="$LLVMGCC_BIN.tar.bz2"
NCURSES_PACKAGE="$NCURSES.tar.gz"
ZLIB_PACKAGE="$ZLIB.tar.gz"
EXPAT_PACKAGE="$EXPAT.tar.gz"

# Command line options
FORCE_CLEAN=0
FORCE_UPDATE=0
FORCE_CONFIGURE=0
INSTALL_PACKAGES=0
SKIP_INSTALL_ERRORS=0
INSTALL_LLVMGCC_BIN=0
VERBOSE_OUTPUT=0
MAKE_THREADS=4
ROOT_DIR="`pwd`"

elapsed_time()
{
  if [[ $# -eq 0 ]]; then
    echo $(date '+%s')
  else
    local  stime=$1
    etime=$(date '+%s')

    if [[ -z "$stime" ]]; then stime=$etime; fi

    dt=$((etime - stime))
    ds=$((dt % 60))
    dm=$(((dt / 60) % 60))
    dh=$((dt / 3600))
    printf '%d:%02d:%02d' $dh $dm $ds
  fi
}

confirm () {
  # call with a prompt string or use a default
  read -r -p "${1:-Are you sure? [Y/n]} " response
  case $response in
    [yY][eE][sS]|[yY]) 
      true
      ;;
    *)
      false
      ;;
  esac
}

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

  eval "scp $REMOTE_PATH/$PACKAGE $LOCAL_DEST/ $LOGGER"

  if [ $PACKAGE_TYPE == "gz" ] || [ $PACKAGE_TYPE == "tgz" ]; then
    eval "tar $TAR_OPTIONS -xvzf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST $LOGGER"
  elif [ $PACKAGE_TYPE == "bz2" ]; then
    eval "tar $TAR_OPTIONS -xvjf $LOCAL_DEST/$PACKAGE -C $LOCAL_DEST $LOGGER"
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
  eval "$ROOT_DIR/src/$NCURSES/configure $NCURSES_CONFIG_OPTIONS $LOGGER"

  echo -n "[Compiling] "
  eval "make -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $NCURSES_ROOT
  eval "make -j $MAKE_THREADS install $LOGGER"

  echo "[Done]"
}

install_zlib()
{
  echo -ne "$ZLIB \t\t"
  check_dirs $ZLIB || { return 0; }
  get_package $ZLIB_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$ZLIB"

  cd $ROOT_DIR/src/$ZLIB

  echo -n "[Configuring] "
  eval "$ROOT_DIR/src/$ZLIB/configure --prefix=$ZLIB_ROOT $LOGGER"

  echo -n "[Compiling] "
  eval "make -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $ZLIB_ROOT
  eval "make -j $MAKE_THREADS install $LOGGER"

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
  eval "$ZLIB_LLVM_OPTIONS $ROOT_DIR/src/$ZLIB-llvm/configure --static --prefix=$ZLIB_ROOT $LOGGER"

  echo -n "[Compiling] "
  eval "make libz.a $LOGGER"

  echo -n "[Installing] "
  mkdir -p $ZLIB_ROOT
  eval "cp -p libz.a $ZLIB_ROOT/lib/libz-llvm.a"

  echo "[Done]"
}

install_expat()
{
  echo -ne "$EXPAT\t\t"
  check_dirs $EXPAT || { return 0; }
  get_package $EXPAT_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$EXPAT"
  cd $ROOT_DIR/src/$EXPAT

  echo -n "[Configuring] "
  eval "$ROOT_DIR/src/$EXPAT/configure --prefix=$EXPAT_ROOT $LOGGER"

  echo -n "[Compiling] "
  eval "make -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $EXPAT_ROOT
  eval "make -j $MAKE_THREADS install $LOGGER"

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
  eval "./bootstrap.sh --prefix=$BOOST_ROOT $LOGGER"
  eval "./bjam $BJAM_OPTIONS $LOGGER"

  echo -n "[Installing] "
  eval "./bjam $BJAM_OPTIONS install $LOGGER"

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
  eval "$ROOT_DIR/src/$LIBUNWIND/configure CFLAGS=\"-U_FORTIFY_SOURCE\" --prefix=$LIBUNWIND_ROOT $LOGGER"

  echo -n "[Compiling] "
  eval "make -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $LIBUNWIND_ROOT
  eval "make -j $MAKE_THREADS install $LOGGER"

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

  eval "LD_LIBRARY_PATH=$GOOGLE_PERFTOOLS_LD_LIBRARY_PATH $GOOGLE_PERFTOOLS_CONFIG_COMMAND $LOGGER"

  echo -n "[Compiling] "
  eval "make -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $GOOGLE_PERFTOOLS_ROOT
  eval "make -j $MAKE_THREADS install $LOGGER"

  echo "[Done]"
}


install_uclibc()
{
  echo -ne "$UCLIBC\t"
  check_dirs $UCLIBC || { return 0; }
  get_package $UCLIBC_PACKAGE $PACKAGE_DIR "$ROOT_DIR/src/$UCLIBC"

  cd $ROOT_DIR/src/$UCLIBC

  echo -n "[Configuring] "
  eval "./configure --with-llvm=$ROOT_DIR/build/$LLVM $LOGGER"

  echo -n "[Compiling] "
  eval "make $LOGGER"

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
  eval "$ROOT_DIR/src/$LLVMGCC/configure $LLVMGCC_CONFIG_OPTIONS $LOGGER"

  LLVMGCC_MAKE_OPTIONS=""

  if test ${ALTCC+defined}; then
    LLVMGCC_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi
  if test ${GXX_INCLUDE_DIR+defined}; then
    LLVMGCC_MAKE_OPTIONS+="--with-gxx-include-dir=$GXX_INCLUDE_DIR "
  fi

  echo -n "[Compiling] "
  eval "make $LLVMGCC_MAKE_OPTIONS -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $LLVMGCC_ROOT
  eval "make $LLVMGCC_MAKE_OPTIONS install $LOGGER"

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

  eval "$ROOT_DIR/src/$LLVM/configure $LLVM_CONFIG_OPTIONS $LOGGER"
}

build_llvm ()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then TARGET=$1; fi

  mkdir -p $ROOT_DIR/build/$LLVM
  cd $ROOT_DIR"/build/$LLVM"

  LLVM_MAKE_OPTIONS=" -j $MAKE_THREADS "

  eval "make ENABLE_OPTIMIZED=0 $LLVM_MAKE_OPTIONS $TARGET $LOGGER"
  eval "make ENABLE_OPTIMIZED=1 $LLVM_MAKE_OPTIONS $TARGET $LOGGER"
}

update_llvm()
{
  echo -ne "$LLVM\t\t"

  if [ ! -e "$ROOT_DIR/src/$LLVM/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$LLVM

  echo -n "[Checking] "
  eval "git remote update $LOGGER"

  if [ $FORCE_UPDATE -eq 1 ] || git status -uno | grep -q behind ; then

    echo -n "[Pulling] "
    eval "git pull --all $LOGGER"

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
  eval "git clone $LLVM_GIT $LOGGER"

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
  KLEE_CONFIG_OPTIONS="--prefix=$KLEE_ROOT "
  KLEE_CONFIG_OPTIONS+="--with-llvmsrc=$ROOT_DIR/src/$LLVM --with-llvmobj=$ROOT_DIR/build/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-uclibc=$UCLIBC_ROOT --enable-posix-runtime "

  KLEE_CONFIG_OPTIONS+="LDFLAGS=\"-L$BOOST_ROOT/lib -L$GOOGLE_PERFTOOLS_ROOT/lib\" "
  KLEE_CONFIG_OPTIONS+="CPPFLAGS=\"-I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include\" "
  KLEE_CONFIG_OPTIONS+="CXXFLAGS=\"-I$BOOST_ROOT/include -I$GOOGLE_PERFTOOLS_ROOT/include\" "

  if test ${ALTCC+defined}; then
   KLEE_CONFIG_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi

  eval "$ROOT_DIR/src/$KLEE/configure $KLEE_CONFIG_OPTIONS $LOGGER"
}

build_klee()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then TARGET=$1; fi

  cd $ROOT_DIR/src/klee
  KLEE_MAKE_OPTIONS="RUNTIME_ENABLE_OPTIMIZED=1 REQUIRES_RTTI=1 -j $MAKE_THREADS "

  if test ${ALTCC+defined}; then
   KLEE_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX VERBOSE=1 "
  fi

  eval "make ENABLE_OPTIMIZED=0 $KLEE_MAKE_OPTIONS $TARGET $LOGGER"
  eval "make ENABLE_OPTIMIZED=1 $KLEE_MAKE_OPTIONS $TARGET $LOGGER"
}

install_klee()
{
  echo -ne "$KLEE\t\t\t"

  check_dirs $KLEE || { return 0; }

  cd $ROOT_DIR"/src"

  echo -n "[Cloning] "
  eval "git clone $KLEE_GIT $LOGGER"

  cd $ROOT_DIR"/src/$KLEE"

  eval "git checkout -b $KLEE_BRANCH origin/$KLEE_BRANCH $LOGGER"

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

  echo -n "[Checking] "
  eval "git remote update $LOGGER"

  if [ $FORCE_UPDATE -eq 1 ] || git status -uno | grep -q behind ; then

    echo -n "[Pulling] "
    eval "git pull --all $LOGGER"

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
  eval "make $TETRINET_MAKE_OPTIONS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $TETRINET_ROOT
  eval "make $TETRINET_MAKE_OPTIONS install $LOGGER"
}

update_tetrinet()
{
  echo -ne "$TETRINET\t\t"

  if [ ! -e "$ROOT_DIR/src/$TETRINET/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$TETRINET

  echo -n "[Checking] "
  eval "git remote update $LOGGER"

  if [ $FORCE_UPDATE -eq 1 ] || git status -uno | grep -q behind ; then

    echo -n "[Pulling] "
    eval "git pull --all $LOGGER"

    if [ $FORCE_CLEAN -eq 1 ]; then 
      echo -n "[Cleaning] "
      eval "make clean $LOGGER"
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
  eval "git clone $TETRINET_GIT $LOGGER"

  cd $ROOT_DIR"/src/$TETRINET"

  eval "git checkout -b $TETRINET_BRANCH origin/$TETRINET_BRANCH $LOGGER"

  build_tetrinet

  echo "[Done]"
}

config_and_build_xpilot()
{
  if [[ $# -ne 1 ]]; then echo "[Error] "; exit; fi

  XPILOT_CONFIG_OPTIONS="--disable-sdl-client --disable-sdl-gameloop "
  XPILOT_CONFIG_OPTIONS+="--disable-sdltest --disable-xp-mapedit "
  XPILOT_CONFIG_OPTIONS+="--disable-replay --disable-sound "
  XPILOT_CONFIG_OPTIONS+="--enable-select-sched --prefix=$XPILOT_ROOT "
  XPILOT_CONFIG_OPTIONS+="--program-suffix=-$1 "

  XPILOT_LLVM_OPTIONS="LLVMINTERP=$LLVM_ROOT/bin/lli UCLIBC_ROOT=$UCLIBC_ROOT LLVM_ROOT=$LLVM_ROOT "
  XPILOT_LLVM_OPTIONS+="LLVMGCC_ROOT=$LLVMGCC_ROOT CC=$ROOT_DIR/src/$XPILOT-$1/llvm_gcc_script.py "

  if [ "$1" == "llvm" ]; then
    XPILOT_CONFIG_OPTIONS="$XPILOT_LLVM_OPTIONS $XPILOT_CONFIG_OPTIONS "
    XPILOT_MAKE_OPTIONS+="$XPILOT_LLVM_OPTIONS "
  fi

  echo -n "[Configuring] "
  eval "$ROOT_DIR/src/$xpilot_opt/configure $XPILOT_CONFIG_OPTIONS $LOGGER"

  echo -n "[Compiling] "
  eval "make $XPILOT_MAKE_OPTIONS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $XPILOT_ROOT
  eval "make $XPILOT_MAKE_OPTIONS install $LOGGER"

  if [ "$1" == "llvm" ]; then
    eval "cp -u $ROOT_DIR/src/$XPILOT-$1/src/client/x11/xpilot-ng-x11.bc $XPILOT_ROOT/bin/ $LOGGER"
    eval "cp -u $ROOT_DIR/src/$XPILOT-$1/src/server/xpilot-ng-server.bc $XPILOT_ROOT/bin/ $LOGGER"
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

  echo -n "[Checking] "
  eval "git remote update $LOGGER"

  if [ $FORCE_UPDATE -eq 1 ] || git status -uno | grep -q behind ; then

    echo -n "[Pulling] "
    eval "git pull --all $LOGGER"

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
  eval "git clone $XPILOT_GIT $xpilot_opt $LOGGER"

  cd $ROOT_DIR"/src/$xpilot_opt"

  eval "git checkout -b $XPILOT_BRANCH origin/$XPILOT_BRANCH $LOGGER"

  config_and_build_xpilot $1

  echo "[Done]"
}


#==============================================================================#
# main
#==============================================================================#

while getopts ":afkcivsbr:j:" opt; do
  case $opt in
    a)
      # Use alternative GCC
      ALTCC=gcc-4.4
      ALTCXX=g++-4.4
      GXX_INCLUDE_DIR="/usr/include/c++/4.4"
      ;;

    f)
      FORCE_UPDATE=1
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
      SKIP_INSTALL_ERRORS=1
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

if [[ -z $ROOT_DIR ]] || [[ ! -e $ROOT_DIR ]]; then
  echo "Valid root directory required. Use commandline option '-r dir-name'"
  exit
fi

# Install directories

UCLIBC_ROOT="$ROOT_DIR/src/$UCLIBC"
KLEE_ROOT="$ROOT_DIR/local"
LLVM_ROOT="$ROOT_DIR/local"
BOOST_ROOT="$ROOT_DIR/local"
LLVMGCC_ROOT="$ROOT_DIR/local"
LIBUNWIND_ROOT="$ROOT_DIR/local"
NCURSES_ROOT="$ROOT_DIR/local"
GOOGLE_PERFTOOLS_ROOT="$ROOT_DIR/local"
TETRINET_ROOT="$ROOT_DIR/local"
ZLIB_ROOT="$ROOT_DIR/local"
EXPAT_ROOT="$ROOT_DIR/local"
XPILOT_ROOT="$ROOT_DIR/local"

LOG_FILE=$ROOT_DIR/`basename $0 .sh`.log

if [ $VERBOSE_OUTPUT -eq 1 ]; then
  LOGGER=" 2>&1 | tee -a $LOG_FILE"
else
  LOGGER=">> $LOG_FILE 2>&1 "
fi

touch $LOG_FILE
echo "$0 ======= `date`" >> $LOG_FILE
etime=$(elapsed_time)

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

else

  update_llvm
  update_klee
  update_tetrinet
  update_xpilot llvm
  update_xpilot x86

fi

echo "Elapsed time: $(elapsed_time $etime)"
