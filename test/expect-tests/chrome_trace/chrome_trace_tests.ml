open Stdune
open Dune_tests_common

let () = init ()

let buf = Buffer.create 0

let c =
  let write s = Buffer.add_string buf s in
  let close () = () in
  Stats.create (Custom { write; close })

let () =
  let module Event = Chrome_trace.Event in
  let module Id = Event.Id in
  let module Timestamp = Event.Timestamp in
  let events =
    [ Event.complete
        ~dur:(Timestamp.of_float_seconds 1.)
        ~args:[ ("foo", `String "bar") ]
        (Event.common ~ts:(Timestamp.of_float_seconds 0.5) ~name:"foo" ())
    ; Event.counter
        (Event.common ~ts:(Timestamp.of_float_seconds 0.5) ~name:"cnt" ())
        [ ("bar", `Int 250) ]
    ; Event.async (Id.String "foo") Event.Start
        (Event.common ~ts:(Timestamp.of_float_seconds 0.5) ~name:"async" ())
        ~args:[ ("foo", `Int 100) ]
    ]
  in
  List.iter events ~f:(Stats.emit c);
  Stats.close c

let buffer_lines () = String.split_lines (Buffer.contents buf)

let%expect_test _ =
  Format.printf "%a@." Pp.to_fmt
    (Pp.vbox (Pp.concat_map (buffer_lines ()) ~sep:Pp.cut ~f:Pp.verbatim));
  [%expect
    {|
[{"args":{"foo":"bar"},"ph":"X","dur":1000000,"name":"foo","cat":"","ts":500000,"pid":0,"tid":0}
,{"ph":"C","args":{"bar":250},"name":"cnt","cat":"","ts":500000,"pid":0,"tid":0}
,{"args":{"foo":100},"ph":"b","id":"foo","name":"async","cat":"","ts":500000,"pid":0,"tid":0}
]
|}]
