open Stdune
open Dune_util

type t

val compare : t -> t -> Ordering.t
val equal : t -> t -> bool
val hash : t -> int

include Comparable_intf.S with type key := t
include Dune_sexp.Conv.S with type t := t
include Stringlike with type t := t

module Opam_compatible : sig
    (** A variant that enforces opam package name constraints: all characters are
        [[a-zA-Z0-9_+-]] with at least a letter. *)

    include Stringlike

    type package_name

    val to_package_name : t -> package_name
    val of_package_name_exn : package_name -> t
    val description_of_valid_string : _ Pp.t
    val make_valid : string -> string
    val equal : t -> t -> bool
    val to_dyn : t -> Dyn.t
    val compare : t -> t -> Ordering.t
    val hash : t -> int

    include Comparable_intf.S with type key := t
  end
  with type package_name := t

val is_opam_compatible : t -> bool
