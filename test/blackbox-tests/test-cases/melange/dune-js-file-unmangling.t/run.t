Test file unmangling with melange.emit that depends on a library, that depends on another library

  $ dune build @melange
  $ node _build/default/entry_module.js
  1
