
  $ . ./helpers.sh
  $ mkrepo

  $ mkpkg ocaml <<EOF
  > EOF

  $ solve ocaml
  Solution for dune.lock:
  ocaml.0.0.1
  

  $ cat dune.lock/lock.dune
  (lang package 0.1)
  
  (ocaml ocaml)
  
  (repositories
   (complete false)
   (used))
  
  (solver_env
   (flags
    ("with-doc" "with-test"))
   (sys)
   (const
    (opam_version 2.2.0~alpha-vendored))
   (repositories default))
