Title: Jenkinsfiles for Beginners and Masochists
Date: 2019-01-16
Tags: Jenkins, Jenkinsfiles
Canonical-URL: https://www.kabisa.nl/tech/jenkinsfiles-for-beginners-and-masochists

*This post first appeared on [Kabisa's Tech Blog](https://www.kabisa.nl/tech/).*

Because [Jenkins](https://jenkins.io/) is one of the biggest names in the field of tools for continuous integration and continuous delivery, it probably needs no introduction.
Because you probably read [every letter on theguild.nl](https://www.theguild.nl/building-github-pull-requests-using-jenkins-pipelines/),
[Pipelines](https://jenkins.io/doc/book/pipeline/) and [Jenkinsfiles](https://jenkins.io/doc/book/pipeline/jenkinsfile/) also need no introduction.
In case you forgot, Jenkinsfiles provide a way to declaratively specify continuous-delivery pipelines,
which are automated expressions of your process for getting software from version control right through to your users and customers,
as [Jenkins puts it](https://jenkins.io/doc/book/pipeline/).
You can keep Jenkinsfiles in the repositories of the apps they test and deploy. When Jenkins finds such a file in a repository, it will set up the pipeline defined in the file and run it. This allows developers to manage the pipelines for their apps without dealing with Jenkins itself.

If you have limited experience with Jenkins,
I’d advise you to run it locally right away and take a look.
If you’re running [Docker](https://www.docker.com/), the simplest way to run Jenkins is by means of a script like the following.

```sh
#!/bin/sh
docker pull jenkinsci/blueocean
docker run -u root --rm -d \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins-data:/var/jenkins_home \
  -v jenkins-root:/root \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /Users/lucengelen/Repositories:/Users/lucengelen/Repositories \
  jenkinsci/blueocean
```

When you compare this script with the [installation instructions provided by Jenkins](https://jenkins.io/doc/book/installing/#docker),
you’ll see some differences.
First, I’ve added `docker pull jenkinsci/blueocean` to ensure that I always use the latest version of the Docker image for Jenkins.
Additionally, I’ve added the command-line arguments `-v jenkins-root:/root` and `-v /Users/lucengelen/Repositories:/Users/lucengelen/Repositories`.
The first ensures that SSH keys are preserved when a new Docker image for Jenkins is built.
The second ensures that the folder where I keep my repositories is accessible from within the Docker container.
You should modify this line to match your situation (or move your repositories to `/Users/lucengelen/Repositories`).

After you’ve executed the commands above, you’ll be able to visit [http://localhost:8080](http://localhost:8080/) in the browser and see Jenkins’ post-installation setup wizard.
Jenkins asks you to enter a key that you can find in its logs, which you can inspect by running `docker logs <CONTAINER_ID>`,
where `<CONTAINER_ID>` is the long string displayed after the docker run command is finished.

Once you’re done with the setup, create a new job in Jenkins with the type “Multibranch Pipeline”.
Give this job a source of type “Git” and point it to the repository [https://github.com/ljpengelen/jenkinsfile](https://github.com/ljpengelen/jenkinsfile).
You’ll see that Jenkins discovers the Jenkinsfile in the root of the repository and tries to run a pipeline for the branches `master` and `staging`.
This will fail for a number of reasons, but that’s okay.

## Starting From Scratch

When experimenting with Jenkins,
it’s often convenient to be able to test changes to a Jenkinsfile without pushing to a remote repository.
If Jenkins is pulling a remote repository for changes,
it will only see the that you’ve pushed.
Using a file URL for a local repository enables you to iterate faster.
Assuming that you’ve clone the repository mentioned above into the folder `/Users/lucengelen/Repositories/jenkinsfile`,
you can create a second multibranch-pipeline job and point it to the repository `file:///Users/lucengelen/Repositories/jenkinsfile`,
for example.

After you’ve done this for the folder were you’ve cloned the repository,
replace the content of the Jenkinsfile in the root of the repository to the following and commit your changes.

```groovy
pipeline {
  agent none

  stages {
    stage("Test back end") {
      agent {
        dockerfile {
          filename "back-end/dockerfiles/ci/Dockerfile"
        }
      }

      steps {
        sh "cd back-end && bin/ci"
      }
    }

    stage("Test front end") {
      agent {
        dockerfile {
          filename "front-end/dockerfiles/ci/Dockerfile"
        }
      }

      steps {
        sh "rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules"
        sh "cd front-end && bin/ci"
      }
    }
  }
}
```

If you’ve committed these changes on a new branch,
you need to ask Jenkins to scan your multibranch pipeline again.
If you’ve committed them to an existing branch,
you can just start a new build for that branch.
You’ll see that this build succeeds.

The tests and linters for both apps are executed inside Docker containers.
The dependencies for both apps are installed inside these containers.
This way, Docker takes care of the caching.

By default, Yarn looks for dependencies in a folder named `node_modules` in the root of your project folder.
The command `cd front-end && bin/ci` is executed in the folder where Jenkins has checked out your repository.
As part of the build of the Docker image for the front end, however,
the dependencies are installed in the folder `/app/node_modules`.
This explains the presence of the command `rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules`.
There’s a Yarn-specific way of configuring an alternative location of the node_modules folder, but it didn’t work for me.
Since this is also a post for masochists, feel free to experiment with it.

## Shooting Yourself in the Foot

You can tell Jenkins to run (parts of) your pipelines on a specific node.
You do this by specifying a label for an agent in your pipeline.
The steps for this particular agent will then be executed on a node with the given label.
Modify your Jenkinsfile as follows.

```groovy
pipeline {
  agent none

  stages {
    stage("Test back end") {
      agent {
        dockerfile {
          filename "back-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "cd back-end && bin/ci"
      }
    }

    stage("Test front end") {
      agent {
        dockerfile {
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules"
        sh "cd front-end && bin/ci"
      }
    }
  }
}
```

If you trigger a new build,
you’ll probably see it fail because there’s no agent with the label “webapps”.
Introduce a new agent by visiting [http://localhost:8080/computer/new](http://localhost:8080/computer/new), choosing a name,
and selecting “permanent agent”.
On the next page, specify a remote root directory, set the label to “webapps”,
and the host to “localhost” or your computer’s hostname.
If you’re on a Mac, you’ll have to [allow remote access via SSH to your machine](https://www.booleanworld.com/access-mac-ssh-remote-login/).
Provide your credentials for logging in via SSH.

If you’ve followed all these steps, you should now be able to run the pipeline, right?
In the end, you’re just executing the steps on your local machine, just like you were doing before.
If you’re working on a Mac, you’ll quickly find that new builds still fail.
For some reason, Docker is not available, and you’ll see a line ending with
`script.sh: line 1: docker: command not found` in the console output of your pipeline.

If you go to the command line and execute the following command, you’ll understand what’s going on.

```shell-session
ssh localhost "echo \$PATH"
```

This will result in something like `/usr/bin:/bin:/usr/sbin:/sbin`.
Be sure to escape the dollar sign because the result of the following command will only add to the confusion.

```shell-session
ssh localhost "echo $PATH"
```

If you run commands like we do above, you end up in a non-interactive, non-login shell.
This is also what Jenkins is doing when it’s executing the steps of the agents in our Jenkinsfile.
In such a shell, you have a different path than in the interactive login shell that you work in when you open a terminal.
On a Mac, the Docker executable is located at `/usr/local/bin/docker`,
which is not in the path of the non-interactive, non-login shell.

To fix this, go back to the configuration of the node you just added and add `PATH=$PATH:/usr/local/bin &&`
as the value for the input “Prefix Start Agent Command” that is part of the advanced settings.

Because we’re just experimenting with Jenkins, there’s no real reason to shoot yourself in the foot like this.
You could leave out the label or configure your main node to run jobs with this label.
I just wanted to warn you about this pitfall in case you ever encountered it in the real world.

## Continuous Delivery

To keep experimenting along, you’ll need an instance of Dokku running somewhere.
Coincidentally, there’s a blog post about setting up an instance of [Dokku on Azure](https://www.theguild.nl/setting-up-dokku-on-azure-with-terraform-and-ansible-a-guided-tour/)
that is almost perfect for the Jenkinsfile below.
You only have to open port 8000 instead of 8080.
You may also have to pick another prefix for your hostnames if the ones below are taken.

```groovy
dokkuHostname = "kabisa-dokku-demo-staging.westeurope.cloudapp.azure.com"
if (env.BRANCH_NAME == "production") {
  dokkuHostname = "kabisa-dokku-demo-production.westeurope.cloudapp.azure.com"
}

pipeline {
  agent none

  stages {
    stage("Test back end") {
      agent {
        dockerfile {
          filename "back-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "cd back-end && bin/ci"
      }
    }

    stage("Test front end") {
      agent {
        dockerfile {
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules"
        sh "cd front-end && bin/ci"
      }
    }

    stage("Deploy back end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "git push -f dokku@${dokkuHostname}:back-end HEAD:refs/heads/master"
      }
    }

    stage("Build front end") {
      agent {
        dockerfile {
          args "-e 'API_BASE_URL=http://${dokkuHostname}:8000/api'"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "cd front-end && yarn build"
      }
    }

    stage("Deploy front end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "rm -rf deploy-front-end"
        sh "git clone dokku@${dokkuHostname}:front-end deploy-front-end"
        sh "rm -rf deploy-front-end/dist"
        sh "mkdir -p deploy-front-end/dist"
        sh "cp -R front-end/dist/* deploy-front-end/dist"
        sh "touch deploy-front-end/.static"
        sh "cd deploy-front-end && git add . && git commit -m \"Deploy\" --allow-empty && git push -f"
      }
    }
  }
}
```

If you want the pipeline above to be successful,
you need to configure SSH in the Docker container running Jenkins so that it uses the right keys.
Execute `docker exec -it <CONTAINER_ID> /bin/sh` to enter the container, store the keys somewhere,
create the file `/root/.ssh/config` if it doesn’t exist yet, and add the following lines to point SSH to the right keys.

```sh
Host kabisa-dokku-demo-staging.westeurope.cloudapp.azure.com
  IdentityFile ~/.ssh/azure_dokku_git_staging

Host kabisa-dokku-demo-production.westeurope.cloudapp.azure.com
  IdentityFile ~/.ssh/azure_dokku_git_production
```

Modify the hostnames and key names in this example to match your situation.

## Better Safe than Sorry

Unless you tell Docker otherwise, it will do as little work as possible when building an image.
It caches the result of each build step of a Dockerfile that it has executed before and uses the result for each new build.
If a new version of the base image you’re using becomes available that conflicts with your app, however,
you won’t notice that when running the tests in a container using an image that is built upon the older,
cached version of the base image.

You can instruct Docker to look for newer verions of your base image during a build with the command-line argument `--pull`.
Because new base images are only available once in a while,
it’s not really wasteful to use this argument all the time when building images.
This is what we’re doing in the Jenkinsfile below.

```groovy
additionalBuildArgs = "--pull"
if (env.BRANCH_NAME == "master") {
  additionalBuildArgs = "--pull --no-cache"
}

dokkuHostname = "kabisa-dokku-demo-staging.westeurope.cloudapp.azure.com"
if (env.BRANCH_NAME == "production") {
  dokkuHostname = "kabisa-dokku-demo-production.westeurope.cloudapp.azure.com"
}

pipeline {
  agent none

  triggers {
    cron(env.BRANCH_NAME == 'master' ? '@weekly' : '')
  }

  stages {
    stage("Test back end") {
      agent {
        dockerfile {
          additionalBuildArgs "${additionalBuildArgs}"
          filename "back-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "cd back-end && bin/ci"
      }
    }

    stage("Test front end") {
      agent {
        dockerfile {
          additionalBuildArgs "${additionalBuildArgs}"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules"
        sh "cd front-end && bin/ci"
      }
    }

    stage("Deploy back end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }
    }

    stage("Build front end") {
      agent {
        dockerfile {
          args "-e 'API_BASE_URL=http://${dokkuHostname}:8000/api'"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      when {
        beforeAgent true
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "cd front-end && yarn build"
      }
    }

    stage("Deploy front end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "rm -rf deploy-front-end"
        sh "git clone dokku@${dokkuHostname}:front-end deploy-front-end"
        sh "rm -rf deploy-front-end/dist"
        sh "mkdir -p deploy-front-end/dist"
        sh "cp -R front-end/dist/* deploy-front-end/dist"
        sh "touch deploy-front-end/.static"
        sh "cd deploy-front-end && git add . && git commit -m \"Deploy\" --allow-empty && git push -f"
      }
    }
  }
}
```

You may have noticed that there’s also a command-line argument `--no-cache` in this Jenkinsfile,
which is only used on the master branch.
This command-line argument instructs Docker to not use any caching at all when building an image.
This means that Docker will download and install all dependencies when building an image.
If there’s something wrong when any of your dependencies, you’ll find out right away.
This is a good way of ensuring that your Docker containers can be built from scratch,
but it would be a waste of resources and bandwith to build images like this for every commit.
In the Jenkinsfile above, images are only built from scratch on the `master` branch.
This ensures that you’ll find out that something is wrong with your Docker image when you merge features to `master`.
To ensure that you’re also notified in case of issues when an app is no longer in active development,
a trigger is added to build the `master` branch once every week.

The line `beforeAgent true` in the when clause of the stage “Build front end” ensures that the Docker image used to build the front end is only built when new changes are pushed to the branches `staging` and `production`.
Without this line, the image would always be built, regardless of the branch.
The when clause would only prevent the steps from being executed.
This is mostly gold plating of the Jenkinsfile,
since the same image is used to run the tests for the front end and build it,
which means that the second Docker build would use cached data anyway.

Because the same container is used for testing and building the front end, the additional arguments for the Docker build command are left out for the build step.

## Shooting Yourself in the Foot Again

So far, some potential issues were masked because we’ve been running Jenkins as root.
In other real-life scenarios, Jenkins will not always be running as root, however.
If you run the [WAR-file version of Jenkins](https://jenkins.io/doc/book/installing/#war-file), for example,
the Jenkins process would be running as the user that executed `java -jar jenkins.war` on the command line.
When you execute a new build in that scenario, you’ll find that it fails again.
The user that’s executing commands in the Docker container for the front end doesn’t have the right access rights.
I advise all masochists to try this at home and watch it fail.

We can easily fix this by explicitly instructing Docker to use the root user again, as shown below.

```groovy
additionalBuildArgs = "--pull"
if (env.BRANCH_NAME == "master") {
  additionalBuildArgs = "--pull --no-cache"
}

dokkuHostname = "kabisa-dokku-demo-staging.westeurope.cloudapp.azure.com"
if (env.BRANCH_NAME == "production") {
  dokkuHostname = "kabisa-dokku-demo-production.westeurope.cloudapp.azure.com"
}

pipeline {
  agent none

  triggers {
    cron(env.BRANCH_NAME == 'master' ? '@weekly' : '')
  }

  stages {
    stage("Test back end") {
      agent {
        dockerfile {
          additionalBuildArgs "${additionalBuildArgs}"
          filename "back-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "cd back-end && bin/ci"
      }
    }

    stage("Test front end") {
      agent {
        dockerfile {
          additionalBuildArgs "${additionalBuildArgs}"
          args "-u root"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules"
        sh "cd front-end && bin/ci"
      }
    }

    stage("Deploy back end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "git push -f dokku@${dokkuHostname}:back-end HEAD:refs/heads/master"
      }
    }

    stage("Build front end") {
      agent {
        dockerfile {
          args "-u root -e 'API_BASE_URL=http://${dokkuHostname}:8000/api'"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      when {
        beforeAgent true
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "cd front-end && yarn build"
      }
    }

    stage("Deploy front end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "rm -rf deploy-front-end"
        sh "git clone dokku@${dokkuHostname}:front-end deploy-front-end"
        sh "rm -rf deploy-front-end/dist"
        sh "mkdir -p deploy-front-end/dist"
        sh "cp -R front-end/dist/* deploy-front-end/dist"
        sh "touch deploy-front-end/.static"
        sh "cd deploy-front-end && git add . && git commit -m \"Deploy\" --allow-empty && git push -f"
      }
    }
  }
```

The test and build steps for the front end are now executed as root,
which seems to work great at first sight.
In fact, due to some peculiarities related to file permission of Docker for Mac, it works great on Mac, period.

If you feel that seeing is believing or have lots of time to kill, boot up a Linux (virtual) machine,
install Docker and Jenkins, set up a multibranch project again, and start a new build.
Afterwards, visit Jenkins’ workspace for the project and check the file permissions.
You’ll notice that some files and folders have been created that are owned by root.
Because Jenkins isn’t running as root,
it is not allowed to delete these files when the time comes to clean up the workspace for your project.
For your own amusement, it’s also worthwhile to check that you don’t have this issue on Macs.

To prevent Jenkins from running out of disk space in the future,
we need to make sure that the files and folders created as root can be deleted by Jenkins.
There are a number of ways to do this,
but one way that doesn’t require any additional configuration of Jenkins is demonstrated in the final version of our Jenkinsfile.

```groovy
additionalBuildArgs = "--pull"
if (env.BRANCH_NAME == "master") {
  additionalBuildArgs = "--pull --no-cache"
}

dokkuHostname = "kabisa-dokku-demo-staging.westeurope.cloudapp.azure.com"
if (env.BRANCH_NAME == "production") {
  dokkuHostname = "kabisa-dokku-demo-production.westeurope.cloudapp.azure.com"
}

pipeline {
  agent none

  triggers {
    cron(env.BRANCH_NAME == 'master' ? '@weekly' : '')
  }

  stages {
    stage("Test back end") {
      agent {
        dockerfile {
          additionalBuildArgs "${additionalBuildArgs}"
          filename "back-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "cd back-end && bin/ci"
      }
    }

    stage("Test front end") {
      agent {
        dockerfile {
          additionalBuildArgs "${additionalBuildArgs}"
          args "-u root"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      steps {
        sh "rm -f front-end/node_modules && ln -s /app/node_modules front-end/node_modules"
        sh "cd front-end && bin/ci"
      }

      post {
        always {
          sh "chown -R \$(stat -c '%u:%g' .) \$WORKSPACE"
        }
      }
    }

    stage("Deploy back end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "git push -f dokku@${dokkuHostname}:back-end HEAD:refs/heads/master"
      }
    }

    stage("Build front end") {
      agent {
        dockerfile {
          args "-u root -e 'API_BASE_URL=http://${dokkuHostname}:8000/api'"
          filename "front-end/dockerfiles/ci/Dockerfile"
          label "webapps"
        }
      }

      when {
        beforeAgent true
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "cd front-end && yarn build"
      }

      post {
        always {
          sh "chown -R \$(stat -c '%u:%g' .) \$WORKSPACE"
        }
      }
    }

    stage("Deploy front end") {
      agent {
        label "webapps"
      }

      when {
        anyOf {
          branch 'staging';
          branch 'production'
        }
      }

      steps {
        sh "rm -rf deploy-front-end"
        sh "git clone dokku@${dokkuHostname}:front-end deploy-front-end"
        sh "rm -rf deploy-front-end/dist"
        sh "mkdir -p deploy-front-end/dist"
        sh "cp -R front-end/dist/* deploy-front-end/dist"
        sh "touch deploy-front-end/.static"
        sh "cd deploy-front-end && git add . && git commit -m \"Deploy\" --allow-empty && git push -f"
      }
    }
  }
```

After the test and build step, we change the owner of all files in the workspace to whoever owns the workspace, which is Jenkins.

## Conclusion

If you ask me, there are two important conclusions to be drawn from this port.
First, Jenkinsfiles are a powerful and convenient tool for continuous integration and continuous delivery.
Second, one instance of Jenkins can be very different from another.
You can’t take a Jenkinsfile from one project to another and expect it to work right away.
I hope that some of the pitfalls described in this post point you in the right direction when you run into trouble in the future.
