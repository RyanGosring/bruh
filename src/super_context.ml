open Import
open Jbuild_types

module Dir_with_jbuild = struct
  type t =
    { src_dir : Path.t
    ; ctx_dir : Path.t
    ; stanzas : Stanzas.t
    ; pkgs    : Pkgs.t
    }
end

module External_dir = struct
  (* Files in the directory, grouped by extension *)
  type t = Path.t list String_map.t

  let create ~dir : t =
    match Path.readdir dir with
    | exception _ -> String_map.empty
    | files ->
      List.map files ~f:(fun fn -> Filename.extension fn, Path.relative dir fn)
      |> String_map.of_alist_multi
  (* CR-someday jdimino: when we can have dynamic targets:

     {[
       |> String_map.mapi ~f:(fun ext files ->
         lazy (
           let alias =
             Alias.make ~dir:Path.root (sprintf "external-files-%s%s" hash ext)
           in
           Alias.add_deps aliases alias files;
           alias
         ))
     ]}
  *)

  let files t ~ext = String_map.find_default ext t ~default:[]
end

type t =
  { context                                 : Context.t
  ; libs                                    : Lib_db.t
  ; stanzas                                 : Dir_with_jbuild.t list
  ; packages                                : Package.t String_map.t
  ; aliases                                 : Alias.Store.t
  ; file_tree                               : File_tree.t
  ; artifacts                               : Artifacts.t
  ; mutable rules                           : Build_interpret.Rule.t list
  ; stanzas_to_consider_for_install         : (Path.t * Stanza.t) list
  ; mutable known_targets_by_src_dir_so_far : String_set.t Path.Map.t
  ; libs_vfile                              : (module Vfile_kind.S with type t = Lib.t list)
  ; cxx_flags                               : string list
  ; vars                                    : string String_map.t
  ; ppx_dir                                 : Path.t
  ; ppx_drivers                             : (string, Path.t) Hashtbl.t
  ; external_dirs                           : (Path.t, External_dir.t) Hashtbl.t
  ; chdir                                   : (Action.t, Action.t) Build.t
  }

let context t = t.context
let aliases t = t.aliases
let stanzas t = t.stanzas
let packages t = t.packages
let artifacts t = t.artifacts
let file_tree t = t.file_tree
let rules t = t.rules
let stanzas_to_consider_for_install t = t.stanzas_to_consider_for_install
let cxx_flags t = t.cxx_flags

let expand_var_no_root t var = String_map.find var t.vars

let get_external_dir t ~dir =
  Hashtbl.find_or_add t.external_dirs dir ~f:(fun dir ->
    External_dir.create ~dir)

let expand_vars t ~dir s =
  String_with_vars.expand s ~f:(function
  | "ROOT" -> Some (Path.reach ~from:dir t.context.build_dir)
  | var -> String_map.find var t.vars)

let resolve_program t ?hint ?(in_the_tree=true) bin =
  match Artifacts.binary t.artifacts ?hint ~in_the_tree bin with
  | Error fail -> Build.Prog_spec.Dyn (fun _ -> fail.fail ())
  | Ok    path -> Build.Prog_spec.Dep path

