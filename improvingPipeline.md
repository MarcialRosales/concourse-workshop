Concourse workshop
----

There are a number of things we can do to improve our pipeline. It won't be in a format of a lab because otherwise the workshop would last for days. However, if time permits, the attendees can choose which of the following topics is of most interests and we can implement them.

- [Use internal repo to resolve dependencies rather than Maven central repo](#topic-1)
- [Create scripts to facilitate setting pipelines](#topic-2)
- [Artifacts version and releases](#topic-3)
- [Publish Unit Test Report](#topic-4)
- [Shared pipelines rather One pipeline per application](#topic-5)
- [Credentials files more structured, flexible, cleaner and with less duplication](#topic-6)
- [Less cluttered pipelines](#topic-7)
- [Customizable Pipelines depending on the type of application](#topic-8)
- [Use dedicated pipelines to build custom images](#topic-9)
- [Automatically tracking Feature-branches](#topic-10)
- [Provision services](#topic-11)

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


## <a name="topic-5"></a> Shared pipelines rather One pipeline per application

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



## <a name="topic-8"></a> Customizable Pipelines depending on the type of application

The idea is to build pipelines like a lego. Rather than having one big pipeline we want to build it from smaller pipeline files. It has 2 advantages:
- Pipelines are easier to read because each pipeline file focuses on one simple functionality
- We can easily customize pipelines by selecting the pieces we want to use

Say we have 3 type of applications:
- Java executable applications, i.e. those we deploy to PCF
  We need to build, test, publish to central repo, deploy and verify that deployed app works.

- Java libraries, i.e pure jar of common infrastructure stuff like caching, etc.
  We need to build and test and eventually publish it to central repo

- Static web site
  We need to package it up, publish to central repo, deploy it and verify that it is running.

First we need to create the various pipeline files for each type of functionality:
- build Java and/or library apps
- deploy to PCF
- build Static sites

Second we need scripts to build different type of applications. Each script calls Spruce to merge the corresponding pipeline file to produce a single pipeline file: e.g. set-java-app-pipeline.sh, set-java-lib-pipeline.sh, set-static-site-pipeline.sh. 


## <a name="topic-10"></a> Automatically tracking Feature-branches 


## <a name="topic-9"></a> Use dedicated pipelines to build custom images

Use custom build images as opposed to public one is considered a best practice. We are in full control of what's inside.

We should have one pipeline to build all the images required by the rest of the pipelines. We propose to place it under `ci/images` folder. 

And we should also have a `docker` folder where we place all the dockerfiles. The pipeline monitors these files.

Say we want to build a docker image to run Terraform. [Terraform](https://www.terraform.io/) is a tool that allows us to write, plan, and create Infrastructure as Code. It is going to be extremely useful to provision the PCF services, either managed or user-provided ones. 

1. Create dockerfile `docker/terraform/Dockerfile`. It downloads Terraform binary, it also downloads source code of `CloudFoundry Provider` and compiles it and registers it as a plugin with terraform.
2. Create pipeline that monitor the dockerfile
  ```YAML
  - name: terraform-dockerfile
    type: git
    source:
      uri: (( grab pipeline.source.uri ))
      branch: (( grab pipeline.source.branch ))
      private_key: (( grab pipeline.source.private_key ))
      paths: [ docker/terraform/*]

  ```
3. Add docker image resource we use to publish it
  ```YAML
  - name: terraform-image
    type: docker-image
    source:
      username: (( grab pipeline.registry.username ))
      password: (( grab pipeline.registry.password ))
      repository: (( concat pipeline.registry.root "/terraform"))

  ```
4. Add job that fetches the dockerfile when it changes, builds the docker image and pushes it.
  ```YAML
  - name: terraform
    public: true
    plan:
    - aggregate:
      - get: terraform-dockerfile
        trigger: true
      - get: pipeline
    - put: terraform-image
      params:
        build: terraform-dockerfile/docker/terraform
  ```
5. Declare credentials within the pipeline repository. We need the following structure:
  ```YAML
  pipeline:
    registry:
      root: marcialfrg
      username: dummy
      password: dummy
  ```
6. Add script `set-images-pipeline.sh` to set this pipeline. It is very similar to the `set-pipeline.sh` except that we use `ci/images/pipeline` rather than `ci/application/pipeline`. 
7. Set up pipeline:
  `scripts/set-images-pipeline.sh local images`
 

## <a name="topic-11"></a> Provision services

If our applications require a number of services in PCF, such as a managed service like a RabbitMQ vhost/user, or a mysql database, or a user-provided-service with the credentials to an external service, we need to automatically provision those before we deploy the application. We cannot expect to do it manually.

We will use Terraform to provision those services. We have built the [Terraform docker image](#topic-9) so we are ready to use it. 

We should have a job to provision services and the deploy job should only trigger when the provision job has successfully completed. 

### Brief introduction to Terraform 

In terraform we use a DSL to describe the final infrastructure we wish to have and Terraform builds that final infrastructure.

If we focus on Cloud Foundry, we want to declare a number of services. To talk to Cloud Foundry we need to configure a **Terraform Provider**. There is an open source (work in progress) provider for Cloud Foundry that allows us to create services, among many other things, in Cloud Foundry. 

In Terraform we declare the infrastructure in `.tf` files. The file below declares the *Cloud Foundry* provider. Terraform has the concept of variables. For instance, we want to externalize the api endpoint, user and password so that we can use this same file for any environment. 
```
provider "cf" {
    api_url = "${var.api_url}"
    user = "${var.user}"
    password = "${var.password}"
}
```

Along with the `provicer.tf` file we have `vars.tf` where we must declare the variables:
```
variable "api_url" {}
variable "user" {}
variable "password" {}

variable "org" { }
variable "space" { }

```

### Applying terraform to our application

Each application may have in their repo a folder (`terraform`) which hosts its infrastructure. 

Previously we said that the pipeline will have a `provision` job between `deploy` and `build-and-verify` jobs. The `provision` job needs terraform files in order to create the corresponding infrastructure. How do we make those terraform files available to the `provision` job is totally up to us. 2 ideas:

- include them in the application's artifact, e.g. within the jar. All we have to do is configure the pom.xml to add the `terraform` folder. 
  ```xml
	  <build>
      <resources>
          <resource>
          <targetPath>terraform</targetPath>
              <directory>terraform</directory>
          </resource>
        </resources>
        ...
    </build>
  ```
- `build-and-verify` job shall produce a release file (zip) which contains the jar and the terraform files.  

The `provision` job calls a task, `terraform`, which extracts the *terraform* folder from the zip file and invokes `terraform apply`. 

### Remote backing state

Terraform produces a local file which contains the state of the infrastructure after we run `terraform apply`. We need to save this file in a central location called [remote state](https://www.terraform.io/docs/state/remote.html). There are a few stores supportes: S3, swift, Artifactory, Consul, and a few others.

If we want to use Terraform we have to configure with a remote store otherwise it will always try to recreate all the infrastructure.


1. Add `terraform` task 
  ```YAML
  platform: linux
  image_resource:
    type: docker-image
    source:
      repository: marcialfrg/terraform
      # TODO PUT A TAG
  inputs:
    - name: pipeline
    - name: artifact
  params:
    TERRAFORM_PATH: "BOOT-INF/classes/terraform"
  run:
    path: pipeline/tasks/terraform.sh

  ```
2. Add script 
  ```sh
  #!/bin/bash

  env | grep TF_VAR 

  cd artifact
  ARTIFACT=`ls *`

  unzip $ARTIFACT $TERRAFORM_PATH/*

  cd $TERRAFORM_PATH 
  terraform plan

  ```
3. Add `provision` job to the pipeline.
  - We want it to trigger when we have a new artifact built by `build-and-verify`
  - We pass the artifact and a number of environment variables to the terraform task
  - The environment variables are [Terraform variables](https://www.terraform.io/docs/configuration/variables.html). We need to define as many variables as defined in `terraform/vars.tf` file. 
  - The actual values for those variables come from the applications's credentials file. This is ok for now, but in the long term we don't want to make our pipeline aware of deployment credentials. Mainly because environments come and go and it is a big hassle to update the pipeline when that occurs.   

  ```YAML
  - name: provision
    plan:
    - get: artifact-repo
      trigger: true
      passed: [build-and-verify]
    - get: pipeline
    - task: apply
      file: pipeline/tasks/terraform.yml
      input_mapping: {artifact: artifact-repo}
      params:
        TF_VAR_api_url: (( grab deployment.dev.pcf.api ))
        TF_VAR_user: (( grab deployment.dev.pcf.username ))
        TF_VAR_password: (( grab deployment.dev.pcf.password ))
        TF_VAR_org: (( grab deployment.dev.pcf.organization ))
        TF_VAR_space: (( grab deployment.dev.pcf.space ))

  ```


