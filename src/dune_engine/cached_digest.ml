open Import

(* The reduced set of file stats this module inspects to decide whether a file
   changed or not *)
module Reduced_stats = struct
  type t =
    { mtime : float
    ; size : int
    ; perm : Unix.file_perm
    }

  let to_dyn { mtime; size; perm } =
    Dyn.Record
      [ ("mtime", Float mtime); ("size", Int size); ("perm", Int perm) ]

  let of_unix_stats (stats : Unix.stats) =
    { mtime = stats.st_mtime; size = stats.st_size; perm = stats.st_perm }

  let compare a b =
    match Float.compare a.mtime b.mtime with
    | (Lt | Gt) as x -> x
    | Eq -> (
      match Int.compare a.size b.size with
      | (Lt | Gt) as x -> x
      | Eq -> Int.compare a.perm b.perm)
end

type file =
  { mutable digest : Digest.t
  ; mutable stats : Reduced_stats.t
  ; mutable stats_checked : int
  }

type t =
  { mutable checked_key : int
  ; mutable max_timestamp : float
  ; table : file Path.Table.t
  }

let db_file = Path.relative Path.build_dir ".digest-db"

let dyn_of_file { digest; stats; stats_checked } =
  Dyn.Record
    [ ("digest", Digest.to_dyn digest)
    ; ("stats", Reduced_stats.to_dyn stats)
    ; ("stats_checked", Int stats_checked)
    ]

let to_dyn { checked_key; max_timestamp; table } =
  Dyn.Record
    [ ("checked_key", Int checked_key)
    ; ("max_timestamp", Float max_timestamp)
    ; ("table", Path.Table.to_dyn dyn_of_file table)
    ]

module P = Persistent.Make (struct
  type nonrec t = t

  let name = "DIGEST-DB"

  let version = 5

  let to_dyn = to_dyn
end)

let needs_dumping = ref false

(* CR-someday amokhov: replace this mutable table with a memoized function. This
   will probably require splitting this module in two, for dealing with source
   and target files, respectively. For source files, we receive updates via the
   file-watching API. For target files, we modify the digests ourselves, without
   subscribing for file-watching updates. *)
let cache =
  lazy
    (match P.load db_file with
    | None ->
      { checked_key = 0; table = Path.Table.create 1024; max_timestamp = 0. }
    | Some cache ->
      cache.checked_key <- cache.checked_key + 1;
      cache)

let get_current_filesystem_time () =
  let special_path = Path.relative Path.build_dir ".filesystem-clock" in
  Io.write_file special_path "<dummy>";
  (Path.Untracked.stat_exn special_path).st_mtime

let wait_for_fs_clock_to_advance () =
  let t = get_current_filesystem_time () in
  while get_current_filesystem_time () <= t do
    (* This is a blocking wait but we don't care too much. This code is only
       used in the test suite. *)
    Unix.sleepf 0.01
  done

let delete_very_recent_entries () =
  let cache = Lazy.force cache in
  if !Clflags.wait_for_filesystem_clock then wait_for_fs_clock_to_advance ();
  let now = get_current_filesystem_time () in
  match Float.compare cache.max_timestamp now with
  | Lt -> ()
  | Eq
  | Gt ->
    Path.Table.filteri_inplace cache.table ~f:(fun ~key:path ~data ->
        match Float.compare data.stats.mtime now with
        | Lt -> true
        | Gt
        | Eq ->
          if !Clflags.debug_digests then
            Console.print
              [ Pp.textf
                  "Dropping cached digest for %s because it has exactly the \
                   same mtime as the file system clock."
                  (Path.to_string_maybe_quoted path)
              ];
          false)

let dump () =
  if !needs_dumping && Path.build_dir_exists () then (
    needs_dumping := false;
    Console.Status_line.with_overlay
      (Live (fun () -> Pp.hbox (Pp.text "Saving digest db...")))
      ~f:(fun () ->
        delete_very_recent_entries ();
        P.dump db_file (Lazy.force cache))
  )

let () = at_exit dump

let invalidate_cached_timestamps () =
  (if Lazy.is_val cache then
    let cache = Lazy.force cache in
    cache.checked_key <- cache.checked_key + 1);
  delete_very_recent_entries ()

let set_max_timestamp cache (stat : Unix.stats) =
  cache.max_timestamp <- Float.max cache.max_timestamp stat.st_mtime

let set_with_stat path digest stat =
  let cache = Lazy.force cache in
  needs_dumping := true;
  set_max_timestamp cache stat;
  Path.Table.set cache.table path
    { digest
    ; stats = Reduced_stats.of_unix_stats stat
    ; stats_checked = cache.checked_key
    }

let set path digest =
  (* the caller of [set] ensures that the files exist *)
  let path = Path.build path in
  let stat = Path.Untracked.stat_exn path in
  set_with_stat path digest stat

module Refresh_result = struct
  type t =
    | Ok of Digest.t
    | No_such_file
    | Error of exn

  let unexpected_kind st_kind =
    Sys_error
      (sprintf "Unexpected file kind %S (%s)"
         (Dune_filesystem_stubs.File_kind.to_string st_kind)
         (Dune_filesystem_stubs.File_kind.to_string_hum st_kind))

  let unix_error error = Sys_error (Unix.error_message error)

  let broken_symlink = Sys_error "Broken symlink"

  let file_does_not_exist =
    Sys_error "Could not digest a file that does not exist"

  let digest_exn = function
    | Ok digest -> digest
    | No_such_file -> raise file_does_not_exist
    | Error exn -> raise exn

  let iter t ~f =
    match t with
    | Ok t -> f t
    | No_such_file
    | Error _ ->
      ()