let create
      ~(context:Context.t)
      ~aliases
      ~dirs_with_dot_opam_files
      ~file_tree
      ~packages
      ~stanzas
      ~filter_out_optional_stanzas_with_missing_deps
  =
  let stanzas =
    List.map stanzas
      ~f:(fun (dir, pkgs, stanzas) ->
        { Dir_with_jbuild.
          src_dir = dir
        ; ctx_dir = Path.append context.build_dir dir
        ; stanzas
        ; pkgs
        })
  in
  let internal_libraries =
    List.concat_map stanzas ~f:(fun { ctx_dir;  stanzas; _ } ->
      List.filter_map stanzas ~f:(fun stanza ->
        match (stanza : Stanza.t) with
        | Library lib -> Some (ctx_dir, lib)
        | _ -> None))
  in
  let dirs_with_dot_opam_files =
    Path.Set.elements dirs_with_dot_opam_files
    |> List.map ~f:(Path.append context.build_dir)
    |> Path.Set.of_list
  in
  let libs =
    Lib_db.create context.findlib internal_libraries
      ~dirs_with_dot_opam_files
  in
  let stanzas_to_consider_for_install =
    if filter_out_optional_stanzas_with_missing_deps then
      List.concat_map stanzas ~f:(fun { ctx_dir; stanzas; _ } ->
        List.filter_map stanzas ~f:(function
          | Library _ -> None
          | stanza    -> Some (ctx_dir, stanza)))
      @ List.map
          (Lib_db.internal_libs_without_non_installable_optional_ones libs)
          ~f:(fun (dir, lib) -> (dir, Stanza.Library lib))
    else
      List.concat_map stanzas ~f:(fun { ctx_dir; stanzas; _ } ->
        List.map stanzas ~f:(fun s -> (ctx_dir, s)))
  in
  let module Libs_vfile =
    Vfile_kind.Make_full
      (struct type t = Lib.t list end)
      (struct
        open Sexp.To_sexp
        let t _dir l = list string (List.map l ~f:Lib.best_name)
      end)
      (struct
        open Sexp.Of_sexp
        let t dir sexp =
          List.map (list string sexp) ~f:(Lib_db.find_exn libs ~from:dir)
      end)
  in
  let artifacts =
    Artifacts.create context (List.map stanzas ~f:(fun (d : Dir_with_jbuild.t) ->
      (d.ctx_dir, d.stanzas)))
  in
  let cxx_flags =
    String.extract_blank_separated_words context.ocamlc_cflags
    |> List.filter ~f:(fun s -> not (String.is_prefix s ~prefix:"-std="))
  in
  let vars =
    let ocamlopt =
      match context.ocamlopt with
      | None -> Path.relative context.ocaml_bin "ocamlopt"
      | Some p -> p
    in
    let make =
      match Bin.make with
      | None   -> "make"
      | Some p -> Path.to_string p
    in
    let (ocaml_release, ocaml_patch, ocaml_revision) =
      let last_dot = String.rindex context.version '.' in
      let len = String.length context.version in
      let plus = String.index context.version '+' in
      let f ~len n =
        let pos = succ n in
        String.sub context.version ~pos ~len:(len - pos)
      in
      String.sub context.version ~pos:0 ~len:last_dot,
      Option.value_map plus ~default:"" ~f:(f ~len),
      f ~len:(Option.value plus ~default:len) last_dot
    in
    [ "-verbose"       , "" (*"-verbose";*)
    ; "CPP"            , sprintf "%s %s -E" context.c_compiler context.ocamlc_cflags
    ; "PA_CPP"         , sprintf "%s %s -undef -traditional -x c -E" context.c_compiler
                           context.ocamlc_cflags
    ; "CC"             , sprintf "%s %s" context.c_compiler context.ocamlc_cflags
    ; "CXX"            , String.concat ~sep:" " (context.c_compiler :: cxx_flags)
    ; "ocaml_bin"      , Path.to_string context.ocaml_bin
    ; "OCAML"          , Path.to_string context.ocaml
    ; "OCAMLC"         , Path.to_string context.ocamlc
    ; "OCAMLOPT"       , Path.to_string ocamlopt
    ; "ocaml_version"  , context.version
    ; "ocaml_release"  , ocaml_release
    ; "ocaml_patch"    , ocaml_patch
    ; "ocaml_revision" , ocaml_revision
    ; "ocaml_where"    , Path.to_string context.stdlib_dir
    ; "ARCH_SIXTYFOUR" , string_of_bool context.arch_sixtyfour
    ; "MAKE"           , make
    ; "null"           , Path.to_string Config.dev_null
    ]
    |> String_map.of_alist
    |> function
    | Ok x -> x
    | Error _ -> assert false
  in
  { context
  ; libs
  ; stanzas
  ; packages
  ; aliases
  ; file_tree
  ; rules = []
  ; stanzas_to_consider_for_install
  ; known_targets_by_src_dir_so_far = Path.Map.empty
  ; libs_vfile = (module Libs_vfile)
  ; artifacts
  ; cxx_flags
  ; vars
  ; ppx_drivers = Hashtbl.create 32
  ; ppx_dir = Path.relative context.build_dir ".ppx"
  ; external_dirs = Hashtbl.create 1024
  ; chdir = Build.arr (fun (action : Action.t) ->
      match action with
      | Chdir _ -> action
      | _ -> Chdir (context.build_dir, action))
  }

