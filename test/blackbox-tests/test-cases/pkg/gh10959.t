Repro `dune exec --watch` crash with pkg management

  $ . ./helpers.sh

  $ mkrepo
  $ add_mock_repo_if_needed


  $ mkdir _multiple
  $ cat >_multiple/dune-project <<EOF
  > (lang dune 3.13)
  > (package (name foo) (allow_empty))
  > (package (name bar) (allow_empty))
  > EOF

  $ cat >dune-project <<EOF
  > (lang dune 3.13)
  > (pin
  >  (url file://$PWD/_multiple)
  >  (package (name foo))
  >  (package (name bar)))
  > (package
  >  (name main)
  >  (depends foo bar))
  > EOF

  $ cat >dune <<EOF
  > (executable
  >  (name x))
  > EOF
  $ cat >x.ml <<EOF
  > let () = print_endline "x"
  > EOF

  $ dune pkg lock
  Solution for dune.lock:
  - bar.dev
  - foo.dev

  $ dune exec -w ./x.exe 2>&1 | grep -io "I must not crash"
  I must not crash

