#!/bin/bash

# Run tests on an ilastik binary for OSX.
# -----------------------------------------------------------------------------

PLATFORM=OSX

source functions.sh

parse_options $*
[ "$ANALYZERS" = "true" ] && die "Code analyzers not supported on OSX!"


[ -n "${BINARYFNAME}" ]  || die "Cannot determine binary file name!"

#extract_binary
echo "Extracting ${BINARYFNAME}"
tar xf "$BINARYFNAME"


CONTENTS_DIR=`pwd`/ilastik.app/Contents
SRC_DIR="$CONTENTS_DIR"/Resources/lib/python2.7/ilastik-meta

# some hacks to get nose running in the py2app bundle
# download full nose tarball and "install" it
NOSEVER=1.3.4
cd ${CONTENTS_DIR}/Resources/lib/python2.7
curl https://pypi.python.org/packages/source/n/nose/nose-$NOSEVER.tar.gz -o nose.tar.gz
tar xf nose.tar.gz --strip-components=1 nose-$NOSEVER/nose
# nose's xunit plugin needs the xml.sax module
# copy the xml module from the system python
cp -r /System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/xml .
# fix symbolic links to our modules
for i in {ilastik,lazyflow,volumina}; do
    rm $i
    ln -s ilastik-meta/$i/$i .
done
ln -s ilastik-meta/ilastik/submodules/eventcapture/eventcapture .

# replace mac_execfile.py script with our nose runner script
cat >"$CONTENTS_DIR"/Resources/mac_execfile.py <<_EOF_
import os
os.chdir(os.environ['PWD'])

import sys
import nose
try:
    sys.exit(nose.run())
except:
    sys.exit(1)
_EOF_


run_tests


[ $FAILED -eq 0 ] || die "Some tests failed!"
