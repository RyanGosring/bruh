  $ $JBUILDER exec -j1 ./qnativerun/run.exe --display short --root .
      ocamldep qnativerun/run.ml.d
        ocamlc q/q_stub.o
    ocamlmklib q/dllq_stubs.so,q/libq_stubs.a
      ocamldep q/q.ml.d
      ocamldep q/q.mli.d
        ocamlc q/.q.objs/q.{cmi,cmti}
        ocamlc qnativerun/.run.eobjs/run.{cmi,cmo,cmt}
      ocamlopt q/.q.objs/q.{cmx,o}
      ocamlopt qnativerun/.run.eobjs/run.{cmx,o}
      ocamlopt q/q.{a,cmxa}
      ocamlopt qnativerun/run.exe
  42
#  $ $JBUILDER exec -j1 ./qbyterun/run.bc --display short --root .
