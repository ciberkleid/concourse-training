# BOSH deployment with concourse
## Usage
* Each directory is a step that should be completed to completion before moving on to the next step
* Each step contains an `up.sh` that should be executed
* Each step requires a `state/` sub-directory which should be clone of an external repository for private credentials and settings. This should be commited and pushed after each step is complete.
* Each `state` repo should contain an `env.sh` file containing KEY=VALUE mappings of required variables. Running `up.sh` will fails unless each value that is specified.

__NOTE__ This repo is only for orchestration and is not *and should not* be referenced by any pipeline

## `up.sh` scripts
The `up.sh` serves as executable documentation. You can either set all the variables and run it or you can view the contents and execute each step on by hand instead.  
