#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if ! [ -d state/ ]; then
  exit "No State, exiting"
  exit 1
fi

source ./state/env.sh
: ${AWS_ACCESS_KEY_ID:?!}
: ${AWS_SECRET_ACCESS_KEY:?"!"}
: ${AWS_DEFAULT_REGION:?"!"}
: ${CONCOURSE_USERNAME:?"!"}
: ${CONCOURSE_PASSWORD:?"!"}
: ${CONCOURSE_TARGET:?"!"}
: ${CONCOURSE_DB_NAME:?"!"}
: ${CONCOURSE_DB_ROLE:?"!"}
: ${CONCOURSE_DB_PASSWORD:?"!"}
: ${VM_KEYPAIR_NAME:?"!"}
: ${DOMAIN:?"!"}
: ${CONCOURSE_BOSH_ENV:?"!"}
: ${CONCOURSE_DEPLOYMENT_NAME:?"!"}
set -x


mkdir -p bin
PATH=$(pwd)/bin:$PATH

if ! [ -f bin/bosh ]; then
  curl -L "https://s3.amazonaws.com/bosh-cli-artifacts/bosh-cli-2.0.1-darwin-amd64" > bin/bosh
  chmod +x bin/bosh
fi

bbl_cmd="bbl --state-dir state/"
if ! [ -f bin/bbl ]; then
  curl -JLO "https://github.com/cloudfoundry/bosh-bootloader/releases/download/v3.0.4/bbl-v3.0.4_osx"
  mv bbl-v3.0.4_osx bin/bbl
  chmod +x bin/bbl
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION
if ! aws --version; then
  pip install --user awscli
fi

if ! aws ec2 describe-key-pairs | grep -q $VM_KEYPAIR_NAME; then
  aws ec2 create-key-pair --key-name $VM_KEYPAIR_NAME | jq -r '.KeyMaterial' > state/$VM_KEYPAIR_NAME.pem
  chmod 400 state/$VM_KEYPAIR_NAME.pem
fi

if ! [ -f state/bbl-state.json ]; then
  $bbl_cmd \
    up \
    --aws-access-key-id $AWS_ACCESS_KEY_ID \
    --aws-secret-access-key $AWS_SECRET_ACCESS_KEY \
    --aws-region $AWS_DEFAULT_REGION \
    --iaas aws \
  ;
fi

if ! [ -f state/rsakey.pem ]; then
  openssl req \
    -newkey rsa:2048 \
    -nodes \
    -keyout state/$DOMAIN.key \
    -x509 \
    -days 365 \
    -subj "/C=US/ST=NY/O=Pivotal/localityName=NYC/commonName=$DOMAIN/organizationalUnitName=Foo/emailAddress=bar" \
    -multivalue-rdn \
    -out state/$DOMAIN.crt \
  ;

  openssl rsa \
    -in state/$DOMAIN.key \
    -out state/rsakey.pem \
  ;
fi

if ! $bbl_cmd lbs; then
  $bbl_cmd \
    create-lbs \
    --type concourse \
    --cert state/$DOMAIN.crt \
    --key state/rsakey.pem
fi

DIRECTOR_ADDRESS=$($bbl_cmd director-address)
if ! bosh env --environment $DIRECTOR_ADDRESS; then
  bosh alias-env $CONCOURSE_BOSH_ENV \
    --environment $DIRECTOR_ADDRESS \
    --ca-cert <($bbl_cmd director-ca-cert) \
    --client $($bbl_cmd director-username) \
    --client-secret $($bbl_cmd director-password) \
  ;

  bosh log-in \
    --environment $CONCOURSE_BOSH_ENV \
    --ca-cert <($bbl_cmd director-ca-cert) \
    --client $($bbl_cmd director-username) \
    --client-secret $($bbl_cmd director-password) \
  ;
fi

if ! bosh stemcells -e $CONCOURSE_BOSH_ENV | grep bosh-aws-xen-hvm-ubuntu-trusty-go_agent; then
  bosh upload-stemcell -e $CONCOURSE_BOSH_ENV https://s3.amazonaws.com/bosh-core-stemcells/aws/bosh-stemcell-3363.9-aws-xen-hvm-ubuntu-trusty-go_agent.tgz
fi

CONCOURSE_LBS_DOMAIN=$($bbl_cmd lbs | sed 's/.*\[\(.*\)\]/\1/')  # Format: Concourse LB: stack-bbl-Concours-1RABRZ7DBDC7F [stack-bbl-Concours-1RABRZ7DBDC7F-585187859.us-west-2.elb.amazonaws.com]
bosh deploy \
  --non-interactive \
  --environment $CONCOURSE_BOSH_ENV \
  --deployment $CONCOURSE_DEPLOYMENT_NAME \
  --vars-store state/vars-store.yml \
  -v concourse_deployment_name=$CONCOURSE_DEPLOYMENT_NAME \
  -v concourse_external_url=http://$CONCOURSE_LBS_DOMAIN \
  -v concourse_basic_auth_username=$CONCOURSE_USERNAME \
  -v concourse_basic_auth_password=$CONCOURSE_PASSWORD \
  -v concourse_atc_db_name=$CONCOURSE_DB_NAME \
  -v concourse_atc_db_role=$CONCOURSE_DB_ROLE \
  -v concourse_atc_db_password=$CONCOURSE_DB_PASSWORD \
  -v concourse_vm_type=t2.small \
  -v concourse_worker_vm_extensions=50GB_ephemeral_disk \
  -v concourse_web_vm_extensions=lb \
  -v concourse_db_disk_type=5GB \
  concourse-deployment.yml \
;

if ! [ -f bin/fly ]; then
  curl -L "http://$CONCOURSE_LBS_DOMAIN/api/v1/cli?arch=amd64&platform=darwin" > bin/fly
  chmod +x bin/fly
fi

if fly login \
  --target $CONCOURSE_TARGET \
  --concourse-url "http://$CONCOURSE_LBS_DOMAIN" \
  --username admin \
  --password password; then
  fly set-team \
    --target $CONCOURSE_TARGET \
    --team-name main \
    --basic-auth-username=$CONCOURSE_USERNAME \
    --basic-auth-password=$CONCOURSE_PASSWORD \
    --non-interactive \
  ;
fi

