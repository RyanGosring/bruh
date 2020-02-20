open Stdune

(** Represents a valid OCaml module name *)
type t

val to_dyn : t -> Dyn.t

include Dune_lang.Conv.S with type t := t

val add_suffix : t -> string -> t

val compare : t -> t -> Ordering.t

val parse_string : string -> t option

val of_string : string -> t

val to_string : t -> string

val uncapitalize : t -> string

val pp_quote : Format.formatter -> t -> unit

module Per_item : Per_item.S with type key = t

module Infix : Comparator.OPS with type t = t

val of_local_lib_name : Lib_name.Local.t -> t

val to_local_lib_name : t -> Lib_name.Local.t

val decode : t Dune_lang.Decoder.t

module Unique : sig
  type name

  (** We use [Unique] module names for OCaml unit names. These must be unique
      across all libraries within a given linkage, so these names often involve
      mangling on top of the user-written names because the user-written names
      are only unique within a library.

      These are the names that are used for the .cmi and .cmx artifacts.

      Since [Unique] module names are sometimes mangled, they should not appear
      in any user-facing messages or configuration files. *)
  type nonrec t

  val of_string : string -> t

  val of_name_assuming_needs_no_mangling : name -> t

  val of_path_assuming_needs_no_mangling : Path.t -> t

  val to_dyn : t -> Dyn.t

  val to_name : t -> name

  val compare : t -> t -> Ordering.t

  val artifact_filename : t -> ext:string -> string

  include Dune_lang.Conv.S with type t := t

  module Map : Map.S with type key = t

  module Set : Set.S with type elt = t
end
with type name := t

val wrap : t -> with_:t -> Unique.t

module Map : Map.S with type key = t

module Set : sig
  include Set.S with type elt = t

  val to_dyn : t -> Dyn.t
end
