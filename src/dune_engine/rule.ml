open! Stdune
open Import
module Action_builder = Action_builder0

module Info = struct
  type t =
    | From_dune_file of Loc.t
    | Internal
    | Source_file_copy of Path.Source.t

  let of_loc_opt = function
    | None -> Internal
    | Some loc -> From_dune_file loc

  let to_dyn : t -> Dyn.t = function
    | From_dune_file loc -> Dyn.Variant ("From_dune_file", [ Loc.to_dyn loc ])
    | Internal -> Dyn.Variant ("Internal", [])
    | Source_file_copy p ->
      Dyn.Variant ("Source_file_copy", [ Path.Source.to_dyn p ])
end

module Promote = struct
  module Lifetime = struct
    type t =
      | Unlimited
      | Until_clean
  end

  module Into = struct
    type t =
      { loc : Loc.t
      ; dir : string
      }
  end

  type t =
    { lifetime : Lifetime.t
    ; into : Into.t option
    ; only : Predicate_lang.Glob.t option
    }
end

module Mode = struct
  type t =
    | Standard
    | Fallback
    | Promote of Promote.t
    | Ignore_source_files
    | Patch_back_source_tree
end

module Id = Id.Make ()

module T = struct
  type t =
    { id : Id.t
    ; context : Build_context.t option
    ; targets : Targets.t
    ; action : Action.Full.t Action_builder.t
    ; mode : Mode.t
    ; info : Info.t
    ; loc : Loc.t
    ; dir : Path.Build.t
    }

  let compare a b = Id.compare a.id b.id

  let equal a b = Id.equal a.id b.id

  let hash t = Id.hash t.id

  let loc t = t.loc

  let to_dyn t : Dyn.t =
    Record [ ("id", Id.to_dyn t.id); ("info", Info.to_dyn t.info) ]
end

include T
module O = Comparable.Make (T)
module Set = O.Set

let add_sandbox_config :
    type a.
    a Action_builder.eval_mode -> Sandbox_config.t -> a Dep.Map.t -> a Dep.Map.t
    =
 fun mode sandbox map ->
  let dep = Dep.sandbox_config sandbox in
  match mode with
  | Lazy -> Dep.Set.add map dep
  | Eager -> Dep.Map.set map dep Dep.Fact.nothing

let make ?(sandbox = Sandbox_config.default) ?(mode = Mode.Standard) ~context
    ?(info = Info.Internal) ~targets action =
  let sandbox =
    match mode with
    | Patch_back_source_tree ->
      Sandbox_config.inter sandbox
        (Sandbox_mode.Set.singleton Sandbox_mode.copy)
    | _ -> sandbox
  in
  let action =
    let open Memo.Build.O in
    Action_builder.memoize "Rule.make"
      (Action_builder.of_thunk
         { f =
             (fun mode ->
               let+ action, deps = Action_builder.run action mode in
               let deps = add_sandbox_config mode sandbox deps in
               (action, deps))
         })
  in
  let report_error ?(extra_pp = []) message =
    match info with
    | From_dune_file loc ->
      let pp = [ Pp.text message ] @ extra_pp in
      User_error.raise ~loc pp
    | Internal
    | Source_file_copy _ ->
      Code_error.raise message
        [ ("info", Info.to_dyn info); ("targets", Targets.to_dyn targets) ]
  in
  let dir =
    match Targets.validate targets with
    | Valid { parent_dir } -> parent_dir
    | No_targets -> report_error "Rule has no targets specified"
    | Inconsistent_parent_dir ->
      report_error "Rule has targets in different directories."
        ~extra_pp:[ Pp.text "Targets:"; Targets.pp targets ]
    | File_and_directory_target_with_the_same_name path ->
      report_error
        (sprintf "%S is declared as both a file and a directory target."
           (Dpath.describe_target path))
  in
  let loc =
    match info with
    | From_dune_file loc -> loc
    | Internal ->
      Loc.in_file
        (Path.drop_optional_build_context
           (Path.build (Path.Build.relative dir "_unknown_")))
    | Source_file_copy p -> Loc.in_file (Path.source p)
  in
  { id = Id.gen (); targets; context; action; mode; info; loc; dir }

let set_action t action =
  let action = Action_builder.memoize "Rule.set_action" action in
  { t with action }

let find_source_dir rule =
  let _, src_dir = Path.Build.extract_build_context_dir_exn rule.dir in
  Source_tree.nearest_dir src_dir

module Anonymous_action = struct
  type t =
    { context : Build_context.t option
    ; action : Action.Full.t
    ; loc : Loc.t option
    ; dir : Path.Build.t
    ; alias : Alias.Name.t option
    ; patch_back_source_tree : bool
    }
end
