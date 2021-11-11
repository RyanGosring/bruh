open! Stdune
module Inotify_lib = Async_inotify_for_dune.Async_inotify

type path_event =
  | Created
  | Moved_into
  | Unlinked
  | Moved_away
  | Modified

let decompose_inotify_event (event : Inotify_lib.Event.t) =
  match event with
  | Created path -> [ (path, Created) ]
  | Unlinked path -> [ (path, Unlinked) ]
  | Modified path -> [ (path, Modified) ]
  | Moved (Away path) -> [ (path, Moved_away) ]
  | Moved (Into path) -> [ (path, Moved_into) ]
  | Moved (Move (from, to_)) -> [ (from, Moved_away); (to_, Moved_into) ]
  | Queue_overflow -> []

let inotify_event_paths event = List.map ~f:fst (decompose_inotify_event event)

module Fs_memo_event = struct
  type kind =
    | Created
    | Deleted
    | File_changed
    | Unknown  (** Treated conservatively as any possible event. *)

  let dyn_of_kind kind =
    Dyn.Encoder.string
      (match kind with
      | Created -> "Created"
      | Deleted -> "Deleted"
      | File_changed -> "File_changed"
      | Unknown -> "Unknown")

  type t =
    { path : Path.t
    ; kind : kind
    }

  let to_dyn { path; kind } =
    let open Dyn.Encoder in
    record [ ("path", Path.to_dyn path); ("kind", dyn_of_kind kind) ]

  let create ~kind ~path =
    if Path.is_in_build_dir path then
      Code_error.raise "Fs_memo.Event.create called on a build path" [];
    { path; kind }
end

module Sync_id = Id.Make ()

module Event = struct
  type t =
    | Fs_memo_event of Fs_memo_event.t
    | Queue_overflow
    | Sync of Sync_id.t
    | Watcher_terminated
end

module Scheduler = struct
  type t =
    { spawn_thread : (unit -> unit) -> unit
    ; thread_safe_send_emit_events_job : (unit -> Event.t list) -> unit
    }
end

