open Import

type t =
  { name : Package_name.t
  ; dependencies : Package_dependency.t list
  }

let to_local (t : t) : Local_package.t =
  let open Local_package in
  { name = t.name
  ; version = None
  ; dependencies = t.dependencies
  ; conflicts = []
  ; depopts = []
  ; pins = Package_name.Map.empty
  ; conflict_class = []
  ; loc = Loc.none
  }
;;

let root_location = "_dev_tools"

module OCamlformat = struct
  (* TODO: just to experiement the solving, it going to be remove *)
  let _ocamlformat_dependency =
    let open Dune_lang in
    let open Package_dependency in
    let constraint_ =
      Package_constraint.Uop (Relop.Eq, Package_constraint.Value.String_literal "0.26.0")
    in
    { name = Package_name.of_string "ocamlformat"; constraint_ = Some constraint_ }
  ;;

  let _ocamlformat_dev =
    { name = Package_name.of_string "ocamlformat-dev"
    ; dependencies = [ _ocamlformat_dependency ]
    }
  ;;

  let ocamlformat_dev_local = to_local _ocamlformat_dev

  let from_ocamlformat_constraint ocamlformat_dependency =
    { name = Package_name.of_string "ocamlformat-dev"
    ; dependencies = [ ocamlformat_dependency ]
    }
  ;;
end