let add_rule t ?sandbox build =
  let build = Build.O.(>>>) build t.chdir in
  let rule = Build_interpret.Rule.make ?sandbox ~context:t.context build in
  t.rules <- rule :: t.rules;
  t.known_targets_by_src_dir_so_far <-
    List.fold_left rule.targets ~init:t.known_targets_by_src_dir_so_far
      ~f:(fun acc target ->
        match Path.extract_build_context (Build_interpret.Target.path target) with
        | None -> acc
        | Some (_, path) ->
          let dir = Path.parent path in
          let fn = Path.basename path in
          let files =
            match Path.Map.find dir acc with
            | None -> String_set.singleton fn
            | Some set -> String_set.add fn set
          in
          Path.Map.add acc ~key:dir ~data:files)

let add_rules t ?sandbox builds =
  List.iter builds ~f:(add_rule t ?sandbox)

let sources_and_targets_known_so_far t ~src_path =
  let sources =
    match File_tree.find_dir t.file_tree src_path with
    | None -> String_set.empty
    | Some dir -> File_tree.Dir.files dir
  in
  match Path.Map.find src_path t.known_targets_by_src_dir_so_far with
  | None -> sources
  | Some set -> String_set.union sources set


module Libs = struct
  open Build.O
  open Lib_db

  let find t ~from name = find t.libs ~from name

  let vrequires t ~dir ~item =
    let fn = Path.relative dir (item ^ ".requires.sexp") in
    Build.Vspec.T (fn, t.libs_vfile)

  let load_requires t ~dir ~item =
    Build.vpath (vrequires t ~dir ~item)

  let vruntime_deps t ~dir ~item =
    let fn = Path.relative dir (item ^ ".runtime-deps.sexp") in
    Build.Vspec.T (fn, t.libs_vfile)

  let load_runtime_deps t ~dir ~item =
    Build.vpath (vruntime_deps t ~dir ~item)

  let with_fail ~fail build =
    match fail with
    | None -> build
    | Some f -> Build.fail f >>> build

  let closure t ~dir ~dep_kind lib_deps =
    let internals, externals, fail = Lib_db.interpret_lib_deps t.libs ~dir lib_deps in
    with_fail ~fail
      (Build.record_lib_deps ~dir ~kind:dep_kind lib_deps
       >>>
       Build.all
         (List.map internals ~f:(fun ((dir, lib) : Lib.Internal.t) ->
            load_requires t ~dir ~item:lib.name))
       >>^ (fun internal_deps ->
         let externals =
           Findlib.closure externals
             ~required_by:dir
             ~local_public_libs:(local_public_libs t.libs)
           |> List.map ~f:(fun pkg -> Lib.External pkg)
         in
         Lib.remove_dups_preserve_order
           (List.concat (externals :: internal_deps) @
            List.map internals ~f:(fun x -> Lib.Internal x))))

  let closed_ppx_runtime_deps_of t ~dir ~dep_kind lib_deps =
    let internals, externals, fail = Lib_db.interpret_lib_deps t.libs ~dir lib_deps in
    with_fail ~fail
      (Build.record_lib_deps ~dir ~kind:dep_kind lib_deps
       >>>
       Build.all
         (List.map internals ~f:(fun ((dir, lib) : Lib.Internal.t) ->
            load_runtime_deps t ~dir ~item:lib.name))
       >>^ (fun libs ->
         let externals =
           Findlib.closed_ppx_runtime_deps_of externals
             ~required_by:dir
             ~local_public_libs:(local_public_libs t.libs)
           |> List.map ~f:(fun pkg -> Lib.External pkg)
         in
         Lib.remove_dups_preserve_order (List.concat (externals :: libs))))

  let lib_is_available t ~from name = lib_is_available t.libs ~from name

  let add_select_rules t ~dir lib_deps =
    List.iter (Lib_db.resolve_selects t.libs ~from:dir lib_deps) ~f:(fun { dst_fn; src_fn } ->
      let src = Path.relative dir src_fn in
      let dst = Path.relative dir dst_fn in
      add_rule t
        (Build.path src
         >>>
         Build.action ~targets:[dst]
           (Copy_and_add_line_directive (src, dst))))

  let real_requires t ~dir ~dep_kind ~item ~libraries ~preprocess ~virtual_deps =
    let all_pps =
      List.map (Preprocess_map.pps preprocess) ~f:Pp.to_string
    in
    let vrequires = vrequires t ~dir ~item in
    add_rule t
      (Build.record_lib_deps ~dir ~kind:dep_kind (List.map virtual_deps ~f:Lib_dep.direct)
       >>>
       Build.fanout
         (closure t ~dir ~dep_kind libraries)
         (closed_ppx_runtime_deps_of t ~dir ~dep_kind
            (List.map all_pps ~f:Lib_dep.direct))
       >>>
       Build.arr (fun (libs, rt_deps) ->
         Lib.remove_dups_preserve_order (libs @ rt_deps))
       >>>
       Build.store_vfile vrequires);
    Build.vpath vrequires

  let requires t ~dir ~dep_kind ~item ~libraries ~preprocess ~virtual_deps =
    let real_requires =
      real_requires t ~dir ~dep_kind ~item ~libraries ~preprocess ~virtual_deps
    in
    let requires =
      if t.context.merlin then
        (* We don't depend on the dot_merlin directly, otherwise everytime it changes we
           would have to rebuild everything.

           .merlin-exists depends on the .merlin and is an empty file. Depending on it
           forces the generation of the .merlin but not recompilation when it
           changes. Maybe one day we should add [Build.path_exists] to do the same in
           general. *)
        Build.path (Path.relative dir ".merlin-exists")
        >>>
        real_requires
      else
        real_requires
    in
    (requires, real_requires)

  let setup_runtime_deps t ~dir ~dep_kind ~item ~libraries ~ppx_runtime_libraries =
    let vruntime_deps = vruntime_deps t ~dir ~item in
    add_rule t
      (Build.fanout
         (closure t ~dir ~dep_kind (List.map ppx_runtime_libraries ~f:Lib_dep.direct))
         (closed_ppx_runtime_deps_of t ~dir ~dep_kind libraries)
       >>>
       Build.arr (fun (rt_deps, rt_deps_of_deps) ->
         Lib.remove_dups_preserve_order (rt_deps @ rt_deps_of_deps))
       >>>
       Build.store_vfile vruntime_deps)

  let lib_files_alias ((dir, lib) : Lib.Internal.t) ~ext =
    Alias.make (sprintf "lib-%s%s-all" lib.name ext) ~dir

  let setup_file_deps_alias t lib ~ext files =
    Alias.add_deps t.aliases (lib_files_alias lib ~ext) files

  let setup_file_deps_group_alias t lib ~exts =
    setup_file_deps_alias t lib
      ~ext:(String.concat exts ~sep:"-and-")
      (List.map exts ~f:(fun ext -> Alias.file (lib_files_alias lib ~ext)))

  let file_deps t ~ext =
    Build.dyn_paths (Build.arr (fun libs ->
      List.fold_left libs ~init:[] ~f:(fun acc (lib : Lib.t) ->
        match lib with
        | External pkg -> begin
            List.rev_append
              (External_dir.files (get_external_dir t ~dir:pkg.dir) ~ext)
              acc
          end
        | Internal lib ->
          Alias.file (lib_files_alias lib ~ext) :: acc)))

  let static_file_deps ~ext lib =
    Alias.dep (lib_files_alias lib ~ext)