module Watch_trie : sig
  (** Specialized trie for fsevent watches *)
  type 'a t

  val empty : 'a t

  val to_list : 'a t -> (Path.External.t * 'a) list

  type 'a add =
    | Under_existing_node
    | Inserted of
        { new_t : 'a t
        ; removed : (Path.External.t * 'a) list
        }

  val add : 'a t -> Path.External.t -> 'a Lazy.t -> 'a add
end = struct
  (* the invariant is that a node can contain either a value or branches, but
     not both *)
  type 'a t =
    | Leaf of Path.External.t * 'a
    | Branch of 'a t String.Map.t

  type 'a add =
    | Under_existing_node
    | Inserted of
        { new_t : 'a t
        ; removed : (Path.External.t * 'a) list
        }

  let empty = Branch String.Map.empty

  let to_list t =
    let rec loop t acc =
      match t with
      | Leaf (k, v) -> (k, v) :: acc
      | Branch m -> String.Map.fold m ~init:acc ~f:loop
    in
    loop t []

  let rec path p a = function
    | [] -> Leaf (p, a)
    | x :: xs -> Branch (String.Map.singleton x (path p a xs))

  let add t key v =
    (* wrong in general, but this is only needed for fsevents *)
    let comps =
      match String.split ~on:'/' (Path.External.to_string key) with
      | "" :: comps -> comps
      | _ ->
        (* fsevents gives us only absolute paths *)
        assert false
    in
    let rec add comps t =
      match (comps, t) with
      | _, Leaf (_, _) -> Under_existing_node
      | [], Branch _ ->
        Inserted { new_t = Leaf (key, Lazy.force v); removed = to_list t }
      | x :: xs, Branch m -> (
        match String.Map.find m x with
        | None ->
          Inserted
            { new_t = Branch (String.Map.set m x (path key (Lazy.force v) xs))
            ; removed = []
            }
        | Some m' -> (
          match add xs m' with
          | Under_existing_node -> Under_existing_node
          | Inserted i ->
            Inserted { i with new_t = Branch (String.Map.set m x i.new_t) }))
    in
    add comps t
end

type kind =
  | Fswatch of
      { pid : Pid.t
      ; wait_for_watches_established : unit -> unit
      }
  | Fsevents of
      { mutable external_ : Fsevents.t Watch_trie.t
      ; runloop : Fsevents.RunLoop.t
      ; scheduler : Scheduler.t
      ; source : Fsevents.t
      ; sync : Fsevents.t
      ; latency : float
      }
  | Inotify of Inotify_lib.t

type t =
  { kind : kind
        (* CR-someday amokhov: The way we handle "ignored files" using this
           mutable table is fragile and also wrong. We use [ignored_files] for
           the [(mode promote)] feature: if a file is promoted, we call
           [ignore_next_file_change_event] so that the upcoming file-change
           event does not invalidate the current build. However, instead of
           ignoring the events, we should merely postpone them and restart the
           build to take the promoted files into account if need be. *)
        (* The [ignored_files] table should be accessed in the scheduler
           thread. *)
  ; ignored_files : (string, unit) Table.t
  ; sync_table : (string, Sync_id.t) Table.t
        (* Pending fs sync operations indexed by the special sync filename. *)
  }

let exclude_patterns =
  [ {|^_opam|}
  ; {|/_opam|}
  ; {|^_esy|}
  ; {|/_esy|}
  ; {|^\.#.*|} (* Such files can be created by Emacs and also Dune itself. *)
  ; {|/\.#.*|}
  ; {|~$|}
  ; {|^#[^#]*#$|}
  ; {|/#[^#]*#$|}
  ; {|^4913$|} (* https://github.com/neovim/neovim/issues/3460 *)
  ; {|/4913$|}
  ]

module Re = Dune_re

let exclude_regex =
  Re.compile
    (Re.alt (List.map exclude_patterns ~f:(fun pattern -> Re.Posix.re pattern)))

let should_exclude path = Re.execp exclude_regex path

module For_tests = struct
  let should_exclude = should_exclude
end

(* [process_inotify_event] needs to run in the scheduler thread because it
   accesses [t.ignored_files]. *)
let process_inotify_event ~ignored_files
    (event : Async_inotify_for_dune.Async_inotify.Event.t) : Event.t list =
  let should_ignore =
    let all_paths = decompose_inotify_event event in
    List.exists all_paths ~f:(fun (path, event) ->
        let path = Path.of_string path in
        let abs_path = Path.to_absolute_filename path in
        if Table.mem ignored_files abs_path then (
          (match event with
          | Created
          | Unlinked
          | Moved_away ->
            (* The event is a part of promotion, but not the last step. The
               typical sequence is [Created] followed by [Modified]. *)
            ()
          | Modified
          | Moved_into ->
            (* Got the final event in promotion sequence. With the current
               promotion implementation the event will be [Modified], but if we
               use renaming instead then [Moved_into] can be expected. *)
            Table.remove ignored_files abs_path);
          true
        ) else
          false)
    || List.for_all all_paths ~f:(fun (path, _event) -> should_exclude path)
  in
  if should_ignore then
    []
  else
    match event with
    | Created path ->
      let path = Path.of_string path in
      [ Fs_memo_event (Fs_memo_event.create ~kind:Created ~path) ]
    | Unlinked path ->
      let path = Path.of_string path in
      [ Fs_memo_event (Fs_memo_event.create ~kind:Deleted ~path) ]
    | Modified path ->
      let path = Path.of_string path in
      [ Fs_memo_event (Fs_memo_event.create ~kind:File_changed ~path) ]
    | Moved move -> (
      match move with
      | Away path ->
        let path = Path.of_string path in
        [ Fs_memo_event (Fs_memo_event.create ~kind:Deleted ~path) ]
      | Into path ->
        let path = Path.of_string path in
        [ Fs_memo_event (Fs_memo_event.create ~kind:Created ~path) ]
      | Move (from, to_) ->
        let from = Path.of_string from in
        let to_ = Path.of_string to_ in
        [ Fs_memo_event (Fs_memo_event.create ~kind:Deleted ~path:from)
        ; Fs_memo_event (Fs_memo_event.create ~kind:Created ~path:to_)
        ])
    | Queue_overflow -> [ Event.Queue_overflow ]

let shutdown t =
  match t.kind with
  | Fswatch { pid; _ } -> `Kill pid
  | Inotify _ -> `No_op
  | Fsevents fsevents ->
    `Thunk
      (fun () ->
        Fsevents.stop fsevents.source;
        Fsevents.stop fsevents.sync;
        Watch_trie.to_list fsevents.external_
        |> List.iter ~f:(fun (_, fs) -> Fsevents.stop fs))

let buffer_capacity = 65536

(* Fixed-size buffer for reading line-by-line from file descriptors. Bug:
   deadlocks if there's a line longer than the capacity of the buffer. TODO: use
   In_channel? *)
module Buffer = struct
  type buffer =
    { data : Bytes.t
    ; mutable size : int
    }

  let create ~capacity = { data = Bytes.create capacity; size = 0 }

  let read_lines buffer fd =
    let len =
      Unix.read fd buffer.data buffer.size (buffer_capacity - buffer.size)
    in
    buffer.size <- buffer.size + len;
    if len = 0 then
      `End_of_file (Bytes.sub_string buffer.data ~pos:0 ~len:buffer.size)
    else
      `Ok
        (let lines = ref [] in
         let line_start = ref 0 in
         for i = 0 to buffer.size - 1 do
           let c = Bytes.get buffer.data i in
           if c = '\n' || c = '\r' then (
             (if !line_start < i then
               let line =
                 Bytes.sub_string buffer.data ~pos:!line_start
                   ~len:(i - !line_start)
               in
               lines := line :: !lines);
             line_start := i + 1
           )
         done;
         buffer.size <- buffer.size - !line_start;
         Bytes.blit ~src:buffer.data ~src_pos:!line_start ~dst:buffer.data
           ~dst_pos:0 ~len:buffer.size;
         List.rev !lines)
end

let special_dir_for_fs_sync =
  lazy
    (Path.Build.relative Path.Build.root ".sync" |> Path.build |> Path.to_string)

let emit_sync t =
  let id = Sync_id.gen () in
  let fn = id |> Sync_id.to_int |> string_of_int in
  let path = Filename.concat (Lazy.force special_dir_for_fs_sync) fn in
  Unix.close (Unix.openfile path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o666);
  Table.set t.sync_table fn id;
  id

let is_special_file_for_fs_sync ~path_as_reported_by_file_watcher =
  (* We use string matching here and that's fine because we match on the path
     reported by the file watcher backend which will always report the same
     string that was used to setup the watch. *)
  Filename.dirname path_as_reported_by_file_watcher
  = Lazy.force special_dir_for_fs_sync

let consume_sync_event table path =
  let basename = Filename.basename path in
  match Table.find table basename with
  | None -> None
  | Some id ->
    Fpath.unlink_no_err path;
    Table.remove table basename;
    Some id

let command ~root ~backend =
  let exclude_paths =
    (* These paths should already exist on the filesystem when the watches are
       initially set up, otherwise the @<path> has no effect for inotifywait. If
       the file is deleted and re-created then "exclusion" is lost. This is why
       we're not including "_opam" and "_esy" in this list, in case they are
       created when dune is already running. *)
    (* these paths are used as patterns for fswatch, so they better not contain
       any regex-special characters *)
    [ "_build" ]
  in
  let root = Path.to_string root in
  let inotify_special_path = Lazy.force special_dir_for_fs_sync in
  match backend with
  | `Fswatch fswatch ->
    (* On all other platforms, try to use fswatch. fswatch's event filtering is
       not reliable (at least on Linux), so don't try to use it, instead act on
       all events. *)
    let excludes =
      List.concat_map
        (exclude_patterns @ List.map exclude_paths ~f:(fun p -> "/" ^ p))
        ~f:(fun x -> [ "--exclude"; x ])
    in
    ( fswatch
    , [ "-r"
      ; root
      ; (* If [inotify_special_path] is not passed here, then the [--exclude
           _build] makes fswatch not descend into [_build], which means it never
           even discovers that [inotify_special_path] exists. This is despite
           the fact that [--include] appears before. *)
        inotify_special_path
      ; "--event"
      ; "Created"
      ; "--event"
      ; "Updated"
      ; "--event"
      ; "Removed"
      ]
      @ [ "--include"; inotify_special_path ]
      @ excludes
    , fun s -> Ok s )

let fswatch_backend () =
  let try_fswatch () =
    Option.map
      (Bin.which ~path:(Env.path Env.initial) "fswatch")
      ~f:(fun fswatch -> `Fswatch fswatch)
  in
  match try_fswatch () with
  | Some res -> res
  | None ->
    User_error.raise [ Pp.text "Please install fswatch to enable watch mode." ]

let select_watcher_backend () =
  if Sys.linux then (
    assert (Ocaml_inotify.Inotify.supported_by_the_os ());
    `Inotify_lib
  ) else if Fsevents.available () then
    `Fsevents
  else
    fswatch_backend ()

let prepare_sync () =
  let dir = Lazy.force special_dir_for_fs_sync in
  match Fpath.clear_dir dir with
  | Cleared -> ()
  | Directory_does_not_exist -> (
    match Fpath.mkdir_p dir with
    | Already_exists
    | Created ->
      ())

let spawn_external_watcher ~root ~backend =
  prepare_sync ();
  let prog, args, parse_line = command ~root ~backend in
  let prog = Path.to_absolute_filename prog in
  let argv = prog :: args in
  let r_stdout, w_stdout = Unix.pipe () in
  let stderr, wait = (None, fun () -> ()) in
  let pid = Spawn.spawn () ~prog ~argv ~stdout:w_stdout ?stderr |> Pid.of_int in
  Unix.close w_stdout;
  Option.iter stderr ~f:Unix.close;
  ((r_stdout, parse_line, wait), pid)

let create_inotifylib_watcher ~sync_table ~ignored_files
    ~(scheduler : Scheduler.t) =
  Inotify_lib.create ~spawn_thread:scheduler.spawn_thread
    ~modify_event_selector:`Closed_writable_fd
    ~send_emit_events_job_to_scheduler:(fun f ->
      scheduler.thread_safe_send_emit_events_job (fun () ->
          let events = f () in
          List.concat_map events ~f:(fun event ->
              let is_fs_sync_event_generated_by_dune =
                match (event : Inotify_lib.Event.t) with
                | Modified path
                | Created path
                | Unlinked path ->
                  Option.some_if
                    (is_special_file_for_fs_sync
                       ~path_as_reported_by_file_watcher:path)
                    path
                | Moved _
                | Queue_overflow ->
                  None
              in
              match is_fs_sync_event_generated_by_dune with
              | None -> process_inotify_event ~ignored_files event
              | Some path -> (
                match consume_sync_event sync_table path with
                | None -> []
                | Some id -> [ Event.Sync id ]))))
    ~log_error:(fun error -> Console.print [ Pp.text error ])

let create_no_buffering ~(scheduler : Scheduler.t) ~root ~backend =
  let ignored_files = Table.create (module String) 64 in
  let sync_table = Table.create (module String) 64 in
  let (pipe, parse_line, wait), pid = spawn_external_watcher ~root ~backend in
  let worker_thread pipe =
    let buffer = Buffer.create ~capacity:buffer_capacity in
    while true do
      (* the job must run on the scheduler thread because it accesses
         [ignored_files] *)
      let job =
        match Buffer.read_lines buffer pipe with
        | `End_of_file _remaining -> fun () -> [ Event.Watcher_terminated ]
        | `Ok lines ->
          fun () ->
            List.concat_map lines ~f:(fun line ->
                match parse_line line with
                | Error s -> failwith s
                | Ok path_s ->
                  if
                    is_special_file_for_fs_sync
                      ~path_as_reported_by_file_watcher:path_s
                  then
                    match consume_sync_event sync_table path_s with
                    | None -> []
                    | Some id -> [ Event.Sync id ]
                  else
                    let path =
                      Path.Expert.try_localize_external (Path.of_string path_s)
                    in
                    let abs_path = Path.to_absolute_filename path in
                    if Table.mem ignored_files abs_path then (
                      (* only use ignored record once *)
                      Table.remove ignored_files abs_path;
                      []
                    ) else
                      [ Fs_memo_event
                          (Fs_memo_event.create ~kind:File_changed ~path)
                      ])
      in
      scheduler.thread_safe_send_emit_events_job job
    done
  in
  scheduler.spawn_thread (fun () -> worker_thread pipe);
  { kind = Fswatch { pid; wait_for_watches_established = wait }
  ; ignored_files
  ; sync_table
  }

let with_buffering ~create ~(scheduler : Scheduler.t) ~debounce_interval =
  let jobs = ref [] in
  let event_mtx = Mutex.create () in
  let event_cv = Condition.create () in
  let res =
    let thread_safe_send_emit_events_job job =
      Mutex.lock event_mtx;
      jobs := job :: !jobs;
      Condition.signal event_cv;
      Mutex.unlock event_mtx
    in
    let scheduler = { scheduler with thread_safe_send_emit_events_job } in
    create ~scheduler
  in
  (* The buffer thread is used to avoid flooding the main thread with file
     changes events when a lot of file changes are reported at once. In
     particular, this avoids restarting the build over and over in a short
     period of time when many events are reported at once.

     It works as follow:

     - when the first event is received, send it to the main thread immediately
     so that we get a fast response time

     - after the first event is received, buffer subsequent events for
     [debounce_interval] *)
  let rec buffer_thread () =
    Mutex.lock event_mtx;
    while List.is_empty !jobs do
      Condition.wait event_cv event_mtx
    done;
    let jobs_batch = List.rev !jobs in
    jobs := [];
    Mutex.unlock event_mtx;
    scheduler.thread_safe_send_emit_events_job (fun () ->
        List.concat_map jobs_batch ~f:(fun job -> job ()));
    Thread.delay debounce_interval;
    buffer_thread ()
  in
  scheduler.spawn_thread buffer_thread;
  res

let create_inotifylib ~scheduler =
  prepare_sync ();
  let ignored_files = Table.create (module String) 64 in
  let sync_table = Table.create (module String) 64 in
  let inotify =
    create_inotifylib_watcher ~sync_table ~ignored_files ~scheduler
  in
  Inotify_lib.add inotify (Lazy.force special_dir_for_fs_sync);
  { kind = Inotify inotify; ignored_files; sync_table }

let fsevents_callback_gen (scheduler : Scheduler.t) ~f events =
  scheduler.thread_safe_send_emit_events_job (fun () ->
      List.filter_map events ~f)

let fsevents_callback (scheduler : Scheduler.t) ~f events =
  fsevents_callback_gen scheduler events ~f:(fun event ->
      let path =
        Fsevents.Event.path event |> Path.of_string
        |> Path.Expert.try_localize_external
      in
      f event path)

let fsevents ?exclusion_paths ~latency ~paths scheduler f =
  let paths = List.map paths ~f:Path.to_absolute_filename in
  let fsevents =
    Fsevents.create ~latency ~paths ~f:(fsevents_callback scheduler ~f)
  in
  Option.iter exclusion_paths ~f:(fun paths ->
      Fsevents.set_exclusion_paths fsevents ~paths);
  fsevents

let fsevents_standard_event event ~ignored_files path =
  let string_path = Fsevents.Event.path event in
  if Table.mem ignored_files string_path then (
    Table.remove ignored_files string_path;
    None
  ) else
    let action = Fsevents.Event.action event in
    let kind =
      match action with
      | Unknown -> Fs_memo_event.Unknown
      | Create -> Created
      | Remove -> Deleted
      | Modify ->
        if Fsevents.Event.kind event = File then
          File_changed
        else
          Unknown
    in
    Some (Event.Fs_memo_event { Fs_memo_event.kind; path })

let create_fsevents ?(latency = 0.2) ~(scheduler : Scheduler.t) () =
  prepare_sync ();
  let ignored_files = Table.create (module String) 64 in
  let sync_table = Table.create (module String) 64 in
  let sync =
    (* We don't use the [fsevents] function here as we want to match on the
       original file path *)
    Fsevents.create ~latency
      ~paths:[ Lazy.force special_dir_for_fs_sync ]
      ~f:
        (fsevents_callback_gen scheduler ~f:(fun event ->
             let path = Fsevents.Event.path event in
             if
               not
                 (is_special_file_for_fs_sync
                    ~path_as_reported_by_file_watcher:path)
             then
               None
             else
               match Fsevents.Event.action event with
               | Remove -> None
               | Unknown
               | Create
               | Modify ->
                 Option.map (consume_sync_event sync_table path) ~f:(fun id ->
                     Event.Sync id)))
  in
  let source =
    let paths = [ Path.root ] in
    let exclusion_paths =
      Path.(build Build.root)
      :: ([ "_esy"; "_opam"; ".git"; ".hg" ]
         |> List.rev_map ~f:(fun base ->
                let path = Path.relative (Path.source Path.Source.root) base in
                path))
      |> List.rev_map ~f:Path.to_absolute_filename
    in
    fsevents ~latency scheduler ~exclusion_paths ~paths
      (fsevents_standard_event ~ignored_files)
  in
  let cv = Condition.create () in
  let runloop_ref = ref None in
  let mutex = Mutex.create () in
  scheduler.spawn_thread (fun () ->
      let runloop = Fsevents.RunLoop.in_current_thread () in
      Mutex.lock mutex;
      runloop_ref := Some runloop;
      Condition.signal cv;
      Mutex.unlock mutex;
      Fsevents.start source runloop;
      Fsevents.start sync runloop;
      match Fsevents.RunLoop.run_current_thread runloop with
      | Ok () -> ()
      | Error exn ->
        Code_error.raise "fsevents callback raised" [ ("exn", Exn.to_dyn exn) ]);
  let external_ = Watch_trie.empty in
  let runloop =
    Mutex.lock mutex;
    while !runloop_ref = None do
      Condition.wait cv mutex
    done;
    Mutex.unlock mutex;
    Option.value_exn !runloop_ref
  in
  { kind = Fsevents { latency; scheduler; sync; source; external_; runloop }
  ; ignored_files
  ; sync_table
  }

let create_external ~root ~debounce_interval ~scheduler ~backend =
  match debounce_interval with
  | None -> create_no_buffering ~root ~scheduler ~backend
  | Some debounce_interval ->
    with_buffering ~scheduler ~debounce_interval
      ~create:(create_no_buffering ~root)
      ~backend

let create_default ?fsevents_debounce ~scheduler () =
  match select_watcher_backend () with
  | `Fswatch _ as backend ->
    create_external ~scheduler ~root:Path.root
      ~debounce_interval:(Some 0.5 (* seconds *)) ~backend
  | `Fsevents -> create_fsevents ?latency:fsevents_debounce ~scheduler ()
  | `Inotify_lib -> create_inotifylib ~scheduler

let wait_for_initial_watches_established_blocking t =
  match t.kind with
  | Fswatch c -> c.wait_for_watches_established ()
  | Fsevents _
  | Inotify _ ->
    (* no initial watches needed: all watches should be set up at the time just
       before file access *)
    ()

let add_watch t path =
  match t.kind with
  | Fsevents f -> (
    match path with
    | Path.In_source_tree _ -> (* already watched by source watcher *) Ok ()
    | In_build_dir _ ->
      Code_error.raise "attempted to watch a directory in build" []
    | External ext -> (
      let ext =
        let rec loop p =
          if Path.is_directory (Path.external_ p) then
            Some ext
          else
            match Path.External.parent p with
            | None ->
              User_warning.emit
                [ Pp.textf "Refusing to watch %s" (Path.External.to_string ext)
                ];
              None
            | Some ext -> loop ext
        in
        loop ext
      in
      match ext with
      | None -> Ok ()
      | Some ext -> (
        let watch =
          lazy
            (fsevents ~latency:f.latency f.scheduler ~paths:[ path ]
               (fsevents_standard_event ~ignored_files:t.ignored_files))
        in
        match Watch_trie.add f.external_ ext watch with
        | Watch_trie.Under_existing_node -> Ok ()
        | Inserted { new_t; removed } ->
          let watch = Lazy.force watch in
          Fsevents.start watch f.runloop;
          List.iter removed ~f:(fun (_, fs) -> Fsevents.stop fs);
          f.external_ <- new_t;
          Ok ())))
  | Fswatch _ ->
    (* Here we assume that the path is already being watched because the coarse
       file watchers are expected to watch all the source files from the
       start *)
    Ok ()
  | Inotify inotify -> (
    try Ok (Inotify_lib.add inotify (Path.to_string path)) with
    | Unix.Unix_error (ENOENT, _, _) -> Error `Does_not_exist)

let ignore_next_file_change_event t path =
  assert (Path.is_in_source_tree path);
  Table.set t.ignored_files (Path.to_absolute_filename path) ()
