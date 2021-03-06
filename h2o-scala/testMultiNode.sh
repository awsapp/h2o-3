#!/bin/bash

# Clean out any old sandbox, make a new one
OUTDIR=sandbox
rm -fr $OUTDIR; mkdir -p $OUTDIR

# Check for os
SEP=:
case "`uname`" in
    CYGWIN* )
      SEP=";"
      ;;
esac

function cleanup () {
  kill -9 ${PID_1} ${PID_2} ${PID_3} ${PID_4} >> /dev/null
  wait 1> /dev/null 2>&1
  RC=`cat $OUTDIR/status.0`
  if [ $RC -ne 0 ]; then
    cat $OUTDIR/out.0
    echo h2o-scala junit tests FAILED
  else
    echo h2o-scala junit tests PASSED
  fi
  exit $RC
}

trap cleanup SIGTERM SIGINT

# Find java command
if [ -z "$TEST_JAVA_HOME" ]; then
  # Use default
  JAVA_CMD="java"
else
  # Use test java home
  JAVA_CMD="$TEST_JAVA_HOME/bin/java"
  # Increase XMX since JAVA_HOME can point to java6
  JAVA6_REGEXP=".*1\.6.*"
  if [[ $TEST_JAVA_HOME =~ $JAVA6_REGEXP ]]; then
    JAVA_CMD="${JAVA_CMD} -Xmx2g"
  fi
fi

# Gradle puts files:
#   build/classes/main - Main h2o core classes
#   build/classes/test - Test h2o core classes
#   build/resources/main - Main resources (e.g. page.html)
# Command to invoke test
JVM="nice $JAVA_CMD -ea -cp build/libs/h2o-scala_2.10.jar${SEP}build/libs/h2o-scala_2.10-test.jar${SEP}../h2o-core/build/libs/h2o-core.jar${SEP}../h2o-core/build/libs/h2o-core-test.jar${SEP}../h2o-genmodel/build/libs/h2o-genmodel.jar${SEP}../lib/*"
echo "$JVM" > $OUTDIR/jvm_cmd.txt

# Runner
# Default JUnit runner is org.junit.runner.JUnitCore
JUNIT_RUNNER="water.junit.H2OTestRunner"

# find all java in the src/test directory
# Cut the "./water/MRThrow.java" down to "water/MRThrow.java"
# Cut the   "water/MRThrow.java" down to "water/MRThrow"
# Slash/dot "water/MRThrow"      becomes "water.MRThrow"
(cd src/test/scala; /usr/bin/find . -name '*.scala' | cut -c3- | sed 's/.scala$//' | sed -e 's/\//./g') > $OUTDIR/tests.txt

# Output the comma-separated list of ignored/dooonly tests
# Ignored tests trump do-only tests
echo $IGNORE > $OUTDIR/tests.ignore.txt
echo $DOONLY > $OUTDIR/tests.doonly.txt

# Launch 4 helper JVMs.  All output redir'd at the OS level to sandbox files.
CLUSTER_NAME=junit_cluster_$$
CLUSTER_BASEPORT=45000
$JVM water.H2O -name $CLUSTER_NAME -baseport $CLUSTER_BASEPORT --ga_opt_out 1> $OUTDIR/out.1 2>&1 & PID_1=$!
$JVM water.H2O -name $CLUSTER_NAME -baseport $CLUSTER_BASEPORT --ga_opt_out 1> $OUTDIR/out.2 2>&1 & PID_2=$!
$JVM water.H2O -name $CLUSTER_NAME -baseport $CLUSTER_BASEPORT --ga_opt_out 1> $OUTDIR/out.3 2>&1 & PID_3=$!
$JVM water.H2O -name $CLUSTER_NAME -baseport $CLUSTER_BASEPORT --ga_opt_out 1> $OUTDIR/out.4 2>&1 & PID_4=$!

# Launch last driver JVM.  All output redir'd at the OS level to sandbox files.
echo Running h2o-scala junit tests...
($JVM -Ddoonly.tests=$DOONLY -Dignore.tests=$IGNORE -Dbuild.id=$BUILD_ID -Djob.name=$JOB_NAME -Dgit.commit=$GIT_COMMIT -Dgit.branch=$GIT_BRANCH -Dai.h2o.name=$CLUSTER_NAME -Dai.h2o.baseport=$CLUSTER_BASEPORT -Dai.h2o.ga_opt_out=yes $JUNIT_RUNNER `cat $OUTDIR/tests.txt` 2>&1 ; echo $? > $OUTDIR/status.0) 1> $OUTDIR/out.0 2>&1

cleanup
