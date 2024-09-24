'dune fmt' could miss the extra-files from "dev-tools.locks" directory for the first run, if the
auto-locking comes before the setup of the dune project meaning the loading of dune source tree.

  $ . ./helpers.sh
  $ mkrepo

Make a fake ocamlformat:
  $ make_fake_ocamlformat "0.1"

A patch that changes the version from "0.1" to "0.26.2":
  $ cat > patch-for-ocamlformat.patch <<EOF
  > diff a/ocamlformat.ml b/ocamlformat.ml
  > --- a/ocamlformat.ml
  > +++ b/ocamlformat.ml
  > @@ -1,6 +1,6 @@
  > -let version = "0.1"
  > +let version = "0.26.2"
  >  let () =
  >    if Sys.file_exists ".ocamlformat-ignore" then
  >    print_endline "ignoring some files"
  >  ;;
  >  let () = print_endline ("formatted with version "^version)
  > EOF

Make the ocamlformat opam package which uses a patch:
  $ mkpkg ocamlformat "0.26.2"  <<EOF
  > build: [
  >   [
  >     "dune"
  >     "build"
  >     "-p"
  >     name
  >     "-j"
  >     jobs
  >   ]
  > ]
  > extra-files: ["patch-for-ocamlformat.patch" "md5=$(md5sum patch-for-ocamlformat.patch | cut -f1 -d' ')"]
  > patches: ["patch-for-ocamlformat.patch"]
  > url {
  >  src:"file://$PWD/ocamlformat-0.1.tar.gz"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.1.tar.gz | cut -f1 -d' ')"
  >  ]
  > }
  > EOF
  $ mkdir -p mock-opam-repository/packages/ocamlformat/ocamlformat.0.26.2/files/
  $ cp patch-for-ocamlformat.patch mock-opam-repository/packages/ocamlformat/ocamlformat.0.26.2/files/

Make a project that uses the fake ocamlformat:
  $ make_project_with_dev_tool_lockdir

First time run
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt 2>&1 | sed -E 's#.*.sandbox/[^/]+#.sandbox/$SANDBOX#g'
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  $ cat foo.ml
  formatted with version 0.26.2
