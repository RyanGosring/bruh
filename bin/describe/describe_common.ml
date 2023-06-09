open Stdune
open Import

(* This command is not yet versioned, but some people are using it in
   non-released tools. If you change the format of the output, please contact:

   - rotor people for "describe workspace"

   - duniverse people for "describe opam-files" *)

(** whether to sanitize absolute paths of workspace items, and their UIDs, to
    ensure reproducible tests *)
let sanitize_for_tests = ref false

(** Option flags for what to do while crawling the workspace *)
type options =
  { with_deps : bool
        (** whether to compute direct dependencies between modules *)
  ; with_pps : bool
        (** whether to include the dependencies to ppx-rewriters (that are used
            at compile time) *)
  }

(** The module [Descr] is a typed representation of the description of a
    workspace, that is provided by the ``dune describe workspace`` command.

    Each sub-module contains a [to_dyn] function, that translates the
    descriptors to a value of type [Dyn.t].

    The typed representation aims at precisely describing the structure of the
    information computed by ``dune describe``, and hopefully make users' life
    easier in decoding the S-expressions into meaningful contents. *)
module Descr = struct
  (** [dyn_path p] converts a path to a value of type [Dyn.t]. Remark: this is
      different from Path.to_dyn, that produces extra tags from a variant
      datatype. *)
  let dyn_path (p : Path.t) : Dyn.t = String (Path.to_string p)

  (** Description of the dependencies of a module *)
  module Mod_deps = struct
    type t =
      { for_intf : Dune_rules.Module_name.t list
            (** direct module dependencies for the interface *)
      ; for_impl : Dune_rules.Module_name.t list
            (** direct module dependencies for the implementation *)
      }

    (** Conversion to the [Dyn.t] type *)
    let to_dyn { for_intf; for_impl } =
      let open Dyn in
      record
        [ ("for_intf", list Dune_rules.Module_name.to_dyn for_intf)
        ; ("for_impl", list Dune_rules.Module_name.to_dyn for_impl)
        ]
  end

  (** Description of modules *)
  module Mod = struct
    type t =
      { name : Dune_rules.Module_name.t  (** name of the module *)
      ; impl : Path.t option  (** path to the .ml file, if any *)
      ; intf : Path.t option  (** path to the .mli file, if any *)
      ; cmt : Path.t option  (** path to the .cmt file, if any *)
      ; cmti : Path.t option  (** path to the .cmti file, if any *)
      ; module_deps : Mod_deps.t  (** direct module dependencies *)
      }

    (** Conversion to the [Dyn.t] type *)
    let to_dyn options { name; impl; intf; cmt; cmti; module_deps } : Dyn.t =
      let open Dyn in
      let optional_fields =
        let module_deps =
          if options.with_deps then
            Some ("module_deps", Mod_deps.to_dyn module_deps)
          else None
        in
        (* we build a list of options, that is later filtered, so that adding
           new optional fields in the future can be done easily *)
        match module_deps with
        | None -> []
        | Some module_deps -> [ module_deps ]
      in
      record
      @@ [ ("name", Dune_rules.Module_name.to_dyn name)
         ; ("impl", option dyn_path impl)
         ; ("intf", option dyn_path intf)
         ; ("cmt", option dyn_path cmt)
         ; ("cmti", option dyn_path cmti)
         ]
      @ optional_fields
  end

  (** Description of executables *)
  module Exe = struct
    type t =
      { names : string list  (** names of the executable *)
      ; requires : Digest.t list
            (** list of direct dependencies to libraries, identified by their
                digests *)
      ; modules : Mod.t list
            (** list of the modules the executable is composed of *)
      ; include_dirs : Path.t list  (** list of include directories *)
      }

    let map_path t ~f = { t with include_dirs = List.map ~f t.include_dirs }

    (** Conversion to the [Dyn.t] type *)
    let to_dyn options { names; requires; modules; include_dirs } : Dyn.t =
      let open Dyn in
      record
        [ ("names", List (List.map ~f:(fun name -> String name) names))
        ; ("requires", Dyn.(list string) (List.map ~f:Digest.to_string requires))
        ; ("modules", list (Mod.to_dyn options) modules)
        ; ("include_dirs", list dyn_path include_dirs)
        ]
  end

  (** Description of libraries *)
  module Lib = struct
    type t =
      { name : Lib_name.t  (** name of the library *)
      ; uid : Digest.t  (** digest of the library *)
      ; local : bool  (** whether this library is local *)
      ; requires : Digest.t list
            (** list of direct dependendies to libraries, identified by their
                digests *)
      ; source_dir : Path.t
            (** path to the directory that contains the sources of this library *)
      ; modules : Mod.t list
            (** list of the modules the executable is composed of *)
      ; include_dirs : Path.t list  (** list of include directories *)
      }

    let map_path t ~f =
      { t with
        source_dir = f t.source_dir
      ; include_dirs = List.map ~f t.include_dirs
      }

    (** Conversion to the [Dyn.t] type *)
    let to_dyn options
        { name; uid; local; requires; source_dir; modules; include_dirs } :
        Dyn.t =
      let open Dyn in
      record
        [ ("name", Lib_name.to_dyn name)
        ; ("uid", String (Digest.to_string uid))
        ; ("local", Bool local)
        ; ("requires", (list string) (List.map ~f:Digest.to_string requires))
        ; ("source_dir", dyn_path source_dir)
        ; ("modules", list (Mod.to_dyn options) modules)
        ; ("include_dirs", (list dyn_path) include_dirs)
        ]
  end

  (** Description of items: executables, or libraries *)
  module Item = struct
    type t =
      | Executables of Exe.t
      | Library of Lib.t
      | Root of Path.t
      | Build_context of Path.t

    let map_path t ~f =
      match t with
      | Executables exe -> Executables (Exe.map_path exe ~f)
      | Library lib -> Library (Lib.map_path lib ~f)
      | Root r -> Root (f r)
      | Build_context c -> Build_context (f c)

    (** Conversion to the [Dyn.t] type *)
    let to_dyn options : t -> Dyn.t = function
      | Executables exe_descr ->
        Variant ("executables", [ Exe.to_dyn options exe_descr ])
      | Library lib_descr ->
        Variant ("library", [ Lib.to_dyn options lib_descr ])
      | Root root ->
        Variant ("root", [ String (Path.to_absolute_filename root) ])
      | Build_context build_ctxt ->
        Variant ("build_context", [ String (Path.to_string build_ctxt) ])
  end

  (** Description of a workspace: a list of items *)
  module Workspace = struct
    type t = Item.t list

    (** Conversion to the [Dyn.t] type *)
    let to_dyn options (items : t) : Dyn.t =
      Dyn.list (Item.to_dyn options) items
  end
