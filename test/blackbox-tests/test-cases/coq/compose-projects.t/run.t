  $ unset DUNE_CACHE

Testing composition of theories accross a dune workspace
  $ dune build B
  Hello
       : Set

Inspecting the build directory
  $ ls _build/default/A/a.vo
  _build/default/A/a.vo
  $ ls _build/default/B/b.vo
  _build/default/B/b.vo
