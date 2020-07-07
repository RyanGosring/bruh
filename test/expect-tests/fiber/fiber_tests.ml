open Stdune
open Fiber.O
open Dyn.Encoder
open Dune_tests_common

let () = init ()

module Scheduler : sig
  exception Never

  val yield : unit -> unit Fiber.t

  val run : 'a Fiber.t -> 'a
end = struct
  let suspended = Queue.create ()

  let yield () =
    let ivar = Fiber.Ivar.create () in
    Queue.push suspended ivar;
    Fiber.Ivar.read ivar

  exception Never

  let run t =
    Fiber.run t ~iter:(fun () ->
        match Queue.pop suspended with
        | None -> raise Never
        | Some e -> Fiber.Fill (e, ()))
end

let failing_fiber () : unit Fiber.t =
  Scheduler.yield () >>= fun () -> raise Exit

let long_running_fiber () =
  let rec loop n =
    if n = 0 then
      Fiber.return ()
    else
      Scheduler.yield () >>= fun () -> loop (n - 1)
  in
  loop 10

let never_fiber () = Fiber.never

let backtrace_result dyn_of_ok =
  Result.to_dyn dyn_of_ok (list Exn_with_backtrace.to_dyn)

let test ?(expect_never = false) to_dyn f =
  let never_raised = ref false in
  ( try Scheduler.run f |> to_dyn |> print_dyn
    with Scheduler.Never -> never_raised := true );
  match (!never_raised, expect_never) with
  | false, false ->
    (* We don't raise in this case b/c we assume something else is being tested *)
    ()
  | true, true -> print_endline "[PASS] Never raised as expected"
  | false, true ->
    print_endline "[FAIL] expected Never to be raised but it wasn't"
  | true, false -> print_endline "[FAIL] unexpected Never raised"

let%expect_test "execution context of ivars" =
  (* The point of this test it show that the execution context is restored when
     a fiber that's blocked on an ivar is resumed. This means that fiber local
     variables are visible for exmaple*)
  let open Fiber.O in
  let ivar = Fiber.Ivar.create () in
  let run_when_filled () =
    let var = Fiber.Var.create () in
    Fiber.Var.set var 42 (fun () ->
        let* peek = Fiber.Ivar.peek ivar in
        assert (peek = None);
        let+ () = Fiber.Ivar.read ivar in
        let value = Fiber.Var.get_exn var in
        Printf.printf "var value %d\n" value)
  in
  let run = Fiber.fork_and_join_unit run_when_filled (Fiber.Ivar.fill ivar) in
  test unit run;
  [%expect {|
    var value 42
    () |}]

let%expect_test "fiber vars are preseved across yields" =
  let var = Fiber.Var.create () in
  let fiber th () =
    assert (Fiber.Var.get var = None);
    Fiber.Var.set var th (fun () ->
        assert (Fiber.Var.get var = Some th);
        let+ () = Scheduler.yield () in
        assert (Fiber.Var.get var = Some th))
  in
  let run = Fiber.fork_and_join_unit (fiber 1) (fiber 2) in
  test unit run;
  [%expect {|
    () |}]

let%expect_test "fill returns a fiber that executes before waiters are awoken" =
  let ivar = Fiber.Ivar.create () in
  let open Fiber.O in
  let waiters () =
    let waiter n () =
      let+ () = Fiber.Ivar.read ivar in
      Printf.printf "waiter %d resumed\n" n
    in
    Fiber.fork_and_join_unit (waiter 1) (waiter 2)
  in
  let run () =
    let* () = Scheduler.yield () in
    let+ () = Fiber.Ivar.fill ivar () in
    Printf.printf "ivar filled\n"
  in
  test unit (Fiber.fork_and_join_unit waiters run);
  [%expect
    {|
    ivar filled
    waiter 1 resumed
    waiter 2 resumed
    () |}]

let%expect_test _ =
  test (backtrace_result unit) (Fiber.collect_errors failing_fiber);
  [%expect {|
Error [ { exn = "Exit"; backtrace = "" } ]
|}]

let%expect_test _ =
  test ~expect_never:true opaque (Fiber.collect_errors never_fiber);
  [%expect {|
[PASS] Never raised as expected
|}]

let%expect_test _ =
  test (backtrace_result unit)
    (Fiber.collect_errors (fun () ->
         failing_fiber () >>= fun () -> failing_fiber ()));
  [%expect {|
Error [ { exn = "Exit"; backtrace = "" } ]
|}]

let log_error (e : Exn_with_backtrace.t) =
  Printf.printf "raised %s\n" (Printexc.to_string e.exn)

let%expect_test _ =
  test (backtrace_result unit)
    (Fiber.collect_errors (fun () ->
         Fiber.with_error_handler failing_fiber ~on_error:log_error));
  [%expect {|
raised Exit
Error []
|}]

let%expect_test _ =
  test
    (backtrace_result (pair unit unit))
    (Fiber.collect_errors (fun () ->
         Fiber.fork_and_join failing_fiber long_running_fiber));
  [%expect {|
Error [ { exn = "Exit"; backtrace = "" } ]
|}]

let%expect_test _ =
  test
    (pair (backtrace_result unit) unit)
    (Fiber.fork_and_join
       (fun () -> Fiber.collect_errors failing_fiber)
       long_running_fiber);
  [%expect {|
(Error [ { exn = "Exit"; backtrace = "" } ], ())
|}]

let%expect_test _ =
  test ~expect_never:true opaque
    (Fiber.fork_and_join
       (fun () ->
         let log_error by (e : Exn_with_backtrace.t) =
           Printf.printf "%s: raised %s\n" by (Printexc.to_string e.exn)
         in
         Fiber.with_error_handler ~on_error:(log_error "outer") (fun () ->
             Fiber.fork_and_join failing_fiber (fun () ->
                 Fiber.with_error_handler
                   ~on_error:(fun e ->
                     log_error "inner" e;
                     raise Exit)
                   failing_fiber)))
       long_running_fiber);
  [%expect
    {|
    outer: raised Exit
    inner: raised Exit
    outer: raised Exit
    [PASS] Never raised as expected |}]

let must_set_flag f =
  let flag = ref false in
  let setter () = flag := true in
  let check_set () =
    print_endline
      ( if !flag then
        "[PASS] flag set"
      else
        "[FAIL] flag not set" )
  in
  try
    f setter;
    check_set ()
  with e ->
    check_set ();
    raise e

let%expect_test _ =
  must_set_flag (fun setter ->
      test ~expect_never:true unit
      @@ Fiber.fork_and_join_unit never_fiber (fun () ->
             Fiber.collect_errors failing_fiber >>= fun res ->
             print_dyn (backtrace_result unit res);
             long_running_fiber () >>= fun () -> Fiber.return (setter ())));
  [%expect
    {|
    Error [ { exn = "Exit"; backtrace = "" } ]
    [PASS] Never raised as expected
    [PASS] flag set |}]

let%expect_test _ =
  let forking_fiber () =
    Fiber.parallel_map [ 1; 2; 3; 4; 5 ] ~f:(fun x ->
        Scheduler.yield () >>= fun () ->
        if x mod 2 = 1 then
          Fiber.return ()
        else
          Printf.ksprintf failwith "%d" x)
  in
  must_set_flag (fun setter ->
      test ~expect_never:true unit
      @@ Fiber.fork_and_join_unit never_fiber (fun () ->
             Fiber.collect_errors forking_fiber >>= fun res ->
             print_dyn (backtrace_result (list unit) res);
             long_running_fiber () >>= fun () -> Fiber.return (setter ())));
  [%expect
    {|
    Error
      [ { exn = "(Failure 2)"; backtrace = "" }
      ; { exn = "(Failure 4)"; backtrace = "" }
      ]
    [PASS] Never raised as expected
    [PASS] flag set |}]

let%expect_test "Sequence.parallel_iter is indeed parallel" =
  let test ~iter_function =
    let rec sequence n =
      if n = 4 then
        Fiber.return Fiber.Sequence.Nil
      else
        Fiber.return (Fiber.Sequence.Cons (n, sequence (n + 1)))
    in
    Scheduler.run
      (iter_function (sequence 1) ~f:(fun n ->
           Printf.printf "%d: enter\n" n;
           let* () = long_running_fiber () in
           Printf.printf "%d: leave\n" n;
           Fiber.return ()))
  in

  (* The [enter] amd [leave] messages must be interleaved to indicate that the
     calls to [f] are executed in parallel: *)
  test ~iter_function:Fiber.Sequence.parallel_iter;
  [%expect
    {|
    1: enter
    2: enter
    3: enter
    1: leave
    2: leave
    3: leave |}];

  (* With [sequential_iter] however, The [enter] amd [leave] messages must be
     paired in sequence: *)
  test ~iter_function:Fiber.Sequence.sequential_iter;
  [%expect
    {|
    1: enter
    1: leave
    2: enter
    2: leave
    3: enter
    3: leave |}]

let%expect_test "Sequence.*_iter can be finalized" =
  let test ~iter_function =
    let rec sequence n =
      if n = 4 then
        Fiber.return Fiber.Sequence.Nil
      else
        Fiber.return (Fiber.Sequence.Cons (n, sequence (n + 1)))
    in
    Scheduler.run
      (Fiber.finalize
         ~finally:(fun () ->
           Printf.printf "finalized";
           Fiber.return ())
         (fun () -> iter_function (sequence 1) ~f:(fun _ -> Fiber.return ())))
  in
  test ~iter_function:Fiber.Sequence.sequential_iter;
  [%expect {| finalized |}];

  test ~iter_function:Fiber.Sequence.parallel_iter;
  [%expect {| finalized |}]

let rec naive_sequence_parallel_iter (t : _ Fiber.Sequence.t) ~f =
  t >>= function
  | Nil -> Fiber.return ()
  | Cons (x, t) ->
    Fiber.fork_and_join_unit
      (fun () -> f x)
      (fun () -> naive_sequence_parallel_iter t ~f)

let%expect_test "Sequence.parallel_iter doesn't leak" =
  (* Check that a naive [parallel_iter] functions on sequences leaks memory,
     while [Fiber.Sequence.parallel_iter] does not. To do that, we construct a
     long sequence and iterate over it. At each iteration, we do a full major GC
     and count the number of live words. With the naive implementation, we check
     that this number increases while with the right one we check that this
     number is constant.

     This test is carefully crafted to avoid creating new live words as we
     iterate through the sequence. As a result, the only new live words that can
     appear are because of the iteration function. *)
  let test ~iter_function ~check =
    let rec sequence n =
      (* This yield is to ensure that we don't build the whole sequence upfront,
         which would cause the number of live words to decrease as we iterate
         through the sequence. *)
      let* () = Scheduler.yield () in
      if n = 0 then
        Fiber.return Fiber.Sequence.Nil
      else
        Fiber.return (Fiber.Sequence.Cons ((), sequence (n - 1)))
    in
    (* We use [-1] as a [None] value to avoid going from [None] to [Some _],
       which would case the number of live words to change *)
    let prev = ref (-1) in
    let ok = ref true in
    let f () =
      Gc.full_major ();
      let curr = (Gc.stat ()).live_words in
      if !prev >= 0 then
        if not (check ~prev:!prev ~curr) then (
          Printf.printf
            "[FAIL] live words not changing as expected: prev=%d, curr=%d\n"
            !prev curr;
          ok := false
        );
      prev := curr;
      Fiber.return ()
    in
    Scheduler.run (iter_function (sequence 100) ~f);
    if !ok then print_string "PASS"
  in

  (* Check that the number of live words keeps on increasing because we are
     leaking memory: *)
  test ~iter_function:naive_sequence_parallel_iter ~check:(fun ~prev ~curr ->
      prev < curr);
  [%expect {| PASS |}];

  (* Check that the number of live words is constant with this iter function: *)
  test ~iter_function:Fiber.Sequence.parallel_iter ~check:(fun ~prev ~curr ->
      prev = curr);
  [%expect {| PASS |}]
