# How Package Management Works

This document gives an explanation on how the new package management
feature introduced in Dune works under the hood. It requires a bit of
familiarity with how OPAM repositories work and how Dune builds packages. Thus
it is aimed at people who want to understand how the feature works, not how it
is used.

For a tour on how to apply package management to a project, refer to the
{doc}`/tutorials/dune-package-management/index` tutorial.

## Motivation

A core part of modern programming is using other existing code to save time.
The history of the OCaml package ecosystem is quite long with a lot of projects
building upon each other over many years. A significant step forward was the
creation of an OCaml Package Manager, OPAM, along with the establishment of a
public package repository which made it a lot more feasible to share code
between people and projects.

Over time best practices have evolved, and while OPAM has incorporated some
changes, due to its existing user base and constraints it couldn't adopt all
the modern workflows.

Dune package management attempts to take the parts of the OPAM ecosystem that
have stood the test of time and couple them with a modern workflow. Some of the
improvements include:

* Automatic package repository updates
* Easily reproducible dependencies
* All package dependencies declared in a single file that is kept in-sync
* Per-project dependencies

Dune plays well with the existing OCaml ecosystem and does not introduce a new
type of packages - it uses the same package repository and Dune packages stay
installable with OPAM.

## Package Management in a Project

This section describes what happens in a Dune project that is using the package
management feature.

## Dependency Selection

The first step is to determine which packages need to be installed.
Traditionally this has been defined in the `depends` field of a projects OPAM
file(s).

Since a while Dune has also supported {doc}`OPAM file generation
</howto/opam-file-generation>` by specifying the package dependencies in the
`dune-project`. Outside of this feature, the `depends` stanza had not been used
by Dune.

The package management feature changes this, as Dune now determines the list of
packages to install from the `depends` stanza in the `dune-project` file. This
allows projects to completely omit generation of `.opam` files, as long as they
use Dune for package management. Thus all dependencies are only declared in one
file.

For compatibility with a larger amount of existing projects Dune will also
collect dependencies from `.opam` files in the project. So while recommended,
there is no obligation to switch to declaring dependencies in the
`dune-project`. Likewise the generation of `.opam` files will still work.

## Locking

To go from a set of dependency constraints for a project to a set of installed
packages and versions there needs to be a step to determine the right packages
and their versions to be installed.

In `opam` this process happens as part of `opam install`, thus linking finding
a solution that satifies the given constrains and installation into one step.
Dune on the other hand moves finding a solution and installing into separate
steps. First a solution is found and then packages are installed separately.

The idea of finding a solution and recording it for later is popular in other
programming language package managers like NPM and is usually called locking.

:::{note}
`opam` also supports creating lock-files. However these are not as central to
the opam workflow as they are in the case of package management in Dune, which
always requires a set of locked packages.
:::

A package lock is in the most general sense just a set of specific packages and
their versions to be installed.

A Dune lockfile extends this to a directory with files that describe the
dependencies. It includes the name of the package and the version. Unlike many
other package managers, the files include a lot of other information as well,
such as the location of the source archives to download (since there is no
central location for all archives), the build instructions (since each package
can use its own way of building) as well as additional metadata like the system
packages it depends upon.

The information is stored in a directory (`dune.lock` by default) as separate
files, because that makes it easier to manage them in source control as it
leads to fewer potential merge conflicts and simplifies review processes.
Storing additional files like patches is also more elegant this way.

### Package Repository Management

To find a valid solution that allows a project to be built it is necessary to
know what packages exist, what versions of these packages exist, what other
packages these depend on etc.

