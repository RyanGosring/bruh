Because INSIDE_DUNE is set for sandboxing Dune does not perform root discovery
in tests. That is why for each call to Dune we specify manually the `root`
directory in these tests.

  $ ln -s realroot linkroot

  $ cd linkroot

  $ dune build

Absolute path with symlinks won't match with Dune's root path in which symlinks
are resolved:
  $ dune ocaml-merlin --dump-config="$(pwd)/realsrc" --root="."
  Path "$TESTCASE_ROOT/linkroot/realsrc" is not in dune workspace ("$TESTCASE_ROOT/realroot").

Absolute path with resolved symlinks will match with Dune's root path:
  $ dune ocaml-merlin \
  > --dump-config="$(pwd | sed 's/linkroot/realroot/')/realsrc" \
  > --root="." | head -n 1
  Foo


Dune ocaml-merlin also accepts paths relative to the current directory
  $ dune ocaml-merlin --dump-config="realsrc" --root="." | head -n 1
  Foo

  $ cd realsrc

  $ opam_prefix="$(opam config var prefix)"
  $ export BUILD_PATH_PREFIX_MAP="/OPAM_PREFIX=$opam_prefix:$BUILD_PATH_PREFIX_MAP"

  $ dune ocaml-merlin --dump-config="." --root=".." | head -n 2
  Foo
  ((STDLIB /OPAM_PREFIX/lib/ocaml)
