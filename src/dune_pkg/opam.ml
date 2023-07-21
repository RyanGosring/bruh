open Stdune
module Package_name = Dune_lang.Package_name

module Local_repo = struct
  let ( / ) = Filename.concat

  type t = { packages_dir_path : Filename.t }

  let minimum_opam_version = OpamVersion.of_string "2.0"

  let validate_repo_file opam_repo_dir_path =
    let opam_repo_file_path = opam_repo_dir_path / "repo" in
    let repo =
      try
        OpamFilename.raw opam_repo_file_path
        |> OpamFile.make |> OpamFile.Repo.read
      with
      | OpamSystem.Internal_error message ->
        User_error.raise [ Pp.text message ]
      | OpamPp.(Bad_format _ | Bad_format_list _ | Bad_version _) as
        bad_format_exn ->
        User_error.raise
          [ Pp.text (OpamPp.string_of_bad_format bad_format_exn) ]
      | unexpected_exn ->
        Code_error.raise
          (Printf.sprintf
             "Unexpected exception raised while validating opam repo file %s"
             (String.maybe_quoted opam_repo_file_path))
          [ ("exception", Exn.to_dyn unexpected_exn) ]
    in
    match OpamFile.Repo.opam_version repo with
    | None ->
      User_error.raise
        [ Pp.textf "The file %s lacks an \"opam-version\" field."
            (String.maybe_quoted opam_repo_file_path)
        ]
        ~hints:
          [ Pp.textf "Add `opam-version: \"%s\"` to the file."
              (OpamVersion.to_string minimum_opam_version)
          ]
    | Some opam_version ->
      if OpamVersion.compare opam_version minimum_opam_version < 0 then
        User_error.raise
          [ Pp.textf
              "The file %s specifies an opam-version which is too low (%s). \
               The minimum opam-version is %s."
              (String.maybe_quoted opam_repo_file_path)
              (OpamVersion.to_string opam_version)
              (OpamVersion.to_string minimum_opam_version)
          ]
          ~hints:
            [ Pp.textf
                "Change the opam-version field to `opam-version: \"%s\"`."
                (OpamVersion.to_string minimum_opam_version)
            ]

  let of_opam_repo_dir_path opam_repo_dir_path =
    if not (Sys.file_exists opam_repo_dir_path) then
      User_error.raise
        [ Pp.textf "%s does not exist" (String.maybe_quoted opam_repo_dir_path)
        ];
    if not (Sys.is_directory opam_repo_dir_path) then
      User_error.raise
        [ Pp.textf "%s is not a directory"
            (String.maybe_quoted opam_repo_dir_path)
        ];
    let packages_dir_path = opam_repo_dir_path / "packages" in
    if
      not
        (Sys.file_exists packages_dir_path && Sys.is_directory packages_dir_path)
    then
      User_error.raise
        [ Pp.textf
            "%s doesn't look like a path to an opam repository as it lacks a \
             subdirectory named \"packages\""
            (String.maybe_quoted opam_repo_dir_path)
        ];
    validate_repo_file opam_repo_dir_path;
    { packages_dir_path }

  (* Return the path to an "opam" file describing a particular package
     (name and version) from this opam repository. *)
  let get_opam_file_path t opam_package =
    t.packages_dir_path
    / OpamPackage.name_to_string opam_package
    / OpamPackage.to_string opam_package
    / "opam"

  (* Reads an opam package definition from an "opam" file in this repository
     corresponding to a package (name and version). *)
  let load_opam_package t opam_package =
    let opam_file_path = get_opam_file_path t opam_package in
    if not (Sys.file_exists opam_file_path) then
      User_error.raise
        [ Pp.textf
            "Couldn't find package file for \"%s\". It was expected to be \
             located in %s but this file does not exist"
            (OpamPackage.to_string opam_package)
            (String.maybe_quoted opam_file_path)
        ];
    OpamFile.OPAM.read (OpamFile.make (OpamFilename.raw opam_file_path))
end

