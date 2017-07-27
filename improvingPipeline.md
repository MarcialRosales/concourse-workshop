Concourse workshop
----

There are a number of things we can do to improve our pipeline. It won't be in a format of a lab because otherwise the workshop would last for days. However, if time permits, the attendees can choose which of the following topics is of most interests and we can implement them.

- [Use internal repo to resolve dependencies rather than Maven central repo](#topic-1)
- [Create scripts to facilitate setting pipelines](#topic-2)
- [Artifacts version and releases](#topic-3)
- [Publish Unit Test Report](#topic-4)
- [Generic Pipelines rather One pipeline per application](#topic-5)
- [Credentials files more structured, flexible, cleaner and with less duplication](#topic-6)


## <a name="topic-1"></a> Use internal repo to resolve dependencies rather than Maven central repo

So far we managed to build our Java application and verify it but it was too slow because Maven had to download all the dependencies from central repo. We need to configure Maven with our internal repository.

Hints:
- We need a new script `tasks/generate-settings.sh`, that generates a standard Maven's `settings.xml` file with the location of our local Maven repository.
- It is fully explained [here](https://github.com/MarcialRosales/maven-concourse-pipeline/tree/02_use_corporate_maven_repo#pipeline-explained)

## <a name="topic-2"></a> Create scripts to facilitate setting pipelines

The idea is to call a script like `scripts/set-pipeline.sh local app1` and it automatically sets the pipeline with the name `app1` using the target `local`. The script assumes that we are current logged in. The script also assumes we have a local `secrets.yml` file. It is up to us how we generate it, e.g. using Lastpass or decrypting it from an encrypted version.

The implementation of that `scripts/set-pipeline.sh` is very trivial:

```sh
#!/bin/bash -e


syntax() {
  echo "Usage: set-pipeline.sh concourse-target pipelineName"
}

PIPELINE_DIR=$(dirname "$0")/..

if [ "$#" -ne 2 ]; then
  syntax
  exit 1
fi

FLY_TARGET=$1
PIPELINE=$2
CREDENTIALS=credentials.yml
SECRETS=secrets.yml

echo "Setting $PIPELINE pipeline in Concourse ..."
fly -t "$FLY_TARGET" set-pipeline -p "$PIPELINE" \
  -c "$PIPELINE_DIR"/ci/application/pipeline.yml -l "$PIPELINE_DIR"/credentials.yml -l "$PIPELINE_DIR"/secrets.yml \

```

## <a name="topic-3"></a> Artifacts version and releases

So far we have produced a snapshot version of our artifact. That snapshot version is fine for continuous integration where we don't really care the actual version number. However, once our product is ready to be released when we need to use release versions, not snapshots. We can use any versioning scheme we like. Semantic versioning is one of them: `major.minor.patch`.

Concourse has a resource, [semver](https://github.com/concourse/semver-resource) which helps with the task of tracking the last version and incrementing it.

Our application has hard-coded the current version in the `pom.xml`. It is `0.0.1-SNAPSHOT`. When we release that snapshot, we produce an artifact like `demo-0.0.1.jar` and we have to edit the pom.xml to bump the patch number to `0.0.2-SNAPSHOT`.

**Briefly about semver resource**: The idea is to have somewhere (git, s3, swift) a file which has a version number. If the file does not exit, we can configure the first version. The process of modifying the version number is very simple. We dont have to do it manually, semver resource does it for us.

Let's start configuring the version number of our application in an external file using semver resource. The initial version number is `0.0.1`. We assume that the `build` task always produces snapshots. Hence, it will append the tag `-SNAPSHOT` at the end of the current version.

1. Add semantic version resource.
  ```YAML
  - name: version
    type: semver
    source:
      driver: git
      initial_version: 0.0.1-SNAPSHOT
      uri: {{source-code-url}}
      private_key: {{source-code-private-key}}
      branch: {{source-code-branch}}
      file: version

  ```
2. Configure `source-code` resource to ignore the `version` file (i.e. it does not trigger when this file changes)

  ```YAML
  - name: source-code
    type: git
    source:
      uri: {{source-code-url}}
      branch: {{source-code-branch}}
      ignore_paths:
        - version
  ```
3. Fetch the version and pass it onto the `build` task

  ```YAML
  - name: build-and-verify
    plan:
    - get: source-code
      trigger: true
    - get: version
    - task: build-and-verify
      file: source-code/tasks/build.yml
    - put: artifact-repo
      params:
        file: build-artifact/*.jar
        pom_file: source-code/pom.xml

  ```

4. Tell maven to use the semantic version

  ```

  VERSION=`cat version/number`-SNAPSHOT

  cd source-code

  echo "Setting maven with version ${VERSION}"
  mvn versions:set -DnewVersion=${VERSION}

  mvn package

  echo "Copying artifacts ..."
  cp -r target/*.jar ../build-artifact
  ```

5. Add private key variable to `secrets.yml`. This is necessary so that **semver** can commit changes to the `source-code` repo where we track the `version` file.

  ```YAML
  ...
  source-code-private-key: |
    -----BEGIN RSA PRIVATE KEY-----
    ....
    ...
    -----END RSA PRIVATE KEY-----

  ```

6. Commit the changes

  ```sh

  git add tasks/build.sh tasks/build.yml
  git add ci/application/pipeline.yml
  git commit -m "Use semver to set maven artifact versions"
  ```

7. Update pipeline

  `scripts/set-pipeline.sh local pipeline`


We should see the task `build` printing out the version found in the file and setting Maven to use that version.

Let's continue adding a few jobs that will assist us when we need to increment the minor or major parts.

1. Add 2 jobs to the pipeline
  ```YAML
  - name: increase-major
    serial: true
    plan:
    - put: version
      params: { bump: major }

  - name: increase-minor
    serial: true
    plan:
    - put: version
      params: { bump: minor }
  ```
2. Update the pipeline
  `scripts/set-pipeline.sh local pipeline`

3. Bump up the minor by triggering the job `increase-minor`. Check that there is a file called `version` with the bumped up version.


The next move is to think about the release process. After every release we are going to bump the path number. But the release process is far more complex to deal with it now and it varies depending who you talk to.


## <a name="topic-4"></a> Publish Unit Test Report

There are not nice dashboards with junit reports like in Bamboo or similar tools. If we don't want to check the build logs to find out which test cases failed, we can add a task that builds the maven site with just the junit reports and publish the site to PCF. But that site would only have the latest build, not a history.


## <a name="topic-5"></a> Generic Pipelines rather One pipeline per application

Let's recap a number of good practices we introduce [here](realPipeline.md#organizing-pipelines):
- [x] Pipeline and variable files (`--load-vars-from`) must be versioned controlled
- [x] Sensitive data (like passwords and private keys) stored in variable files should never be versioned controlled (or at least in clear)
- [x] Pipelines and variable files should be stored along with the application (or microservice) we are building
- [ ] We should not reinvent the wheel on each application. We should build pipelines in such a way that we can use them to build any application
- [x] We are aiming for consistent builds. Lock down pipeline and resource type's versions too
- [x] Tasks should be defined in "Task Definition" files rather than inline in the pipeline

### Move the pipeline infrastructure to a dedicated git repository

1. Create a new git repo for the pipelines, e.g. `concourse-workshop-ci`
2. Move the folders `ci`, `scripts`, and `tasks` to the pipelines repo
3. Pipeline repo becomes another resource
  ```YAML

  - name: pipeline
    type: git
    source:
      uri: {{pipeline-url}}
      branch: {{pipeline-branch}}
      private_key: {{pipeline-private-key}}

  ```
4. Fetch pipeline resource because tasks are no longer in `source-code` but in `pipeline`:
  ```YAML
  - name: build-and-verify
    plan:
    - get: source-code
      trigger: true
    - get: pipeline
    - get: version
    - task: build-and-verify
      file: pipeline/tasks/build.yml
    - put: artifact-repo
      params:
        file: build-artifact/*.jar
        pom_file: source-code/pom.xml

  ```
  Did not include the deploy job for brevity sake.

5. Update tasks definition files because they should take `pipeline` input because scripts are now in that input folder.
  ```YAML
  platform: linux
  image_resource:
    type: docker-image
    source:
      repository: maven
      tag: 3.3.9-jdk-8
  inputs:
    - name: pipeline
    - name: source-code
    - name: version
  outputs:
    - name: build-artifact
  run:
    path: pipeline/tasks/build.sh

  ```
  We need to make this change to the other task definition files.

6. Add new credentials to the application's credentials file. Ideally, we want to lock down the version of the pipeline rather using the latest.
  ```YAML
  pipeline-code-url: git@github.com:MarcialRosales/concourse-workshop-ci
  pipeline-code-branch: master
  ```

7. Change `set-pipeline.sh` script so that we can call it from the application's root folder
  ```sh
  #!/bin/bash -e


  syntax() {
    echo "Usage: set-pipeline.sh concourse-target pipelineName"
  }

  PIPELINE_DIR=$(dirname "$0")/..

  if [ "$#" -ne 2 ]; then
    syntax
    exit 1
  fi

  FLY_TARGET=$1
  PIPELINE=$2
  CREDENTIALS=credentials.yml
  SECRETS=secrets.yml

  echo "Setting $PIPELINE pipeline in Concourse ..."
  fly -t "$FLY_TARGET" set-pipeline -p "$PIPELINE" \
    -c "$PIPELINE_DIR"/ci/application/pipeline.yml -l $CREDENTIALS -l $SECRETS \

  ```
8. Update pipeline from the application's root folder where the credentials files are.
  `../concourse-workshop-ci/scripts/set-pipeline.sh local app1`


Adding a new Java application, we would only require to:
- Add `credentials.yml` which refers to the git URL of the java application
- Add `secrets.yml`
- Check out the pipeline repo so that we can call `set-pipeline.sh`
- Call `../concourse-workshop-ci/scripts/set-pipeline.sh local applicationName`


##  <a name="topic-6"></a> Credentials files more structured, flexible, cleaner and with less duplication

Variable interpolation is quite limited in Concourse:
- flat namespace
- string manipulation not possible like string concatenation
- lots of variable value duplication because we cannot use the value of one variable to define another

Wouldn't be better if `credentials.yml` would look like this:

```YAML
app:      
  name: demo
  initial_version: 0.0.1
  artifact: com.example:demo:jar
  source:
    uri: git@github.com:MarcialRosales/concourse-workshop-app1
    branch: master

pipeline:
  source:
    uri: http://192.168.1.36:8081/nexus/content/repositories/snapshots
    branch: master

  repository:
    uri: https://registry.npm.r3pi.net

deployment:
  pcf:
    api: https://api.system-dev.chdc20-cf.solera.com
    organization: marcial.rosales@r3pi.io
    space: sandbox
    skip_cert_check: false

    host: mr-demo
    domain: apps-dev.chdc20-cf.solera.com

```

1. Use hierarchical YAML in credentials and secrets
2. Use Spruce to resolve credential in the pipeline
  ```YAML
  resources:

  - name: pipeline
    type: git
    source:
      uri: (( grab pipeline.source.uri ))
      branch: (( grab pipeline.source.branch ))
      private_key: (( grab pipeline.source.private_key ))

  ```
  Replace every {{var}} with the corresponding (( grab equivalent.var ))
3. Use Spruce to render pipeline in `set-pipeline.sh`
```sh
....

tmp=$(mktemp $TMPDIR/pipeline.XXXXXX.yml)
trap 'rm $tmp' EXIT

PIPELINE_FILES="$PIPELINE_DIR/ci/application/pipeline.yml"

echo "Generating $PIPELINE pipeline ..."
spruce merge --prune meta --prune pipeline --prune app --prune deployment $PIPELINE_FILES $CREDENTIALS $SECRETS > $tmp

echo "Setting $PIPELINE pipeline in Concourse ..."
fly -t "$FLY_TARGET" set-pipeline -p "$PIPELINE" -c $tmp

```

## <a name="topic-7"></a> Less cluttered pipelines

As the number of jobs increases it is better to split them into several views where each view groups jobs related to certain aspect of the pipeline.
We are going to create 2 groups: main and versioning. In the versioning we move all the jobs related to version handling.

1. Add the following to the pipeline:
  ```YAML
  groups:
  - name: main
    jobs:
    - build-and-verify
    - deploy
  - name: versioning
    jobs:
    - increase-minor
    - increase-major

  resource-types:
    ....
  ```
