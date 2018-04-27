This test define an installed "plop" with a "plop.ca-marche-pas"
sub-package which depend on a library that doesn't exist.

The build itself uses only "plop.ca-marche", which doesn't have this
problem. So jbuilder shouldn't crash because of "plop.ca-marche-pas"

We need ocamlfind to run this test

  $ jbuilder build @install --display short --only hello
        ocamlc root/.hello.objs/hello.{cmi,cmo,cmt}
      ocamlopt root/.hello.objs/hello.{cmx,$ext_obj}
      ocamlopt root/hello.{$ext_lib,cmxa}
      ocamlopt root/hello.cmxs
        ocamlc root/hello.cma

  $ jbuilder build @install --display short --only pas-de-bol 2>&1 | sed 's/[^ "]*findlib-packages/.../'
      ocamldep root/a.ml.d
  File ".../plop/META", line 1, characters 0-0:
  Error: Library "une-lib-qui-nexiste-pas" not found.
  -> required by library "plop.ca-marche-pas" in .../plop
  Hint: try: jbuilder external-lib-deps --missing --only-packages pas-de-bol @install
      ocamldep root/b.ml.d
        ocamlc root/.pas_de_bol.objs/pas_de_bol.{cmi,cmo,cmt}
      ocamlopt root/.pas_de_bol.objs/pas_de_bol.{cmx,$ext_obj}
