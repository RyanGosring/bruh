open Import

(* CR-someday amokhov: Most of these records will have [dir = empty]. We might
   want to somehow optimise for the common case, e.g. by switching to a sum type
   with the [Files_only] constructor. It's best not to expose the current
   representation so we can easily change it in future. *)
type t =
  { files : Path.Build.Set.t
  ; dirs : Path.Build.Set.t
  }

module File = struct
  let create file = { files = Path.Build.Set.singleton file; dirs = Path.Build.Set.empty }
end

module Files = struct
  let create files = { files; dirs = Path.Build.Set.empty }
end

let create ~files ~dirs = { files; dirs }
let empty = { files = Path.Build.Set.empty; dirs = Path.Build.Set.empty }

let combine x y =
  { files = Path.Build.Set.union x.files y.files
  ; dirs = Path.Build.Set.union x.dirs y.dirs
  }
;;

let diff t { files; dirs } =
  { files = Path.Build.Set.diff t.files files; dirs = Path.Build.Set.diff t.dirs dirs }
;;

let is_empty { files; dirs } =
  Path.Build.Set.is_empty files && Path.Build.Set.is_empty dirs
;;

let head { files; dirs } =
  match Path.Build.Set.choose files with
  | Some _ as target -> target
  | None -> Path.Build.Set.choose dirs
;;

let head_exn t =
  match head t with
  | Some target -> target
  | None -> Code_error.raise "Targets.head_exn applied to empty set of targets" []
;;

let to_dyn { files; dirs } =
  Dyn.Record [ "files", Path.Build.Set.to_dyn files; "dirs", Path.Build.Set.to_dyn dirs ]
;;

let all { files; dirs } = Path.Build.Set.to_list files @ Path.Build.Set.to_list dirs

let exists { files; dirs } ~f =
  Path.Build.Set.exists files ~f || Path.Build.Set.exists dirs ~f
;;

let iter { files; dirs } ~file ~dir =
  Path.Build.Set.iter files ~f:file;
  Path.Build.Set.iter dirs ~f:dir
;;

module Validated = struct
  type nonrec t = t =
    { files : Path.Build.Set.t
    ; dirs : Path.Build.Set.t
    }

  let to_dyn = to_dyn
  let head = head_exn
  let unvalidate t = t
end

module Validation_result = struct
  type t =
    | Valid of
        { parent_dir : Path.Build.t
        ; targets : Validated.t
        }
    | No_targets
    | Inconsistent_parent_dir
    | File_and_directory_target_with_the_same_name of Path.Build.t
end

let validate t =
  match is_empty t with
  | true -> Validation_result.No_targets
  | false ->
    (match Path.Build.Set.inter t.files t.dirs |> Path.Build.Set.choose with
     | Some path -> File_and_directory_target_with_the_same_name path
     | None ->
       let parent_dir = Path.Build.parent_exn (head_exn t) in
       (match exists t ~f:(fun path -> Path.Build.(parent_exn path <> parent_dir)) with
        | true -> Inconsistent_parent_dir
        | false -> Valid { parent_dir; targets = t }))
;;

