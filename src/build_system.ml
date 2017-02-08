open Import
open Future

module Pset  = Path.Set
module Pmap  = Path.Map
module Vspec = Build.Vspec

module Exec_status = struct
  type t =
    | Not_started of (targeting:Path.t -> unit Future.t)
    | Starting of { for_file : Path.t }
    | Running of { for_file : Path.t; future : unit Future.t }
end

module Rule = struct
  type t =
    { deps         : Pset.t
    ; targets      : Pset.t
    ; lib_deps     : Build.lib_deps Pmap.t
    ; mutable exec : Exec_status.t
    }
end

module File_kind = struct
  type 'a t =
    | Ignore_contents : unit t
    | Sexp_file       : 'a Vfile_kind.t -> 'a t

  let eq : type a b. a t -> b t -> (a, b) eq option = fun a b ->
    match a, b with
    | Ignore_contents, Ignore_contents -> Some Eq
    | Sexp_file a    , Sexp_file b     -> Vfile_kind.eq a b
    | _                                -> None

  let eq_exn a b = Option.value_exn (eq a b)
end

module File_spec = struct
  type 'a t =
    { rule         : Rule.t (* Rule which produces it *)
    ; mutable kind : 'a File_kind.t
    ; mutable data : 'a option
    }

  type packed = T : _ t -> packed

  let create rule kind =
    T { rule; kind; data = None }
end

type t =
  { (* File specification by targets *)
    files : (Path.t, File_spec.packed) Hashtbl.t
  }

let find_file_exn t file =
  Hashtbl.find_exn t.files file ~string_of_key:(fun fn -> sprintf "%S" (Path.to_string fn))
    ~table_desc:(fun _ -> "<target to rule>")

module Build_error = struct
  type t =
    { backtrace : Printexc.raw_backtrace
    ; dep_path  : Path.t list
    ; exn       : exn
    }

  let backtrace t = t.backtrace
  let dependency_path t = t.dep_path
  let exn t = t.exn

  exception E of t

  let raise t ~targeting ~backtrace exn =
    let rec build_path acc targeting ~seen =
      assert (not (Pset.mem targeting seen));
      let seen = Pset.add targeting seen in
      let (File_spec.T file) = find_file_exn t targeting in
      match file.rule.exec with
      | Not_started _ -> assert false
      | Running { for_file; _ } | Starting { for_file } ->
        if for_file = targeting then
          acc
        else
          build_path (for_file :: acc) for_file ~seen
    in
    let dep_path = build_path [targeting] targeting ~seen:Pset.empty in
    raise (E { backtrace; dep_path; exn })
end

let wait_for_file t fn ~targeting =
  match Hashtbl.find t.files fn with
  | None ->
    if Path.is_in_build_dir fn then
      die "no rule found for %s" (Path.to_string fn)
    else if Path.exists fn then
      return ()
    else
      die "file unavailable: %s" (Path.to_string fn)
  | Some (File_spec.T file) ->
    match file.rule.exec with
    | Not_started f ->
      file.rule.exec <- Starting { for_file = targeting };
      let future =
        with_exn_handler (fun () -> f ~targeting:fn)
          ~handler:(fun exn backtrace ->
              match exn with
              | Build_error.E _ -> reraise exn
              | exn -> Build_error.raise t exn ~targeting:fn ~backtrace)
      in
      file.rule.exec <- Running { for_file = targeting; future };
      future
    | Running { future; _ } -> future
    | Starting _ ->
      (* Recursive deps! *)
      let rec build_loop acc targeting =
        let acc = targeting :: acc in
        if fn = targeting then
          acc
        else
          let (File_spec.T file) = find_file_exn t targeting in
          match file.rule.exec with
          | Not_started _ | Running _ -> assert false
          | Starting { for_file } ->
            build_loop acc for_file
      in
      let loop = build_loop [fn] targeting in
      die "Dependency cycle between the following files:\n    %s"
        (String.concat ~sep:"\n--> "
           (List.map loop ~f:Path.to_string))

