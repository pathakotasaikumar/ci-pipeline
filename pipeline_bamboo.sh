#!/bin/bash

BASEDIR=$(dirname "$0")

if [[ ! -z $1 ]]; then
  action=$1
else
  echo "first parameter, action, is required:"
fi

# dry mode flag to enable testing
# use second parameter to execute all flows
if [[ ! -z $2 ]]; then
  dry_run=$2
else
  dry_run=$bamboo_pipeline_cd_regression_dry_run
fi

# updating exec permisions
chmod 755 "$BASEDIR/bin/rake.sh" 

# helpers start
function deploy_build 
{
  build=$1

  echo "Deploying build: $build"

  if [[ ! -z $dry_run ]]; then
    echo "  - dry run, returning 0"
    exit 0
  fi

  bamboo_buildNumber=$build \
    "$BASEDIR/bin/rake.sh" deploy
}

function release_build 
{
  build=$1

  echo "Releasing build: $build"

  if [[ ! -z $dry_run ]]; then
    echo "  - dry run, exiting 0"
    exit 0
  fi

  bamboo_buildNumber=$build \
    "$BASEDIR/bin/rake.sh" release
}

function teardown_build 
{
  build=$1

  echo "Tearing down build: $build"

  if [[ ! -z $dry_run ]]; then
    echo "  - dry run, exiting 0"
    exit 0
  fi

  bamboo_buildNumber=$build \
    "$BASEDIR/bin/rake.sh" teardown
}

function teardown_build_force
{
  build=$1

  echo "Tearing down build: $build"

  if [[ ! -z $dry_run ]]; then
    echo "  - dry run, exiting 0"
    exit 0
  fi

  bamboo_buildNumber=$build \
  bamboo_force_teardown_of_released_build=true \
    "$BASEDIR/bin/rake.sh" teardown
}
# helpers end

# bamboo buiuld number helpers start
function build1_number
{
   if [[ ! -z $dry_run ]]; then
    echo "1"
  else
    echo "${bamboo_buildNumber}1"
  fi
}

function build2_number
{
  if [[ ! -z $dry_run ]]; then
    echo "2"
  else
    echo "${bamboo_buildNumber}2"
  fi
}
# bamboo buiuld number helpers end

# bamboo CD builds
function bamboo_deploy1
{
  build1=$(build1_number)
  build2=$(build2_number)

  # deploy build #1
  deploy_build $build1

  # on failure, do nothing - pipeline cleans it up
  action_exit=$?
  [ $action_exit -eq 0 ] && echo "Exit code is 0, continue..."
  [ $action_exit -ne 0 ] && echo "Exiting with non-zero code [$action_exit]" \
    exit $action_exit
}

function bamboo_deploy2
{
  build1=$(build1_number)
  build2=$(build2_number)

  # deploy build #2
  deploy_build $build2
  action_exit=$?

  [ $action_exit -eq 0 ] && echo "Exit code is 0, continue..."
  
  # on failure, clean up build #1 with force flag
  if [ $action_exit -ne 0 ]; then
    echo "Failed to deploy, performing clean up. Exit code was: $action_exit" 

    teardown_build_force $build1
    teardown1_exit=$?
    echo "Run teardown1 with exit code [$teardown1_exit]" 
    
    exit $action_exit
  fi
}

function bamboo_release1
{
  build1=$(build1_number)
  build2=$(build2_number)

  # release build #1
  release_build $build1
  action_exit=$?

  [ $action_exit -eq 0 ] && echo "Exit code is 0, continue..."
  
  # on failure, clean up build #1 with force flag
  if [ $action_exit -ne 0 ]; then
    echo "Failed to release, performing clean up. Exit code was: $action_exit" 

    teardown_build_force $build1
    teardown1_exit=$?
    echo "Run teardown1 with exit code [$teardown1_exit]" 
    
    exit $action_exit
  fi
}

function bamboo_release2
{
  build1=$(build1_number)
  build2=$(build2_number)

  # release build #2
  release_build $build2
  action_exit=$?

  [ $action_exit -eq 0 ] && echo "Exit code is 0, continue..."
  
  # on failure, clean up build #2 AND build #2
  if [ $action_exit -ne 0 ]; then
    echo "Failed to release, performing clean up. Exit code was: $action_exit" 

    teardown_build_force $build2
    teardown2_exit=$?
    echo "Run teardown2 with exit code [$teardown2_exit]" 

    teardown_build_force $build1
    teardown1_exit=$?
    echo "Run teardown1 with exit code [$teardown1_exit]" 
    
    exit $action_exit
  fi
}

function bamboo_teardown1
{
  build1=$(build1_number)
  build2=$(build2_number)

  # teardown build #1
  teardown_build $build1
  action_exit=$?

  [ $action_exit -eq 0 ] && echo "Exit code is 0, continue..."

  # on failure, clean up build #2
  if [ $action_exit -ne 0 ]; then
    echo "Failed to teardown, performing clean up. Exit code was: $action_exit" 
   
    teardown_build_force $build2
    teardown2_exit=$?
    echo "Run teardown2 with exit code [$teardown2_exit]" 

    exit $action_exit
  fi
}

function bamboo_teardown2
{
  build1=$(build1_number)
  build2=$(build2_number)

  # teardown build #2
  teardown_build_force $build2
  action_exit=$?
  
  # on failure, do nothing, build #1 teardown should have been already passed
  [ $action_exit -eq 0 ] && echo "Exit code is 0, continue..."
  [ $action_exit -ne 0 ] && echo "Exiting with non-zero code [$action_exit]" \
    exit $action_exit
}

$action

# always exit 0
# previous tasks would clean up and exit 1 if any issue occured
echo "Exiting pipeline_bamboo with code 0"
exit 0