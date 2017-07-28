Concourse workshop
----


# Building basic pipeline to familiarize with pipeline concepts and Concourse itself (**fly** and Web UI)

We are going to build a pipeline step by step and on each step we introduce new concepts into the pipeline.

## But what is a pipeline then?
  - A chain of actions or tasks where each task takes some input and produces an output. For instance in the diagram below, `Build` takes a `source` as input and produces a `jar` as output. That same `jar` becomes the input for `Deploy`.
    ```
        {source}----[ Build ]---{jar}---[ Deploy ]----
    ```
  - In Concourse, we define a pipeline in a plain YML file. No UI, no external configuration required in concourse. This is called **pipeline as code**.
  - We deploy the pipeline in Concourse by calling the appropriate commands in **fly**

## Benefit of this approach:
  - Reproducible builds because configuration is on a file which should be versioned controlled (e.g. git) and Concourse has no state, workers are stateless.
  - Because there is no state in Concourse, no big deal if we loose Concourse. With Bosh we can have Concourse deployed in minutes. We only need to redeploy our pipelines.


Concourse is more than a CI tool. It is an automation tool that allows us to take any input (**resource**) and orchestrate the execution of scripts (**tasks**) which take input(s) and produce output(s) (another **resource**).

In order to understand the concepts and mechanincs of Concourse, we are going to build a *Hello world* pipeline. We will do it incrementally, one lab at a time:
- [Lab 1 - Print the hello world](#lab1)
- [Lab 2 - Produce a file with a greeting message](#lab2)
- [Lab 3 - Produce a file with a greeting message which must be configured thru a variable](#lab3)
- [Lab 4 - Refactor print-hello-world into produce-greeting and print-greeting](#lab4)
- [Lab 5 - Read part of the greeting message from a git repository](#lab5)
- [Lab 6 - Send greeting message to a slack channel and remove the `print-greeting` task](#lab6)
- [Lab 7 - Send a different greeting message to slack channel if the task `produce-greeting` failed](#lab7)
- [Lab 8 - Send greeting message every few minutes](#lab8)
- [Bonus lab - Execute tasks in parallel](#bonus)

## <a name="lab1"></a> Lab 1 - Print the hello world

Lets start building a "hello world" pipeline to learn the pipeline mechanics and get familiar with Concourse UI too.

1. Create a folder. e.g. `mkdir hello-world-ci`
2. We create the following file `pipeline.yml` within the folder we just created:  
  Don't worry if you don't understand this file. Before we complete this lab we will introduce a few concepts that will make it easier to understand it.

  ```YAML
  jobs:
  - name: job-hello-world
    plan:
    - task: print-hello-world
      config:
        platform: linux
        image_resource:
          type: docker-image
          source: {repository: busybox}
        run:
          path: echo
          args:
          - "hello world"
  ```
3. Let's deploy the pipeline first.  
  `fly -t main sp -p hello-world -c pipeline.yml`

  `sp` is the alias of `set-pipeline`  
  `c` is the name of the pipeline file  
  `p` is the name we want to give to our pipeline  

4. Concourse will always print out the difference between what it exists in concourse and what we are deploying. Because this is a brand new pipeline all lines are in green color.

  ```YAML
  jobs:
    job job-hello-world has been added:
      name: job-hello-world
      plan:
      - task: print-hello-world
        config:
          platform: linux
          image_resource:
            type: docker-image
            source:
              repository: busybox
          run:
            path: echo
            args:
            - hello world
            dir: ""

  apply configuration? [yN]:
  ```
5. Lets visit Concourse UI.

  ![Concourse first pipeline](assets/concourse-2.png)

  - Available pipelines
  - Pipeline's states: paused, running. We are in full control.
  - We can unpause it from the UI or from **fly**:  
    `fly -t main up -p hello-world`
  - Job's states

  > Why is it useful to pause a pipeline or a job or even a resource? One good reason is when we are pushing changes to our application's report but we dont want to trigger the pipeline until we are done with all the changes. Or when the pipeline has some issues (e.g. wrong credentials, bug in some script) that we need to fix and the meanwhile we don't wnat an application's commit to trigger it. 

6. Triggering jobs
  - manually (via **fly** or thru UI) or automatic (via a resource)  
    `fly -t local tj hello-world/job-hello-world` to trigger a job
  - conditions that must be met before running a job:
    - it cannot be paused neither the pipeline
    - it has not exceeded the maximum concurrent jobs (http://concourse.ci/configuring-jobs.html#max_in_flight, http://concourse.ci/configuring-jobs.html#serial or http://concourse.ci/configuring-jobs.html#serial_groups)
  - Concourse runs each task in a separate container (in the docker image we specified in the task)
  - Monitor job execution thru UI or thru **fly**  
    `fly -t local builds` list all the jobs executed and being executed  
    `fly -t local watch -j hello-world/job-hello-world` tail the logs from the jobId. We obtain the jobId from the previous command.  


### Pipeline concepts

- A **pipeline** is a chain of jobs. Soon we will see what chains the jobs together. (See `jobs` in pipeline yml)
- **Jobs** describe the actual work a pipeline does. A Job consists of a build plan. (See `plan` )
- A **build plan** consists of multiple steps. For now, each step is a task. But we will see later that there are 2 more steps: *fetch* and *update resource steps*. These steps can be arranged to run in parallel or in sequence. (See array with just one element `task`)
- A **task** is a script executed within a container using a docker image that we specify in the pipeline. We can use any scripting language available in the docker's image, e.g. python, perl, bash, ruby. (see  `platform`, `image_resource`, and `run` attributes of a task)

### A bit about Concourse Architecture

We already know that Concourse is made up of a UI+RestAPI and a number of worker machines. The UI+RestAPI is called **ATC**. In addition to ATC, Concourse also has:

- **Workers** are machines running Garden, a container technology developed by Pivotal. There can be many and we scale Concourse by adding more of these.
- Tasks have an attribute called `platform`. And worker machines register with a platform's name, e.g. linux, windows, darwin, iphone, etc. 
- There is another component called **TSA**. Each worker registers itself with the Concourse cluster via the TSA.


## <a name="lab2"></a> Lab 2 - Produce a file with a greeting message

We continue with the previous pipeline but this time we are going to put more logic into the task. We can make it as complicated as it needs to be. We are going to produce a file with a greeting and print out that file. 

1. Produce a new pipeline file.  
  
  ```YAML
  ---
  jobs:
  - name: job-hello-world
    plan:
    - task: print-hello-world
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        run:
          path: sh
          args:
            - -c
            - |
              echo "hello world" > greeting
              cat greeting

  ```
  > If we need to execute several shell commands  we need to pipe them as illustrated in the pipeline.

2. Deploy the new pipeline with a different name:  
  `fly -t local sp -p greeting -c pipeline.yml`

## <a name="lab3"></a> Lab 3 - Produce a file with a greeting message which must be configured thru a variable

We want to configure the greeting message without having to change the pipeline. Concourse supports the concept of *variables*. In the pipeline we use a variable like `{{var-name}}` and when we set the pipeline thru **fly** we specify the value for that variable. Very simple. **fly** does variable interpolation right before we set the pipeline. For more information, check out http://concourse.ci/fly-set-pipeline.html.

Variables allows us to customize a pipeline but what about if we need to customize a task?  Tasks accept parameters and Concourse pass those parameters to the container as environment variables. For example, if we define our task with the parameter `MSG: {{var-name}}`, the container will have an environment variable called `MSG` and we can use it, e.g. `echo $MSG`. Obviously, we need to pass the value of `MSG` to **fly** when we set the pipeline.

Let's put it in practice. 

1. We are replacing the message "hello world" with a variable called `GRETTING_MSG`. To reference this variable from the pipeline we use this syntax  `{{GRETTING_MSG}}`. However, we need to pass this variable as a [parameters](http://concourse.ci/running-tasks.html#params) to the task.

  ```YAML
  ---
  jobs:
  - name: job-hello-world
    plan:
    - task: print-hello-world
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        params:
          MSG: {{GREETING_MSG}}
        run:
          path: sh
          args:
            - -c
            - |
              echo "$MSG" > greeting
              cat greeting

  ```
2. We need to create a new file called `credentials.yml` where we define the values for the variables we use in the pipeline:
  ```YAML
  GREETING_MSG: hello world
  ```

3. We deploy our new pipeline. 
  - We need to specify the new `credentials.yml` file.
    `fly -t local sp -p greeting -c pipeline.yml -l credentials.yml`
  - It is possible to pass variables directly from the command line but that is cumbersome. 
  - See how Concourse displays the final pipeline with all the variables resolved.
  - variable interpolation is quite simple, we cannot do string concatenation like this `{{var1}}-{{var2}}`. If we need that same value we need to create a new variable.
  - there is another way of doing variable interpolation that we will explorer in another lab.


## <a name="lab4"></a> Lab 4 - Refactor print-hello-world into produce-greeting and print-greeting

We learnt earlier that a job has a build plan which consists of multiple steps. We are going to introduce a second step/task to our job. Additionally, we are going to introduce the concept of artifacts. The first task will produce an output artifact and the second task will consume that output as an input artifact.

> For the advanced user: Artifacts most commonly come from Resources, e.g. a git resource. When Concourse clones the git repository, it produces an artifact which is then passed as input into a task.


1. Produce a new pipeline file. This time we have 2 tasks: `produce-greeting` and `print-greeting`. The first task produces an output artifact. An artifact maps to a folder or volume in container terms. The task `produce-greeting` has an output artifact called `greeting`. And that same artifact is passed as an input artifact to the next task `print-greeting`.
  ```YAML
  ---
  jobs:
  - name: job-hello-world
    plan:
    - task: produce-greeting
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        outputs:
          - name: greetings
        run:
          path: sh
          args:
            - -c
            - |
              echo "hello world" > greeting
              cp greeting greetings

    - task: print-greeting
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        inputs:
          - name: greetings
        run:
          path: sh
          args:
            - -c
            - |
              cat greetings/greeting

  ```

2. Tasks within a plan are executed sequentially and conditionally. If the first task fails, the job fails. Try to add the command `exit 2` at the end of the first task:
```YAML

        run:
          path: sh
          args:
            - -c
            - |
              echo "hello world" > greeting
              cp greeting greetings
              exit 2
```
3. If you deploy it and run it, it terminates on the first task. We will see later on how we can tell Concourse to run a bunch of tasks in parallel.

Note: When the job terminates, the artifacts we have generated within the job like the `greetings` one, are destroyed. They are simply volumes that Concourse mounts onto the containers but once the job terminates those volumes are destroyed. If we don't want to loose that data we need to put it somewhere, i.e. onto an output **resource**, e.g. to Nexus or Artifactory.  

## <a name="lab5"></a> Lab 5 - Read part of the greeting message from a git repository

The greeting message should consist of the `GREETING_MSG` variable followed by the first line of the README.md file from a github repo.

It is time to introduce **resources**, the other key element of a pipeline. Let's recap the pipeline concepts before we work on our next pipeline:

- **Resources** are inputs to a job (and ultimately tasks), and outputs from a job (and ultimately from a task) which are versioned (most of the time), specially if they are inputs.
- **Artifact** are input/output volumes. An input **resource** like a Git repo will have its own artifact where Concourse clones the repo.
- A **pipeline** is a chain of jobs which are linked each other via **resources**
- **Jobs** are a group of tasks that will automatically trigger when there is a new version of an input **resource**. If there is nothing new, there is nothing to do.


1. Produce a new pipeline file. We have introduced a new element to our pipeline, `resources` and in particular the resource of type `git` called `messages`. If you want to know more about what attribute we can specify for this resource go to https://github.com/concourse/git-resource. To know what other resources exist, check out http://concourse.ci/resource-types.html.

```YAML
---
resources:
- name: messages
  type: git
  source:
    uri: https://github.com/MarcialRosales/maven-concourse-pipeline

jobs:
- name: job-hello-world
  plan:
  - get: messages
  - task: produce-greeting
    config:
      platform: linux
      image_resource:
        type: docker-image
        source:
          repository: busybox
      inputs:
        - name: messages
      outputs:
        - name: greetings
      run:
        path: sh
        args:
          - -c
          - |
            MSG=`head -1 messages/README.md`
            echo "hello $MSG !!!" > greeting
            cp greeting greetings

  removed the 2nd job for brevity             
```

2. Deploy the pipeline
  `fly -t local sp -p hello-world4 -c pipeline.yml`

  ![Concourse pipeline with a resource](assets/concourse-3.png)

  - A resource is implemented as a docker image with 3 scripts: check, in, and out. If this is only an input resource, the **check** script  returns the latest version available in that resource. The **in** script produces zero or many files in a folder named after the resource's name. The **out** script takes files from a folder and send them to some target location, e.g. a mail server, a slack server, nexus, etc.
  - Resources are always rendered with black background cross
  - Check the status of the resource: running (version), paused, and failed.
  - Jobs can be manually trigger.
  - But they can also be automatically triggered when there is a new version of a resource
  - Resources linked to a job with a dashed-line means that a new version of the resource will not trigger the job
  - Resources linked to a job with a bold-line means that a new version will trigger the job
  - Concourse shows for each build, each resource and the version that was used in that build.


3. And run it

  ![Concourse build with resource](assets/concourse-4.png)

  - A job fetches the latest version (by default it is the latest) available in the resource
  - Concourse UI shows for each job's build, the fetched resources (with a south pointing arrow), the tasks invoked (with `>_` symbol) and the put resources (none for now in our pipeline). Each fetched resource has its version. And for git resources, it shows very useful information such as branch, committer, date and the commit message.  


4. Modify the pipeline so that it triggers when there is a new version of the github repo. For hints: http://concourse.ci/get-step.html#trigger

  Did it run automatically right after you set the pipeline?

5. Commit a change and push it to your repo so that Concourse detects it.

### Troubleshooting

Sometimes our build fails we don't understand why and it would be great if we could access the container where the task or the resource ran.

In addition to the Web UI, we can get the list of last builds executed in Concourse: 
`fly -t local builds` 

We can tail the logs of a running job:
`fly -t local watch -j pipelineName/jobName`

We can "ssh" into the containers running in the job. We know that each step of a build plan runs on a separate container, so we can have containers running tasks and resources.
To "ssh" into a running container:
`fly -t local hijack -j pipelineName/jobName` it will prompt us which container we want to "ssh" into. 

We can be more specific and "ssh" directly into the container running a task step without Concourse prompting us for which container we want to access.
`fly -t example intercept -j some-pipeline/some-job -b some-build -s some-ste` 

Or we can access a container running a resource:
`fly -t example intercept --check some-pipeline/some-resource`

> Concourse destroys containers when they are not necessary. But it does not destroy them immediately giving us the chance to "ssh" into.

For more information, check the [docs](https://concourse.ci/fly-intercept.html).


## <a name="lab6"></a> Lab 6 - Send greeting message to a slack channel and remove the `print-greeting` task

In the previous lab, we added the **git** **resource** we see below. We used it as an input resource.
  ```YAML
  resources:
  - name: messages
    type: git
    source:
      uri: https://github.com/MarcialRosales/maven-concourse-pipeline

  ```
In this lab, we are going to use another resource but this time it is an only output resource. Concourse comes with a number of [resources types](https://concourse.ci/resource-types.html) installed out of the box. But we can add new resource types. We are going to add one for [slack notifications](https://github.com/cloudfoundry-community/slack-notification-resource).

Let's go step by step:

1. Go to https://my.slack.com/services/new/incoming-webhook/
2. Select your private channel
3. Slack produces a webhook url usually in the form: https://hooks.slack.com/services/XXXX
4. Modify the pipeline we have been working on and add these lines at the beginning. We are telling Concourse that we want to declare a new resource type. To do so, we give it a name and the docker image that implements it.

  ```YAML
  resource_types:
  - name: slack-notification
    type: docker-image
    source:
      repository: cfcommunity/slack-notification-resource
      tag: latest
  ```

  > Where is Concourse downloading those images from? By default, it uses docker hub. However we can specify our own docker registry.

5. We need to add a new resource for the slack notification. We configure the resource to point to our webhook url.
  ```YAML
  - name: slack-greeeting
    type: slack-notification
    source:
      url: https://hooks.slack.com/services/XXXXX
  ```
6. And we use the slack notification resource that we called it `slack-greeting` to send a notification. To do so, we use the `put` step.

  ```YAML
  - put: slack-greeeting
    params:
      text_file: greetings/greeting
      text: |
        The job-hello-world had a result. Check it out at: $ATC_EXTERNAL_URL/builds/$BUILD_ID
        Result was: $TEXT_FILE_CONTENT
  ```
  > When we use a `get` or `put` step, Concourse provides certain metadata via environment variables. http://concourse.ci/implementing-resources.html#resource-metadata

We know that Concourse executes a build plan step by step. If the task `print-greeting` failed (try it out by adding `exit 2` command), it would skip the last step, the `put` step.

## <a name="lab7"></a> Lab 7 - Send a different greeting message to slack channel if the task `produce-greeting` failed

We can tag every step in a build plan with a callback step. The callbacks are `on_success`, `on_failure`, `ensure`.

1. Send a different slack message when the task fails.

```YAML
jobs:
- name: job-hello-world
  plan:
  - get: messages
    trigger: true
  - task: produce-greeting
    on_failure:
      put: slack-greeeting
      params:
        text_file: greetings/greeting
        text: |
          The task print-greeting has failed. Check it out at: $ATC_EXTERNAL_URL/builds/$BUILD_ID
          Result was: $TEXT_FILE_CONTENT
    config:

  rest removed for brevity
```

## <a name="lab8"></a> Send greeting message every few minutes

We can schedule Concourse to trigger jobs in time intervals. The timer is implemented as a [Resource](https://github.com/concourse/time-resource). 

1. Add timer resource which triggers every minute.
  ```YAML
  - name: every1m
    type: time
    source: {interval: 1m}

  ```
2. And fetch it from any job that we want to trigger.
  ```YAML
  jobs:
  - name: job-hello-world
    plan:
    - get: messages
      trigger: true
    - get: every1m
      trigger: true

  ```

## <a name="bonus"></a> Bonus lab - Execute tasks in parallel

Rather than having a single produce-greeting we have produce-header, produce-body, and produce-tail tasks. We want to execute them in parallel and then take the artifacts produced by each one of them to produce a final greeting message.

We use the [aggregate](https://concourse.ci/aggregate-step.html) step and place all the tasks we want to execute in parallel. It is up to Concourse to decide the order and the parallelism. The guarantees are that only when all tasks within the aggregate have successfully completed, it continues with the build plan. If any task failed, the entire aggregate is considered to have failed.  

```YAML
---
jobs:
- name: job-hello-world
  plan:
  - aggregate:
    - task: produce-header
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        outputs:
          - name: header
        run:
          path: sh
          args:
            - -c
            - |
              echo "producting header"
              echo "hello world" > header/greeting
    - task: produce-body
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        outputs:
          - name: body
        run:
          path: sh
          args:
            - -c
            - |
              echo "producting body"
              echo "welcome " > body/greeting
    - task: produce-tail
      config:
        platform: linux
        image_resource:
          type: docker-image
          source:
            repository: busybox
        outputs:
          - name: tail
        run:
          path: sh
          args:
            - -c
            - |
              echo "producting tail"
              echo "regards " > tail/greeting

  - task: print-greeting
    config:
      platform: linux
      image_resource:
        type: docker-image
        source:
          repository: busybox
      inputs:
        - name: header
        - name: body
        - name: tail
      run:
        path: sh
        args:
          - -c
          - |
            cat header/greeting body/greeting tail/greeting

```

We can use aggregate step with resources too.

### More troubleshooting

The number of containers increase very rapidily with the number of pipelines. It is useful to know which containers are currently running. Sometimes the worker machines gets overloaded and jobs fails. 

`fly -t local containers` lists the active containers across all your workers. It is really useful because it tells to which pipeline they belong to and job. 

`fly -t local workers` lists the available workers with the number of containers running each. 

Should you suspect that jobs are failing either due to high cpu utilization or not enough disk space check the Concourse's dashboard provided by Global IT.
![Concourse dashboard](assets/concourse-9.png) 

