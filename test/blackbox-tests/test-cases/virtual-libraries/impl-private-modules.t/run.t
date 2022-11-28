They can only introduce private modules:
  $ dune build --debug-dependency-path
  Private module Baz
  implementing bar

Note the aliasing scheme for implementations differs form other libraries. In
particular, we use a longer prefix for private modules of implementations so
that they never collide with modules present in the virtual library.

  $ cat _build/default/impl/foo__foo_impl__.ml-gen
  (* generated by dune *)
  
  (** @canonical Foo.Bar *)
  module Bar = Foo__Bar
  
  (** @canonical Foo.Priv *)
  module Priv = Foo__foo_impl____Priv

Here we look at the raw artifacts for our implementation and verify it matches
the alias:

  $ ls _build/default/impl/.foo_impl.objs/byte/*.cmi
  _build/default/impl/.foo_impl.objs/byte/foo__Bar.cmi
  _build/default/impl/.foo_impl.objs/byte/foo__foo_impl__.cmi
  _build/default/impl/.foo_impl.objs/byte/foo__foo_impl____Priv.cmi
