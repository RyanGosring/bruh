This is a current bug, 'dune fmt' misses extra files from "dev-tools.locks" directory for the first run.

  $ . ./helpers.sh
  $ mkrepo

Make a fake ocamlformat:
  $ make_fake_ocamlformat "0.1"

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
  Error:
  .sandbox/$SANDBOX/_private/default/.dev-tool/ocamlformat/ocamlformat/source/patch-for-ocamlformat.patch:
  No such file or directory
  -> required by
     _build/_private/default/.dev-tool/ocamlformat/ocamlformat/target/bin/ocamlformat
  -> required by _build/default/.formatted/foo.ml
  -> required by alias .formatted/fmt
  -> required by alias fmt

Second time run
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2
