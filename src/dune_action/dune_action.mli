(** Monadic interface for *)

module Protocol = Protocol
module Path = Path

(* TODO jstaron: Add module documentation. *)

type 'a t

(** [return a] creates a pure computation resulting in [a]. *)
val return : 'a -> 'a t

(** If [at] is computation resulting in [a] then [map at ~f] is a computation
  resulting in [f a]. *)
val map : 'a t -> f:('a -> 'b) -> 'b t

(** If [at] is computation resulting in [a] and [ab] is computation resulting
  in [b] then [both at bt] is a computation resulting in [(a, b)]. *)
val both : 'a t -> 'b t -> ('a * 'b) t

val stage : 'a t -> f:('a -> 'b t) -> 'b t

(** [read_file ~path:file] returns a computation depending on a [file] to be
  run and resulting in a file content. *)
val read_file : path:Path.t -> string t

(** [write_file ~path:file ~data] returns a computation that writes [data] to a
  [file].

    Note: [file] must be declared as a target in dune build file. *)
val write_file : path:Path.t -> data:string -> unit t

(* TODO jstaron: If program tries to read empty directory, dune does not copy
  it to `_build` so we get a "No such file or directory" error. *)

(** [read_directory ~path:directory] returns a computation depending on a
  listing of a [directory] and all source and target files contained in that
    directory. Computation will result in a directory listing. *)
val read_directory : path:Path.t -> string list t

(** Runs the computation. This function never returns. *)
val run : unit t -> 'a

(*_ See the Jane Street Style Guide for an explanation of [Private] submodules:
  https://opensource.janestreet.com/standards/#private-submodules *)
module Private : sig
  val do_run : unit t -> unit

  module Execution_error : sig
    exception E of string
  end
end
