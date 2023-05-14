(** Frontend the lock directory format *)

open Import
open Dune_lang

module Source : sig
  type t =
    | External_copy of Loc.t * Path.External.t
    | Fetch of
        { url : Loc.t * string
        ; checksum : (Loc.t * Checksum.t) option
        }
end

module Pkg_info : sig
  type t =
    { name : Package_name.t
    ; version : string
    ; dev : bool
    ; source : Source.t option
    }
end

module Env_update : sig
  type 'a t =
    { op : OpamParserTypes.env_update_op
    ; var : Env.Var.t
    ; value : 'a
    }

  val decode : String_with_vars.t t Dune_sexp.Decoder.t
end

module Pkg : sig
  type t =
    { build_command : Action.t option
    ; install_command : Action.t option
    ; deps : Package_name.t list
    ; info : Pkg_info.t
    ; lock_dir : Path.Source.t
    ; exported_env : String_with_vars.t Env_update.t list
    }

  val decode :
    (lock_dir:Path.Source.t -> Package_name.t -> t) Dune_sexp.Decoder.t
end

type t =
  { version : Syntax.Version.t
  ; packages : Pkg.t Package_name.Map.t
  }

val path : Path.Source.t

val metadata : Filename.t

module Metadata : Dune_sexp.Versioned_file.S with type data := unit
