open Stdune

module Fd_count = struct
  type t =
    | Unknown
    | This of int

  let try_to_use_lsof () =
    (* note: we do not use the Process module here, because it would create a
       circular dependency *)
    let temp = Temp.create File ~prefix:"dune." ~suffix:".lsof" in
    let stdout =
      Unix.openfile
        (Path.to_absolute_filename temp)
        [ O_WRONLY; O_CREAT; O_TRUNC; O_SHARE_DELETE ]
        0o666
    in
    let prog = "/usr/sbin/lsof" in
    let argv = [ prog; "-w"; "-p"; string_of_int (Unix.getpid ()) ] in
    let pid = Spawn.spawn ~prog ~argv ~stdout () in
    Unix.close stdout;
    match Unix.waitpid [] (Pid.to_int pid) with
    | _, Unix.WEXITED 0 ->
      let num_lines = List.length (Io.input_lines (Io.open_in temp)) in
      This (num_lines - 1)
    (* the output contains a header line *)
    | _ -> Unknown

  let get () =
    match Sys.readdir "/proc/self/fd" with
    | exception _ -> (
      match try_to_use_lsof () with
      | exception _ -> Unknown
      | value -> value)
    | files -> This (Array.length files - 1 (* -1 for the dirfd *))
end

let evaluated_rules = ref 0

let new_evaluated_rule () = incr evaluated_rules

let () = Hooks.End_of_build.always (fun () -> evaluated_rules := 0)

let trace = ref None

let record () =
  Option.iter !trace ~f:(fun reporter ->
      Chrome_trace.emit_gc_counters reporter;
      let now = Chrome_trace.Event.Timestamp.now () in
      let event =
        let args = [ ("value", Chrome_trace.Json.Int !evaluated_rules) ] in
        let common =
          Chrome_trace.Event.common ~name:"evaluated_rules" ~ts:now ~pid:0
            ~tid:0 ()
        in
        Chrome_trace.Event.counter common args
      in
      Chrome_trace.emit reporter event;
      match Fd_count.get () with
      | Unknown -> ()
      | This fds ->
        let event =
          let args = [ ("value", Chrome_trace.Json.Int fds) ] in
          let common =
            Chrome_trace.Event.common ~name:"fds" ~ts:now ~pid:0 ~tid:0 ()
          in
          Chrome_trace.Event.counter common args
        in
        Chrome_trace.emit reporter event)

let enable path =
  let reporter = Chrome_trace.make path in
  trace := Some reporter;
  at_exit (fun () -> Chrome_trace.close reporter)

let with_process ~program ~args fiber =
  match !trace with
  | None -> fiber
  | Some reporter ->
    let open Fiber.O in
    let event = Chrome_trace.on_process_start reporter ~program ~args in
    let+ result = fiber in
    Chrome_trace.on_process_end reporter event;
    result
