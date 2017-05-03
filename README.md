# BOSH deployment with concourse
## Usage
* Each directory is a step that should be completed to completion before moving on to the next step
* Each step contains and `up.sh` that should be executed
* Each step requires a `state/` sub-directory which should be clone of an external repository for private credentials and settings
* Each `state` repo should contain an `env.sh` file containing KEY=VALUE mappings of required variables. Running `up.sh` will fails unless each value that is specified.

## LICENSE
Copyright Pivotal. All rights reserved.
