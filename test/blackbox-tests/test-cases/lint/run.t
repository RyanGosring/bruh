The lint alias will run preprocessing actions listed under (lint):

  $ dune build @detect/lint
           ppx alias detect/lint
  File "detect/add.ml", line 1, characters 33-38:
  This addition can be done statically.

When using ppxlib, it is possible to define and promote corrections:

  $ cat correct/add.ml
  $ cat _build/default/correct/add.ml
  $ cp correct/add.ml.orig correct/add.ml
  $ dune build @correct/lint
  File "correct/add.ml", line 1, characters 0-0:
  Files _build/default/correct/add.ml and _build/default/correct/add.ml.lint-corrected differ.
  [1]
  $ dune promote correct/add.ml
  Promoting _build/default/correct/add.ml.lint-corrected to correct/add.ml.
  $ cat correct/add.ml
  let () = Printf.printf "%d\n" @@ 3


  $ ./_build/default/.ppx/6d75c4ca276fcac46c7d8bcae4c17f1d/ppx.exe -impl correct/add.ml.orig