end

module Deps = struct
  open Build.O
  open Dep_conf

  let dep t ~dir = function
    | File  s ->
      let path = Path.relative dir (expand_vars t ~dir s) in
      Build.path path
      >>^ fun _ -> [path]
    | Alias s ->
      let path = Alias.file (Alias.make ~dir (expand_vars t ~dir s)) in
      Build.path path
      >>^ fun _ -> []
    | Glob_files s -> begin
        let path = Path.relative dir (expand_vars t ~dir s) in
        let dir = Path.parent path in
        let s = Path.basename path in
        match Glob_lexer.parse_string s with
        | Ok re ->
          Build.paths_glob ~dir (Re.compile re)
        | Error (_pos, msg) ->
          die "invalid glob in %s/jbuild: %s" (Path.to_string dir) msg
      end
    | Files_recursively_in s ->
      let path = Path.relative dir (expand_vars t ~dir s) in
      Build.files_recursively_in ~dir:path ~file_tree:t.file_tree
      >>^ Path.Set.elements

  let interpret t ~dir l =
    Build.all (List.map l ~f:(dep t ~dir))
    >>^ List.concat
end

module Pkg_version = struct
  open Build.O

  module V = Vfile_kind.Make(struct type t = string option end)
      (functor (C : Sexp.Combinators) -> struct
        let t = C.option C.string
      end)

  let spec sctx (p : Package.t) =
    let fn =
      Path.relative (Path.append sctx.context.build_dir p.path)
        (sprintf "%s.version.sexp" p.name)
    in
    Build.Vspec.T (fn, (module V))

  let read sctx p = Build.vpath (spec sctx p)

  let set sctx p get =
    let spec = spec sctx p in
    add_rule sctx (get >>> Build.store_vfile spec);
    Build.vpath spec
