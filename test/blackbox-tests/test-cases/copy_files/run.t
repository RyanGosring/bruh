  $ dune build --root test1 test.exe .merlin --display short --debug-dependency-path
  Entering directory 'test1'
      ocamldep .foo.objs/dummy.ml.d
        ocamlc bar$ext_obj
      ocamllex lexers/lexer1.ml
      ocamldep .test.eobjs/test.ml.d
        ocamlc .foo.objs/byte/dummy.{cmi,cmo,cmt}
    ocamlmklib dllfoo_stubs$ext_dll,libfoo_stubs$ext_lib
      ocamldep .test.eobjs/lexer1.ml.d
      ocamlopt .foo.objs/native/dummy.{cmx,o}
      ocamlopt foo.{a,cmxa}
        ocamlc .test.eobjs/byte/lexer1.{cmi,cmo,cmt}
        ocamlc .test.eobjs/byte/test.{cmi,cmo,cmt}
      ocamlopt .test.eobjs/native/lexer1.{cmx,o}
      ocamlopt .test.eobjs/native/test.{cmx,o}
      ocamlopt test.exe
  $ dune build --root test1 @bar-source --display short
  Entering directory 'test1'
  #line 1 "include/bar.h"
  int foo () {return 42;}
  $ dune build --root test2 @foo/cat
  Entering directory 'test2'
  # 1 "dummy.txt"
  hello
