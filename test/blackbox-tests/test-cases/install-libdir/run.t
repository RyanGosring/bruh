`dune install` should handle destination directories that don't exist

  $ dune build @install
  $ dune install --prefix install --libdir lib
  Installing install/lib/foo/META
  Installing install/lib/foo/foo$ext_lib
  Installing install/lib/foo/foo.cma
  Installing install/lib/foo/foo.cmi
  Installing install/lib/foo/foo.cmt
  Installing install/lib/foo/foo.cmx
  Installing install/lib/foo/foo.cmxa
  Installing install/lib/foo/foo.cmxs
  Installing install/lib/foo/foo.dune
  Installing install/lib/foo/foo.ml
  Installing install/lib/foo/opam
  Installing install/bin/exec

If prefix is passed, the default for libdir is `$prefix/lib`:

  $ dune install --prefix install --dry-run
  Installing install/lib/foo/META
  Installing install/lib/foo/foo$ext_lib
  Installing install/lib/foo/foo.cma
  Installing install/lib/foo/foo.cmi
  Installing install/lib/foo/foo.cmt
  Installing install/lib/foo/foo.cmx
  Installing install/lib/foo/foo.cmxa
  Installing install/lib/foo/foo.cmxs
  Installing install/lib/foo/foo.dune
  Installing install/lib/foo/foo.ml
  Installing install/lib/foo/opam
  Installing install/bin/exec
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/META to install/lib/foo/META (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo$ext_lib to install/lib/foo/foo$ext_lib (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.cma to install/lib/foo/foo.cma (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.cmi to install/lib/foo/foo.cmi (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.cmt to install/lib/foo/foo.cmt (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.cmx to install/lib/foo/foo.cmx (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.cmxa to install/lib/foo/foo.cmxa (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.cmxs to install/lib/foo/foo.cmxs (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.dune to install/lib/foo/foo.dune (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/foo.ml to install/lib/foo/foo.ml (executable: false)
  Creating directory install/lib/foo
  Copying _build/install/default/lib/foo/opam to install/lib/foo/opam (executable: false)
  Creating directory install/bin
  Copying _build/install/default/bin/exec to install/bin/exec (executable: true)

If prefix is not passed, libdir defaults to the output of `ocamlfind printconf
destdir`:

  $ export OCAMLFIND_DESTDIR=/OCAMLFIND_DESTDIR; dune install --dry-run 2>&1 | sed "s#$(opam config var prefix)#OPAM_VAR_PREFIX#" ; dune uninstall --dry-run 2>&1 | sed "s#$(opam config var prefix)#OPAM_VAR_PREFIX#"
  Installing /OCAMLFIND_DESTDIR/foo/META
  Installing /OCAMLFIND_DESTDIR/foo/foo$ext_lib
  Installing /OCAMLFIND_DESTDIR/foo/foo.cma
  Installing /OCAMLFIND_DESTDIR/foo/foo.cmi
  Installing /OCAMLFIND_DESTDIR/foo/foo.cmt
  Installing /OCAMLFIND_DESTDIR/foo/foo.cmx
  Installing /OCAMLFIND_DESTDIR/foo/foo.cmxa
  Installing /OCAMLFIND_DESTDIR/foo/foo.cmxs
  Installing /OCAMLFIND_DESTDIR/foo/foo.dune
  Installing /OCAMLFIND_DESTDIR/foo/foo.ml
  Installing /OCAMLFIND_DESTDIR/foo/opam
  Installing OPAM_VAR_PREFIX/bin/exec
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/META to /OCAMLFIND_DESTDIR/foo/META (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo$ext_lib to /OCAMLFIND_DESTDIR/foo/foo$ext_lib (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.cma to /OCAMLFIND_DESTDIR/foo/foo.cma (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.cmi to /OCAMLFIND_DESTDIR/foo/foo.cmi (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.cmt to /OCAMLFIND_DESTDIR/foo/foo.cmt (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.cmx to /OCAMLFIND_DESTDIR/foo/foo.cmx (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.cmxa to /OCAMLFIND_DESTDIR/foo/foo.cmxa (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.cmxs to /OCAMLFIND_DESTDIR/foo/foo.cmxs (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.dune to /OCAMLFIND_DESTDIR/foo/foo.dune (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/foo.ml to /OCAMLFIND_DESTDIR/foo/foo.ml (executable: false)
  Creating directory /OCAMLFIND_DESTDIR/foo
  Copying _build/install/default/lib/foo/opam to /OCAMLFIND_DESTDIR/foo/opam (executable: false)
  Creating directory OPAM_VAR_PREFIX/bin
  Copying _build/install/default/bin/exec to OPAM_VAR_PREFIX/bin/exec (executable: true)
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/META
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo$ext_lib
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.cma
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.cmi
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.cmt
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.cmx
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.cmxa
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.cmxs
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.dune
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/foo.ml
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) /OCAMLFIND_DESTDIR/foo/opam
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo
  Removing (if it exists) OPAM_VAR_PREFIX/bin/exec
  Removing directory (if empty) OPAM_VAR_PREFIX/bin
  Removing directory (if empty) /OCAMLFIND_DESTDIR/foo

If only libdir is passed, binaries are installed under prefix/bin and libraries
in libdir:

  $ dune install --libdir /LIBDIR --dry-run 2>&1 | sed "s#$(opam config var prefix)#OPAM_VAR_PREFIX#" ; dune uninstall --libdir /LIBDIR --dry-run 2>&1 | sed "s#$(opam config var prefix)#OPAM_VAR_PREFIX#"
  Installing /LIBDIR/foo/META
  Installing /LIBDIR/foo/foo$ext_lib
  Installing /LIBDIR/foo/foo.cma
  Installing /LIBDIR/foo/foo.cmi
  Installing /LIBDIR/foo/foo.cmt
  Installing /LIBDIR/foo/foo.cmx
  Installing /LIBDIR/foo/foo.cmxa
  Installing /LIBDIR/foo/foo.cmxs
  Installing /LIBDIR/foo/foo.dune
  Installing /LIBDIR/foo/foo.ml
  Installing /LIBDIR/foo/opam
  Installing OPAM_VAR_PREFIX/bin/exec
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/META to /LIBDIR/foo/META (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo$ext_lib to /LIBDIR/foo/foo$ext_lib (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.cma to /LIBDIR/foo/foo.cma (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.cmi to /LIBDIR/foo/foo.cmi (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.cmt to /LIBDIR/foo/foo.cmt (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.cmx to /LIBDIR/foo/foo.cmx (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.cmxa to /LIBDIR/foo/foo.cmxa (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.cmxs to /LIBDIR/foo/foo.cmxs (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.dune to /LIBDIR/foo/foo.dune (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/foo.ml to /LIBDIR/foo/foo.ml (executable: false)
  Creating directory /LIBDIR/foo
  Copying _build/install/default/lib/foo/opam to /LIBDIR/foo/opam (executable: false)
  Creating directory OPAM_VAR_PREFIX/bin
  Copying _build/install/default/bin/exec to OPAM_VAR_PREFIX/bin/exec (executable: true)
  Removing (if it exists) /LIBDIR/foo/META
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo$ext_lib
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.cma
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.cmi
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.cmt
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.cmx
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.cmxa
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.cmxs
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.dune
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/foo.ml
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) /LIBDIR/foo/opam
  Removing directory (if empty) /LIBDIR/foo
  Removing (if it exists) OPAM_VAR_PREFIX/bin/exec
  Removing directory (if empty) OPAM_VAR_PREFIX/bin
  Removing directory (if empty) /LIBDIR/foo
