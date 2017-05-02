#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if ! [ -d state/ ]; then
  exit "No State, exiting"
  exit 1
fi

source state/env.sh
CONCOURSE_TARGET=${CONCOURSE_TARGET:?"env!"}
CONCOURSE_PASSWORD=${CONCOURSE_PASSWORD:?"env!"}
CONCOURSE_PIPELINE=${CONCOURSE_PIPELINE:?"env!"}
STATE_REPO_URL=${STATE_REPO_URL:?"env!"}
STATE_REPO_PRIVATE_KEY=${STATE_REPO_PRIVATE_KEY:?"env!"}

bbl_cmd="bbl --state-dir state/"
CONCOURSE_DOMAIN=$($bbl_cmd lbs | sed 's/.*\[\(.*\)\]/\1/')  # Format: Concourse LB: stack-bbl-Concours-1RABRZ7DBDC7F [stack-bbl-Concours-1RABRZ7DBDC7F-585187859.us-west-2.elb.amazonaws.com]

mkdir -p bin
PATH=$(pwd)/bin:$PATH

if ! [ -f bin/bbl ]; then
  curl -L "https://github.com/cloudfoundry/bosh-bootloader/releases/download/v3.0.4/bbl-v3.0.4_osx" > bin/bbl
  chmod +x bin/bbl
fi

if ! [ -f bin/fly ]; then
  curl -L "http://$CONCOURSE_DOMAIN/api/v1/cli?arch=amd64&platform=darwin" > bin/fly
  chmod +x bin/fly
fi

if fly login \
  --target $CONCOURSE_TARGET \
  --concourse-url "http://$CONCOURSE_DOMAIN" \
  --username admin \
  --password password; then
  fly set-team \
    --target $CONCOURSE_TARGET \
    --team-name main \
    --basic-auth-username=admin \
    --basic-auth-password=$CONCOURSE_PASSWORD \
    --non-interactive \
  ;
fi

if ! fly targets | grep $CONCOURSE_TARGET; then
  fly login \
    --target $CONCOURSE_TARGET \
    --concourse-url "http://$CONCOURSE_DOMAIN" \
    --username admin \
    --password $CONCOURSE_PASSWORD \
  ;
fi

if ! fly pipelines -t $CONCOURSE_TARGET | grep $CONCOURSE_PIPELINE; then
  fly set-pipeline \
    --target $CONCOURSE_TARGET \
    --pipeline $CONCOURSE_PIPELINE \
    --config cf-deployment-pipeline.yml \
    --var state_repo_url="$STATE_REPO_URL" \
    --var state_repo_private_key="$STATE_REPO_PRIVATE_KEY" \
    --var system_domain="cf.$DOMAIN" \
    --non-interactive \
  ;
fi
