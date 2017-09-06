#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if ! [ -d state/ ]; then
  exit "No State, exiting"
  exit 1
fi

source state/env.sh
: ${AWS_ACCESS_KEY_ID:?"!"}
: ${AWS_SECRET_ACCESS_KEY:?"!"}
: ${AWS_DEFAULT_REGION:?"!"}
: ${CONCOURSE_DOMAIN:?"!"}
: ${CONCOURSE_USERNAME:?"!"}
: ${CONCOURSE_PASSWORD:?"!"}
: ${CONCOURSE_BOSH_ENV:?"!"}
: ${DOMAIN:?"!"}
: ${CONCOURSE_TARGET:?"!"}
: ${CONCOURSE_PIPELINE:?"!"}
: ${BBL_LB_CERT:?"!"}
: ${BBL_LB_KEY:?"!"}
: ${STATE_REPO_URL:?"!"}
: ${STATE_REPO_PRIVATE_KEY:?"!"}
: ${UAA_ADMIN_SECRET:?"!"}
: ${APPUSER_USERNAME:?"!"}
: ${APPUSER_PASSWORD:?"!"}
: ${APPUSER_ORG:?"!"}
: ${APPUSER_SPACE:?"!"}
: ${PIPELINE_REPO_URL:?"!"}
set -x

mkdir -p bin
PATH=$(pwd)/bin:$PATH

if ! [ -f bin/bbl ]; then
  curl -L "https://github.com/cloudfoundry/bosh-bootloader/releases/download/v3.0.4/bbl-v3.0.4_osx" > bin/bbl
  chmod +x bin/bbl
fi

if ! [ -f bin/bosh ]; then
  curl -L "https://s3.amazonaws.com/bosh-cli-artifacts/bosh-cli-2.0.1-darwin-amd64" > bin/bosh
  chmod +x bin/bosh
fi

if ! [ -f bin/fly ]; then
  curl -L "http://$CONCOURSE_DOMAIN/api/v1/cli?arch=amd64&platform=darwin" > bin/fly
  chmod +x bin/fly
fi

if ! [ -f bin/cf ]; then
  curl -L "https://cli.run.pivotal.io/stable?release=macosx64-binary&version=6.26.0&source=github-rel" | tar xzO cf > bin/cf
  chmod +x bin/cf
fi

if ! uaac --version; then
  gem install uaac
fi

fly login \
  --target $CONCOURSE_TARGET \
  --concourse-url "http://$CONCOURSE_DOMAIN" \
  --username $CONCOURSE_USERNAME \
  --password $CONCOURSE_PASSWORD \
;

fly set-pipeline \
  --target $CONCOURSE_TARGET \
  --pipeline $CONCOURSE_PIPELINE \
  --config pipelines/bosh-create-env/pipeline.yml \
  -v bbl_env_name=$CONCOURSE_BOSH_ENV \
  -v bbl_aws_region=$AWS_DEFAULT_REGION \
  -v bbl_aws_access_key_id=$AWS_ACCESS_KEY_ID \
  -v bbl_aws_secret_access_key=$AWS_SECRET_ACCESS_KEY \
  -v bbl_lbs_ssl_cert="$BBL_LB_CERT" \
  -v bbl_lbs_ssl_signing_key="$BBL_LB_KEY" \
  -v pipeline_repo_url=$PIPELINE_REPO_URL \
  -v state_repo_url=$STATE_REPO_URL \
  -v state_repo_private_key="$STATE_REPO_PRIVATE_KEY" \
  -v system_domain=$DOMAIN \
  --non-interactive \
;
exit

if ! fly builds -t $CONCOURSE_TARGET -j $CONCOURSE_PIPELINE/create-infrastructure | grep "succeeded" >/dev/null; then
  echo "Exiting... create-infrastructure hasn't succeeded yet. Manually trigger and wait for it to succeed before re-running this"
  exit 1
fi

if ! [ -f state/director/bosh-env.sh ]; then
  echo "Exiting... use bbl print-env to create state/director/bosh-env.sh"
  exit 1
fi

if ! [ -f state/director/cloud-config.yml ]; then
  echo "Exiting... use bbl cloud-config to create state/director/cloud-config.yml"
  exit 1
fi

if ! [ -f state/director/state.json ]; then
  echo "Exiting... use jq '.bosh.state' to create state/director/state.json"
  exit 1
fi


if ! fly builds -t $CONCOURSE_TARGET -j $CONCOURSE_PIPELINE/deploy-director | grep "succeeded" >/dev/null; then
  echo "Exiting... deploy-director hasn't succeeded yet. Manually trigger and wait for it to succeed before re-running this"
  exit 1
fi

if ! fly builds -t $CONCOURSE_TARGET -j $CONCOURSE_PIPELINE/deploy-cf | grep "succeeded" >/dev/null; then
  echo "Exiting... deploy-cf hasn't succeeded yet. Manually trigger and wait for it to succeed before re-running this"
  exit 1
fi

if ! uaac target | grep uaa.$DOMAIN; then
  uaac target uaa.$DOMAIN --skip-ssl-validation
fi

if ! uaac contexts | grep access_token; then
  uaac token client get admin -s $UAA_ADMIN_SECRET
fi

if ! uaac me | grep invalid_token; then
  uaac token client get admin -s $UAA_ADMIN_SECRET
fi

if ! uaac users | grep $APPUSER_USERNAME; then
  uaac user add $APPUSER_USERNAME -p $APPUSER_PASSWORD --emails user@example.com
  uaac member add cloud_controller.admin $APPUSER_USERNAME
  uaac member add uaa.admin $APPUSER_USERNAME
  uaac member add scim.read $APPUSER_USERNAME
  uaac member add scim.write $APPUSER_USERNAME
fi

if ! cf target | grep "https://api.$DOMAIN"; then
  cf login \
    -a https://api.$DOMAIN \
    -u $APPUSER_USERNAME \
    -p $APPUSER_PASSWORD \
    -o system \
    --skip-ssl-validation \
  ;
fi

if ! cf orgs | grep $APPUSER_ORG; then
  cf create-org $APPUSER_ORG
fi

if ! cf target | grep -e "Org: *$APPUSER_ORG"; then
  cf target -o $APPUSER_ORG
fi

if ! cf spaces | grep $APPUSER_SPACE; then
  cf create-space $APPUSER_SPACE
fi

if ! cf target | grep -e "Space: *$APPUSER_SPACE"; then
  cf target -o $APPUSER_ORG -s $APPUSER_SPACE
fi
