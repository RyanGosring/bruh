The dune cache should be enabled by 'default'
(not by default on main branch since it's a feature flag)
  $ export DUNE_CACHE=enabled
  $ echo "(lang dune 3.16)" > dune-project

  $ cat > dune << EOF
  > (library
  >  (name foo))
  > EOF

  $ cat > foo.ml << EOF
  > let f x y = x + y
  > EOF

Set up cache directory
  $ export DUNE_CACHE_ROOT=$(pwd)/dune_test_cache
  $ mkdir $DUNE_CACHE_ROOT

  $ DUNE_CACHE=disabled dune build
  $ ls $DUNE_CACHE_ROOT
We have not written anything to the cache yet.

Change source files to force a recompilation
  $ cat > foo.ml << EOF
  > let f x y = x - y
  > EOF

  $ dune build
  $ ls $DUNE_CACHE_ROOT
  files
  meta
  temp
  values
Cache has been written to!
