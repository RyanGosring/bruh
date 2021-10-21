(** Creation and management of sandboxes *)

open Stdune

type t

val dir : t -> Path.Build.t

(** [map_path t p] returns the path corresponding to [p] inside the sandbox. *)
val map_path : t -> Path.Build.t -> Path.Build.t

val create :
     mode:Sandbox_mode.some
  -> deps:Dep.Facts.t
  -> rule_dir:Path.Build.t
  -> chdirs:Path.Set.t
  -> rule_digest:Digest.t
  -> expand_aliases:bool
  -> t

val move_targets_to_build_dir : t -> targets:Path.Build.Set.t -> unit

val destroy : t -> unit
