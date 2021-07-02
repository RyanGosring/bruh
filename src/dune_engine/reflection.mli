open Import
module Non_evaluated_rule = Rule

module Rule : sig
  type t = private
    { id : Rule.Id.t
    ; dir : Path.Build.t
    ; deps : Dep.Set.t
    ; expanded_deps : Path.Set.t
    ; targets : Path.Build.Set.t
    ; context : Build_context.t option
    ; action : Action.t
    }
end

(** Used by Jane Street internal rules. *)
val evaluate_rule : Non_evaluated_rule.t -> Rule.t Memo.Build.t

val eval :
  recursive:bool -> request:unit Action_builder.t -> Rule.t list Memo.Build.t
