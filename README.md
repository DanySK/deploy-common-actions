# Autodelivery
#### This action has been inspired by "Deploy Common Actions"

## What it does
Updates common files and secrets across multiple repositories in one shot.

## Exemplary use case
Imagine you got multiple repositories with the same continuous integration configuration (e.g., the same `.travis.yml` or github workflow files).
Now, every time you want to make a change, you probably want to propagate it across the board.
In the case you are propagating a GitHub Actions workflow, you are presumably also setting up signign keys and similar stuff.
And doing it requires *precious time* to be spent for a *repetitive action*: unacceptable.
This action is here to help.

## Action inputs and configuration

* `token`: Github secret token. Must be a user token, GH Actions tokens won't work. 
You need at least `public_repo` to work with private repositories and `repo` to work with private repositories.
In case you want to push changes to your GitHub Actions workflows, also check the `workflows` permission.
* `user`: GitHub username of the user performing the delivery. Defaults internally to GITHUB_ACTOR in case it's unspecified
* `configuration_file`: Path to the Autodelivery YAML configuration file (whose syntax is described later on), relative to the local repository root.
Defaults to 'auto-delivery.yml'
* `commit_author`: Committer's name. Defaults to `Autodelivery [bot]`
* `author_email`: Commiter's email. Defaults to `autodelivery@autodelivery.bot`
* `labels`: Comma separated list of labels to apply to the pull request. Defaults to ''. Non existing labels will be created using the color in colors (if a color positionally matches the label) or generating a random color.
* `colors`: Comma separated list of colors, in HTML format (six hexadecimal entries, e.g., 'fa1234')

This action has no outputs.

### Repository structure

You are expected to define one payload per folder.
The contents of the folder will be copied inside the target repositories defined in the YAML configuration file.

```
.
├── .github/workflow/deploy.yml # Your workflow to deploy the script, as shown in the example below.
├── my-common-travis-stuff # A common workflow 
|   └──  .travis.yml
├── some-standard-gradle-project # A common workflow 
|   └── gradle
|   |   ├── wrapper.jar
|   |   └── gradle-wrapper.properties
|   ├── build.gradle.kts
|   └── settings.gradle.kts
├── a-github-actions-example # A common workflow 
|   └── .github
|       └── workflows
|           ├── my-action-1.yml
|           └── my-action-2.yml
└── auto-delivery.yml
```

### Propagating secrets

Secrets propagation is performed using environment variables:
the secret you want to propagate must be available in the repository hosting this action
(of course, otherwise it would be impossible to access)
into an environment variable with the same name of the target secret variable.

### YAML configuration file

The YAML configuration file tells Autodelivery where to deliver which subfolder.
For the previous example, the file might look like something like this:

```yaml
files:
  my-common-travis-stuff: # same as the folder name
    owner1: # Can be a user or an organization
      repo1: # Repository name. If no branch is specified, the default is 'master'
      repo2: develop # A branch can be specified with a string
      repo3: # Multiple branches can be targeted by using a list
        - master
        - develop
    owner2: repo1 # If you got a single repo you care of, and the master branch is fine, then just use a string
  some-standard-gradle-project:
    someuser: a-gradle-repository
  a-github-actions-example:
    my-organization:
      a-repository-using-actions: develop
      another-repository-but-with-master-as-development-branch:
    another-user-or-organization:
      yeah-you-got-how-it-works: master
secrets:
  MY_SECRET_VARIABLE: # Must be an environment variable that is available when the action is performed
    some-owner: some-repository
    same-syntax-as-files: you-can-be-DRY-using-anchors-and-merge-keys
```

### GitHub Action

In order to use this action to automate the delivery, use a configuration such as:

```yaml
name: Autodelivery
on:
  push:
jobs:
  autodelivery:
    runs-on: ubuntu-latest
    steps:
    - uses: DanySK/autodelivery@master # Replace with a version!
      with:
        # You can omit everything but token (mandatory) and user (recommended) if you are okay with the defaults
        token: ${{ secrets.GH_TOKEN }}
        user: DanySK
        configuration_file: 'auto-delivery.yml'
        commit_author: Danilo Pianini
        author_email: danilo.pianini@gmail.com
```

### Running example

Since it's easier done that said, and since I use this myself for my repositories, [here is an example](https://github.com/DanySK/gha-ci-centralized-automated-deployer).