end

(** Crawl the workspace to get all the data *)
module Crawl = struct
  open Dune_rules
  open Dune_engine
  open Memo.O
  module Ml_kind = Ocaml.Ml_kind

  (** Computes the digest of a library *)
  let uid_of_library (lib : Lib.t) : Digest.t =
    let name = Lib.name lib in
    if Lib.is_local lib then
      let source_dir = Lib_info.src_dir (Lib.info lib) in
      Digest.generic (name, Path.to_string source_dir)
    else Digest.generic name

  let immediate_deps_of_module ~options ~obj_dir ~modules unit =
    match options.with_deps with
    | false -> Action_builder.return { Ml_kind.Dict.intf = []; impl = [] }
    | true ->
      let deps = Dune_rules.Dep_rules.immediate_deps_of unit modules obj_dir in
      let open Action_builder.O in
      let+ intf, impl = Action_builder.both (deps Intf) (deps Impl) in
      { Ml_kind.Dict.intf; impl }

  (** Builds the description of a module from a module and its object directory *)
  let module_ ~obj_dir ~(deps_for_intf : Module.t list)
      ~(deps_for_impl : Module.t list) (m : Module.t) : Descr.Mod.t =
    let source ml_kind =
      Option.map (Module.source m ~ml_kind) ~f:Module.File.path
    in
    let cmt ml_kind =
      Dune_rules.Obj_dir.Module.cmt_file obj_dir m ~ml_kind ~cm_kind:(Ocaml Cmi)
    in
    { Descr.Mod.name = Module.name m
    ; impl = source Impl
    ; intf = source Intf
    ; cmt = cmt Impl
    ; cmti = cmt Intf
    ; module_deps =
        { for_intf = List.map ~f:Module.name deps_for_intf
        ; for_impl = List.map ~f:Module.name deps_for_impl
        }
    }

  (** Builds the list of modules *)
  let modules ~obj_dir
      ~(deps_of : Module.t -> Module.t list Ml_kind.Dict.t Action_builder.t)
      (modules_ : Modules.t) : Descr.Mod.t list Memo.t =
    Modules.fold_no_vlib ~init:(Memo.return []) modules_ ~f:(fun m macc ->
        let* acc = macc in
        let deps = deps_of m in
        let+ { Ml_kind.Dict.intf = deps_for_intf; impl = deps_for_impl }, _ =
          Dune_engine.Action_builder.run deps Eager
        in
        module_ ~obj_dir ~deps_for_intf ~deps_for_impl m :: acc)

  (** Builds a workspace item for the provided executables object *)
  let executables sctx ~options ~project ~dir (exes : Dune_file.Executables.t) :
      (Descr.Item.t * Lib.Set.t) option Memo.t =
    let first_exe = snd (List.hd exes.names) in
    let* modules_, obj_dir =
      Dir_contents.get sctx ~dir >>= Dir_contents.ocaml
      >>| Ml_sources.modules_and_obj_dir ~for_:(Exe { first_exe })
    in

    let pp_map =
      Staged.unstage
      @@
      let version = (Super_context.context sctx).ocaml.version in
      Preprocessing.pped_modules_map
        (Preprocess.Per_module.without_instrumentation exes.buildable.preprocess)
        version
    in
    let deps_of module_ =
      let module_ = pp_map module_ in
      immediate_deps_of_module ~options ~obj_dir ~modules:modules_ module_
    in
    let obj_dir = Obj_dir.of_local obj_dir in
    let* scope =
      Scope.DB.find_by_project (Super_context.context sctx) project
    in
    let* modules_ = modules ~obj_dir ~deps_of modules_ in
    let+ requires =
      let* compile_info = Exe_rules.compile_info ~scope exes in
      let open Resolve.Memo.O in
      let* requires = Lib.Compile.direct_requires compile_info in
      if options.with_pps then
        let+ pps = Lib.Compile.pps compile_info in
        pps @ requires
      else Resolve.Memo.return requires
    in
    match Resolve.peek requires with
    | Error () -> None
    | Ok libs ->
      let include_dirs = Obj_dir.all_cmis obj_dir in
      let exe_descr =
        { Descr.Exe.names = List.map ~f:snd exes.names
        ; requires = List.map ~f:uid_of_library libs
        ; modules = modules_
        ; include_dirs
        }
      in
      Some (Descr.Item.Executables exe_descr, Lib.Set.of_list libs)

  (** Builds a workspace item for the provided library object *)
  let library sctx ~options (lib : Lib.t) : Descr.Item.t option Memo.t =
    let* requires = Lib.requires lib in
    match Resolve.peek requires with
    | Error () -> Memo.return None
    | Ok requires ->
      let name = Lib.name lib in
      let info = Lib.info lib in
      let src_dir = Lib_info.src_dir info in
      let obj_dir = Lib_info.obj_dir info in
      let+ modules_ =
        match Lib.is_local lib with
        | false -> Memo.return []
        | true ->
          Dir_contents.get sctx ~dir:(Path.as_in_build_dir_exn src_dir)
          >>= Dir_contents.ocaml
          >>| Ml_sources.modules_and_obj_dir ~for_:(Library name)
          >>= fun (modules_, obj_dir_) ->
          let pp_map =
            Staged.unstage
            @@
            let version = (Super_context.context sctx).ocaml.version in
            Preprocessing.pped_modules_map
              (Preprocess.Per_module.without_instrumentation
                 (Lib_info.preprocess info))
              version
          in
          let deps_of module_ =
            immediate_deps_of_module ~options ~obj_dir:obj_dir_
              ~modules:modules_ (pp_map module_)
          in
          modules ~obj_dir ~deps_of modules_
      in
      let include_dirs = Obj_dir.all_cmis obj_dir in
      let lib_descr =
        { Descr.Lib.name
        ; uid = uid_of_library lib
        ; local = Lib.is_local lib
        ; requires = List.map requires ~f:uid_of_library
        ; source_dir = src_dir
        ; modules = modules_
        ; include_dirs
        }
      in
      Some (Descr.Item.Library lib_descr)

  (** [source_path_is_in_dirs dirs p] tests whether the source path [p] is a
      descendant of some of the provided directory [dirs]. If [dirs = None],
      then it always succeeds. If [dirs = Some l], then a matching directory is
      search in the list [l]. *)
  let source_path_is_in_dirs dirs (p : Path.Source.t) =
    match dirs with
    | None -> true
    | Some dirs ->
      List.exists ~f:(fun dir -> Path.Source.is_descendant p ~of_:dir) dirs

  (** Tests whether a dune file is located in a path that is a descendant of
      some directory *)
  let dune_file_is_in_dirs dirs (dune_file : Dune_file.t) =
    source_path_is_in_dirs dirs dune_file.dir

  (** Tests whether a library is located in a path that is a descendant of some
      directory *)
  let lib_is_in_dirs dirs (lib : Lib.t) =
    source_path_is_in_dirs dirs
      (Path.drop_build_context_exn @@ Lib_info.best_src_dir @@ Lib.info lib)

  (** Builds a workspace item for the root path *)
  let root () = Descr.Item.Root Path.root

  (** Builds a workspace item for the build directory path *)
  let build_ctxt (context : Context.t) : Descr.Item.t =
    Descr.Item.Build_context (Path.build context.build_dir)

  (** Builds a workspace description for the provided dune setup and context *)
  let workspace options dirs
      ({ Dune_rules.Main.conf; contexts = _; scontexts } :
        Dune_rules.Main.build_system) (context : Context.t) :
      Descr.Workspace.t Memo.t =
    let sctx = Context_name.Map.find_exn scontexts context.name in
    let open Memo.O in
    let* dune_files =
      Dune_load.Dune_files.eval conf.dune_files ~context
      >>| List.filter ~f:(dune_file_is_in_dirs dirs)
    in
    let* exes, exe_libs =
      (* the list of workspace items that describe executables, and the list of
         their direct library dependencies *)
      Memo.parallel_map dune_files ~f:(fun (dune_file : Dune_file.t) ->
          Memo.parallel_map dune_file.stanzas ~f:(fun stanza ->
              let dir =
                Path.Build.append_source context.build_dir dune_file.dir
              in
              match stanza with
              | Dune_file.Executables exes ->
                executables sctx ~options ~project:dune_file.project ~dir exes
              | _ -> Memo.return None)
          >>| List.filter_opt)
      >>| List.concat >>| List.split
    in
    let exe_libs =
      (* conflate the dependencies of executables into a single set *)
      Lib.Set.union_all exe_libs
    in
    let* project_libs =
      let ctx = Super_context.context sctx in
      (* the list of libraries declared in the project *)
      Memo.parallel_map conf.projects ~f:(fun project ->
          let* scope = Scope.DB.find_by_project ctx project in
          Scope.libs scope |> Lib.DB.all)
      >>| Lib.Set.union_all
      >>| Lib.Set.filter ~f:(lib_is_in_dirs dirs)
    in

    let+ libs =
      (* the executables' libraries, and the project's libraries *)
      Lib.Set.union exe_libs project_libs
      |> Lib.Set.to_list
      |> Lib.descriptive_closure ~with_pps:options.with_pps
      >>= Memo.parallel_map ~f:(library ~options sctx)
      >>| List.filter_opt
    in
    let root = root () in
    let build_ctxt = build_ctxt context in
    root :: build_ctxt :: (exes @ libs)
end


module Format = struct
  type t =
    | Sexp
    | Csexp

  let all = [ ("sexp", Sexp); ("csexp", Csexp) ]

  let arg =
    let doc = Printf.sprintf "$(docv) must be %s" (Arg.doc_alts_enum all) in
    Arg.(value & opt (enum all) Sexp & info [ "format" ] ~docv:"FORMAT" ~doc)

  let print_as_sexp dyn =
    let rec dune_lang_of_sexp : Sexp.t -> Dune_lang.t = function
      | Atom s -> Dune_lang.atom_or_quoted_string s
      | List l -> List (List.map l ~f:dune_lang_of_sexp)
    in
    let cst =
      dyn |> Sexp.of_dyn |> dune_lang_of_sexp
      |> Dune_lang.Ast.add_loc ~loc:Loc.none
      |> Dune_lang.Cst.concrete
    in
    let version = Dune_lang.Syntax.greatest_supported_version Stanza.syntax in
    Pp.to_fmt Stdlib.Format.std_formatter
      (Dune_lang.Format.pp_top_sexps ~version [ cst ])

  let print_dyn t dyn =
    match t with
    | Csexp -> Csexp.to_channel stdout (Sexp.of_dyn dyn)
    | Sexp -> print_as_sexp dyn
end
