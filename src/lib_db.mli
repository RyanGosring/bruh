(** Where libraries are

    This module is used to implement [Super_context.Libs].
*)

open Import

type t

val create
  :  Findlib.t
  -> dirs_with_dot_opam_files:Path.Set.t
  -> (Path.t * Jbuild.Library.t) list
  -> t

val find     : t -> from:Path.t -> string -> Lib.t option
val find_exn : t -> from:Path.t -> string -> Lib.t
val find_fail : t -> from:Path.t -> string -> (Lib.t,fail) result

val internal_libs_without_non_installable_optional_ones : t -> Lib.Internal.t list

val interpret_lib_deps
  :  t
  -> dir:Path.t
  -> Jbuild.Lib_dep.t list
  -> Lib.Internal.t list * Findlib.package list * fail option

type resolved_select =
  { src_fn : string
  ; dst_fn : string
  }

val resolve_selects
  :  t
  -> from:Path.t
  -> Jbuild.Lib_dep.t list
  -> resolved_select list

val lib_is_available : t -> from:Path.t -> string -> bool

(** For [Findlib.closure] *)
val local_public_libs : t -> Path.t String_map.t
