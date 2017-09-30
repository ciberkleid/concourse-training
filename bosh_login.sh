bbl_cmd="bbl --state-dir ."
BOSH_ENV_ADDRESS=$($bbl_cmd director-address)
BOSH_ENV_ALIAS=cf-bosh-env
if ! bosh env --environment $BOSH_ENV_ADDRESS; then
  bosh alias-env $BOSH_ENV_ALIAS \
    --environment $BOSH_ENV_ADDRESS \
    --ca-cert <($bbl_cmd director-ca-cert) \
    --client $($bbl_cmd director-username) \
    --client-secret $($bbl_cmd director-password) \
  ;

  bosh log-in \
    --environment $BOSH_ENV_ALIAS \
    --ca-cert <($bbl_cmd director-ca-cert) \
    --client $($bbl_cmd director-username) \
    --client-secret $($bbl_cmd director-password) \
  ;
fi
