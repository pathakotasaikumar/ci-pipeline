#!/bin/bash
set -e

# Redirect all output to /var/log/bootstrap.log and /dev/console
exec > >(tee /var/log/bootstrap.log | logger -t bootstrap -s 2>/dev/console) 2>&1

# Load context into environment
. /root/context
. /etc/profile.d/set_qcp_proxy.sh

# Execute all test scripts
ANY_FAILED=0
for SCRIPT in ./tests/*.sh; do
  SCRIPT_NAME=`basename $SCRIPT`
  echo "=== Executing test script '$SCRIPT_NAME' ==="

  EXIT_CODE=0
  chmod +x $SCRIPT
  sh $SCRIPT || EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS: Test script '$SCRIPT_NAME' has completed successfully"
  else
    echo "FAILURE: Test script '$SCRIPT_NAME' has failed (exit code $EXIT_CODE)"
    ANY_FAILED=1
  fi
  echo ""
done

echo ""
if [ $ANY_FAILED -eq 0 ]; then
  echo " === SUCCESS: all test scripts have passed ==="
else
  echo " === FAILURE: one or more tests have failed ==="
fi

echo "Ensuring we can access dot files artefacts"
cat .test_folder/.test_file || EXIT_CODE=$?

echo " ===== TEST RESULTS ===== " > /var/log/deploy.log
cat /var/log/bootstrap.log > /var/log/deploy.log

exit $ANY_FAILED