end

module Do_action = struct
  open Build.O
  module U = Action.Unexpanded

  let run t action ~dir =
    let action =
      Action.Unexpanded.expand t.context dir action ~f:(function
        | "ROOT" -> Path t.context.build_dir
        | var ->
          match expand_var_no_root t var with
          | Some s -> Str s
          | None -> Not_found)
    in
    let { Action.Infer.Outcome.deps; targets } = Action.Infer.infer action in
    Build.path_set deps
    >>>
    Build.action ~dir ~targets:(Path.Set.elements targets) action
end

module Action = struct
  open Build.O
  module U = Action.Unexpanded

  type resolved_forms =
    { (* Mapping from ${...} forms to their resolutions *)
      artifacts : Action.var_expansion String_map.t
    ; (* Failed resolutions *)
      failures  : fail list
    ; (* All "name" for ${lib:name:...}/${lib-available:name} forms *)
      lib_deps  : Build.lib_deps
    ; vdeps     : (unit, Action.var_expansion) Build.t String_map.t
    }

  let add_artifact ?lib_dep acc ~var result =
    let lib_deps =
      match lib_dep with
      | None -> acc.lib_deps
      | Some (lib, kind) -> String_map.add acc.lib_deps ~key:lib ~data:kind
    in
    match result with
    | Ok path ->
      { acc with
        artifacts = String_map.add acc.artifacts ~key:var ~data:path
      ; lib_deps
      }
    | Error fail ->
      { acc with
        failures = fail :: acc.failures
      ; lib_deps
      }

  let map_result = function
    | Ok x -> Ok (Action.Path x)
    | Error _ as e -> e

  let extract_artifacts sctx ~dir ~dep_kind ~package_context t =
    let init =
      { artifacts = String_map.empty
      ; failures  = []
      ; lib_deps  = String_map.empty
      ; vdeps     = String_map.empty
      }
    in
    U.fold_vars t ~init ~f:(fun acc loc var ->
      let module A = Artifacts in
      match String.lsplit2 var ~on:':' with
      | Some ("exe"     , s) -> add_artifact acc ~var (Ok (Path (Path.relative dir s)))
      | Some ("path"    , s) -> add_artifact acc ~var (Ok (Path (Path.relative dir s)))
      | Some ("bin"     , s) ->
        add_artifact acc ~var (A.binary (artifacts sctx) s |> map_result)
      | Some ("lib"     , s)
      | Some ("libexec" , s) ->
        let lib_dep, res = A.file_of_lib (artifacts sctx) ~from:dir s in
        add_artifact acc ~var ~lib_dep:(lib_dep, dep_kind) (map_result res)
      | Some ("lib-available", lib) ->
        add_artifact acc ~var ~lib_dep:(lib, Optional)
          (Ok (Str (string_of_bool (Libs.lib_is_available sctx ~from:dir lib))))
      (* CR-someday jdimino: allow this only for (jbuild_version jane_street) *)
      | Some ("findlib" , s) ->
        let lib_dep, res =
          A.file_of_lib (artifacts sctx) ~from:dir s ~use_provides:true
        in
        add_artifact acc ~var ~lib_dep:(lib_dep, Required) (map_result res)
      | Some ("version", s) -> begin
          match Pkgs.resolve package_context s with
          | Ok p ->
            let x =
              Pkg_version.read sctx p >>^ function
              | None -> Action.Str ""
              | Some s -> Str s
            in
            { acc with vdeps = String_map.add acc.vdeps ~key:var ~data:x }
          | Error s ->
            { acc with failures = { fail = fun () -> Loc.fail loc "%s" s } :: acc.failures }
        end
      | _ -> acc)

  let expand_var =
    fun sctx ~artifacts ~targets ~deps var_name ->
      match String_map.find var_name artifacts with
      | Some exp -> exp
      | None ->
        match var_name with
        | "@" -> Action.Paths (targets, Concat)
        | "!@" -> Action.Paths (targets, Split)
        | "<" ->
          (match deps with
           | []       -> Str "" (* CR-someday jdimino: this should be an error *)
           | dep :: _ -> Path dep)
        | "^" -> Paths (deps, Concat)
        | "!^" -> Paths (deps, Split)
        | "ROOT" -> Path sctx.context.build_dir
        | var ->
          match expand_var_no_root sctx var with
          | Some s -> Str s
          | None -> Not_found

  let run sctx t ~dir ~dep_kind ~targets ~package_context
    : (Path.t list, Action.t) Build.t =
    let forms = extract_artifacts sctx ~dir ~dep_kind ~package_context t in
    let build =
      Build.record_lib_deps_simple ~dir forms.lib_deps
      >>>
      Build.path_set
        (String_map.fold forms.artifacts ~init:Path.Set.empty
           ~f:(fun ~key:_ ~data:exp acc ->
             match exp with
             | Action.Path p -> Path.Set.add p acc
             | Paths (ps, _) -> Path.Set.union acc (Path.Set.of_list ps)
             | Not_found | Str _ -> acc))
      >>>
      Build.arr (fun paths -> ((), paths))
      >>>
      let vdeps = String_map.bindings forms.vdeps in
      Build.first (Build.all (List.map vdeps ~f:snd))
      >>^ (fun (vals, deps) ->
        let artifacts =
          List.fold_left2 vdeps vals ~init:forms.artifacts ~f:(fun acc (var, _) value ->
            String_map.add acc ~key:var ~data:value)
        in
        U.expand sctx.context dir t
          ~f:(expand_var sctx ~artifacts ~targets ~deps))
      >>>
      Build.action_dyn () ~dir ~targets
    in
    match forms.failures with
    | [] -> build
    | fail :: _ -> Build.fail fail >>> build
