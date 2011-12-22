#!/bin/bash

# see http://www.davidpashley.com/articles/writing-robust-shell-scripts.html
set -u # Exit if uninitialized value is used 
set -e # Exit on non-true value
set -o pipefail # exit on fail of any command in a pipe

###################### EDIT THIS SECTION FOR YOUR SYSTEM ######################

#ROOT_DIR="/playpen/rac/gsec"

# Make configuration
MAKE_THREADS=32

# Alternative GCC version 
#ALTCC=gcc-4.5
#ALTCXX=g++-4.5
#GXX_INCLUDE_DIR="/usr/include/c++/4.5"

###############################################################################

_gcc_fullversion() {
  local ver="$1"; shift
  set -- `$CC -E -P - <<<"__GNUC__ __GNUC_MINOR__ __GNUC_PATCHLEVEL__"`
  eval echo "$ver"
}
gcc-fullversion() {  
  _gcc_fullversion '$1.$2.$3' "$@" 
}
gcc-version() {  
  _gcc_fullversion '$1.$2' "$@" 
}
gcc-major-version() {  
  _gcc_fullversion '$1' "$@"
}
gcc-minor-version() {
  _gcc_fullversion '$2' "$@"
}

# Packages to install
LLVM="llvm-2.7"
LLVMGCC="llvm-gcc-4.2-2.7"
LLVMGCC_BIN="llvm-gcc4.2-2.7-x86_64-linux"
KLEE="klee"
UCLIBC="klee-uclibc"
BOOST="boost_1_42_0"
GOOGLE_PERFTOOLS="google-perftools-1.8.3"
UDIS86="udis86-1.7"
LIBUNWIND="libunwind-1.0.1"

GIT_DIR="/afs/cs.unc.edu/home/rac/repos/research/"
LLVM_GIT="$GIT_DIR/$LLVM.git"
KLEE_GIT="$GIT_DIR/$KLEE.git"

PACKAGE_DIR="/afs/cs.unc.edu/home/rac/public/research/files"
UCLIBC_PACKAGE="$PACKAGE_DIR/klee-uclibc-0.01-x64.tgz"
BOOST_PACKAGE="$PACKAGE_DIR/$BOOST.tar.gz"
GOOGLE_PERFTOOLS_PACKAGE="$PACKAGE_DIR/$GOOGLE_PERFTOOLS.tar.gz"
UDIS86_PACKAGE="$PACKAGE_DIR/$UDIS86.tar.gz"
LIBUNWIND_PACKAGE="$PACKAGE_DIR/$LIBUNWIND.tar.gz"
LLVMGCC_PACKAGE="$PACKAGE_DIR/$LLVMGCC.source.tgz"
LLVMGCC_BIN_PACKAGE="$PACKAGE_DIR/$LLVMGCC_BIN.tar.bz2"

# Install directories
UCLIBC_ROOT="$ROOT_DIR/src/$UCLIBC"

KLEE_ROOT="$ROOT_DIR/local"
LLVM_ROOT="$ROOT_DIR/local"
BOOST_ROOT="$ROOT_DIR/local"
LLVMGCC_ROOT="$ROOT_DIR/local/$LLVMGCC"
LIBUNWIND_ROOT="$ROOT_DIR/local"
GOOGLE_PERFTOOLS_ROOT="$ROOT_DIR/local"

# Command line options
FORCE_CLEAN=0
FORCE_UPDATE=0
FORCE_CONFIGURE=0
INSTALL_PACKAGES=0
SKIP_INSTALL_ERRORS=0
LLVM_GCC_BINARY=0

LOG_FILE=$ROOT_DIR/`basename $0 .sh`.log
LOGGER=">> $LOG_FILE 2>&1 "

function timer()
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

check_dirs()
{
  if [ -e $ROOT_DIR/src/$1 ] ||
     [ -e $ROOT_DIR/build/$1 ]; then
    if [ $SKIP_INSTALL_ERRORS -eq 1 ]; then
      echo "[Skipping] (Already exists, integrity unconfirmed) "
      return 1
    else
      echo "[Error] "
      exit
    fi
  fi
}

install_boost()
{
  echo -ne "$BOOST\t\t"

  check_dirs $BOOST || { return 0; }

  cd $ROOT_DIR/src/

  echo -n "[Extracting] "
  eval "tar -xvzf $BOOST_PACKAGE $LOGGER"

  cd $ROOT_DIR/src/$BOOST

  echo -n "[Compiling] "
  eval "./bootstrap.sh --prefix=$BOOST_ROOT $LOGGER"
  eval "./bjam --without-mpi -j$MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  eval "./bjam --without-mpi -j$MAKE_THREADS install $LOGGER"

  echo "[Done]"
}

