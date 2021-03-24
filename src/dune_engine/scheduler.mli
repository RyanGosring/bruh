(** Scheduling *)

open! Import
open Stdune

module Config : sig
  module Display : sig
    type t =
      | Progress  (** Single interactive status line *)
      | Short  (** One line per command *)
      | Verbose  (** Display all commands fully *)
      | Quiet  (** Only display errors *)

    val all : (string * t) list

    val to_string : t -> string

    (** The console backend corresponding to the selected display mode *)
    val console_backend : t -> Console.Backend.t
  end

  module Rpc : sig
    type t =
      | Client
      | Server of
          { handler : Dune_rpc_server.t
          ; backlog : int
          }
  end

  type t =
    { concurrency : int
    ; display : Display.t
    ; rpc : Rpc.t option
    ; stats : Stats.t option
    }
end

module Run : sig
  module Event : sig
    type build_result =
      | Success
      | Failure

    type go = Tick

    type poll =
      | Go of go
      | Source_files_changed
      | Build_interrupted
      | Build_finish of build_result
  end

  (** Runs [once] in a loop, executing [finally] after every iteration, even if
      Fiber.Never was encountered.

      If any source files change in the middle of iteration, it gets canceled.

      If [shutdown] is called, the current build will be canceled and new builds
      will not start. *)
  val poll :
       Config.t
    -> on_event:(Config.t -> Event.poll -> unit)
    -> once:(unit -> [ `Continue | `Stop ] Fiber.t)
    -> finally:(unit -> unit)
    -> unit

  val go :
       Config.t
    -> on_event:(Config.t -> Event.go -> unit)
    -> (unit -> 'a Fiber.t)
    -> 'a
end

type t

(** Get the instance of the scheduler that runs the current fiber. *)
val t : unit -> t

(** [with_job_slot f] waits for one job slot (as per [-j <jobs] to become
    available and then calls [f]. *)
val with_job_slot : (Config.t -> 'a Fiber.t) -> 'a Fiber.t

(** Wait for the following process to terminate *)
val wait_for_process : Pid.t -> Unix.process_status Fiber.t

(** Wait for dune cache to be disconnected. Drop any other event. *)
val wait_for_dune_cache : unit -> unit

(** Make the scheduler ignore next change to a certain file in watch mode.

    This is used with promoted files that are copied back to the source tree
    after generation *)
val ignore_for_watch : Path.t -> unit

(** Number of jobs currently running in the background *)
val running_jobs_count : t -> int

(** Execute the given callback with current directory temporarily changed *)
val with_chdir : dir:Path.t -> f:(unit -> 'a) -> 'a

(** Send a task that will run in the scheduler thread *)
val send_sync_task : (unit -> unit) -> unit

(** Start the shutdown sequence. Among other things, it causes Dune to cancel
    the current build and stop accepting RPC clients. *)
val shutdown : unit -> unit Fiber.t

module Rpc : sig
  (** Rpc related functions *)

  (** [csexp_client path f] connects to [path] and calls [f] with the connected
      session.

      This is needed for implementing low level functions such as
      [$ dune rpc init] *)
  val csexp_client : Dune_rpc.Where.t -> Csexp_rpc.Client.t

  (** [csexp_connect i o] creates a session where requests are read from [i] and
      responses are written to [o].

      This is needed for implementing low level functions such as
      [$ dune rpc init] *)
  val csexp_connect : in_channel -> out_channel -> Csexp_rpc.Session.t

  val client :
       Dune_rpc.Where.t
    -> Dune_rpc.Initialize.Request.t
    -> on_notification:(Dune_rpc.Call.t -> unit Fiber.t)
    -> f:(Drpc_client.t -> 'a Fiber.t)
    -> 'a Fiber.t

  (** [add_to_env] Sets DUNE_RPC to the socket where rpc is listening *)
  val add_to_env : Env.t -> Env.t

  (** Stop accepting new rpc connections. Fiber returns when all existing
      connetions terminate *)
  val stop : unit -> unit Fiber.t
end
