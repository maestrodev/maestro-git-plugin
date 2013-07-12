maestro-git-plugin
====================

A Maestro Plugin that allows execution of shell commands

Task
----

/git/clone

Task Parameters
---------------

* "Path"

  The location on disk to store the cloned repository

* "URL"

  URL to be passed to GIT as parameter to "git clone $URL"

* "Branch"

  Default: "master"

  The branch to checkout once the repository has been cloned

* "Clean Working Copy"

  Default: false

  If "true" will delete the working directory (Path) and force a "git clone" to be performed, otherwise existing repository will be updated with "git pull" (if present)

* "Force Build"

  Default: false

  Determines what the composition will do if the repository has already been cloned and no new changes have been detected.
  true: Will allow composition to continue and perform normal build process
  false: Composition will stop
  
  Note: This field is set to 'true' when a composition is manually started, and left at 'false' if the composition starts due to an external trigger (i.e. a commit notification from a git server)


Task
----

/git/branch

Task Parameters
---------------

* "Path"

  The location on disk to store the cloned repository

* "Branch Name" (note, different from clone)

  The branch to create

* "Remote Repo"

  The repository to push the new branch to (i.e. "origin")


Task
----

/git/tag

Task Parameters
---------------

* "Path"

  The location on disk to store the cloned repository

* "Remote Branch" (note, different from clone & branch)

  The branch to create

* "Remote Repo"

  The repository to push the new branch to (i.e. "origin")

* "Tag Name"

  Tag name to apply

* "Commit Checksum"

  Git Reference ID (Hash) to apply tag to

* "Message"

  Default: ""

  Commit message