open Stdune
open Utils

type key = Digest.t

type metadata = Sexp.t list

let default_root () =
  Path.L.relative (Path.of_string Xdg.cache_dir) ["dune"; "db"; "v2"]

type promotion =
  | Already_promoted of Path.t * Path.t
  | Promoted of Path.t * Path.t

let key_to_string = Digest.to_string

let key_of_string = Digest.from_hex

let promotion_to_string = function
  | Already_promoted (original, promoted) ->
      Printf.sprintf "%s already promoted as %s" (Path.to_string original)
        (Path.to_string promoted)
  | Promoted (original, promoted) ->
      Printf.sprintf "%s promoted as %s" (Path.to_string original)
        (Path.to_string promoted)

(* How to handle collisions. E.g. another version could assume collisions are not possible *)
module Collision = struct
  type res = Found of Path.t | Not_found of Path.t

  (* We need to ensure we do not create holes in the suffix numbering for this to work *)
  let search path file =
    let rec loop n =
      let path = Path.extend_basename path ~suffix:("." ^ string_of_int n) in
      if Sys.file_exists (Path.to_string path) then
        if Io.compare_files path file == Ordering.Eq then Found path
        else loop (n + 1)
      else Not_found path
    in
    loop 1
end

module type FSScheme = sig
  val path : Path.t -> Digest.t -> Path.t

  val list : Path.t -> Path.t list
end

(* Where to store file with a given hash. In this case ab/abcdef. *)
module FirstTwoCharsSubdir : FSScheme = struct
  let path root hash =
    let hash = Digest.to_string hash in
    let short_hash = String.sub hash ~pos:0 ~len:2 in
    Path.L.relative root [short_hash; hash]

  let list root =
    let f dir =
      let is_hex_char c =
        let char_in s e = Char.compare c s >= 0 && Char.compare c e <= 0 in
        char_in 'a' 'f' || char_in '0' '9'
      and root = Path.L.relative root [dir] in
      if String.for_all ~f:is_hex_char dir then
        Array.map
          ~f:(fun filename -> Path.L.relative root [filename])
          (Sys.readdir (Path.to_string root))
      else Array.of_list []
    in
    Array.to_list
      (Array.concat
         (Array.to_list (Array.map ~f (Sys.readdir (Path.to_string root)))))
end

module FSSchemeImpl = FirstTwoCharsSubdir

let apply ~f o v = match o with Some o -> f v o | None -> v

module type memory = sig
  type t

  val promote :
       t
    -> (Path.t * Digest.t) list
    -> key
    -> metadata
    -> (string * string) option
    -> (promotion list, string) Result.t

  val search : t -> key -> (metadata * (Path.t * Path.t) list, string) Result.t
end