module Produced = struct
  (* CR-someday amokhov: A hierarchical representation of the produced file
     trees may be better. It would allow for hierarchical traversals and reduce
     the number of internal invariants. *)
  type 'a t =
    { files : 'a Path.Build.Map.t
    ; dirs : 'a Filename.Map.t Path.Build.Map.t
    }

  module Error = struct
    type t =
      | Missing_dir of Path.Build.t
      | Unreadable_dir of Path.Build.t * Unix_error.Detailed.t
      | Unsupported_file of Path.Build.t * File_kind.t

    let message = function
      | Missing_dir dir ->
        [ Pp.textf
            "Rule failed to produce directory %S"
            (Path.Build.drop_build_context_maybe_sandboxed_exn dir
             |> Path.Source.to_string_maybe_quoted)
        ]
      | Unreadable_dir (dir, (unix_error, _, _)) ->
        (* CR-soon amokhov: This case is untested. *)
        [ Pp.textf
            "Rule produced unreadable directory %S"
            (Path.Build.drop_build_context_maybe_sandboxed_exn dir
             |> Path.Source.to_string_maybe_quoted)
        ; Pp.verbatim (Unix.error_message unix_error)
        ]
      | Unsupported_file (file, kind) ->
        (* CR-soon amokhov: This case is untested. *)
        [ Pp.textf
            "Rule produced file %S with unrecognised kind %S"
            (Path.Build.drop_build_context_maybe_sandboxed_exn file
             |> Path.Source.to_string_maybe_quoted)
            (File_kind.to_string kind)
        ]
    ;;

    let to_string_hum = function
      | Missing_dir _ -> "missing directory"
      | Unreadable_dir (_, unix_error) -> Unix_error.Detailed.to_string_hum unix_error
      | Unsupported_file _ -> "unsupported file kind"
    ;;
  end

  let of_validated =
    let rec collect dir : (unit Filename.Map.t Path.Build.Map.t, Error.t) result =
      match Path.Untracked.readdir_unsorted_with_kinds (Path.build dir) with
      | Error (Unix.ENOENT, _, _) -> Error (Missing_dir dir)
      | Error e -> Error (Unreadable_dir (dir, e))
      | Ok dir_contents ->
        let open Result.O in
        let+ filenames, dirs =
          Result.List.fold_left
            dir_contents
            ~init:(Filename.Map.empty, Path.Build.Map.empty)
            ~f:(fun (acc_filenames, acc_dirs) (filename, kind) ->
              match (kind : File_kind.t) with
              (* CR-someday rleshchinskiy: Make semantics of symlinks more consistent. *)
              | S_LNK | S_REG ->
                Ok (String.Map.add_exn acc_filenames filename (), acc_dirs)
              | S_DIR ->
                let+ dir = collect (Path.Build.relative dir filename) in
                acc_filenames, Path.Build.Map.union_exn acc_dirs dir
              | _ -> Error (Unsupported_file (Path.Build.relative dir filename, kind)))
        in
        if not (String.Map.is_empty filenames)
        then Path.Build.Map.add_exn dirs dir filenames
        else dirs
    in
    fun (validated : Validated.t) ->
      match Path.Build.Set.to_list_map validated.dirs ~f:collect |> Result.List.all with
      | Error _ as error -> error
      | Ok dirs ->
        let files =
          Path.Build.Set.to_map validated.files ~f:(fun (_ : Path.Build.t) -> ())
        in
        (* The [union_exn] below can't raise because each map in [dirs] contains
           unique keys, which are paths rooted at the corresponding [dir]s. *)
        let dirs =
          List.fold_left dirs ~init:Path.Build.Map.empty ~f:Path.Build.Map.union_exn
        in
        Ok { files; dirs }
  ;;

  let of_file_list_exn list =
    { files = Path.Build.Map.of_list_exn list; dirs = Path.Build.Map.empty }
  ;;

  let all_files { files; dirs } =
    let disallow_duplicates file _payload1 _payload2 =
      Code_error.raise
        (sprintf
           "Targets.Produced.all_files: duplicate file %S"
           (Path.Build.to_string file))
        [ "files", Path.Build.Map.to_dyn Dyn.opaque files
        ; "dirs", Path.Build.Map.to_dyn (Filename.Map.to_dyn Dyn.opaque) dirs
        ]
    in
    let files_in_dirs =
      Path.Build.Map.foldi dirs ~init:Path.Build.Map.empty ~f:(fun dir filenames ->
        let paths =
          Path.Build.Map.of_list_exn
            (Filename.Map.to_list_map filenames ~f:(fun filename payload ->
               Path.Build.relative dir filename, payload))
        in
        Path.Build.Map.union paths ~f:disallow_duplicates)
    in
    Path.Build.Map.union ~f:disallow_duplicates files files_in_dirs
  ;;

  let all_files_seq t =
    Seq.append
      (Path.Build.Map.to_seq t.files)
      (Seq.concat
         (Path.Build.Map.to_seq t.dirs
          |> Seq.map ~f:(fun (dir, filenames) ->
            Filename.Map.to_seq filenames
            |> Seq.map ~f:(fun (filename, payload) ->
              Path.Build.relative dir filename, payload))))
  ;;

  let digest { files; dirs } =
    let all_digests =
      Path.Build.Map.values files
      :: Path.Build.Map.to_list_map dirs ~f:(fun _ -> Filename.Map.values)
    in
    Digest.generic (List.concat all_digests)
  ;;

  (* Dummy digest because we want to continue discovering all the errors
     and we need some value to return in [mapi]. It will never be returned *)
  let dummy_digest = Digest.generic ""

  exception Short_circuit

  let collect_digests
    { files; dirs }
    ~all_errors
    ~(f : Path.Build.t -> 'a -> (Digest.t, 'e) result)
    =
    let errors = ref [] in
    let f path a =
      match f path a with
      | Ok s -> s
      | Error e ->
        errors := (path, e) :: !errors;
        if all_errors then dummy_digest else raise_notrace Short_circuit
    in
    let result =
      try
        let files = Path.Build.Map.mapi files ~f in
        let dirs =
          Path.Build.Map.mapi dirs ~f:(fun dir ->
            Filename.Map.mapi ~f:(fun filename -> f (Path.Build.relative dir filename)))
        in
        { files; dirs }
      with
      | Short_circuit -> { files = Path.Build.Map.empty; dirs = Path.Build.Map.empty }
    in
    match Nonempty_list.of_list !errors with
    | None -> Ok result
    | Some list -> Error list
  ;;

  let to_dyn { files; dirs } =
    Dyn.record
      [ "files", Path.Build.Map.to_dyn Dyn.opaque files
      ; "dirs", Path.Build.Map.to_dyn (Filename.Map.to_dyn Dyn.opaque) dirs
      ]
  ;;
end
