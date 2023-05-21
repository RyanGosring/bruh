include Stdune
module Digest = Dune_digest
module Console = Dune_console
module Metrics = Dune_metrics
module Log = Dune_util.Log
module Stringlike = Dune_util.Stringlike
module Stringlike_intf = Dune_util.Stringlike_intf
module Persistent = Dune_util.Persistent
module Execution_env = Dune_util.Execution_env
module Predicate_lang = Dune_lang.Predicate_lang
module Glob = Dune_glob.V1
module Outputs = Dune_lang.Action.Outputs
module Inputs = Dune_lang.Action.Inputs
module File_perm = Dune_lang.Action.File_perm
module Diff = Dune_lang.Action.Diff
include No_io

(* To make bug reports usable *)
let () = Printexc.record_backtrace true

let protect = Exn.protect

let protectx = Exn.protectx