module Target = struct
  type t =
    | Normal of Path.t
    | Vfile : _ Vspec.t -> t

  let path = function
    | Normal p -> p
    | Vfile (Vspec.T (p, _)) -> p

  let paths ts =
    List.fold_left ts ~init:Pset.empty ~f:(fun acc t ->
      Pset.add (path t) acc)
end

let get_file : type a. t -> Path.t -> a File_kind.t -> a File_spec.t = fun t fn kind ->
  match Hashtbl.find t.files fn with
  | None -> die "no rule found for %s" (Path.to_string fn)
  | Some (File_spec.T file) ->
    let Eq = File_kind.eq_exn kind file.kind in
    file

let save_vfile (type a) (module K : Vfile_kind.S with type t = a) fn x =
  K.save x ~filename:(Path.to_string fn)

module Build_interpret = struct
  include Build.Repr

  let deps t ~all_targets_by_dir =
    let rec loop : type a b. (a, b) t -> Pset.t -> Pset.t = fun t acc ->
      match t with
      | Arr _ -> acc
      | Prim _ -> acc
      | Store_vfile _ -> acc
      | Compose (a, b) -> loop a (loop b acc)
      | First t -> loop t acc
      | Second t -> loop t acc
      | Split (a, b) -> loop a (loop b acc)
      | Fanout (a, b) -> loop a (loop b acc)
      | Paths fns -> Pset.union fns acc
      | Vpath (Vspec.T (fn, _)) -> Pset.add fn acc
      | Paths_glob (dir, re) -> begin
          match Pmap.find dir (Lazy.force all_targets_by_dir) with
          | None -> Pset.empty
          | Some targets ->
            Pset.filter targets ~f:(fun path ->
                Re.execp re (Path.basename path))
        end
      | Dyn_paths t -> loop t acc
      | Record_lib_deps _ -> acc
      | Fail _ -> acc
    in
    loop t Pset.empty

  let lib_deps =
    let rec loop : type a b. (a, b) t -> Build.lib_deps Pmap.t -> Build.lib_deps Pmap.t
      = fun t acc ->
        match t with
        | Arr _ -> acc
        | Prim _ -> acc
        | Store_vfile _ -> acc
        | Compose (a, b) -> loop a (loop b acc)
        | First t -> loop t acc
        | Second t -> loop t acc
        | Split (a, b) -> loop a (loop b acc)
        | Fanout (a, b) -> loop a (loop b acc)
        | Paths _ -> acc
        | Vpath _ -> acc
        | Paths_glob _ -> acc
        | Dyn_paths t -> loop t acc
        | Record_lib_deps (dir, deps) ->
          let data =
            match Pmap.find dir acc with
            | None -> deps
            | Some others -> Build.merge_lib_deps deps others
          in
          Pmap.add acc ~key:dir ~data
        | Fail _ -> acc
    in
    fun t -> loop t Pmap.empty

  let targets =
    let rec loop : type a b. (a, b) t -> Target.t list -> Target.t list = fun t acc ->
      match t with
      | Arr _ -> acc
      | Prim { targets; _ } ->
        List.fold_left targets ~init:acc ~f:(fun acc fn -> Target.Normal fn :: acc)
      | Store_vfile spec -> Vfile spec :: acc
      | Compose (a, b) -> loop a (loop b acc)
      | First t -> loop t acc
      | Second t -> loop t acc
      | Split (a, b) -> loop a (loop b acc)
      | Fanout (a, b) -> loop a (loop b acc)
      | Paths _ -> acc
      | Vpath _ -> acc
      | Paths_glob _ -> acc
      | Dyn_paths t -> loop t acc
      | Record_lib_deps _ -> acc
      | Fail _ -> acc
    in
    fun t -> loop t []

  let exec bs t x ~targeting =
    let rec exec
      : type a b. (a, b) t -> a -> b Future.t = fun t x ->
      let return = Future.return in
      match t with
      | Arr f -> return (f x)
      | Prim { exec; _ } -> exec x
      | Store_vfile (Vspec.T (fn, kind)) ->
        let file = get_file bs fn (Sexp_file kind) in
        assert (file.data = None);
        file.data <- Some x;
        save_vfile kind fn x;
        Future.return ()
      | Compose (a, b) ->
        exec a x >>= exec b
      | First t ->
        let x, y = x in
        exec t x >>= fun x ->
        return (x, y)
      | Second t ->
        let x, y = x in
        exec t y >>= fun y ->
        return (x, y)
      | Split (a, b) ->
        let x, y = x in
        both (exec a x) (exec b y)
      | Fanout (a, b) ->
        both (exec a x) (exec b x)
      | Paths _ -> return x
      | Paths_glob _ -> return x
      | Vpath (Vspec.T (fn, kind)) ->
        let file : b File_spec.t = get_file bs fn (Sexp_file kind) in
        return (Option.value_exn file.data)
      | Dyn_paths t ->
        exec t x >>= fun fns ->
        all_unit (List.rev_map fns ~f:(wait_for_file bs ~targeting)) >>= fun () ->
        return x
      | Record_lib_deps _ -> return x
      | Fail { fail } -> fail ()
    in
    exec t x