end

module PP = struct
  open Build.O

  let pp_fname fn =
    let fn, ext = Filename.split_extension fn in
    (* We need to to put the .pp before the .ml so that the compiler realises that
       [foo.pp.mli] is the interface for [foo.pp.ml] *)
    fn ^ ".pp" ^ ext

  let pped_module ~dir (m : Module.t) ~f =
    let ml_pp_fname = pp_fname m.impl.name in
    f Ml_kind.Impl (Path.relative dir m.impl.name) (Path.relative dir ml_pp_fname);
    let intf =
      Option.map m.intf ~f:(fun intf ->
        let pp_fname = pp_fname intf.name in
        f Intf (Path.relative dir intf.name) (Path.relative dir pp_fname);
        {intf with name = pp_fname})
    in
    { m with
      impl = { m.impl with name = ml_pp_fname }
    ; intf
    }

  let migrate_driver_main = "ocaml-migrate-parsetree.driver-main"

  let build_ppx_driver sctx ~dir ~dep_kind ~target pp_names ~driver =
    let ctx = sctx.context in
    let mode = Context.best_mode ctx in
    let compiler = Option.value_exn (Context.compiler ctx mode) in
    let pp_names = pp_names @ [migrate_driver_main] in
    let libs =
      Libs.closure sctx ~dir ~dep_kind (List.map pp_names ~f:Lib_dep.direct)
    in
    let libs =
      (* Put the driver back at the end, just before migrate_driver_main *)
      match driver with
      | None -> libs
      | Some driver ->
        libs >>^ fun libs ->
        let is_driver name = name = driver || name = migrate_driver_main in
        let libs, drivers =
          List.partition_map libs ~f:(fun lib ->
            if (match lib with
              | External pkg -> is_driver pkg.name
              | Internal (_, lib) ->
                is_driver lib.name ||
                match lib.public with
                | None -> false
                | Some { name; _ } -> is_driver name)
            then
              Inr lib
            else
              Inl lib)
        in
        let user_driver, migrate_driver =
          List.partition_map drivers ~f:(fun lib ->
            if Lib.best_name lib = migrate_driver_main then
              Inr lib
            else
              Inl lib)
        in
        libs @ user_driver @ migrate_driver
    in
    (* Provide a better error for migrate_driver_main given that this is an implicit
       dependency *)
    let libs =
      match Libs.find sctx ~from:dir migrate_driver_main with
      | None ->
        Build.fail { fail = fun () ->
          die "@{<error>Error@}: I couldn't find '%s'.\n\
               I need this library in order to use ppx rewriters.\n\
               See the manual for details.\n\
               Hint: opam install ocaml-migrate-parsetree"
            migrate_driver_main
        }
        >>>
        libs
      | Some _ ->
        libs
    in
    add_rule sctx
      (libs
       >>>
       Build.dyn_paths (Build.arr (Lib.archive_files ~mode ~ext_lib:ctx.ext_lib))
       >>>
       Build.run ~context:ctx (Dep compiler)
         [ A "-o" ; Target target
         ; Dyn (Lib.link_flags ~mode)
         ])

  let get_ppx_driver sctx pps ~dir ~dep_kind =
    let driver, names =
      match List.rev_map pps ~f:Pp.to_string with
      | [] -> (None, [])
      | driver :: rest ->
        (Some driver, List.sort rest ~cmp:String.compare @ [driver])
    in
    let key =
      match names with
      | [] -> "+none+"
      | _  -> String.concat names ~sep:"+"
    in
    match Hashtbl.find sctx.ppx_drivers key with
    | Some x -> x
    | None ->
      let ppx_dir = Path.relative sctx.ppx_dir key in
      let exe = Path.relative ppx_dir "ppx.exe" in
      build_ppx_driver sctx names ~dir ~dep_kind ~target:exe ~driver;
      Hashtbl.add sctx.ppx_drivers ~key ~data:exe;
      exe

  let target_var = String_with_vars.of_string "${@}" ~loc:Loc.none
  let root_var   = String_with_vars.of_string "${ROOT}" ~loc:Loc.none

  let cookie_library_name lib_name =
    match lib_name with
    | None -> []
    | Some name -> ["--cookie"; sprintf "library-name=%S" name]

  (* Generate rules for the reason modules in [modules] and return a
     a new module with only OCaml sources *)
  let setup_reason_rules sctx ~dir (m : Module.t) =
    let ctx = sctx.context in
    let refmt = resolve_program sctx "refmt" ~hint:"opam install reason" in
    let rule src target =
      let src_path = Path.relative dir src in
      Build.run ~context:ctx refmt
        [ A "--print"
        ; A "binary"
        ; Dep src_path ]
        ~stdout_to:(Path.relative dir target) in
    let impl =
      match m.impl.syntax with
      | OCaml -> m.impl
      | Reason ->
        let ml = Module.File.to_ocaml m.impl in
        add_rule sctx (rule m.impl.name ml.name);
        ml in
    let intf =
      Option.map m.intf ~f:(fun f ->
        match f.syntax with
        | OCaml -> f
        | Reason ->
          let mli = Module.File.to_ocaml f in
          add_rule sctx (rule f.name mli.name);
          mli) in
    { m with impl ; intf }

  (* Generate rules to build the .pp files and return a new module map where all filenames
     point to the .pp files *)
  let pped_modules sctx ~dir ~dep_kind ~modules ~preprocess ~preprocessor_deps ~lib_name
        ~package_context =
    let preprocessor_deps =
      Build.memoize "preprocessor deps"
        (Deps.interpret sctx ~dir preprocessor_deps)
    in
    String_map.map modules ~f:(fun (m : Module.t) ->
      let m = setup_reason_rules sctx ~dir m in
      match Preprocess_map.find m.name preprocess with
      | No_preprocessing -> m
      | Action action ->
        pped_module m ~dir ~f:(fun _kind src dst ->
          add_rule sctx
            (preprocessor_deps
             >>>
             Build.path src
             >>>
             Action.run sctx
               (Redirect
                  (Stdout,
                   target_var,
                   Chdir (root_var,
                          action)))
               ~dir
               ~dep_kind
               ~targets:[dst]
               ~package_context))
      | Pps { pps; flags } ->
        let ppx_exe = get_ppx_driver sctx pps ~dir ~dep_kind in
        pped_module m ~dir ~f:(fun kind src dst ->
          add_rule sctx
            (preprocessor_deps
             >>>
             Build.run ~context:sctx.context
               (Dep ppx_exe)
               [ As flags
               ; A "--dump-ast"
               ; As (cookie_library_name lib_name)
               ; A "-o"; Target dst
               ; Ml_kind.ppx_driver_flag kind; Dep src
               ])
        )
    )
end

let expand_and_eval_set ~dir set ~standard =
  let open Build.O in
  match Ordered_set_lang.Unexpanded.files set |> String_set.elements with
  | [] ->
    let set = Ordered_set_lang.Unexpanded.expand set ~files_contents:String_map.empty in
    Build.return (Ordered_set_lang.eval_with_standard set ~standard)
  | files ->
    let paths = List.map files ~f:(Path.relative dir) in
    Build.all (List.map paths ~f:Build.read_sexp)
    >>^ fun sexps ->
    let files_contents = List.combine files sexps |> String_map.of_alist_exn in
    let set = Ordered_set_lang.Unexpanded.expand set ~files_contents in
    Ordered_set_lang.eval_with_standard set ~standard