module Env = struct
  type t = OpamVariable.variable_contents OpamVariable.Map.t

  let empty : t = OpamVariable.Map.empty

  let global () : t =
    OpamGlobalState.with_ `Lock_none (fun global_state ->
        OpamVariable.Map.filter_map
          (fun _variable (contents, _description) -> Lazy.force contents)
          global_state.global_variables)

  let find_by_name (t : t) ~name =
    OpamVariable.Map.find_opt (OpamVariable.of_string name) t

  let add ~var ~value t =
    let variable = OpamVariable.of_string var in
    let content = OpamVariable.string value in
    OpamVariable.Map.add variable content t

  let union = OpamVariable.Map.union (fun _left right -> right)
end

module Local_repo_with_env = struct
  type t =
    { local_repo : Local_repo.t
    ; env : Env.t
    }
end

module Solver = Opam_0install.Solver.Make (Opam_solver.Context_for_dune)

module Repo_state = struct
  type t = Local_repo_with_env of Local_repo_with_env.t

  let load_opam_package t opam_package =
    match t with
    | Local_repo_with_env { local_repo; _ } ->
      Local_repo.load_opam_package local_repo opam_package

  let create_context t local_packages ~solver_env ~version_preference =
    match t with
    | Local_repo_with_env { local_repo = { packages_dir_path }; env } ->
      Opam_solver.Context_for_dune.create_dir_context ~solver_env
        ~env:(fun name -> Env.find_by_name env ~name)
        ~packages_dir_path ~local_packages ~version_preference
end

module Repo_selection = struct
  type t = Local_repo_with_env.t

  let local_repo_with_env ~opam_repo_dir ~env =
    let opam_repo_dir_path = Path.to_string opam_repo_dir in
    { Local_repo_with_env.local_repo =
        Local_repo.of_opam_repo_dir_path opam_repo_dir_path
    ; env
    }

  (* [with_state ~f t] calls [f] on a [Repo_state.t] implied by [t] and
     returns the result. Don't let the [Repo_state.t] escape the function [f].
  *)
  let with_state ~f local_repo_with_env =
    f (Repo_state.Local_repo_with_env local_repo_with_env)
end

module Summary = struct
  type t = { opam_packages_to_lock : OpamPackage.t list }

  let selected_packages_message t ~lock_dir_path =
    let parts =
      match t.opam_packages_to_lock with
      | [] ->
        [ Pp.tag User_message.Style.Success
            (Pp.text "(no dependencies to lock)")
        ]
      | opam_packages_to_lock ->
        List.map opam_packages_to_lock ~f:(fun package ->
            Pp.text (OpamPackage.to_string package))
    in
    User_message.make
      (Pp.textf "Solution for %s:"
         (Path.Source.to_string_maybe_quoted lock_dir_path)
      :: parts)
end

let opam_package_to_lock_file_pkg ~repo_state ~local_packages opam_package =
  let name = OpamPackage.name opam_package in
  let version =
    OpamPackage.version opam_package |> OpamPackage.Version.to_string
  in
  let dev = OpamPackage.Name.Map.mem name local_packages in
  let info =
    { Lock_dir.Pkg_info.name =
        Package_name.of_string (OpamPackage.Name.to_string name)
    ; version
    ; dev
    ; source = None
    ; extra_sources = []
    }
  in
  let opam_file =
    match OpamPackage.Name.Map.find_opt name local_packages with
    | None -> Repo_state.load_opam_package repo_state opam_package
    | Some local_package -> local_package
  in
  (* This will collect all the atoms from the package's dependency formula regardless of conditions *)
  let deps =
    OpamFormula.fold_right
      (fun acc (name, _condition) -> name :: acc)
      [] opam_file.depends
    |> List.map ~f:(fun name ->
           (Loc.none, Package_name.of_string (OpamPackage.Name.to_string name)))
  in
  (* TODO set these from the commands in the opam file *)
  { Lock_dir.Pkg.build_commands = []
  ; install_commands = []
  ; deps
  ; info
  ; exported_env = []
  }

let solve_package_list local_packages context =
  let result =
    try
      (* [Solver.solve] returns [Error] when it's unable to find a solution to
         the dependencies, but can also raise exceptions, for example if opam
         is unable to parse an opam file in the package repository. To prevent
         an unexpected opam exception from crashing dune, we catch all
         exceptions raised by the solver and report them as [User_error]s
         instead. *)
      Solver.solve context (OpamPackage.Name.Map.keys local_packages)
    with
    | OpamPp.(Bad_format _ | Bad_format_list _ | Bad_version _) as bad_format ->
      User_error.raise [ Pp.text (OpamPp.string_of_bad_format bad_format) ]
    | unexpected_exn ->
      Code_error.raise "Unexpected exception raised while solving dependencies"
        [ ("exception", Exn.to_dyn unexpected_exn) ]
  in
  match result with
  | Error e -> User_error.raise [ Pp.text (Solver.diagnostics e) ]
  | Ok packages -> Solver.packages_of_result packages

let solve_lock_dir ~solver_env ~version_preference ~repo_selection
    local_packages =
  let is_local_package package =
    OpamPackage.Name.Map.mem (OpamPackage.name package) local_packages
  in
  Repo_selection.with_state repo_selection ~f:(fun repo_state ->
      let context =
        Repo_state.create_context repo_state local_packages ~solver_env
          ~version_preference
      in
      let opam_packages_to_lock =
        solve_package_list local_packages context
        (* don't include local packages in the lock dir *)
        |> List.filter ~f:(Fun.negate is_local_package)
      in
      let summary = { Summary.opam_packages_to_lock } in
      let lock_dir =
        match
          List.map opam_packages_to_lock ~f:(fun opam_package ->
              let pkg =
                opam_package_to_lock_file_pkg ~repo_state ~local_packages
                  opam_package
              in
              (pkg.info.name, pkg))
          |> Package_name.Map.of_list
        with
        | Error (name, _pkg1, _pkg2) ->
          Code_error.raise
            (sprintf "Solver selected multiple packages named \"%s\""
               (Package_name.to_string name))
            []
        | Ok pkgs_by_name ->
          Lock_dir.create_latest_version pkgs_by_name ~ocaml:None
      in
      (summary, lock_dir))
