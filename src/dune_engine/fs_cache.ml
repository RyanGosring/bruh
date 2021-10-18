open! Stdune
open! Import

(* CR-someday amokhov: Persistently store the caches of (some?) operations. *)

(* CR-someday amokhov: Implement garbage collection. *)

type 'a t =
  { name : string (* For debugging *)
  ; sample : Path.t -> 'a
  ; cache : 'a Path.Table.t
  ; equal : 'a -> 'a -> bool (* Used to implement cutoff *)
  ; update_hook : Path.t -> unit (* Run this hook before updating an entry. *)
  }

let create ?(update_hook = fun _path -> ()) name ~sample ~equal =
  { name; sample; equal; cache = Path.Table.create 128; update_hook }

let read { sample; cache; _ } path =
  match Path.Table.find cache path with
  | Some cached_result -> cached_result
  | None ->
    let result = sample path in
    Path.Table.add_exn cache path result;
    result

module Update_result = struct
  type t =
    | Skipped (* No need to update a given entry because it has no readers *)
    | Updated of { changed : bool }

  let combine x y =
    match (x, y) with
    | Skipped, res
    | res, Skipped ->
      res
    | Updated { changed = x }, Updated { changed = y } ->
      Updated { changed = x || y }

  let empty = Skipped

  let to_dyn = function
    | Skipped -> Dyn.Variant ("Skipped", [])
    | Updated { changed } ->
      Dyn.Variant ("Updated", [ Dyn.Record [ ("changed", Dyn.Bool changed) ] ])
end

let update { sample; cache; equal; update_hook; _ } path =
  match Path.Table.find cache path with
  | None -> Update_result.Skipped
  | Some old_result -> (
    update_hook path;
    let new_result = sample path in
    match equal old_result new_result with
    | true -> Updated { changed = false }
    | false ->
      Path.Table.set cache path new_result;
      Updated { changed = true })

module Reduced_stats = struct
  type t =
    { st_dev : int
    ; st_ino : int
    ; st_kind : Unix.file_kind
    ; st_perm : Unix.file_perm
    ; st_size : int
    ; st_mtime : float
    ; st_ctime : float
    }

  let of_unix_stats
      { Unix.st_dev; st_ino; st_kind; st_perm; st_size; st_mtime; st_ctime; _ }
      =
    { st_dev; st_ino; st_kind; st_perm; st_size; st_mtime; st_ctime }

  let equal x y =
    Ordering.is_eq (Float.compare x.st_mtime y.st_mtime)
    && Ordering.is_eq (Float.compare x.st_ctime y.st_ctime)
    && Int.equal x.st_size y.st_size
    && Int.equal x.st_perm y.st_perm
    && Int.equal x.st_dev y.st_dev
    && Int.equal x.st_ino y.st_ino
    && Dune_filesystem_stubs.File_kind.equal x.st_kind y.st_kind
end

module Dir_contents_unsorted = struct
  type t = (string * Dune_filesystem_stubs.File_kind.t) list

  let equal =
    List.equal
      (Tuple.T2.equal String.equal Dune_filesystem_stubs.File_kind.equal)
end

module Untracked = struct
  let path_exists =
    create "path_exists" ~sample:Path.Untracked.exists ~equal:Bool.equal

  let path_stat =
    let sample path =
      Path.Untracked.stat path |> Result.map ~f:Reduced_stats.of_unix_stats
    in
    create "path_stat" ~sample
      ~equal:(Result.equal Reduced_stats.equal Unix_error.Detailed.equal)

  (* CR-someday amokhov: There is an overlap in functionality between this
     module and [cached_digest.ml]. In particular, digests are stored twice, in
     two separate tables. We should find a way to merge the tables into one. *)
  let path_digest =
    let sample = Cached_digest.Untracked.source_or_external_file in
    let update_hook = Cached_digest.Untracked.invalidate_cached_timestamp in
    create "path_digest" ~sample ~update_hook
      ~equal:Cached_digest.Digest_result.equal

  let dir_contents_unsorted =
    create "dir_contents_unsorted"
      ~sample:Path.Untracked.readdir_unsorted_with_kinds
      ~equal:
        (Result.equal Dir_contents_unsorted.equal Unix_error.Detailed.equal)
end

module Debug = struct
  let name t = t.name
end
