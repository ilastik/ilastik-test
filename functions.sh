
# simple function to exit with an error message
die() {
    echo "$1" >&2
    exit 1
}


parse_options() {
    read -d '' HELPSTRING <<- "_EOF_"
    Usage: $0 [-a] [-d <download.html>] [-b <binary.tar.gz>]
        where 
          -a turns on static analyzers such as pylint and coverage
          -d optionally specify an HTML file to parse for the binary URL
          -b optionally specify binary file to use for testing
_EOF_

    while getopts ":ab:d:h" opt; do
        case $opt in
            a)
                ANALYZERS=true
                ;;
            b)
                BINARYFNAME="${OPTARG}"
                ;;
            d)
                [ -f "${OPTARG}" ] || die "Cannot find HTML file ${OPTARG}!"
                HTMLFNAME="${OPTARG}"
                ;;
            h)
                echo "$HELPSTRING"
                exit 0
                ;;
            \?)
                echo "$HELPSTRING"
                die "Invalid option: -$OPTARG"
                ;;
        esac
    done

    # we need at least one of BINARYFNAME or HTMLFNAME
    # the case where both are defined is covered below
    [ -n "$BINARYFNAME" ] || [ -n "$HTMLFNAME" ] || die \
        "At least one of -b or -d is needed."

    if [ -n "${HTMLFNAME}" ]; then
        [ -n "${BINARYFNAME}" ] && die \
            "Only one of -b and -d options can be used at the same time!"
        [ -f "${HTMLFNAME}" ] || die "Cannot find HTML file ${BINARYFNAME}!"
        fetch_binary "${HTMLFNAME}"
    elif [ -z "${BINARYFNAME}" ]; then
        die "One of -d or -b options must be specified"
    fi

    [ -n ${BINARYFNAME} ] && [ -f ${BINARYFNAME} ] || die \
        "Cannot find binary file ${BINARYFNAME}!"
}

fetch_binary() {
    INFILE=$1
    BINARYURL=`sed -ne \
        "s#.*\(http://files.ilastik.org/ilastik-[^\"]*-$PLATFORM[^\"]*\).*#\1#p"\
        < $INFILE`
    echo Downloading binary from $BINARYURL...
    BINARYFNAME=`basename $BINARYURL`
    curl $BINARYURL -o $BINARYFNAME
    echo Binary downloaded to $BINARYFNAME.
}

run_nose() {
    case "$PLATFORM" in
        Linux)
            NOSECMD="python -c \"import nose, sys; sys.exit(nose.run())\""
            ;;
        OSX)
            NOSECMD="$CONTENTS_DIR"/MacOS/mac_execfile
            ;;
        *)
            die "Unknown platform for NOSECMD!"
    esac

    XUNITFILE=$SRC_DIR/nosetests.$1.xml
    NOSEARGS="--with-xunit --xunit-file=$XUNITFILE "

    if [ "$ANALYZERS" = "true" ]; then
        NOSEARGS+="--with-coverage --cover-package=$1 --cover-inclusive "
    fi
    
    FULLCMD="find . -iname \"*test*.py\" | xargs $NOSECMD $NOSEARGS"
    eval $FULLCMD || FAILED=1

    # fix testsuite name in the xunit file
    [ -f "$XUNITFILE" ] && sed -e "s/name\=\"/name\=\"$1./g" -i '' "$XUNITFILE"

    # move coverage files to a central location to merge them later
    if [ "$ANALYZERS" = "true" ]; then
        COVCOUNT=$(($COVCOUNT+1))
        cp .coverage $SRC_DIR/.coverage.$COVCOUNT
        coverage xml -o $SRC_DIR/coverage.$1.xml
    fi
}

run_gui_test() {
    case "$PLATFORM" in
        Linux)
            ILASTIKCMD="python $SRC_DIR/ilastik/ilastik.py"
            ;;
        OSX)
            ILASTIKCMD="$CONTENTS_DIR"/MacOS/ilastik
            ;;
        *)
            die "Unknown platform for NOSECMD!"
    esac
    FILENAME=${1##*/}
    XUNITFILE=$SRC_DIR/nosetests.${FILENAME%.py}.xml

    NOSEARGS="--with-xunit --xunit-file=$XUNITFILE "
    if [ "$ANALYZERS" = "true" ]; then
        NOSEARGS+="--with-coverage --cover-package=$1 --cover-inclusive "
    fi
    
    eval $ILASTIKCMD --playback_script $1 --exit_on_failure --exit_on_success \
        $NOSEARGS
    # fix testsuite name in the xunit file
    [ -f "$XUNITFILE" ] && \
        sed -e "s/name\=\"/name\=\"recorded./g" -i '' "$XUNITFILE"

    # move coverage files to a central location to merge them later
    if [ "$ANALYZERS" = "true" ]; then
        COVCOUNT=$(($COVCOUNT+1))
        cp .coverage $SRC_DIR/.coverage.$COVCOUNT
        coverage xml -o $SRC_DIR/coverage.$COVCOUNT.xml
    fi
}

run_pylint() {
    # this is a noop if $ANALYZERS are not "true"
    [ "$ANALYZERS" = "true" ] || return
    OUTFILE="$SRC_DIR/pylint.$1.out"
    #:C0103: *Invalid name "%s" (should match %s)*
    #  Used when the name doesn't match the regular expression associated
    #  to its type (constant, variable, class...).
    #:C0111: *Missing docstring*
    #  Used when a module, function, class or method has no docstring.
    #  Some special methods like __init__ doesn't necessary require a
    #  docstring.
    #:C0301): *Line too long (%s/%s)*
    #  Used when a line is longer than a given number of characters.
    #:C0303: *Trailing whitespace*
    #  Used when there is whitespace between the end of a line and the
    #  newline.
    #:C0324: *Comma not followed by a space*
    #  Used when a comma (",") is not followed by a space.
    #:C0330: *Wrong %s indentation%s.*
    pylint -f parseable -d C0103,C0111,C0301,C0303,C0324,C0330 \
--extension-pkg-whitelist=vigra,numpy,PyQt4.QtGui,PyQt4.QtCore $1 |\
tee "$OUTFILE"
    # we need relative file paths
    [ -f "$OUTFILE"] && sed -e "s#$SRC_DIR/##" -i '' "$OUTFILE"
}

run_tests() {
    FAILED=0
    COVCOUNT=0

    echo ----------------------------
    echo Running volumina tests...
    cd "$SRC_DIR/volumina/tests"
    run_nose volumina
    run_pylint volumina

    echo ----------------------------
    echo Running lazyflow tests...
    cd "$SRC_DIR/lazyflow/tests"
    run_nose lazyflow
    run_pylint lazyflow

    echo ----------------------------
    echo Running ilastik headless tests...
    cd "$SRC_DIR/ilastik/tests"
    run_nose ilastik
    run_pylint ilastik

    echo ----------------------------
    echo Running GUI tests...
    cd "$SRC_DIR/ilastik/tests"
    for i in `find recorded_test_cases -iname "*.py"`; do
        run_gui_test $i
    done

    if [ "$ANALYZERS" = "true" ]; then
        cd $SRC_DIR
        coverage combine
        coverage xml
        sed -e "s#$SRC_DIR/##" -i '' coverage.xml
    fi
}
