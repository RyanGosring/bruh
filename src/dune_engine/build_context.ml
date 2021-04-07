open! Stdune
open! Import

type t =
  { name : Context_name.t
  ; build_dir : Path.Build.t
  ; host : t option
  }

let create ~name ~build_dir ~host = { name; build_dir; host }
