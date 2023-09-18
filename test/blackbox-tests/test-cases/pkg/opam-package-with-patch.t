This test checks that the patches field of an opam file is correctly translated into the
appropriate build step.

  $ . ./helpers.sh

Generate a mock opam repository
  $ mkdir -p mock-opam-repository
  $ cat >mock-opam-repository/repo <<EOF
  > opam-version: "2.0"
  > EOF


Make a package with a patch
  $ mkpkg with-patch <<EOF
  > opam-version: "2.0"
  > patches: ["foo.patch"]
  > build: ["cat" "foo.ml"]
  > EOF


  $ mkdir -p mock-opam-repository/packages/with-patch/with-patch.0.0.1/files
  $ cat >mock-opam-repository/packages/with-patch/with-patch.0.0.1/files/foo.patch <<EOF
  > diff --git a/foo.ml b/foo.ml
  > index b69a69a5a..ea988f6bd 100644
  > --- a/foo.ml
  > +++ b/foo.ml
  > @@ -1,2 +1,2 @@
  > -This is wrong
  > +This is right
  > EOF

  $ solve_project <<EOF
  > (lang dune 3.8)
  > (package
  >  (name x)
  >  (allow_empty)
  >  (depends with-patch))
  > EOF
  Solution for dune.lock:
  with-patch.0.0.1
  
  $ cat >>dune.lock/with-patch.pkg <<EOF
  > (source (copy $PWD/source))
  > EOF

The lockfile should contain the patch action. 

  $ cat dune.lock/with-patch.pkg 
  (version 0.0.1)
  
  (build
   (progn
    (patch foo.patch)
    (run cat foo.ml)))
  (source (copy $TESTCASE_ROOT/source))

  $ mkdir source
  $ cat > source/foo.ml <<EOF
  > This is wrong
  > EOF

  $ build_pkg with-patch 
  This is right
