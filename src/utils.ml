open Import

let system_shell_exn =
  let cmd, arg, os =
    if Sys.win32 then
      ("cmd", "/c", "on Windows")
    else
      ("sh", "-c", "")
  in
  let bin = lazy (Bin.which cmd) in
  fun ~needed_to ->
    match Lazy.force bin with
    | Some path -> (path, arg)
    | None ->
      die "I need %s to %s but I couldn't find it :(\n\
           Who doesn't have %s%s?!"
        cmd needed_to cmd os

let bash_exn =
  let bin = lazy (Bin.which "bash") in
  fun ~needed_to ->
    match Lazy.force bin with
    | Some path -> path
    | None ->
      die "I need bash to %s but I couldn't find it :("
        needed_to

let signal_name =
  let table =
    let open Sys in
    [ sigabrt   , "ABRT"
    ; sigalrm   , "ALRM"
    ; sigfpe    , "FPE"
    ; sighup    , "HUP"
    ; sigill    , "ILL"
    ; sigint    , "INT"
    ; sigkill   , "KILL"
    ; sigpipe   , "PIPE"
    ; sigquit   , "QUIT"
    ; sigsegv   , "SEGV"
    ; sigterm   , "TERM"
    ; sigusr1   , "USR1"
    ; sigusr2   , "USR2"
    ; sigchld   , "CHLD"
    ; sigcont   , "CONT"
    ; sigstop   , "STOP"
    ; sigtstp   , "TSTP"
    ; sigttin   , "TTIN"
    ; sigttou   , "TTOU"
    ; sigvtalrm , "VTALRM"
    ; sigprof   , "PROF"
    (* These ones are only available in OCaml >= 4.03 *)
    ; -22       , "BUS"
    ; -23       , "POLL"
    ; -24       , "SYS"
    ; -25       , "TRAP"
    ; -26       , "URG"
    ; -27       , "XCPU"
    ; -28       , "XFSZ"
    ]
  in
  fun n ->
    match List.assoc n table with
    | exception Not_found -> sprintf "%d\n" n
    | s -> s

let jbuild_name_in ~dir =
  match Path.extract_build_context dir with
  | None ->
    Path.to_string (Path.relative dir "jbuild")
  | Some (ctx_name, dir) ->
    sprintf "%s (context %s)"
      (Path.to_string (Path.relative dir "jbuild"))
      ctx_name

let describe_target fn =
  match Path.extract_build_context fn with
  | Some (".aliases", dir) ->
    sprintf "alias %s" (Path.to_string dir)
  | _ ->
    Path.to_string fn

let program_not_found ?context ?hint prog =
  die "@{<error>Error@}: Program %s not found in PATH%s%a" prog
    (match context with
     | None -> ""
     | Some name -> sprintf " (context: %s)" name)
    (fun fmt -> function
       | None -> ()
       | Some h -> Format.fprintf fmt "@ Hint: %s" h)
    hint
