#!/bin/bash
# Long running instance Puppet Bootstrap script
# This script is used to sanely bootstrap an instance against a LRI Puppetmaster.
# 
# For more information please see the documentation in confluence at:
# https://confluence.qantas.com.au/display/QCP/Long+Running+Instances
#
#

. /etc/profile.d/context.sh

unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
MTOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export PUPPET_DEVELOPMENT=false
export QCPHOSTNAME="q`curl -s -H "X-aws-ec2-metadata-token: $MTOKEN" http://169.254.169.254/latest/meta-data/instance-id | rev | cut -c 1-14 | rev`"
export PUPPETRUNS=3
export PUPPETNUM=1

while getopts ":s:e:c:d:" opt; do
  case ${opt} in
    s ) # process option s
        export PUPPET_SERVER=$OPTARG
      ;;
    e ) # process option e
        export PUPPET_ENVIRONMENT=$OPTARG
      ;;
    c )
        # Process option c
        export PUPPET_CERTNAME=$OPTARG
        if [ -z $PUPPET_CERTNAME ] ; then
          export PUPPET_CERTNAME="${pipeline_Ams}-${pipeline_Qda}-${pipeline_As}-${pipeline_Ase}-${QCPHOSTNAME}"
        fi
      ;;

   d ) # Process option d
       export PUPPET_DEVELOPMENT=$OPTARG
      ;;

    \? ) echo "Usage: $0 [-s] [-e] [-c]  "
      ;;
  esac
done

# Catch for the certname being null.
if [ -z $PUPPET_CERTNAME ] ; then
  echo "No custom certificate provided - Setting to standard certname value"
  export PUPPET_CERTNAME="${pipeline_Ams}-${pipeline_Qda}-${pipeline_As}-${pipeline_Ase}-${QCPHOSTNAME}"
fi

echo "LRI Instance Puppet Bootstrap script"
echo "  Using the Puppet Server: ${PUPPET_SERVER}"
echo "  Using the Puppet Environment: ${PUPPET_ENVIRONMENT}"
echo "  Using the Puppet Certificate Name: ${PUPPET_CERTNAME}"
echo "  Using the Puppet Development Value: ${PUPPET_DEVELOPMENT}"

# Still to be implemented - Stubbed out for now.
echo "- Checking for /etc/qcp_lri_state.yaml"
if [ ! -f /etc/qcp_lri_state.yaml ]; then
    echo "There is no qcp_lri_state file is present - Reserved for future functionality"
else
    echo "/etc/qcp_lri_state.yaml exists - This is indicates a recovery build"
fi

# If there is an existing Puppet agent found on the instance - Remove it
if  $(rpm -q --quiet puppet-agent); then
  echo "Puppet Agent is found"
  yum erase -q -y puppet-agent
  rm -rf /etc/puppetlabs/ /etc/puppet/ /opt/puppetlabs /var/log/puppet /var/log/puppetlabs /var/lib/puppet/
  crontab -r # Nuke prospero enforce if on the current SOE
else
  echo "Puppet agent is not found - No action to take"
fi

# Populate the CSR attributes for trusted fact values.
echo '- Populating /etc/puppetlabs/puppet/csr_attributes.yaml'

if [ ! -d /etc/puppetlabs/puppet/ ]; then
    mkdir -p /etc/puppetlabs/puppet
fi

if [ $PUPPET_DEVELOPMENT == "false" ]; then

cat > /etc/puppetlabs/puppet/csr_attributes.yaml << YAML
extension_requests:
    pp_environment: ${PUPPET_ENVIRONMENT}
YAML

else

cat > /etc/puppetlabs/puppet/csr_attributes.yaml << YAML
extension_requests:
    pp_environment: ${PUPPET_ENVIRONMENT}
    pp_apptier: development
YAML

fi

# Bootstrap the agent from the Puppet master.
echo '- Triggering installation registration of agent'
curl -s -k https://${PUPPET_SERVER}:8140/packages/current/install.bash | bash -s  agent:certname="${PUPPET_CERTNAME}" agent:environment=${PUPPET_ENVIRONMENT} --puppet-service-ensure stopped --puppet-service-enable true

# Running a set of Puppet runs during the bootstrap.

echo "Attempting ${PUPPETRUNS} Puppet runs"

echo '- Triggering inital run of Puppet agent and bootstrap'
/opt/puppetlabs/bin/puppet agent -tov --detailed-exitcodes
echo "Puppet return code was: $?"
sleep 30 # The new puppet-agent-6.x needs more time to run. MG
echo '- Triggering second run of Puppet agent and bootstrap'
/opt/puppetlabs/bin/puppet agent -tov --detailed-exitcodes
export PUPPETRETURN=$?
echo "Puppet return code was: $PUPPETRETURN"

echo '- Triggering thrid run of Puppet agent and bootstrap'
/opt/puppetlabs/bin/puppet agent -tov --detailed-exitcodes
export PUPPETRETURN=$?
echo "Puppet return code was: $PUPPETRETURN"

exit $PUPPETRETURN

