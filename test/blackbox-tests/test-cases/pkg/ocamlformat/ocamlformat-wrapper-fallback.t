Exercise running the ocamlformat wrapper command outside of a dune
project.

Make a fake ocamlformat executable and add it to PATH.
  $ mkdir -p bin
  $ cat > bin/ocamlformat << EOF
  > #!/bin/sh
  > echo "Hello, World!"
  > EOF
  $ chmod a+x bin/ocamlformat
  $ export PATH=$PWD/bin:$PATH

This is necessary for dune to act as it normally would outside of a
dune workspace.
  $ unset INSIDE_DUNE

Run the wrapper command from a temporary directory. With INSIDE_DUNE
unset dune would otherwise pick up the dune project itself as the
current workspace.
  $ cd $(mktemp -d)
  $ dune tools exec ocamlformat --fallback=path-only
  Not in a dune project but ocamlformat appears to be installed. Dune will
  attempt to run ocamlformat from your PATH.
       Running '$TESTCASE_ROOT/bin/ocamlformat'
  Hello, World!
