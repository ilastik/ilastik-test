#!/bin/bash

# Run tests on an ilastik binary for Linux.
#
# -----------------------------------------------------------------------------

PLATFORM=Linux

source functions.sh

parse_options $*


[ -n "${BINARYFNAME}" ]  || die "Cannot determine binary file name!"

#extract_binary
DIRNAME=`echo "${BINARYFNAME}" |  sed -e "s/[a-z]*-$PLATFORM.*/-$PLATFORM/"`
echo "Extracting ${BINARYFNAME} to $DIRNAME"
tar xf "$BINARYFNAME"
[ -d "$DIRNAME" ] || die \
    "Tarball $FILENAME did not produce directory $DIRNAME"
cd $DIRNAME


# duplicate logic from run_ilastik.sh
export BUILDEM_DIR=`pwd`
export ILASTIK_USE_CLEAN_LD_LIBRARY_PATH=1
source bin/setenv_ilastik_gui.sh
echo Using Python from: `which python`

if [ "$ANALYZERS" = "true" ]; then
    # use easy_install as a module
    # the shebang in $BUILDEM_DIR/bin/easy_install refers to the build dir
    python -m easy_install coverage
    python -m easy_install pylint
fi

SRC_DIR=$BUILDEM_DIR/src/ilastik
FAILED=0
COVCOUNT=0
ILASTIKCMD="python $SRC_DIR/ilastik/ilastik.py"

run_tests

if [ "$ANALYZERS" = "true" ]; then
    cd $SRC_DIR
    coverage combine
    coverage xml
fi

[ $FAILED -eq 0 ] || die "Some tests failed!"