end

let add_spec t fn spec ~allow_override =
  if not allow_override && Hashtbl.mem t.files fn then
    die "multiple rules generated for %s" (Path.to_string fn);
  Hashtbl.add t.files ~key:fn ~data:spec

let create_file_specs t targets rule ~allow_override =
  List.iter targets ~f:(function
    | Target.Normal fn ->
      add_spec t fn (File_spec.create rule Ignore_contents) ~allow_override
    | Target.Vfile (Vspec.T (fn, kind)) ->
      add_spec t fn (File_spec.create rule (Sexp_file kind)) ~allow_override)

module Pre_rule = struct
  type t =
    { build   : (unit, unit) Build.Repr.t
    ; targets : Target.t list
    }

  let make build =
    let build = Build.repr build in
    { build
    ; targets = Build_interpret.targets build
    }
end

let compile_rule t ~all_targets_by_dir ?(allow_override=false) pre_rule =
  let { Pre_rule. build; targets = target_specs } = pre_rule in
  let deps = Build_interpret.deps build ~all_targets_by_dir in
  let targets = Target.paths target_specs in
  let lib_deps = Build_interpret.lib_deps build in

  if !Clflags.debug_rules then begin
    let f set =
      Pset.elements set
      |> List.map ~f:Path.to_string
      |> String.concat ~sep:", "
    in
    if Pmap.is_empty lib_deps then
      Printf.eprintf "{%s} -> {%s}\n" (f deps) (f targets)
    else
      let lib_deps =
        Pmap.fold lib_deps ~init:String_map.empty ~f:(fun ~key:_ ~data acc ->
          Build.merge_lib_deps acc data)
        |> String_map.bindings
        |> List.map ~f:(fun (name, kind) ->
          match (kind : Build.lib_dep_kind) with
          | Required -> name
          | Optional -> sprintf "%s (optional)" name)
        |> String.concat ~sep:", "
      in
      Printf.eprintf "{%s}, libs:{%s} -> {%s}\n" (f deps) lib_deps (f targets)
  end;

  let exec = Exec_status.Not_started (fun ~targeting ->
    Pset.iter targets ~f:(fun fn ->
      match Path.kind fn with
      | Local local -> Path.Local.ensure_parent_directory_exists local
      | External _ -> ());
    all_unit
      (Pset.fold deps ~init:[] ~f:(fun fn acc -> wait_for_file t fn ~targeting :: acc))
    >>= fun () ->
    Build_interpret.exec t build () ~targeting
  ) in
  let rule =
    { Rule.
      deps    = deps
    ; targets = targets
    ; lib_deps
    ; exec
    }
  in
  create_file_specs t target_specs rule ~allow_override

let setup_copy_rules t ~all_non_target_source_files ~all_targets_by_dir =
  String_map.iter (Context.all ()) ~f:(fun ~key:_ ~data:(ctx : Context.t) ->
    let ctx_dir = ctx.build_dir in
    Pset.iter all_non_target_source_files ~f:(fun path ->
      let build = Build.copy ~src:path ~dst:(Path.append ctx_dir path) in
      (* We temporarily allow overrides while setting up copy rules
         from the source directory so that artifact that are already
         present in the source directory are not re-computed.

         This allows to keep generated files in tarballs. Maybe we
         should allow it on a case-by-case basis though.  *)
      compile_rule t (Pre_rule.make build)
        ~all_targets_by_dir
        ~allow_override:true))