install_libunwind()
{
  echo -ne "$LIBUNWIND\t\t"

  check_dirs $LIBUNWIND || { return 0; }

  echo -n "[Extracting] "
  cd $ROOT_DIR/src/
  eval "tar -xvzf $LIBUNWIND_PACKAGE $LOGGER"

  mkdir -p $ROOT_DIR/build/$LIBUNWIND
  cd $ROOT_DIR/build/$LIBUNWIND

  echo -n "[Configuring] "
  eval "$ROOT_DIR/src/$LIBUNWIND/configure --prefix=$LIBUNWIND_ROOT $LOGGER"

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

  echo -n "[Extracting] "
  cd $ROOT_DIR/src/
  eval "tar -xvzf $GOOGLE_PERFTOOLS_PACKAGE $LOGGER"

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
  eval "LD_LIBRARY_PATH=$LIBUNWIND_ROOT/lib $GOOGLE_PERFTOOLS_CONFIG_COMMAND $LOGGER"

  echo -n "[Compiling] "
  eval "make -j $MAKE_THREADS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $GOOGLE_PERFTOOLS_ROOT
  eval "make -j $MAKE_THREADS install $LOGGER"

  echo "[Done]"
}


install_uclibc()
{
  echo -ne "$UCLIBC\t\t"

  check_dirs $UCLIBC || { return 0; }

  cd $ROOT_DIR/src/

  echo -n "[Extracting] "
  eval "tar -xvzf $UCLIBC_PACKAGE $LOGGER"

  cd $ROOT_DIR/src/$UCLIBC

  echo -n "[Configuring] "
  eval "./configure --with-llvm=$ROOT_DIR/build/$LLVM $LOGGER"

  echo -n "[Compiling] "
  eval "make oldconfig $LOGGER"
  eval "make $LOGGER"

  echo "[Done]"
} 

install_llvmgcc_bin()
{
  echo -ne "$LLVMGCC\t"

  check_dirs $LLVMGCC || { return 0; }
  check_dirs $LLVMGCC.source || { return 0; }

  echo -n "[Extracting] "
  eval "tar -xjf $LLVMGCC_BIN_PACKAGE -C $ROOT_DIR/local $LOGGER"

  mv $ROOT_DIR/local/$LLVMGCC_BIN $LLVMGCC_ROOT

  echo "[Done]"
}

install_llvmgcc_from_source()
{
  echo -ne "$LLVMGCC\t"

  check_dirs $LLVMGCC || { return 0; }
  check_dirs $LLVMGCC.source || { return 0; }

  echo -n "[Extracting] "
  cd $ROOT_DIR/src/
  eval "tar -xzf $LLVMGCC_PACKAGE $LOGGER"

  mkdir -p $ROOT_DIR/build/$LLVMGCC
  cd $ROOT_DIR/build/$LLVMGCC

  LLVMGCC_CONFIG_OPTIONS="--enable-llvm=$LLVM_ROOT --prefix=$LLVMGCC_ROOT "
  LLVMGCC_CONFIG_OPTIONS+="--program-prefix=llvm- --enable-languages=c,c++ "

  echo -n "[Configuring] "
  eval "$ROOT_DIR/src/$LLVMGCC.source/configure $LLVMGCC_CONFIG_OPTIONS $LOGGER"

  LLVMGCC_MAKE_OPTIONS="-j $MAKE_THREADS "

  if test ${ALTCC+defined}; then
    LLVMGCC_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi
  if test ${GXX_INCLUDE_DIR+defined}; then
    LLVMGCC_MAKE_OPTIONS+="--with-gxx-include-dir=$GXX_INCLUDE_DIR "
  fi

  echo -n "[Compiling] "
  eval "make $LLVMGCC_MAKE_OPTIONS $LOGGER"

  echo -n "[Installing] "
  mkdir -p $LLVMGCC_ROOT
  eval "make $LLVMGCC_MAKE_OPTIONS install $LOGGER"

  echo "[Done]"
}

config_llvm ()
{ 
  mkdir -p $ROOT_DIR/build/$LLVM
  cd $ROOT_DIR"/build/$LLVM"
  eval "$ROOT_DIR/src/$LLVM/configure --enable-optimized --with-llvmgccdir=$LLVMGCC_ROOT --prefix=$LLVM_ROOT $LOGGER"
}

build_llvm ()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then
    TARGET=$1
  fi

  mkdir -p $ROOT_DIR/build/$LLVM
  cd $ROOT_DIR"/build/$LLVM"

  LLVM_MAKE_OPTIONS=" -j $MAKE_THREADS "

  if test ${ALTCC+defined}; then
    LLVM_MAKE_OPTIONS+="CC=$ALTCC CXX=$ALTCXX "
  fi
  if test ${GXX_INCLUDE_DIR+defined}; then
    LLVM_MAKE_OPTIONS+="--with-gxx-include-dir=$GXX_INCLUDE_DIR "
  fi

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

  echo -n "[Checking updates] "
  eval "git remote update $LOGGER"

  if [ $FORCE_UPDATE -eq 1 ] || git status -uno | grep -q behind ; then

    echo -n "[Pulling updates] "
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