In OPAM this information is tracked in a central repository called
[OPAM-repository](https://github.com/ocaml/opam-repository) which contains all
the metadata for published packages.

It is managed using Git and OPAM typically uses a snapshot of it to look up the
dependencies when trying to find a solution that satisfies the constraints.

Likewise, Dune uses the same repository, however instead of snapshots of the
files it uses the Git repository directly. In fact, Dune maintains a shared
internal cache containing all Git repositories that projects use. This has the
advantage that updates to the metadata are very fast since only the newest
revisions have to be retrieved. The downside is that for the creation of the
cache the entire repository has to be cloned first.

Given a priorization of fast updates, whenever Dune needs to determine the
available packages, it will update the repository first. Thus each locking
process by default will use the newest set of packages available.

However it is also possible to specify specific revisions of the repositories,
to get a reproducible solution. Due to using Git any previous revision of the
repository can be used, by specifying a commit hash.

Dune defines two repositories by default:

* `upstream` which refers to the default branch of `opam-repository`, which
  contains all the publically released packages.
* `overlay` which refers to
  [opam-overlay](https://github.com/ocaml-dune/opam-overlays), which defines
  packages patched to work with package management. The long-term goal is to
  have as few packages as possible in this repository as more and more packages
  work within Dune package management upstream. Check the
  [compatibility](#compatibility) section for details.

### Solving

After Dune has retrieved the constraints and the set of possible packages it is
necessary to determine which packages and versions should be selected for the
package lock.

To do so, Dune uses
[opam-0install-solver](https://github.com/ocaml-opam/opam-0install-solver),
which is a variant of the 0install solver to find solutions for OPAM packages.

Contrary to `opam`, the Dune solver always starts from a blank slate. It
assumes nothing is installed and everything needs to be installed. This has the
advantage that solving is simpler and previous solver solutions don't interfere
with the current one. Thus given the same inputs it should always have the same
outputs; no state is held between the solver runs.

This can lead to more packages being installed (as OPAM won't by default
install new versions of packages if the existing versions satisfy the
constraints) but it avoids interference from already installed packages that
lead to potentially different solutions.

After solving is done, the solution gets written into the lock directory with
all the metadata that is necessary to build and install the packages. From this
point on, there is no need to access any package repositories.

:::{note}
Solving and locking does not download the package sources. These are downloaded
in a later step.
:::

## Building

When building, Dune will read the information from the lock directory and set
up rules to use the packages. Check {doc}`/explanation/mental-model` for
details about rules.

The rules that the package management sets up include:

* Fetch rules to download the sources as well as any additional sources like
  patches and unpack them
* Build rules to evaluate the build instructions from the build instructions
  stored in the lock directory
* Install rules to put the artifacts that were built into the appropriate,
  Dune-managed folders

Creating these processes as rules means that they will only be executed on
demand, thus if the project has already downloaded the sources, it does not
need to download them again. Likewise, if packages are installed, they stay
installed.

The results of the rules are stored in the `_build` directory of the project
and managed automatically by Dune. Thus when cleaning the build directory, the
installed packages are cleaned as well and will be reinstalled at the next
build.

When building the users project, the installed packages are added to the
necessary search paths, thus user code can use the dependencies without any
additional configuration.

(compatibility)=
## Packaging for Dune Compatibility

Dune can build and install most packages as dependencies, even if they are not
built with Dune themselves. Dune will execute the build instructions from the
lock file, very similar to `opam`.

However, there are some important restrictions that packages must adhere to to
be able to work with Dune.

The most important one is that the packages must not use absolute paths to
refer to files. That means, they cannot read the path they are being built or
installed into and expect this path to be stable. Dune builds packages in a
sandbox location and after the build has finished it moves the files to the
actual destination.

The reason for this is that one hand it enables building without messing up the
current state and on the other hand it allows for caching artifacts across
projects.

To sidestep these restructions in many cases the solution is to use relative
paths, as Dune guarantees that packages installed into different sections are
installed in a way where their relative location stays the same.

A minor difference is that Dune does not support packages installing themselves
into the standard library, thus being available without having to be declared a
dependency.

For this reason the `overlay` repository exists, which contains packages where
the upstream packages are incompatible with Dune package management, but were
patched to work in Dune.
