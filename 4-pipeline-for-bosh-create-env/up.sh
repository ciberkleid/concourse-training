#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if ! [ -d state/ ]; then
  exit "No State, exiting"
  exit 1
fi

source state/env.sh
true ${AWS_ACCESS_KEY_ID:?"!"}
true ${AWS_SECRET_ACCESS_KEY:?"!"}
true ${AWS_DEFAULT_REGION:?"!"}
true ${CONCOURSE_DOMAIN:?"!"}
true ${CONCOURSE_USERNAME:?"!"}
true ${CONCOURSE_PASSWORD:?"!"}
true ${CONCOURSE_BOSH_ENV:?"!"}
true ${DOMAIN:?"!"}
true ${CONCOURSE_TARGET:?"!"}
true ${CONCOURSE_PIPELINE:?"!"}
true ${BBL_LB_CERT:?"!"}
true ${BBL_LB_KEY:?"!"}
true ${STATE_REPO_URL:?"!"}
true ${STATE_REPO_PRIVATE_KEY:?"!"}
true ${UAA_ADMIN_SECRET:?"!"}
true ${APPUSER_USERNAME:?"!"}
true ${APPUSER_PASSWORD:?"!"}
true ${APPUSER_ORG:?"!"}
true ${APPUSER_SPACE:?"!"}
true ${PIPELINE_REPO_URL:?"!"}

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

if ! fly targets | grep $CONCOURSE_TARGET; then
  fly login \
    --target $CONCOURSE_TARGET \
    --concourse-url "http://$CONCOURSE_DOMAIN" \
    --username $CONCOURSE_USERNAME \
    --password $CONCOURSE_PASSWORD \
  ;
fi

#if ! [ -f state/pipelines/bosh-create-env/params.yml ]; then
  cat > state/pipelines/bosh-create-env/params.yml <<EOF
bbl_env_name: $CONCOURSE_BOSH_ENV
bbl_aws_region: $AWS_DEFAULT_REGION
bbl_aws_access_key_id: $AWS_ACCESS_KEY_ID
bbl_aws_secret_access_key: $AWS_SECRET_ACCESS_KEY
bbl_lbs_ssl_cert: !!binary $(echo "$BBL_LB_CERT" | base64)
bbl_lbs_ssl_signing_key: !!binary $(echo "$BBL_LB_KEY" | base64)
pipeline_repo_url: $PIPELINE_REPO_URL
state_repo_url: $STATE_REPO_URL
state_repo_private_key: !!binary $(echo "$STATE_REPO_PRIVATE_KEY" | base64)
system_domain: $DOMAIN
EOF
#fi

#if ! fly pipelines -t $CONCOURSE_TARGET | grep $CONCOURSE_PIPELINE; then
  fly set-pipeline \
    --target $CONCOURSE_TARGET \
    --pipeline $CONCOURSE_PIPELINE \
    --config pipelines/bosh-create-env/pipeline.yml \
    --load-vars-from state/pipelines/bosh-create-env/params.yml \
    --non-interactive \
  ;
#fi
exit 1

if ! fly builds -t $CONCOURSE_TARGET -j $CONCOURSE_PIPELINE/update-bosh | grep "succeeded" >/dev/null; then
  echo "Exiting... update-bosh hasn't succeeded yet. Manually trigger and wait for it to succeed before re-running this"
  exit 1
fi

if ! fly builds -t $CONCOURSE_TARGET -j $CONCOURSE_PIPELINE/update-stemcells | grep "succeeded" >/dev/null; then
  echo "Exiting... update-stemcells hasn't succeeded yet. Manually trigger and wait for it to succeed before re-running this"
  exit 1
fi

if ! fly builds -t $CONCOURSE_TARGET -j $CONCOURSE_PIPELINE/update-cf | grep "succeeded" >/dev/null; then
  echo "Exiting... update-cf hasn't succeeded yet. Manually trigger and wait for it to succeed before re-running this"
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
