 Temporary special merlin support for melange only libs

  $ cat >dune-project <<EOF
  > (lang dune 3.6)
  > (using melange 0.1)
  > EOF

  $ lib=foo
  $ cat >dune <<EOF
  > (library
  >  (name $lib)
  >  (private_modules bar)
  >  (modes melange))
  > EOF

  $ touch bar.ml $lib.ml
  $ dune build @check
  $ dune ocaml merlin dump-config "$PWD" | grep -i "$lib"
  Foo
    $TESTCASE_ROOT/_build/default/.foo.objs/melange)
     Foo__
    $TESTCASE_ROOT/_build/default/.foo.objs/melange)
     Foo__
  Foo__
    $TESTCASE_ROOT/_build/default/.foo.objs/melange)
     Foo__

All 3 entries (Foo, Foo__ and Bar) contain a ppx directive

  $ dune ocaml merlin dump-config $PWD | grep -i "ppx"
   (FLG (-ppx "melc -as-ppx -bs-jsx 3"))
   (FLG (-ppx "melc -as-ppx -bs-jsx 3"))
   (FLG (-ppx "melc -as-ppx -bs-jsx 3"))

  $ target=output
  $ cat >dune <<EOF
  > (melange.emit
  >  (target "$target")
  >  (entries main)
  >  (module_system commonjs))
  > EOF

  $ touch main.ml
  $ dune build @check
  $ dune ocaml merlin dump-config $PWD | grep -i "$target"
    $TESTCASE_ROOT/_build/default/.output.mobjs/melange)

The melange.emit entry contains a ppx directive

  $ dune ocaml merlin dump-config $PWD | grep -i "ppx"
   (FLG (-ppx "melc -as-ppx -bs-jsx 3"))
