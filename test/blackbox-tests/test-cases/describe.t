Test for the `dune describe` command
====================================

Setup
-----

  $ cat >dune-project <<EOF
  > (lang dune 2.3)
  > (package
  >  (name foo)
  >  (synopsis "foo bar baz"))
  > (generate_opam_files)
  > EOF

  $ cat >dune <<EOF
  > (library
  >  (name dummy_ppx)
  >  (kind ppx_rewriter)
  >  (libraries ppxlib)
  >  (modules dummy_ppx))
  > 
  > (library
  >  (public_name foo)
  >  (libraries foo.x)
  >  (modules foo))
  > 
  > (library
  >  (name foo_x)
  >  (public_name foo.x)
  >  (modules foo_x))
  > 
  > (executable
  >  (name main)
  >  (libraries foo_x foo)
  >  (modules main))
  > 
  > (library
  >  (name bar)
  >  (preprocess (pps dummy_ppx))
  >  (modules bar bar2))
  > 
  > (executable
  >  (name main2)
  >  (libraries foo_x foo)
  >  (modules main2 main2_aux1 main2_aux2 main2_aux3 main2_aux4)
  >  (modules_without_implementation main2_aux4))
  > 
  > (executable
  >   (name main3)
  >   (libraries cmdliner)
  >   (modules main3))
  > 
  > (library
  >  (name per_module_pp_lib)
  >  (modules pp1 pp2)
  >  (preprocess (per_module ((pps dummy_ppx) pp2))))
  > 
  > (executable
  >  (name per_module_pp_exe)
  >  (modules per_module_pp_exe pp3 pp4)
  >  (preprocess (per_module ((pps dummy_ppx) pp4))))
  > 
  > (library
  >  (name per_module_action_lib)
  >  (modules action1 action2)
  >  (preprocess (per_module ((action (cat %{input-file})) action2))))
  > 
  > (library
  >  (name per_module_action_exe)
  >  (modules per_module_action_exe action3 action4)
  >  (preprocess (per_module ((action (cat %{input-file})) action4))))
  > EOF

  $ cat >dummy_ppx.ml <<EOF
  > (* dummy PPX rewriter, for use in tests *)
  > let () =
  >   Ppxlib.Driver.register_transformation
  >     "dummy"
  >     ~impl:(fun s -> s)
  > EOF

  $ touch foo.ml
  $ touch foo_x.ml
  $ touch main.ml

  $ cat >bar.ml <<EOF
  > let x = Bar2.x
  > let%dummy _ = (x = 42)
  > EOF

  $ cat >bar2.ml <<EOF
  > let x = 42
  > EOF

  $ cat >main2.ml <<EOF
  > let x = Main2_aux1.x
  > EOF

  $ cat >main2_aux1.ml <<EOF
  > let x = Main2_aux2.x
  > let y : Main2_aux4.t = Main2_aux2.x
  > EOF

  $ cat >main2_aux1.mli <<EOF
  > val x: Main2_aux3.t
  > val y: Main2_aux4.t
  > EOF

  $ cat >main2_aux2.ml <<EOF
  > let x = 0
  > EOF

  $ cat >main2_aux3.ml <<EOF
  > type t = int
  > EOF

  $ cat >main2_aux3.mli <<EOF
  > type t = int
  > EOF

  $ cat >main2_aux4.mli <<EOF
  > type t = int
  > EOF

  $ touch main3.ml

  $ cat >pp1.ml <<EOF
  > let x = 0
  > EOF

  $ cat >pp2.ml <<EOF
  > let%dummy _ = (Pp1.x = 0)
  > let y = 0
  > EOF

  $ cat >pp4.ml <<EOF
  > type t =
  > | Foo
  > | Bar of bool
  > [@@deriving enumerate]
  > EOF

  $ cat >pp3.ml <<EOF
  > let foo = Pp4.foo
  > EOF

  $ cat >per_module_pp_exe.ml <<EOF
  > let () = assert (List.mem Pp3.foo Pp4.all)
  > EOF

  $ cat >action1.ml <<EOF
  > let x = 0
  > EOF

  $ cat >action2.ml <<EOF
  > let y = Action1.x
  > EOF

  $ cp action1.ml action3.ml
  $ cp action2.ml action4.ml
  $ cat >per_module_action_exe.ml <<EOF
  > let () = assert (Action3.x = Action4.y)
  > EOF

