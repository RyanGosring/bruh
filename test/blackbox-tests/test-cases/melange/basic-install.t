# Test that .cmxs are installed with the executable bit set

  $ cat >dune-project <<EOF
  > (lang dune 3.6)
  > (package (name foo))
  > (using melange 0.1)
  > EOF
  $ cat >dune <<EOF
  > (library
  >  (modes melange)
  >  (public_name foo))
  > EOF

  $ cat >foo.ml <<EOF
  > let x = "foo"
  > EOF

  $ dune build @install
  $ cat ./_build/default/foo.install
  lib: [
    "_build/install/default/lib/foo/META"
    "_build/install/default/lib/foo/dune-package"
    "_build/install/default/lib/foo/foo.ml"
    "_build/install/default/lib/foo/melange/foo.cmi" {"melange/foo.cmi"}
    "_build/install/default/lib/foo/melange/foo.cmj" {"melange/foo.cmj"}
    "_build/install/default/lib/foo/melange/foo.cmt" {"melange/foo.cmt"}
  ]

  $ cat ./_build/install/default/lib/foo/dune-package
  (lang dune 3.7)
  (name foo)
  (sections (lib .))
  (files
   (lib
    (META dune-package foo.ml melange/foo.cmi melange/foo.cmj melange/foo.cmt)))
  (library
   (name foo)
   (kind normal)
   (main_module_name Foo)
   (modules (singleton (name Foo) (obj_name foo) (visibility public) (impl))))