end

let digest_path_with_stats path stats =
  match
    Digest.path_with_stats path (Digest.Stats_for_digest.of_unix_stats stats)
  with
  | Ok digest -> Refresh_result.Ok digest
  | Unexpected_kind -> Error (Refresh_result.unexpected_kind stats.st_kind)
  | Error ENOENT -> No_such_file
  | Error error -> Error (Refresh_result.unix_error error)

let refresh stats path =
  (* Note that by the time we reach this point, [stats] may become stale due to
     concurrent processes modifying the [path], so this function can actually
     return [No_such_file] even if the caller managed to obtain the [stats]. *)
  let result = digest_path_with_stats path stats in
  Refresh_result.iter result ~f:(fun digest -> set_with_stat path digest stats);
  result

let catch_fs_errors f =
  match f () with
  | result -> result
  | exception ((Unix.Unix_error _ | Sys_error _) as exn) ->
    Refresh_result.Error exn

(* Here we make only one [stat] call on the happy path. *)
let refresh_without_removing_write_permissions path =
  catch_fs_errors (fun () ->
      match Path.Untracked.stat_exn path with
      | stats -> refresh stats path
      | exception Unix.Unix_error (ENOENT, _, _) -> (
        (* Test if this is a broken symlink for better error messages. *)
        match Path.Untracked.lstat_exn path with
        | exception Unix.Unix_error (ENOENT, _, _) -> No_such_file
        | _stats_so_must_be_a_symlink -> Error Refresh_result.broken_symlink))

(* CR-someday amokhov: We do [lstat] followed by [stat] only because we do not
   want to remove write permissions from the symbolic link's target, which may
   be outside of the build directory and not under out control. It seems like it
   should be possible to avoid paying for two system calls ([lstat] and [stat])
   here, e.g., by telling the subsequent [chmod] to not follow symlinks. *)
let refresh_and_remove_write_permissions path =
  catch_fs_errors (fun () ->
      match Path.Untracked.lstat_exn path with
      | exception Unix.Unix_error (ENOENT, _, _) -> No_such_file
      | stats ->
        let stats =
          (* CR-someday amokhov: Shall we raise if [stats.st_kind = S_DIR]? What
             about stranger kinds like [S_SOCK]? *)
          match stats.st_kind with
          | S_LNK -> (
            try Path.Untracked.stat_exn path with
            | Unix.Unix_error (ENOENT, _, _) ->
              raise Refresh_result.broken_symlink)
          | S_REG ->
            let perm =
              Path.Permissions.remove ~mode:Path.Permissions.write stats.st_perm
            in
            Path.chmod ~mode:perm path;
            { stats with st_perm = perm }
          | _ -> stats
        in
        refresh stats path)

let refresh path ~remove_write_permissions =
  let path = Path.build path in
  match remove_write_permissions with
  | false -> refresh_without_removing_write_permissions path
  | true -> refresh_and_remove_write_permissions path

let peek_file path =
  let cache = Lazy.force cache in
  match Path.Table.find cache.table path with
  | None -> None
  | Some x ->
    Some
      (if x.stats_checked = cache.checked_key then
        x.digest
      else
        let stats = Path.Untracked.stat_exn path in
        let reduced_stats = Reduced_stats.of_unix_stats stats in
        match Reduced_stats.compare x.stats reduced_stats with
        | Eq ->
          (* Even though we're modifying the [stats_checked] field, we don't
             need to set [needs_dumping := true] here. This is because
             [checked_key] is incremented every time we load from disk, which
             makes it so that [stats_checked < checked_key] for all entries
             after loading, regardless of whether we save the new value here or
             not. *)
          x.stats_checked <- cache.checked_key;
          x.digest
        | Gt
        | Lt ->
          let digest =
            digest_path_with_stats path stats |> Refresh_result.digest_exn
          in
          if !Clflags.debug_digests then
            Console.print
              [ Pp.textf "Re-digested file %s because its stats changed:"
                  (Path.to_string_maybe_quoted path)
              ; Dyn.pp
                  (Dyn.Record
                     [ ("old_digest", Digest.to_dyn x.digest)
                     ; ("new_digest", Digest.to_dyn digest)
                     ; ("old_stats", Reduced_stats.to_dyn x.stats)
                     ; ("new_stats", Reduced_stats.to_dyn reduced_stats)
                     ])
              ];
          needs_dumping := true;
          set_max_timestamp cache stats;
          x.digest <- digest;
          x.stats <- reduced_stats;
          x.stats_checked <- cache.checked_key;
          digest)

let peek_or_refresh_file path =
  match peek_file path with
  | Some digest -> digest
  | None ->
    refresh_without_removing_write_permissions path |> Refresh_result.digest_exn

let build_file path = peek_or_refresh_file (Path.build path)

let remove path =
  let path = Path.build path in
  let cache = Lazy.force cache in
  needs_dumping := true;
  Path.Table.remove cache.table path

module Untracked = struct
  let source_or_external_file = peek_or_refresh_file
end
