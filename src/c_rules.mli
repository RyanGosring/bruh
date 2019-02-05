open Stdune

module Gen (S : sig val sctx : Super_context.t end) : sig
  val build_o_files
    :  c_sources:C.Sources.t
    -> c_flags:Ordered_set_lang.Unexpanded.t C.Kind.Dict.t
    -> dir:Path.t
    -> expander:Expander.t
    -> requires:Lib.L.t Or_exn.t
    -> dir_contents:Dir_contents.t
    -> Path.t list
end
