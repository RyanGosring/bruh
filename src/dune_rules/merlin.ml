open! Dune_engine
open! Stdune
open Import
module SC = Super_context

module Processed = struct
  (* The actual content of the merlin file as built by the [Unprocessed.process]
     function from the unprocessed info gathered through [gen_rules]. The first
     three fields map directly to Merlin's B, S and FLG directives and the last
     one represents a list of preprocessors described by a preprocessing flag
     and its arguments. *)

  type pp_flag =
    { flag : string
    ; args : string
    }

  (* Most of the configuration is shared accros a same lib/exe... *)
  type config =
    { stdlib_dir : Path.t
    ; obj_dirs : Path.Set.t
    ; src_dirs : Path.Set.t
    ; flags : string list
    ; extensions : string Ml_kind.Dict.t list
    }

  (* ...but modules can have different preprocessing specifications*)
  type t =
    { config : config
    ; modules : Module_name.t list
    ; pp_config : pp_flag option Module_name.Per_item.t
    }

  module D = struct
    type nonrec t = t

    let name = "merlin-conf"

    let version = 2

    let to_dyn _ = Dyn.String "Use [dune ocaml dump-dot-merlin] instead"
  end

  module Persist = Dune_util.Persistent.Make (D)

  let load_file f =
    (* Failing to load the file at that point means that the configuration file
       has been written by a version of Dune in which the [Merlin.Processed.t]
       type is different from the one in the current version. *)
    Option.map ~f:Result.return (Persist.load f)
    |> Option.value
         ~default:
           (Error
              "The current Merlin configuration has been generated by another, \
               incompatible, version of Dune. Please rebuild the project. \
               (Using the same version of Dune as the one running the \
               `ocaml-merlin` server.)")

  let to_sexp ~pp { stdlib_dir; obj_dirs; src_dirs; flags; extensions } =
    let serialize_path = Path.to_absolute_filename in
    let to_atom s = Sexp.Atom s in
    let make_directive tag value = Sexp.List [ Atom tag; value ] in
    let make_directive_of_path tag path =
      make_directive tag (Sexp.Atom (serialize_path path))
    in
    let stdlib_dir = [ make_directive_of_path "STDLIB" stdlib_dir ] in
    let exclude_query_dir = [ Sexp.List [ Atom "EXCLUDE_QUERY_DIR" ] ] in
    let obj_dirs =
      Path.Set.to_list obj_dirs |> List.map ~f:(make_directive_of_path "B")
    in
    let src_dirs =
      Path.Set.to_list src_dirs |> List.map ~f:(make_directive_of_path "S")
    in
    let flags =
      let flags =
        match flags with
        | [] -> []
        | flags ->
          [ make_directive "FLG" (Sexp.List (List.map ~f:to_atom flags)) ]
      in
      match pp with
      | None -> flags
      | Some { flag; args } ->
        make_directive "FLG" (Sexp.List [ Atom flag; Atom args ]) :: flags
    in
    let suffixes =
      List.map extensions ~f:(fun { Ml_kind.Dict.impl; intf } ->
          make_directive "SUFFIX" (Sexp.Atom (Printf.sprintf "%s %s" impl intf)))
    in
    Sexp.List
      (List.concat
         [ stdlib_dir; exclude_query_dir; obj_dirs; src_dirs; flags; suffixes ])

  let quote_for_dot_merlin s =
    let s =
      if Sys.win32 then
        (* We need this hack because merlin unescapes backslashes (except when
           protected by single quotes). It is only a problem on windows because
           Filename.quote is using double quotes. *)
        String.escape_only '\\' s
      else
        s
    in
    if String.need_quoting s then
      Filename.quote s
    else
      s

  let to_dot_merlin stdlib_dir pp_configs flags obj_dirs src_dirs extensions =
    let serialize_path p = Path.to_absolute_filename p in
    let b = Buffer.create 256 in
    let printf = Printf.bprintf b in
    let print = Buffer.add_string b in
    Buffer.clear b;
    print "EXCLUDE_QUERY_DIR\n";
    printf "STDLIB %s\n" (serialize_path stdlib_dir);
    Path.Set.iter obj_dirs ~f:(fun p -> printf "B %s\n" (serialize_path p));
    Path.Set.iter src_dirs ~f:(fun p -> printf "S %s\n" (serialize_path p));
    List.iter extensions ~f:(fun { Ml_kind.Dict.impl; intf } ->
        printf "SUFFIX %s" (Printf.sprintf "%s %s" impl intf));
    (* We print all FLG directives as comments *)
    List.iter pp_configs
      ~f:
        (Module_name.Per_item.fold ~init:() ~f:(fun pp () ->
             Option.iter pp ~f:(fun { flag; args } ->
                 printf "# FLG %s\n" (flag ^ " " ^ quote_for_dot_merlin args))));
    List.iter flags ~f:(fun flags ->
        match flags with
        | [] -> ()
        | flags ->
          print "# FLG";
          List.iter flags ~f:(fun f -> printf " %s" (quote_for_dot_merlin f));
          print "\n");
    Buffer.contents b

  let get { modules; pp_config; config } ~filename =
    (* We only match the first part of the filename : foo.ml -> foo foo.cppo.ml
       -> foo *)
    let fname =
      String.lsplit2 filename ~on:'.'
      |> Option.map ~f:fst
      |> Option.value ~default:filename
      |> String.lowercase
    in
    List.find_opt modules ~f:(fun name ->
        let fname' = Module_name.to_string name |> String.lowercase in
        String.equal fname fname')
    |> Option.map ~f:(fun name ->
           let pp = Module_name.Per_item.get pp_config name in
           to_sexp ~pp config)

  let print_file path =
    match load_file path with
    | Error msg -> Printf.eprintf "%s\n" msg
    | Ok { modules; pp_config; config } ->
      let pp_one module_ =
        let pp = Module_name.Per_item.get pp_config module_ in
        let sexp = to_sexp ~pp config in
        let open Pp.O in
        Pp.vbox (Pp.text (Module_name.to_string module_))
        ++ Pp.newline
        ++ Pp.vbox (Sexp.pp sexp)
        ++ Pp.newline
      in
      Format.printf "%a%!" Pp.to_fmt (Pp.concat_map modules ~f:pp_one)

  let print_generic_dot_merlin paths =
    let configs = Result.List.map paths ~f:load_file in
    match configs with
    | Error msg -> Printf.eprintf "%s\n" msg
    | Ok [] -> Printf.eprintf "No merlin configuration found.\n"
    | Ok (init :: tl) ->
      let pp_configs, obj_dirs, src_dirs, flags, extensions =
        (* We merge what is easy to merge and ignore the rest *)
        List.fold_left tl
          ~init:
            ( [ init.pp_config ]
            , init.config.obj_dirs
            , init.config.src_dirs
            , [ init.config.flags ]
            , init.config.extensions )
          ~f:
            (fun (acc_pp, acc_obj, acc_src, acc_flags, acc_ext)
                 { modules = _
                 ; pp_config
                 ; config =
                     { stdlib_dir = _; obj_dirs; src_dirs; flags; extensions }
                 } ->
            ( pp_config :: acc_pp
            , Path.Set.union acc_obj obj_dirs
            , Path.Set.union acc_src src_dirs
            , flags :: acc_flags
            , extensions @ acc_ext ))
      in
      Printf.printf "%s\n"
        (to_dot_merlin init.config.stdlib_dir pp_configs flags obj_dirs src_dirs
           extensions)
end

module Unprocessed = struct
  (* We store separate information for each "module". These informations do not
     reflect the actual content of the Merlin configuration yet but are needed
     for it's elaboration via the function [process : Unprocessed.t ... ->
     Processed.t] *)
  type config =
    { stdlib_dir : Path.t
    ; requires : Lib.Set.t
    ; flags : string list Action_builder.t
    ; preprocess :
        Preprocess.Without_instrumentation.t Preprocess.t Module_name.Per_item.t
    ; libname : Lib_name.Local.t option
    ; source_dirs : Path.Source.Set.t
    ; objs_dirs : Path.Set.t
    ; extensions : string Ml_kind.Dict.t list
    }

  type t =
    { ident : Merlin_ident.t
    ; config : config
    ; modules : Modules.t
    }

  let make ?(requires = Resolve.return []) ~stdlib_dir ~flags
      ?(preprocess = Preprocess.Per_module.no_preprocessing ()) ?libname
      ?(source_dirs = Path.Source.Set.empty) ~modules ~obj_dir ~dialects ~ident
      () =
    (* Merlin shouldn't cause the build to fail, so we just ignore errors *)
    let requires =
      match Resolve.peek requires with
      | Ok l -> Lib.Set.of_list l
      | Error () -> Lib.Set.empty
    in
    let objs_dirs =
      Obj_dir.byte_dir obj_dir |> Path.build |> Path.Set.singleton
    in
    let flags =
      match Modules.alias_module modules with
      | None -> Ocaml_flags.common flags
      | Some m ->
        Ocaml_flags.prepend_common
          [ "-open"; Module_name.to_string (Module.name m) ]
          flags
        |> Ocaml_flags.common
    in
    let extensions = Dialect.DB.extensions_for_merlin dialects in
    let config =
      { stdlib_dir
      ; requires
      ; flags
      ; preprocess
      ; libname
      ; source_dirs
      ; objs_dirs
      ; extensions
      }
    in
    { ident; config; modules }

  let quote_if_needed s =
    if String.need_quoting s then
      Filename.quote s
    else
      s

  let pp_flag_of_action ~expander ~loc ~action :
      Processed.pp_flag option Action_builder.t =
    match (action : Action_dune_lang.t) with
    | Run (exe, args) -> (
      let args =
        let open Option.O in
        let* args, input_file = List.destruct_last args in
        if String_with_vars.is_pform input_file (Var Input_file) then
          Some args
        else
          None
      in
      match args with
      | None -> Action_builder.return None
      | Some args ->
        let action =
          let action = Preprocessing.chdir (Run (exe, args)) in
          Action_unexpanded.expand_no_targets ~loc ~expander ~deps:[]
            ~what:"preprocessing actions" action
        in
        let pp_of_action exe args =
          match exe with
          | Error _ -> None
          | Ok exe ->
            let args =
              Path.to_absolute_filename exe :: args
              |> List.map ~f:quote_if_needed
              |> String.concat ~sep:" "
            in
            Some Processed.{ flag = "-pp"; args }
        in
        Action_builder.map action ~f:(function
          | Run (exe, args) -> pp_of_action exe args
          | Chdir (_, Run (exe, args)) -> pp_of_action exe args
          | Chdir (_, Chdir (_, Run (exe, args))) -> pp_of_action exe args
          | _ -> None))
    | _ -> Action_builder.return None

  let pp_flags sctx ~expander libname preprocess :
      Processed.pp_flag option Action_builder.t =
    let scope = Expander.scope expander in
    match
      Preprocess.remove_future_syntax preprocess ~for_:Merlin
        (Result.ok_exn (Super_context.context sctx).lib_config.ocaml)
          .ocaml_version
    with
    | Action (loc, (action : Action_dune_lang.t)) ->
      pp_flag_of_action ~expander ~loc ~action
    | No_preprocessing -> Action_builder.return None
    | Pps { loc; pps; flags; staged = _ } ->
      let open Action_builder.O in
      let* exe, flags =
        Preprocessing.get_ppx_driver sctx ~loc ~expander ~lib_name:libname
          ~flags ~scope pps
      in
      let args =
        Path.to_absolute_filename (Path.build exe) :: "--as-ppx" :: flags
        |> List.map ~f:quote_if_needed
        |> String.concat ~sep:" "
      in
      Action_builder.return (Some Processed.{ flag = "-ppx"; args })

  let process
      { modules
      ; ident = _
      ; config =
          { stdlib_dir
          ; extensions
          ; flags
          ; objs_dirs
          ; source_dirs
          ; requires
          ; preprocess
          ; libname
          }
      } sctx ~more_src_dirs ~expander =
    let open Action_builder.O in
    let+ config =
      let+ flags = flags
      and+ src_dirs, obj_dirs =
        Action_builder.memo_build
          (let open Memo.Build.O in
          Memo.Build.parallel_map (Lib.Set.to_list requires) ~f:(fun lib ->
              let+ dirs = Lib.src_dirs lib in
              (lib, dirs))
          >>| List.fold_left
                ~init:(Path.set_of_source_paths source_dirs, objs_dirs)
                ~f:(fun (src_dirs, obj_dirs) (lib, more_src_dirs) ->
                  ( Path.Set.union src_dirs more_src_dirs
                  , let public_cmi_dir =
                      Obj_dir.public_cmi_dir (Lib.obj_dir lib)
                    in
                    Path.Set.add obj_dirs public_cmi_dir )))
      in
      let src_dirs =
        Path.Set.union src_dirs
          (Path.Set.of_list_map ~f:Path.source more_src_dirs)
      in
      { Processed.stdlib_dir; src_dirs; obj_dirs; flags; extensions }
    and+ pp_config =
      Module_name.Per_item.map_action_builder preprocess
        ~f:(pp_flags sctx ~expander libname)
    in
    let modules =
      (* And copy for each module the resulting pp flags *)
      Modules.fold_no_vlib modules ~init:[] ~f:(fun m acc ->
          Module.name m :: acc)
    in
    { Processed.modules; pp_config; config }
end

let dot_merlin sctx ~dir ~more_src_dirs ~expander (t : Unprocessed.t) =
  let open Memo.Build.O in
  let merlin_file = Merlin_ident.merlin_file_path dir t.ident in
  let* () =
    Rules.Produce.Alias.add_deps (Alias.check ~dir)
      (Action_builder.path (Path.build merlin_file))
  in
  let merlin = Unprocessed.process t sctx ~more_src_dirs ~expander in
  let action =
    Action_builder.With_targets.write_file_dyn merlin_file
      (Action_builder.with_no_targets
         (Action_builder.map ~f:Processed.Persist.to_string merlin))
  in
  SC.add_rule sctx ~dir action

let add_rules sctx ~dir ~more_src_dirs ~expander merlin =
  Memo.Build.when_ (SC.context sctx).merlin (fun () ->
      dot_merlin sctx ~more_src_dirs ~expander ~dir merlin)

include Unprocessed
