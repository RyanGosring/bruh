We create two libraries where one depends on the the other. The dependency
library also has more than one src dir.

  $ echo "(lang dune 2.0)" > dune-project
  $ mkdir -p lib1/sub
  $ cat >lib1/dune <<EOF
  > (include_subdirs unqualified)
  > (library (name lib1))
  > EOF
  $ touch lib1/sub/foo.ml
  $ touch lib1/bar.ml
  $ mkdir lib2
  $ cat >lib2/dune <<EOF
  > (library
  >  (name lib2)
  >  (libraries lib1)
  >  (modules ()))
  > EOF

  $ opam_prefix="$(ocamlc -where)"
  $ export BUILD_PATH_PREFIX_MAP="/OPAM_PREFIX=$opam_prefix:$BUILD_PATH_PREFIX_MAP"
Dune now does mapping that includes mapping the opam root to /install_root, so the
above export will be superceded.
  $ dune build lib2/.merlin-conf/lib-lib2
  $ dune ocaml merlin dump-config $PWD/lib2
  Lib2
  ((STDLIB /install_root/lib/ocaml)
   (EXCLUDE_QUERY_DIR)
   (B
    $TESTCASE_ROOT/_build/default/lib1/.lib1.objs/byte)
   (B
    $TESTCASE_ROOT/_build/default/lib2/.lib2.objs/byte)
   (S
    $TESTCASE_ROOT/lib1)
   (S
    $TESTCASE_ROOT/lib1/sub)
   (S
    $TESTCASE_ROOT/lib2)
   (FLG
    (-w
     @1..3@5..28@30..39@43@46..47@49..57@61..62-40
     -strict-sequence
     -strict-formats
     -short-paths
     -keep-locs
     -g)))
