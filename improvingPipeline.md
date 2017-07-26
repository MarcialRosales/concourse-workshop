Concourse workshop
----

There are a number of things we can do to improve our pipeline. It won't be in a format of a lab because otherwise the workshop would last for days. However, if time permits, the attendees can choose which of the following topics is of most interests and we can implement them.

- [Use internal central repo to resolve dependencies (MUST)](#topic-1)
- [Create scripts to facilitate setting pipelines](#topic-2)
- [Artifacts version and releases](#topic-3)
- [Publish Unit Test Report](#topic-4)

## <a name="topic-1"></a> Use internal central repo to resolve dependencies (MUST)

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


## Build Pipelines so that they can be used to build any application

Let's recap a number of good practices we introduce [here](realPipeline.md#organizing-pipelines):
- [x] Pipeline and variable files (`--load-vars-from`) must be versioned controlled.  **Done**
- [x] Sensitive data (like passwords and private keys) stored in variable files should never be versioned controlled (or at least in clear) **Done**
- [x] Pipelines and variable files should be stored along with the application (or microservice) we are building **Done**
- [ ] We should not reinvent the wheel on each application. Instead keep pipelines artifacts on a separate git repo. **Not done yet**
- [x] We are aiming for consistent builds. Lock down pipeline and resource type's versions too. **Done**
- [x] Tasks should be defined in "Task Definition" files rather than inline in the pipeline **Done**
