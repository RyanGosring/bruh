(** Findlib database *)

open Import

module Package_not_found : sig
  type t =
    { package     : string
    ; required_by : string list
    }
end

exception Package_not_found of Package_not_found.t

module External_dep_conflicts_with_local_lib : sig
  type t =
    { package             : string
    ; required_by         : string
    ; required_locally_in : Path.t
    ; defined_locally_in  : Path.t
    }
end

exception External_dep_conflicts_with_local_lib of External_dep_conflicts_with_local_lib.t

(** Findlib database *)
type t

val create
  :  stdlib_dir:Path.t
  -> path:Path.t list
  -> t

val path : t -> Path.t list

type package =
  { name             : string
  ; dir              : Path.t
  ; version          : string
  ; description      : string
  ; archives         : string list Mode.Dict.t
  ; plugins          : string list Mode.Dict.t
  ; jsoo_runtime     : string list
  ; requires         : package list
  ; ppx_runtime_deps : package list
  ; has_headers      : bool
  }

val find     : t -> required_by:string list -> string -> package option
val find_exn : t -> required_by:string list -> string -> package

val available : t -> required_by:string list -> string -> bool

val root_package_name : string -> string

(** [local_public_libs] is a map from public library names to where they are defined in
    the workspace. These must not appear as dependency of a findlib package *)
val closure
  :  required_by:Path.t
  -> local_public_libs:Path.t String_map.t
  -> package list
  -> package list
val closed_ppx_runtime_deps_of
  :  required_by:Path.t
  -> local_public_libs:Path.t String_map.t
  -> package list
  -> package list

val root_packages : t -> string list
val all_packages  : t -> package list

val stdlib_with_archives : t -> package