module Memory = struct
  type t = {root: Path.t; log: Log.t}

  let path_files memory = Path.L.relative memory.root ["files"]

  let path_meta memory = Path.L.relative memory.root ["meta"]

  let path_tmp memory = Path.L.relative memory.root ["temp"]

  let with_lock memory f =
    let lock =
      Stdune.Lockf.lock
        (Path.to_string (Path.L.relative memory.root [".lock"]))
    in
    let finally () = Stdune.Lockf.unlock lock in
    Exn.protect ~f ~finally

  let search memory hash file =
    Collision.search (FSSchemeImpl.path (path_files memory) hash) file

  let promote memory paths key metadata repo =
    let open Result.O in
    let metadata =
      apply
        ~f:(fun metadata (remote, commit) ->
          metadata
          @ [ Sexp.List [Sexp.Atom "repo"; Sexp.Atom remote]
            ; Sexp.List [Sexp.Atom "commit_id"; Sexp.Atom commit] ])
        repo metadata
    in
    let promote (path, expected_hash) =
      Log.infof memory.log "promote %s" (Path.to_string path) ;
      let hardlink path =
        let tmp = path_tmp memory in
        (* dune-memory uses a single writer model, the promoted file name can be constant *)
        let dest = Path.L.relative tmp ["promoting"] in
        (let dest = Path.to_string dest in
         if Sys.file_exists dest then Unix.unlink dest else mkpath tmp ;
         Unix.link (Path.to_string path) dest) ;
        dest
      in
      let tmp = hardlink path in
      let effective_hash = snd (Digest.path_stat_digest tmp) in
      if Digest.compare effective_hash expected_hash != Ordering.Eq then (
        let message =
          Printf.sprintf "hash mismatch: %s != %s"
            (Digest.to_string effective_hash)
            (Digest.to_string expected_hash)
        in
        Log.infof memory.log "%s" message ;
        Result.Error message )
      else
        match search memory effective_hash tmp with
        | Collision.Found p ->
            Unix.unlink (Path.to_string tmp) ;
            Result.Ok (Already_promoted (path, p))
        | Collision.Not_found p ->
            mkpath (Path.parent_exn p) ;
            let dest = Path.to_string p in
            Unix.rename (Path.to_string tmp) dest ;
            (* Remove write permissions *)
            Unix.chmod dest (stat.st_perm land 0o555) ;
            Result.Ok (Promoted (path, p))
    in
    let f () =
      Result.List.map ~f:promote paths
      >>| fun promoted ->
      let metadata_path = FSSchemeImpl.path (path_meta memory) key in
      mkpath (Path.parent_exn metadata_path) ;
      Io.write_file metadata_path
        (Csexp.to_string
           (Sexp.List
              [ Sexp.List (Sexp.Atom "metadata" :: metadata)
              ; Sexp.List
                  [ Sexp.Atom "produced-files"
                  ; Sexp.List
                      (List.map
                         ~f:(function
                           | Promoted (o, p) | Already_promoted (o, p) ->
                               Sexp.List
                                 [ Sexp.Atom (Path.to_string o)
                                 ; Sexp.Atom (Path.to_string p) ])
                         promoted) ] ])) ;
      promoted
    in
    with_lock memory f

  let search memory key =
    let path = FSSchemeImpl.path (path_meta memory) key in
    let f () =
      let open Result.O in
      ( try
          Io.with_file_in path ~f:(fun input ->
              Csexp.parse (Stream.of_channel input))
        with Sys_error _ -> Result.Error "no cached file" )
      >>= (function
            | Sexp.List l -> Result.ok l | _ -> Result.Error "invalid metadata")
      >>= function
      | [ Sexp.List (Sexp.Atom s_metadata :: metadata)
        ; Sexp.List [Sexp.Atom s_produced; Sexp.List produced] ] -> (
          if
            (not (String.equal s_metadata "metadata"))
            && String.equal s_produced "produced-files"
          then Result.Error "invalid metadata scheme: wrong key"
          else
            Result.List.map produced ~f:(function
              | Sexp.List [Sexp.Atom f; Sexp.Atom t] ->
                  Result.Ok (Path.of_string f, Path.of_string t)
              | _ ->
                  Result.Error "invalid metadata scheme in produced files list")
            >>| function produced -> (metadata, produced) )
      | _ ->
          Result.Error "invalid metadata scheme"
    in
    with_lock memory f
end

let make ?log ?(root = default_root ()) () =
  if Path.basename root <> "v2" then Result.Error "unable to read dune-memory"
  else
    Result.ok
      { Memory.root
      ; Memory.log= (match log with Some log -> log | None -> Log.no_log) }

let trim memory free =
  let path = Memory.path_files memory in
  let files = FSSchemeImpl.list path in
  let f path =
    let stat = Unix.stat (Path.to_string path) in
    if stat.st_nlink = 1 then Some (path, stat.st_size, stat.st_ctime)
    else None
  and compare (_, _, t1) (_, _, t2) =
    Ordering.of_int (Pervasives.compare t1 t2)
  in
  let files = List.sort ~compare (List.filter_map ~f files)
  and delete (freed, res) (path, size, _) =
    if freed >= free then (freed, res)
    else (
      Unix.unlink (Path.to_string path) ;
      (freed + size, path :: res) )
  in
  Memory.with_lock memory (fun () ->
      List.fold_left ~init:(0, []) ~f:delete files)
