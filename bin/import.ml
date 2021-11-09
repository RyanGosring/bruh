open Stdune
open Dune_engine
module Term = Cmdliner.Term
module Manpage = Cmdliner.Manpage
module Super_context = Dune_rules.Super_context
module Context = Dune_rules.Context
module Config = Dune_util.Config
module Local_install_path = Dune_engine.Local_install_path
module Lib_name = Dune_engine.Lib_name
module Build_system = Dune_engine.Build_system
module Findlib = Dune_rules.Findlib
module Package = Dune_engine.Package
module Dune_package = Dune_rules.Dune_package
module Hooks = Dune_engine.Hooks
module Action_builder = Dune_engine.Action_builder
module Action = Dune_engine.Action
module Dep = Dune_engine.Dep
module Action_to_sh = Dune_engine.Action_to_sh
module Dpath = Dune_engine.Dpath
module Install = Dune_engine.Install
module Section = Dune_engine.Section
module Watermarks = Dune_rules.Watermarks
module Diff_promotion = Dune_engine.Diff_promotion
module Colors = Dune_rules.Colors
module Dune_project = Dune_engine.Dune_project
module Workspace = Dune_rules.Workspace
module Cached_digest = Dune_engine.Cached_digest
module Targets = Dune_engine.Targets
module Profile = Dune_rules.Profile
module Log = Dune_util.Log
module Dune_rpc = Dune_rpc_private
module Graph = Dune_graph.Graph
include Common.Let_syntax

let in_group (t, info) = (Term.Group.Term t, info)

module Main : sig
  include module type of struct
    include Dune_rules.Main
  end

  val setup : unit -> build_system Memo.Build.t Fiber.t
end = struct
  include Dune_rules.Main

  let setup () =
    let open Fiber.O in
    let* scheduler = Scheduler.t () in
    Console.Status_line.set
      (Live
         (fun () ->
           let progression = Build_system.get_current_progress () in
           Pp.verbatim
             (sprintf "Done: %u/%u (jobs: %u)"
                progression.number_of_rules_executed
                progression.number_of_rules_discovered
                (Scheduler.running_jobs_count scheduler))));
    Fiber.return (Memo.Build.of_thunk get)
end

module Scheduler = struct
  include Dune_engine.Scheduler

  let maybe_clear_screen ~details_hum (dune_config : Dune_config.t) =
    match dune_config.terminal_persistence with
    | Clear_on_rebuild -> Console.reset ()
    | Preserve ->
      if Dune_util.Config.inside_dune then
        (* Don't print this when running inside Dune because:

           - it is quite verbose

           - [details_hum] is not reproducible since at the point we get here we
           might not have accumulated all the FS changes produced by the test *)
        ()
      else
        let message =
          sprintf "********** NEW BUILD (%s) **********"
            (String.concat ~sep:", " details_hum)
        in
        Console.print_user_message
          (User_message.make
             [ Pp.nop
             ; Pp.tag User_message.Style.Success (Pp.verbatim message)
             ; Pp.nop
             ])

  let on_event dune_config _config = function
    | Scheduler.Run.Event.Tick -> Console.Status_line.refresh ()
    | Source_files_changed { details_hum } ->
      maybe_clear_screen ~details_hum dune_config
    | Skipped_restart -> ()
    | Build_interrupted ->
      Console.Status_line.set
        (Live
           (fun () ->
             let progression = Build_system.get_current_progress () in
             Pp.seq
               (Pp.tag User_message.Style.Error
                  (Pp.verbatim "Source files changed"))
               (Pp.verbatim
                  (sprintf ", restarting current build... (%u/%u)"
                     progression.number_of_rules_executed
                     progression.number_of_rules_discovered))))

  let go ~(common : Common.t) ~config:dune_config f =
    let stats = Common.stats common in
    let config = Dune_config.for_scheduler dune_config None stats in
    Scheduler.Run.go config ~on_event:(on_event dune_config) f

  let go_watch_mode ~(common : Common.t) ~config:dune_config run =
    let open Fiber.O in
    let stats = Common.stats common in
    let rpc_where = Some (Dune_rpc_impl.Where.default ()) in
    let config = Dune_config.for_scheduler dune_config rpc_where stats in
    let file_watcher = Common.file_watcher common in
    let rpc = Option.value_exn (Common.rpc common) in
    let rec loop () =
      let* () = Dune_rpc_impl.Server.acknowledge_build_starting rpc in
      Scheduler.Run.poll_iter ~f:run >>= function
      | Shutdown -> Fiber.return ()
      | Finished res ->
        let build_outcome : Dune_rpc_impl.Decl.Build_outcome.t =
          match res with
          | Error `Already_reported -> Failure
          | Ok () -> Success
        in
        let message =
          match build_outcome with
          | Success -> Pp.tag User_message.Style.Success (Pp.verbatim "Success")
          | Failure ->
            Pp.tag User_message.Style.Error (Pp.verbatim "Had errors")
        in
        Console.Status_line.set
          (Constant
             (Pp.seq message
                (Pp.verbatim ", waiting for filesystem changes...")));
        let* () =
          Dune_rpc_impl.Server.acknowledge_build_finished rpc build_outcome
        in
        let* () = Scheduler.Run.wait_for_file_change () in
        loop ()
    in
    let run () =
      Fiber.fork_and_join_unit
        (fun () ->
          let rpc_config = Dune_rpc_impl.Server.config rpc in
          Dune_rpc_impl.Run.run rpc_config config.stats)
        (fun () ->
          Memo.Perf_counters.reset ();
          loop ())
    in
    Scheduler.Run.go config ~file_watcher ~on_event:(on_event dune_config) run
end

let restore_cwd_and_execve (common : Common.t) prog argv env =
  let prog =
    if Filename.is_relative prog then
      let root = Common.root common in
      Filename.concat root.dir prog
    else
      prog
  in
  Proc.restore_cwd_and_execve prog argv ~env

(* Adapted from
   https://github.com/ocaml/opam/blob/fbbe93c3f67034da62d28c8666ec6b05e0a9b17c/src/client/opamArg.ml#L759 *)
let command_alias cmd name =
  let term, info = cmd in
  let orig = Term.name info in
  let doc = Printf.sprintf "An alias for $(b,%s)." orig in
  let man =
    [ `S "DESCRIPTION"
    ; `P
        (Printf.sprintf "$(mname)$(b, %s) is an alias for $(mname)$(b, %s)."
           name orig)
    ; `P (Printf.sprintf "See $(mname)$(b, %s --help) for details." orig)
    ; `Blocks Common.help_secs
    ]
  in
  (term, Term.info name ~docs:"COMMAND ALIASES" ~doc ~man)