let create ~file_tree ~rules =
  let rules = List.map rules ~f:Pre_rule.make in
  let all_source_files =
    File_tree.fold file_tree ~init:Pset.empty ~f:(fun dir acc ->
        let path = File_tree.Dir.path dir in
        Pset.union acc
          (File_tree.Dir.files dir
           |> String_set.elements
           |> List.map ~f:(Path.relative path)
           |> Pset.of_list))
  in
  let all_copy_targets =
    String_map.fold (Context.all ()) ~init:Pset.empty ~f:(fun ~key:_ ~data:(ctx : Context.t) acc ->
        Pset.union acc (Pset.elements all_source_files
                        |> List.map ~f:(Path.append ctx.build_dir)
                        |> Pset.of_list))
  in
  let all_other_targets =
    List.fold_left rules ~init:Pset.empty ~f:(fun acc { Pre_rule.targets; _ } ->
      List.fold_left targets ~init:acc ~f:(fun acc target ->
        Pset.add (Target.path target) acc))
  in
  let all_targets_by_dir = lazy (
    Pset.elements (Pset.union all_copy_targets all_other_targets)
    |> List.filter_map ~f:(fun path ->
      if Path.is_root path then
        None
      else
        Some (Path.parent path, path))
    |> Pmap.of_alist_multi
    |> Pmap.map ~f:Pset.of_list
  ) in
  let t = { files = Hashtbl.create 1024 } in
  List.iter rules ~f:(compile_rule t ~all_targets_by_dir ~allow_override:false);
  setup_copy_rules t ~all_targets_by_dir
    ~all_non_target_source_files:
      (Pset.diff all_source_files all_other_targets);
  t

let remove_old_artifacts t =
  let rec walk dir =
    let keep =
      Path.readdir dir
      |> List.filter ~f:(fun fn ->
        let fn = Path.relative dir fn in
        if Path.is_directory fn then
          walk fn
        else begin
          let keep = Hashtbl.mem t.files fn in
          if not keep then Path.unlink fn;
          keep
        end)
      |> function
      | [] -> false
      | _  -> true
    in
    if not keep then Path.rmdir dir;
    keep
  in
  String_map.iter (Context.all ()) ~f:(fun ~key:_ ~data:(ctx : Context.t) ->
    if Path.exists ctx.build_dir then
      ignore (walk ctx.build_dir : bool))

let do_build_exn t targets =
  remove_old_artifacts t;
  all_unit (List.map targets ~f:(fun fn -> wait_for_file t fn ~targeting:fn))

let do_build t targets =
  try
    Ok (do_build_exn t targets)
  with Build_error.E e ->
    Error e

let rules_for_files t paths =
  List.filter_map paths ~f:(fun path ->
    match Hashtbl.find t.files path with
    | None -> None
    | Some (File_spec.T { rule; _ }) -> Some (path, rule))

module File_closure =
  Top_closure.Make(Path)
    (struct
      type graph = t
      type t = Path.t * Rule.t
      let key (path, _) = path
      let deps (_, rule) bs = rules_for_files bs (Pset.elements rule.Rule.deps)
    end)

let all_lib_deps t targets =
  match File_closure.top_closure t (rules_for_files t targets) with
  | Ok l ->
    List.fold_left l ~init:Pmap.empty ~f:(fun acc (_, rule) ->
      Pmap.merge acc rule.Rule.lib_deps ~f:(fun _ a b ->
        match a, b with
        | None, None -> None
        | Some a, None -> Some a
        | None, Some b -> Some b
        | Some a, Some b -> Some (Build.merge_lib_deps a b)))
  | Error cycle ->
    die "dependency cycle detected:\n   %s"
      (List.map cycle ~f:(fun (path, _) -> Path.to_string path)
       |> String.concat ~sep:"\n-> ")
