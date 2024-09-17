open! Import
module Pkg_dev_tool = Dune_rules.Pkg_dev_tool

let exe_path = Path.build @@ Pkg_dev_tool.exe_path Ocamlformat
let exe_name = Pkg_dev_tool.exe_name Ocamlformat

let run_dev_tool common ~args =
  let exe_path_string = Path.to_string exe_path in
  Console.print_user_message
    (Dune_rules.Pkg_build_progress.format_user_message
       ~verb:"Running"
       ~object_:(User_message.command (String.concat ~sep:" " (exe_name :: args))));
  Console.finish ();
  restore_cwd_and_execve common exe_path_string (exe_path_string :: args) Env.initial
;;

let dev_tool_exe_exists () = Path.exists exe_path

let build_dev_tool common =
  match dev_tool_exe_exists () with
  | true ->
    (* Avoid running the build system if the executable already exists
       to reduce unnecessary latency in the common case. *)
    Fiber.return ()
  | false ->
    let open Fiber.O in
    let+ result =
      Build_cmd.run_build_system ~common ~request:(fun _build_system ->
        Action_builder.path exe_path)
    in
    (match result with
     | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
     | Ok () -> ())
;;

let is_in_dune_project builder =
  Workspace_root.create
    ~default_is_cwd:(Common.Builder.default_root_is_cwd builder)
    ~specified_by_user:(Common.Builder.root builder)
  |> Result.is_ok
;;

module Fallback = struct
  type t =
    | Opam_then_path
    | Path_only

  let all = [ "opam-then-path", Opam_then_path; "path-only", Path_only ]
  let term = Arg.(value & opt (enum all) Opam_then_path & info [ "fallback" ])

  type empty = |

  (* This function replaces the dune process with the
     process started by the command so it does not return,
     hence its empty return type. *)
  let run_command prog args env : empty =
    let prog_string = Path.to_string prog in
    let argv = prog_string :: args in
    Console.print_user_message
      (Dune_rules.Pkg_build_progress.format_user_message
         ~verb:"Running"
         ~object_:(User_message.command (String.concat ~sep:" " argv)));
    Console.finish ();
    Proc.restore_cwd_and_execve prog_string argv ~env
  ;;

  let run_via_opam args env =
    match Bin.which ~path:(Env_path.path env) "opam" with
    | None -> Error `Opam_not_installed
    | Some opam_path ->
      Console.print_user_message
        (User_message.make
           [ Pp.textf
               "Not in a dune project but opam appears to be installed. Dune will \
                attempt to run %s via opam."
               exe_name
           ]);
      Ok (run_command opam_path ([ "exec"; exe_name; "--" ] @ args) env)
  ;;

  let run_via_path args env =
    match Bin.which ~path:(Env_path.path env) exe_name with
    | None -> Error `Not_in_path
    | Some path ->
      Console.print_user_message
        (User_message.make
           [ Pp.textf
               "Not in a dune project but %s appears to be installed. Dune will attempt \
                to run %s from your PATH."
               exe_name
               exe_name
           ]);
      Ok (run_command path args env)
  ;;

  let run_via_opam_then_path args env =
    let (Error `Opam_not_installed) = run_via_opam args env in
    run_via_path args env
  ;;

  (* Attempt to launch ocamlformat from the current opam switch, and
     failing that from the PATH. This is necessary so that editors
     configured to run ocamlformat via dune can still be used to format
     ocaml code outside of dune projects. *)
  let run t args env =
    let (Error `Not_in_path) =
      match t with
      | Opam_then_path -> run_via_opam_then_path args env
      | Path_only -> run_via_path args env
    in
    User_error.raise
      [ Pp.textf "Not in a dune project and %s doesn't appear to be installed." exe_name ]
  ;;
end

let term =
  let+ builder = Common.Builder.term
  and+ args = Arg.(value & pos_all string [] (info [] ~docv:"ARGS"))
  and+ fallback = Fallback.term in
  match is_in_dune_project builder with
  | false -> Fallback.run fallback args Env.initial
  | true ->
    let common, config = Common.init builder in
    Scheduler.go ~common ~config (fun () ->
      let open Fiber.O in
      let* () = Lock_dev_tool.lock_ocamlformat () in
      let+ () = build_dev_tool common in
      run_dev_tool common ~args)
;;

let info =
  let doc =
    {|Wrapper for running ocamlformat intended to be run automatically
     by a text editor. All positional arguments will be passed to the
     ocamlformat executable (pass flags to ocamlformat after the '--'
     argument, such as 'dune ocamlformat -- --help'). If this command
     is run from inside a dune project, dune will download and build
     the ocamlformat opam package and run the ocamlformat executable
     from there rather. Otherwise, dune will attempt to run the
     ocamlformat executable from your current opam switch. If opam is
     not installed, dune will attempt to run ocamlformat from your
     PATH.|}
  in
  Cmd.info "ocamlformat" ~doc
;;

let command = Cmd.v info term
