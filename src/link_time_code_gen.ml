open Import

module CC = Compilation_context
module SC = Super_context

type t =
  { to_link : Lib.Lib_and_module.t list
  ; force_linkall : bool
  }

let generate_and_compile_module cctx ~name:basename ~code ~requires =
  let sctx       = CC.super_context cctx in
  let obj_dir    = CC.obj_dir       cctx in
  let dir        = CC.dir           cctx in
  let name = Module.Name.of_string basename in
  let module_ =
    let src_dir = Path.build (Obj_dir.obj_dir obj_dir) in
    Module.generated ~src_dir name
  in
  SC.add_rule ~dir sctx (
    let ml =
      Module.file module_ ~ml_kind:Impl
      |> Option.value_exn
      |> Path.as_in_build_dir_exn
    in
    Build.write_file ml code);
  let opaque =
    Ocaml_version.supports_opaque_for_mli
      (Super_context.context sctx).version
  in
  let cctx =
    Compilation_context.create
      ~super_context:sctx
      ~expander:(Compilation_context.expander cctx)
      ~scope:(Compilation_context.scope cctx)
      ~dir_kind:(Compilation_context.dir_kind cctx)
      ~obj_dir
      ~modules:(Module.Name.Map.singleton name module_)
      ~requires_compile:requires
      ~requires_link:(lazy requires)
      ~flags:Ocaml_flags.empty
      ~opaque
      ~dynlink:(Compilation_context.dynlink cctx)
      ()
  in
  Module_compilation.build_module
    ~dep_graphs:(Dep_graph.Ml_kind.dummy module_)
    cctx
    module_;
  module_

let findlib_init_code ~preds ~libs =
  let public_libs =
    List.filter
      ~f:(fun lib ->
        let info = Lib.info lib in
        let status = Lib_info.status info in
        not (Lib_info.Status.is_private status))
      libs
  in
  Format.asprintf "%t@." (fun ppf ->
    List.iter public_libs ~f:(fun lib ->
      Format.fprintf ppf "Findlib.record_package Findlib.Record_core %a;;@\n"
        Lib_name.pp_quoted (Lib.name lib));
    Format.fprintf ppf "let preds = %a in@\n"
      (Fmt.ocaml_list Variant.pp)
      (Variant.Set.to_list preds);
    Format.fprintf ppf "let preds = (if Dynlink.is_native then \
                        \"native\" else \"byte\") :: preds in@\n";
    Format.fprintf ppf "Findlib.record_package_predicates preds;;@\n")

let handle_special_libs cctx =
  Result.map (CC.requires_link cctx) ~f:(fun libs ->
    let sctx = CC.super_context cctx in
    let module M = Dune_file.Library.Special_builtin_support.Map in
    let specials = Lib.L.special_builtin_support libs in
    let to_link = Lib.Lib_and_module.L.of_libs libs in
    if not (M.mem specials Findlib_dynload) then
      { force_linkall = false
      ; to_link
      }
    else begin
      (* If findlib.dynload is linked, we stores in the binary the
         packages linked by linking just after findlib.dynload a
         module containing the info *)
      let requires =
        let open Result.O in
        (* This shouldn't fail since findlib.dynload depends on
           dynlink and findlib. That's why it's ok to use a dummy
           location. *)
        let+ dynlink =
          Lib.DB.resolve (SC.public_libs sctx)
            (Loc.none, Lib_name.of_string_exn ~loc:None "dynlink")
        and+ findlib =
          Lib.DB.resolve (SC.public_libs sctx)
            (Loc.none, Lib_name.of_string_exn ~loc:None "findlib")
        in
        [ dynlink; findlib ]
      in
      let code = findlib_init_code ~preds:Findlib.Package.preds ~libs in
      let module_ =
        generate_and_compile_module
          cctx
          ~name:"findlib_initl"
          ~code
          ~requires
      in
      let obj_dir = Compilation_context.obj_dir cctx in
      let rec insert = function
        | [] -> assert false
        | x :: l ->
          match x with
          | Lib.Lib_and_module.Module _ ->
            x :: insert l
          | Lib lib ->
            let info = Lib.info lib in
            let special_builtin_support = Lib_info.special_builtin_support info in
            match special_builtin_support with
            | Some Findlib_dynload ->
              let obj_dir = Obj_dir.of_local obj_dir in
              x :: Module (obj_dir, module_) :: l
            | _ -> x :: insert l
      in
      { force_linkall = true
      ; to_link = insert to_link
      }
    end)