config_cliver()
{
  cd $ROOT_DIR/src/$KLEE
  KLEE_CONFIG_OPTIONS="--prefix=$KLEE_ROOT "
  KLEE_CONFIG_OPTIONS+="--with-llvmsrc=$ROOT_DIR/src/$LLVM --with-llvmobj=$ROOT_DIR/build/$LLVM "
  KLEE_CONFIG_OPTIONS+="--with-uclibc=$UCLIBC_ROOT --enable-posix-runtime "
  KLEE_CONFIG_OPTIONS+="LDFLAGS=\"-L$BOOST_ROOT/lib/ -L$GOOGLE_PERFTOOLS_ROOT/lib\" "
  KLEE_CONFIG_OPTIONS+="CPPFLAGS=\"-I$BOOST_ROOT/include/ -I$GOOGLE_PERFTOOLS_ROOT/include\" "
  KLEE_CONFIG_OPTIONS+="CXXFLAGS=\"-I$BOOST_ROOT/include/ -I$GOOGLE_PERFTOOLS_ROOT/include\" "
  eval "$ROOT_DIR/src/$KLEE/configure $KLEE_CONFIG_OPTIONS $LOGGER"
}

build_cliver()
{
  local TARGET=""
  if [[ $# -ge 1 ]]; then
    TARGET=$1
  fi

  cd $ROOT_DIR/src/klee
  KLEE_MAKE_OPTIONS="RUNTIME_ENABLE_OPTIMIZED=1 REQUIRES_RTTI=1 -j $MAKE_THREADS "

  #eval "make ENABLE_OPTIMIZED=0 ENABLE_PROFILING=0 $KLEE_MAKE_OPTIONS $TARGET $LOGGER"
  eval "make ENABLE_OPTIMIZED=0 $KLEE_MAKE_OPTIONS $TARGET $LOGGER"
  eval "make ENABLE_OPTIMIZED=1 $KLEE_MAKE_OPTIONS $TARGET $LOGGER"
}

install_cliver()
{
  echo -ne "$KLEE\t\t\t"

  check_dirs $KLEE || { return 0; }

  cd $ROOT_DIR"/src"

  echo -n "[Cloning] "
  eval "git clone $KLEE_GIT $LOGGER"

  cd $ROOT_DIR"/src/$KLEE"

  eval "git checkout -b cliver origin/cliver $LOGGER"

  echo -n "[Configuring] "
  config_cliver

  echo -n "[Compiling] "
  build_cliver

  echo -n "[Installing] "
  mkdir -p $KLEE_ROOT
  build_cliver install

  echo "[Done]"
}

update_cliver()
{
  echo -ne "$KLEE\t\t\t"

  if [ ! -e "$ROOT_DIR/src/$KLEE/.git" ]; then
    echo "[Error] (git directory missing) "; exit;
  fi

  cd $ROOT_DIR/src/$KLEE

  echo -n "[Checking updates] "
  eval "git remote update $LOGGER"

  if [ $FORCE_UPDATE -eq 1 ] || git status -uno | grep -q behind ; then

    echo -n "[Pulling updates] "
    eval "git pull --all $LOGGER"

    if [ $FORCE_CONFIGURE -eq 1 ]; then 
      echo -n "[Configuring] "
      config_cliver
    fi

    if [ $FORCE_CLEAN -eq 1 ]; then 
      echo -n "[Cleaning] "
      build_cliver clean
    fi

    echo -n "[Compiling] "
    build_cliver

    echo -n "[Installing] "
    mkdir -p $KLEE_ROOT
    build_cliver install
  fi

  echo "[Done]"
}


#==============================================================================#
# main
#==============================================================================#

while getopts "fkcivsb" opt; do
  case $opt in
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
      LOGGER=" 2>&1 | tee -a $LOG_FILE"
      ;;
 
    s)
      SKIP_INSTALL_ERRORS=1
      ;;
    b)
      LLVM_GCC_BINARY=1
      ;;

  esac
done

touch $LOG_FILE
echo "$0 ======= `date`" >> $LOG_FILE
t=$(timer)

if [ $INSTALL_PACKAGES -eq 1 ]; then

  mkdir -p $ROOT_DIR/{src,local,build}
  echo "Installing all packages" 

  install_llvm

  if [ $LLVMGCC_BINARY -eq 1 ]; then
    install_llvmgcc_bin
  else
    install_llvmgcc_from_source
  fi

  install_libunwind
  install_google_perftools
  install_boost
  install_uclibc
  install_cliver

else

  update_llvm
  update_cliver

fi

echo "Elapsed time: $(timer $t)"