Describe various things
-----------------------

Warning: when testing the ``dune describe workspace`` command, do not
forget to pass the ``--sanitize-for-tests`` flags, so that the tests
are reproducible, and are kept consistent between different machines.
``dune describe workspace`` may indeed print absolute paths, that are
not stable across different setups.

  $ dune describe workspace --lang 0.1 --sanitize-for-tests
  ((executables
    ((names (main))
     (requires
      (c17373aee51bab94097b4b7818553cf3 5dd4bd87ad37b4f5713085aff4bee9c9))
     (modules
      (((name Main)
        (impl (_build/default/main.ml))
        (intf ())
        (cmt (_build/default/.main.eobjs/byte/dune__exe__Main.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.main.eobjs/byte))))
   (executables
    ((names (main2))
     (requires
      (c17373aee51bab94097b4b7818553cf3 5dd4bd87ad37b4f5713085aff4bee9c9))
     (modules
      (((name Main2_aux4)
        (impl ())
        (intf (_build/default/main2_aux4.mli))
        (cmt ())
        (cmti (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux4.cmti)))
       ((name Main2_aux3)
        (impl (_build/default/main2_aux3.ml))
        (intf (_build/default/main2_aux3.mli))
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux3.cmt))
        (cmti (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux3.cmti)))
       ((name Main2_aux2)
        (impl (_build/default/main2_aux2.ml))
        (intf ())
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux2.cmt))
        (cmti ()))
       ((name Main2_aux1)
        (impl (_build/default/main2_aux1.ml))
        (intf (_build/default/main2_aux1.mli))
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux1.cmt))
        (cmti (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux1.cmti)))
       ((name Main2)
        (impl (_build/default/main2.ml))
        (intf ())
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2.cmt))
        (cmti ()))
       ((name Dune__exe)
        (impl (_build/default/.main2.eobjs/dune__exe.ml-gen))
        (intf ())
        (cmt (_build/default/.main2.eobjs/byte/dune__exe.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.main2.eobjs/byte))))
   (executables
    ((names (main3))
     (requires (c480a7c584d174c22d86dbdb79515d7d))
     (modules
      (((name Main3)
        (impl (_build/default/main3.ml))
        (intf ())
        (cmt (_build/default/.main3.eobjs/byte/dune__exe__Main3.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.main3.eobjs/byte))))
   (executables
    ((names (per_module_pp_exe))
     (requires ())
     (modules
      (((name Pp4)
        (impl (_build/default/pp4.ml))
        (intf ())
        (cmt (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe__Pp4.cmt))
        (cmti ()))
       ((name Pp3)
        (impl (_build/default/pp3.ml))
        (intf ())
        (cmt (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe__Pp3.cmt))
        (cmti ()))
       ((name Per_module_pp_exe)
        (impl (_build/default/per_module_pp_exe.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe__Per_module_pp_exe.cmt))
        (cmti ()))
       ((name Dune__exe)
        (impl (_build/default/.per_module_pp_exe.eobjs/dune__exe.ml-gen))
        (intf ())
        (cmt (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.per_module_pp_exe.eobjs/byte))))
   (library
    ((name bar)
     (uid 97586d5adea44246d88d31b0f6e340ed)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Bar2)
        (impl (_build/default/bar2.ml))
        (intf ())
        (cmt (_build/default/.bar.objs/byte/bar__Bar2.cmt))
        (cmti ()))
       ((name Bar)
        (impl (_build/default/bar.ml))
        (intf ())
        (cmt (_build/default/.bar.objs/byte/bar.cmt))
        (cmti ()))
       ((name Bar__)
        (impl (_build/default/bar__.ml-gen))
        (intf ())
        (cmt (_build/default/.bar.objs/byte/bar__.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.bar.objs/byte))))
   (library
    ((name cmdliner)
     (uid c480a7c584d174c22d86dbdb79515d7d)
     (local false)
     (requires ())
     (source_dir /FINDLIB//cmdliner)
     (modules ())
     (include_dirs (/FINDLIB//cmdliner))))
   (library
    ((name compiler-libs.common)
     (uid c9367091ddd9a70d99fc22ede348f17c)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ocaml/compiler-libs)
     (modules ())
     (include_dirs (/FINDLIB//ocaml/compiler-libs))))
   (library
    ((name dummy_ppx)
     (uid 8773da23dc506fbda63b4ff411075fb9)
     (local true)
     (requires
      (ba85adfb1c97e7d7af3df35b16b2fc0d 2c61db8e94cb08e0fe642152aee8121a))
     (source_dir _build/default)
     (modules
      (((name Dummy_ppx)
        (impl (_build/default/dummy_ppx.ml))
        (intf ())
        (cmt (_build/default/.dummy_ppx.objs/byte/dummy_ppx.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.dummy_ppx.objs/byte))))
   (library
    ((name foo)
     (uid 5dd4bd87ad37b4f5713085aff4bee9c9)
     (local true)
     (requires (c17373aee51bab94097b4b7818553cf3))
     (source_dir _build/default)
     (modules
      (((name Foo)
        (impl (_build/default/foo.ml))
        (intf ())
        (cmt (_build/default/.foo.objs/byte/foo.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.foo.objs/byte))))
   (library
    ((name foo.x)
     (uid c17373aee51bab94097b4b7818553cf3)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Foo_x)
        (impl (_build/default/foo_x.ml))
        (intf ())
        (cmt (_build/default/.foo_x.objs/byte/foo_x.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.foo_x.objs/byte))))
   (library
    ((name ocaml-compiler-libs.common)
     (uid 1f2b5eb300ea716920494385a31bb5fb)
     (local false)
     (requires (c9367091ddd9a70d99fc22ede348f17c))
     (source_dir /FINDLIB//ocaml-compiler-libs/common)
     (modules ())
     (include_dirs (/FINDLIB//ocaml-compiler-libs/common))))
   (library
    ((name ocaml-compiler-libs.shadow)
     (uid 2363fd46dac995a1c79679dfa1a9881b)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ocaml-compiler-libs/shadow)
     (modules ())
     (include_dirs (/FINDLIB//ocaml-compiler-libs/shadow))))
   (library
    ((name per_module_action_exe)
     (uid 241344d239919555633eb26a01215e22)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Per_module_action_exe)
        (impl (_build/default/per_module_action_exe.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe.cmt))
        (cmti ()))
       ((name Action4)
        (impl (_build/default/action4.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe__Action4.cmt))
        (cmti ()))
       ((name Action3)
        (impl (_build/default/action3.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe__Action3.cmt))
        (cmti ()))
       ((name Per_module_action_exe__)
        (impl (_build/default/per_module_action_exe__.ml-gen))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe__.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.per_module_action_exe.objs/byte))))
   (library
    ((name per_module_action_lib)
     (uid a8434281597a2d5c0db820319d93c1f7)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Action2)
        (impl (_build/default/action2.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_lib.objs/byte/per_module_action_lib__Action2.cmt))
        (cmti ()))
       ((name Action1)
        (impl (_build/default/action1.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_lib.objs/byte/per_module_action_lib__Action1.cmt))
        (cmti ()))
       ((name Per_module_action_lib)
        (impl (_build/default/per_module_action_lib.ml-gen))
        (intf ())
        (cmt
         (_build/default/.per_module_action_lib.objs/byte/per_module_action_lib.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.per_module_action_lib.objs/byte))))
   (library
    ((name per_module_pp_lib)
     (uid 7fc36e5c5f46521a6842f4167e4c75b2)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Pp2)
        (impl (_build/default/pp2.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_lib.objs/byte/per_module_pp_lib__Pp2.cmt))
        (cmti ()))
       ((name Pp1)
        (impl (_build/default/pp1.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_lib.objs/byte/per_module_pp_lib__Pp1.cmt))
        (cmti ()))
       ((name Per_module_pp_lib)
        (impl (_build/default/per_module_pp_lib.ml-gen))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_lib.objs/byte/per_module_pp_lib.cmt))
        (cmti ()))))
     (include_dirs (_build/default/.per_module_pp_lib.objs/byte))))
   (library
    ((name ppx_derivers)
     (uid e68a558facd1546b51c7abdbf6aed1cb)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ppx_derivers)
     (modules ())
     (include_dirs (/FINDLIB//ppx_derivers))))
   (library
    ((name ppxlib)
     (uid 2c61db8e94cb08e0fe642152aee8121a)
     (local false)
     (requires
      (ba85adfb1c97e7d7af3df35b16b2fc0d
       2363fd46dac995a1c79679dfa1a9881b
       5014e215e204cf8da6c32644cda1b31e
       43b7cbe1f93f4f502ec614971027cff9
       e68a558facd1546b51c7abdbf6aed1cb
       24f4eb12e3ff51b310dbf7443c6087be
       5ae836dcdead11d5c16815297c5a1ae6
       249b2edaf3cc552a247667041bb5f015
       449445be7a24ce51e119d57e9e255d3f))
     (source_dir /FINDLIB//ppxlib)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib))))
   (library
    ((name ppxlib.ast)
     (uid ba85adfb1c97e7d7af3df35b16b2fc0d)
     (local false)
     (requires
      (5014e215e204cf8da6c32644cda1b31e 249b2edaf3cc552a247667041bb5f015))
     (source_dir /FINDLIB//ppxlib/ast)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/ast))))
   (library
    ((name ppxlib.astlib)
     (uid 5014e215e204cf8da6c32644cda1b31e)
     (local false)
     (requires
      (1f2b5eb300ea716920494385a31bb5fb c9367091ddd9a70d99fc22ede348f17c))
     (source_dir /FINDLIB//ppxlib/astlib)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/astlib))))
   (library
    ((name ppxlib.print_diff)
     (uid 43b7cbe1f93f4f502ec614971027cff9)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ppxlib/print_diff)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/print_diff))))
   (library
    ((name ppxlib.stdppx)
     (uid 5ae836dcdead11d5c16815297c5a1ae6)
     (local false)
     (requires
      (449445be7a24ce51e119d57e9e255d3f 249b2edaf3cc552a247667041bb5f015))
     (source_dir /FINDLIB//ppxlib/stdppx)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/stdppx))))
   (library
    ((name ppxlib.traverse_builtins)
     (uid 24f4eb12e3ff51b310dbf7443c6087be)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ppxlib/traverse_builtins)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/traverse_builtins))))
   (library
    ((name sexplib0)
     (uid 449445be7a24ce51e119d57e9e255d3f)
     (local false)
     (requires ())
     (source_dir /FINDLIB//sexplib0)
     (modules ())
     (include_dirs (/FINDLIB//sexplib0))))
   (library
    ((name stdlib-shims)
     (uid 249b2edaf3cc552a247667041bb5f015)
     (local false)
     (requires ())
     (source_dir /FINDLIB//stdlib-shims)
     (modules ())
     (include_dirs (/FINDLIB//stdlib-shims)))))

  $ dune describe workspace --lang 0.1 --with-deps --sanitize-for-tests
  ((executables
    ((names (main))
     (requires
      (c17373aee51bab94097b4b7818553cf3 5dd4bd87ad37b4f5713085aff4bee9c9))
     (modules
      (((name Main)
        (impl (_build/default/main.ml))
        (intf ())
        (cmt (_build/default/.main.eobjs/byte/dune__exe__Main.cmt))
        (cmti ())
        (module_deps ((for_intf ()) (for_impl ()))))))
     (include_dirs (_build/default/.main.eobjs/byte))))
   (executables
    ((names (main2))
     (requires
      (c17373aee51bab94097b4b7818553cf3 5dd4bd87ad37b4f5713085aff4bee9c9))
     (modules
      (((name Main2_aux4)
        (impl ())
        (intf (_build/default/main2_aux4.mli))
        (cmt ())
        (cmti (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux4.cmti))
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Main2_aux3)
        (impl (_build/default/main2_aux3.ml))
        (intf (_build/default/main2_aux3.mli))
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux3.cmt))
        (cmti (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux3.cmti))
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Main2_aux2)
        (impl (_build/default/main2_aux2.ml))
        (intf ())
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux2.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Main2_aux1)
        (impl (_build/default/main2_aux1.ml))
        (intf (_build/default/main2_aux1.mli))
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux1.cmt))
        (cmti (_build/default/.main2.eobjs/byte/dune__exe__Main2_aux1.cmti))
        (module_deps
         ((for_intf
           (Main2_aux3 Main2_aux4))
          (for_impl
           (Main2_aux2 Main2_aux4)))))
       ((name Main2)
        (impl (_build/default/main2.ml))
        (intf ())
        (cmt (_build/default/.main2.eobjs/byte/dune__exe__Main2.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl (Main2_aux1)))))
       ((name Dune__exe)
        (impl (_build/default/.main2.eobjs/dune__exe.ml-gen))
        (intf ())
        (cmt (_build/default/.main2.eobjs/byte/dune__exe.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))))
     (include_dirs (_build/default/.main2.eobjs/byte))))
   (executables
    ((names (main3))
     (requires (c480a7c584d174c22d86dbdb79515d7d))
     (modules
      (((name Main3)
        (impl (_build/default/main3.ml))
        (intf ())
        (cmt (_build/default/.main3.eobjs/byte/dune__exe__Main3.cmt))
        (cmti ())
        (module_deps ((for_intf ()) (for_impl ()))))))
     (include_dirs (_build/default/.main3.eobjs/byte))))
   (executables
    ((names (per_module_pp_exe))
     (requires ())
     (modules
      (((name Pp4)
        (impl (_build/default/pp4.ml))
        (intf ())
        (cmt (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe__Pp4.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Pp3)
        (impl (_build/default/pp3.ml))
        (intf ())
        (cmt (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe__Pp3.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl (Pp4)))))
       ((name Per_module_pp_exe)
        (impl (_build/default/per_module_pp_exe.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe__Per_module_pp_exe.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl
           (Pp3 Pp4)))))
       ((name Dune__exe)
        (impl (_build/default/.per_module_pp_exe.eobjs/dune__exe.ml-gen))
        (intf ())
        (cmt (_build/default/.per_module_pp_exe.eobjs/byte/dune__exe.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))))
     (include_dirs (_build/default/.per_module_pp_exe.eobjs/byte))))
   (library
    ((name bar)
     (uid 97586d5adea44246d88d31b0f6e340ed)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Bar2)
        (impl (_build/default/bar2.ml))
        (intf ())
        (cmt (_build/default/.bar.objs/byte/bar__Bar2.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Bar)
        (impl (_build/default/bar.ml))
        (intf ())
        (cmt (_build/default/.bar.objs/byte/bar.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl (Bar2)))))
       ((name Bar__)
        (impl (_build/default/bar__.ml-gen))
        (intf ())
        (cmt (_build/default/.bar.objs/byte/bar__.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))))
     (include_dirs (_build/default/.bar.objs/byte))))
   (library
    ((name cmdliner)
     (uid c480a7c584d174c22d86dbdb79515d7d)
     (local false)
     (requires ())
     (source_dir /FINDLIB//cmdliner)
     (modules ())
     (include_dirs (/FINDLIB//cmdliner))))
   (library
    ((name compiler-libs.common)
     (uid c9367091ddd9a70d99fc22ede348f17c)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ocaml/compiler-libs)
     (modules ())
     (include_dirs (/FINDLIB//ocaml/compiler-libs))))
   (library
    ((name dummy_ppx)
     (uid 8773da23dc506fbda63b4ff411075fb9)
     (local true)
     (requires
      (ba85adfb1c97e7d7af3df35b16b2fc0d 2c61db8e94cb08e0fe642152aee8121a))
     (source_dir _build/default)
     (modules
      (((name Dummy_ppx)
        (impl (_build/default/dummy_ppx.ml))
        (intf ())
        (cmt (_build/default/.dummy_ppx.objs/byte/dummy_ppx.cmt))
        (cmti ())
        (module_deps ((for_intf ()) (for_impl ()))))))
     (include_dirs (_build/default/.dummy_ppx.objs/byte))))
   (library
    ((name foo)
     (uid 5dd4bd87ad37b4f5713085aff4bee9c9)
     (local true)
     (requires (c17373aee51bab94097b4b7818553cf3))
     (source_dir _build/default)
     (modules
      (((name Foo)
        (impl (_build/default/foo.ml))
        (intf ())
        (cmt (_build/default/.foo.objs/byte/foo.cmt))
        (cmti ())
        (module_deps ((for_intf ()) (for_impl ()))))))
     (include_dirs (_build/default/.foo.objs/byte))))
   (library
    ((name foo.x)
     (uid c17373aee51bab94097b4b7818553cf3)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Foo_x)
        (impl (_build/default/foo_x.ml))
        (intf ())
        (cmt (_build/default/.foo_x.objs/byte/foo_x.cmt))
        (cmti ())
        (module_deps ((for_intf ()) (for_impl ()))))))
     (include_dirs (_build/default/.foo_x.objs/byte))))
   (library
    ((name ocaml-compiler-libs.common)
     (uid 1f2b5eb300ea716920494385a31bb5fb)
     (local false)
     (requires (c9367091ddd9a70d99fc22ede348f17c))
     (source_dir /FINDLIB//ocaml-compiler-libs/common)
     (modules ())
     (include_dirs (/FINDLIB//ocaml-compiler-libs/common))))
   (library
    ((name ocaml-compiler-libs.shadow)
     (uid 2363fd46dac995a1c79679dfa1a9881b)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ocaml-compiler-libs/shadow)
     (modules ())
     (include_dirs (/FINDLIB//ocaml-compiler-libs/shadow))))
   (library
    ((name per_module_action_exe)
     (uid 241344d239919555633eb26a01215e22)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Per_module_action_exe)
        (impl (_build/default/per_module_action_exe.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl
           (Action3 Action4)))))
       ((name Action4)
        (impl (_build/default/action4.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe__Action4.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Action3)
        (impl (_build/default/action3.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe__Action3.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Per_module_action_exe__)
        (impl (_build/default/per_module_action_exe__.ml-gen))
        (intf ())
        (cmt
         (_build/default/.per_module_action_exe.objs/byte/per_module_action_exe__.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))))
     (include_dirs (_build/default/.per_module_action_exe.objs/byte))))
   (library
    ((name per_module_action_lib)
     (uid a8434281597a2d5c0db820319d93c1f7)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Action2)
        (impl (_build/default/action2.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_lib.objs/byte/per_module_action_lib__Action2.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl (Action1)))))
       ((name Action1)
        (impl (_build/default/action1.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_action_lib.objs/byte/per_module_action_lib__Action1.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Per_module_action_lib)
        (impl (_build/default/per_module_action_lib.ml-gen))
        (intf ())
        (cmt
         (_build/default/.per_module_action_lib.objs/byte/per_module_action_lib.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))))
     (include_dirs (_build/default/.per_module_action_lib.objs/byte))))
   (library
    ((name per_module_pp_lib)
     (uid 7fc36e5c5f46521a6842f4167e4c75b2)
     (local true)
     (requires ())
     (source_dir _build/default)
     (modules
      (((name Pp2)
        (impl (_build/default/pp2.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_lib.objs/byte/per_module_pp_lib__Pp2.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Pp1)
        (impl (_build/default/pp1.ml))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_lib.objs/byte/per_module_pp_lib__Pp1.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))
       ((name Per_module_pp_lib)
        (impl (_build/default/per_module_pp_lib.ml-gen))
        (intf ())
        (cmt
         (_build/default/.per_module_pp_lib.objs/byte/per_module_pp_lib.cmt))
        (cmti ())
        (module_deps
         ((for_intf ())
          (for_impl ()))))))
     (include_dirs (_build/default/.per_module_pp_lib.objs/byte))))
   (library
    ((name ppx_derivers)
     (uid e68a558facd1546b51c7abdbf6aed1cb)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ppx_derivers)
     (modules ())
     (include_dirs (/FINDLIB//ppx_derivers))))
   (library
    ((name ppxlib)
     (uid 2c61db8e94cb08e0fe642152aee8121a)
     (local false)
     (requires
      (ba85adfb1c97e7d7af3df35b16b2fc0d
       2363fd46dac995a1c79679dfa1a9881b
       5014e215e204cf8da6c32644cda1b31e
       43b7cbe1f93f4f502ec614971027cff9
       e68a558facd1546b51c7abdbf6aed1cb
       24f4eb12e3ff51b310dbf7443c6087be
       5ae836dcdead11d5c16815297c5a1ae6
       249b2edaf3cc552a247667041bb5f015
       449445be7a24ce51e119d57e9e255d3f))
     (source_dir /FINDLIB//ppxlib)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib))))
   (library
    ((name ppxlib.ast)
     (uid ba85adfb1c97e7d7af3df35b16b2fc0d)
     (local false)
     (requires
      (5014e215e204cf8da6c32644cda1b31e 249b2edaf3cc552a247667041bb5f015))
     (source_dir /FINDLIB//ppxlib/ast)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/ast))))
   (library
    ((name ppxlib.astlib)
     (uid 5014e215e204cf8da6c32644cda1b31e)
     (local false)
     (requires
      (1f2b5eb300ea716920494385a31bb5fb c9367091ddd9a70d99fc22ede348f17c))
     (source_dir /FINDLIB//ppxlib/astlib)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/astlib))))
   (library
    ((name ppxlib.print_diff)
     (uid 43b7cbe1f93f4f502ec614971027cff9)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ppxlib/print_diff)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/print_diff))))
   (library
    ((name ppxlib.stdppx)
     (uid 5ae836dcdead11d5c16815297c5a1ae6)
     (local false)
     (requires
      (449445be7a24ce51e119d57e9e255d3f 249b2edaf3cc552a247667041bb5f015))
     (source_dir /FINDLIB//ppxlib/stdppx)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/stdppx))))
   (library
    ((name ppxlib.traverse_builtins)
     (uid 24f4eb12e3ff51b310dbf7443c6087be)
     (local false)
     (requires ())
     (source_dir /FINDLIB//ppxlib/traverse_builtins)
     (modules ())
     (include_dirs (/FINDLIB//ppxlib/traverse_builtins))))
   (library
    ((name sexplib0)
     (uid 449445be7a24ce51e119d57e9e255d3f)
     (local false)
     (requires ())
     (source_dir /FINDLIB//sexplib0)
     (modules ())
     (include_dirs (/FINDLIB//sexplib0))))
   (library
    ((name stdlib-shims)
     (uid 249b2edaf3cc552a247667041bb5f015)
     (local false)
     (requires ())
     (source_dir /FINDLIB//stdlib-shims)
     (modules ())
     (include_dirs (/FINDLIB//stdlib-shims)))))


Test other formats
------------------

  $ dune describe workspace --format csexp --lang 0.1 --sanitize-for-tests | cut -c 1-85
  ((11:executables((5:names(4:main))(8:requires(32:c17373aee51bab94097b4b7818553cf332:5

Test errors
-----------

  $ dune describe --lang 0.1 workspac
  Error: Unknown constructor workspac
  Hint: did you mean workspace?
  [1]

  $ dune describe --lang 0.1 workspace xxx
  Error: Too many argument for workspace
  [1]

  $ dune describe --lang 1.0
  dune describe: Only --lang 0.1 is available at the moment as this command is not yet
                 stabilised. If you would like to release a software that relies on the output
                 of 'dune describe', please open a ticket on
                 https://github.com/ocaml/dune.
  Usage: dune describe [OPTION]... [STRING]...
  Try `dune describe --help' or `dune --help' for more information.
  [1]

opam file listing
-----------------

  $ dune describe --lang 0.1 opam-files | dune_cmd expand_lines
  ((foo.opam
    "# This file is generated by dune, edit dune-project instead
  opam-version: \"2.0\"
  synopsis: \"foo bar baz\"
  depends: [
    \"dune\" {>= \"2.3\"}
  ]
  build: [
    [\"dune\" \"subst\"] {pinned}
    [
      \"dune\"
      \"build\"
      \"-p\"
      name
      \"-j\"
      jobs
      \"@install\"
      \"@runtest\" {with-test}
      \"@doc\" {with-doc}
    ]
  ]
  "))
