open Import

type exn_handler = exn -> Printexc.raw_backtrace -> unit

type 'a t = { mutable state : 'a state }

and 'a state =
  | Return of 'a
  | Sleep of 'a handlers
  | Repr of 'a t

and 'a handlers =
  | Empty
  | One    of exn_handler * ('a -> unit)
  | Append of 'a handlers * 'a handlers

let exn_handler = ref (fun exn _ -> reraise exn)

let append h1 h2 =
  match h1, h2 with
  | Empty, _ -> h2
  | _, Empty -> h1
  | _ -> Append (h1, h2)

let rec repr t =
  match t.state with
  | Repr t' -> let t'' = repr t' in if t'' != t' then t.state <- Repr t''; t''
  | _       -> t

let run_handlers handlers x =
  let rec loop handlers acc =
    match handlers with
    | Empty -> continue acc
    | One (handler, f) ->
      exn_handler := handler;
      (try
         f x
       with exn ->
         let bt = Printexc.get_raw_backtrace () in
         handler exn bt);
      continue acc
    | Append (h1, h2) -> loop h1 (h2 :: acc)
  and continue = function
    | [] -> ()
    | h :: acc -> loop h acc
  in
  protectx !exn_handler
    ~finally:(fun saved ->
        exn_handler := saved)
    ~f:(fun _ ->
        loop handlers [])

let connect t1 t2 =
  let t1 = repr t1 and t2 = repr t2 in
  match t1.state with
  | Sleep h1 ->
    if t1 == t2 then
      ()
    else begin
      match t2.state with
      | Repr _ -> assert false
      | Sleep h2 ->
        t2.state <- Repr t1;
        t1.state <- Sleep (append h1 h2)
      | Return x as state2 ->
        t1.state <- state2;
        run_handlers h1 x
    end
  | _ ->
    assert false

let return x = { state = Return x }

let sleeping () = { state = Sleep Empty }

let ( >>= ) t f =
  let t = repr t in
  match t.state with
  | Return v -> f v
  | Sleep handlers ->
    let res = sleeping () in
    t.state <- Sleep (append handlers (One (!exn_handler,
                                            fun x -> connect res (f x))));
    res
  | Repr _ ->
    assert false

let ( >>| ) t f = t >>= fun x -> return (f x)

let with_exn_handler f ~handler =
  let saved = !exn_handler in
  exn_handler := handler;
  match f () with
  | x -> exn_handler := saved; x
  | exception exn ->
    let bt = Printexc.get_raw_backtrace () in
    exn_handler := saved;
    handler exn bt;
    reraise exn

let both a b =
  a >>= fun a ->
  b >>= fun b ->
  return (a, b)

let create f =
  let t = sleeping () in
  f t;
  t

module Ivar = struct
  type nonrec 'a t = 'a t

  let fill t x =
    let t = repr t in
    match t.state with
    | Repr _ -> assert false
    | Return _ -> failwith "Future.Ivar.fill"
    | Sleep handlers ->
      t.state <- Return x;
      run_handlers handlers x
end

let rec all = function
  | [] -> return []
  | x :: l ->
    x     >>= fun x ->
    all l >>= fun l ->
    return (x :: l)

let rec all_unit = function
  | [] -> return ()
  | x :: l ->
    x >>= fun () ->
    all_unit l

type job =
  { prog      : string
  ; args      : string list
  ; dir       : string option
  ; stdout_to : string option
  ; env       : string array option
  ; ivar      : unit Ivar.t
  }

let to_run : job Queue.t = Queue.create ()

let run ?dir ?stdout_to ?env prog args =
  let dir =
    match dir with
    | Some "." -> None
    | _ -> dir
  in
  create (fun ivar ->
    Queue.push { prog; args; dir; stdout_to; env; ivar } to_run)

let tmp_files = ref String_set.empty
let () =
  at_exit (fun () ->
    let fns = !tmp_files in
    tmp_files := String_set.empty;
    String_set.iter fns ~f:(fun fn ->
      try Sys.remove fn with _ -> ()))

let run_capture_gen ?dir ?env prog args ~f =
  let fn = Filename.temp_file "jbuild" ".output" in
  tmp_files := String_set.add fn !tmp_files;
  run ?dir ~stdout_to:fn ?env prog args >>= fun () ->
  let s = f fn in
  Sys.remove fn;
  tmp_files := String_set.remove fn !tmp_files;
  return s

let run_capture       = run_capture_gen ~f:read_file
let run_capture_lines = run_capture_gen ~f:lines_of_file

let run_capture_line ?dir ?env prog args =
  run_capture_lines ?dir ?env prog args >>| function
  | [x] -> x
  | l ->
    let cmdline =
      let s = String.concat (prog :: args) ~sep:" " in
      match dir with
      | None -> s
      | Some dir -> sprintf "cd %s && %s" dir s
    in
    match l with
    | [] ->
      die "command returned nothing: %s" cmdline
    | _ ->
      die "command returned too many lines: %s\n%s"
        cmdline (String.concat l ~sep:"\n")

module Scheduler = struct
  let key_for_color prog =
    let s = Filename.basename prog in
    match String.lsplit2 s ~on:'.' with
    | None -> s
    | Some (s, _) -> s

  let command_line { prog; args; dir; stdout_to; _ } =
    let quote = quote_for_shell in
    let prog =
      let s = quote prog in
      Ansi_color.colorize ~key:(key_for_color prog) s
    in
    let s = String.concat (prog :: List.map args ~f:quote) ~sep:" " in
    let s =
      match stdout_to with
      | None -> s
      | Some fn -> sprintf "%s > %s" s fn
    in
    match dir with
    | None -> s
    | Some dir -> sprintf "(cd %s && %s)" dir s

  let stderr_supports_colors = lazy(
    not Sys.win32        &&
    Unix.(isatty stderr) &&
    match Sys.getenv "TERM" with
    | exception Not_found -> false
    | "dumb" -> false
    | _ -> true
  )

  let strip_colors_for_stderr s =
    if Lazy.force Ansi_color.stderr_supports_colors then
      s
    else
      Ansi_color.strip s

  type running_job =
    { id              : int
    ; job             : job
    ; pid             : int
    ; output_filename : string
    ; (* for logs, with ansi colors code always included in the string *)
      command_line    : string
    ; log             : out_channel option
    }

  let running = Hashtbl.create 128

  let handle_process_status job (status : Unix.process_status) =
    match status with
    | WEXITED   0 -> ()
    | WEXITED   n -> die "Command [%d] exited with code %d"     job.id n
    | WSIGNALED n -> die "Command [%d] got killed by signal %d" job.id n
    | WSTOPPED  _ -> assert false

  let process_done ?(exiting=false) job (status : Unix.process_status) =
    Hashtbl.remove running job.pid;
    let output =
      let s = read_file job.output_filename in
      let len = String.length s in
      if len > 0 && s.[len - 1] <> '\n' then
        s ^ "\n"
      else
        s
    in
    Sys.remove job.output_filename;
    Option.iter job.log ~f:(fun oc ->
      Printf.fprintf oc "$ %s\n%s"
        (Ansi_color.strip job.command_line)
        (Ansi_color.strip output);
      (match status with
       | WEXITED   0 -> ()
       | WEXITED   n -> Printf.fprintf oc "[%d]\n" n
       | WSIGNALED n -> Printf.fprintf oc "[got signal %d]\n" n
       | WSTOPPED  _ -> assert false);
      flush oc
    );
    if not exiting then begin
      match status with
      | WEXITED 0 ->
        if output <> "" then
          Printf.eprintf "Output[%d]:\n%s%!" job.id output;
        Ivar.fill job.job.ivar ()
      | WEXITED n ->
        Printf.eprintf "\nCommand [%d] exited with code %d:\n$ %s\n%s%!"
          job.id n
          (strip_colors_for_stderr job.command_line)
          (strip_colors_for_stderr output);
        die ""
      | WSIGNALED n ->
        Printf.eprintf "\nCommand [%d] got signal %d:\n$ %s\n%s%!"
          job.id n
          (strip_colors_for_stderr job.command_line)
          (strip_colors_for_stderr output);
        die ""
      | WSTOPPED _ -> assert false
    end

  let gen_id =
    let next = ref (-1) in
    fun () -> incr next; !next

  let rec wait_win32 () =
    let finished =
      Hashtbl.fold running ~init:[] ~f:(fun ~key:pid ~data:job acc ->
        let pid, status = Unix.waitpid [WNOHANG] pid in
        if pid <> 0 then begin
          (pid, job, status) :: acc
        end else
          acc)
    in
    match finished with
    | [] ->
      Unix.sleepf 0.001;
      wait_win32 ()
    | _ ->
      List.iter finished ~f:(fun (pid, job, status) ->
        process_done job status)

  let () =
    at_exit (fun () ->
      let pids =
        Hashtbl.fold running ~init:[] ~f:(fun ~key:_ ~data:job acc -> job :: acc)
      in
      List.iter pids ~f:(fun job ->
        let _, status = Unix.waitpid [] job.pid in
        process_done job status ~exiting:true))

  let rec go_rec cwd log t =
    match (repr t).state with
    | Return v -> v
    | _ ->
      while Hashtbl.length running < !Clflags.concurrency &&
            not (Queue.is_empty to_run) do
        let job = Queue.pop to_run in
        let id = gen_id () in
        let command_line = command_line job in
        if !Clflags.debug_run then
          Printf.eprintf "Running[%d]: %s\n%!" id
            (strip_colors_for_stderr command_line);
        Option.iter job.dir ~f:(fun dir -> Sys.chdir dir);
        let argv = Array.of_list (job.prog :: job.args) in
        let output_filename = Filename.temp_file "jbuilder" ".output" in
        let output_fd = Unix.openfile output_filename [O_WRONLY] 0 in
        let stdout, close_stdout =
          match job.stdout_to with
          | None -> (output_fd, false)
          | Some fn ->
            let fd = Unix.openfile fn [O_WRONLY; O_CREAT; O_TRUNC] 0o666 in
            (fd, true)
        in
        let pid =
          match job.env with
          | None ->
            Unix.create_process job.prog argv
              Unix.stdin stdout output_fd
          | Some env ->
            Unix.create_process_env job.prog argv env
              Unix.stdin stdout output_fd
        in
        Unix.close output_fd;
        if close_stdout then Unix.close stdout;
        Option.iter job.dir ~f:(fun _ -> Sys.chdir cwd);
        Hashtbl.add running ~key:pid
          ~data:{ id
                ; job
                ; pid
                ; output_filename
                ; command_line
                ; log
                }
      done;
      if Sys.win32 then
        wait_win32 ()
      else begin
        let pid, status = Unix.wait () in
        let job =
          Hashtbl.find_exn running pid ~string_of_key:(sprintf "<pid:%d>")
            ~table_desc:(fun _ -> "<running-jobs>")
        in
        process_done job status
      end;
      go_rec cwd log t

  let go ?log t =
    Lazy.force Ansi_color.setup_env_for_ocaml_colors;
    let cwd = Sys.getcwd () in
    go_rec cwd log t
end
