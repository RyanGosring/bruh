open Import
open Dune_lang.Decoder

type allowed_vars =
  | Any
  | Only of (string * Dune_lang.Syntax.Version.t) list

(* The following variables are the ones allowed in the enabled_if fields of
   libraries, executables and install stanzas. While allowed variables for
   theses stanzas are the same, the version at which they were allowed differs. *)
let common_vars_list =
  [ "architecture"
  ; "system"
  ; "model"
  ; "os_type"
  ; "ccomp_type"
  ; "profile"
  ; "ocaml_version"
  ]

let common_vars ~since =
  Only (List.map ~f:(fun var -> (var, since)) common_vars_list)

let decode ?(allowed_vars = Any) ~since () =
  let check_vars blang =
    match allowed_vars with
    | Any -> return blang
    | Only allowed_vars ->
      Blang.fold_vars blang ~init:(return blang) ~f:(fun var dec ->
          let raise_error () =
            let loc = String_with_vars.Var.loc var in
            let var_names = List.map ~f:fst allowed_vars in
            User_error.raise ~loc
              [ Pp.textf "Only %s are allowed in this 'enabled_if' field."
                  (String.enumerate_and var_names)
              ]
          in
          match String_with_vars.Var.(name var, payload var) with
          | _, Some _ -> raise_error ()
          | name, None -> (
            match List.assoc allowed_vars name with
            | None -> raise_error ()
            | Some min_ver ->
              let* current_ver = Dune_lang.Syntax.get_exn Stanza.syntax in
              if min_ver > current_ver then
                let loc = String_with_vars.Var.loc var in
                let what = "This variable" in
                Dune_lang.Syntax.Error.since loc Stanza.syntax min_ver ~what
              else
                return () >>> dec ))
  in
  let decode =
    ( match since with
    | None -> Blang.decode
    | Some since -> Dune_lang.Syntax.since Stanza.syntax since >>> Blang.decode
    )
    >>= check_vars
  in
  field "enabled_if" ~default:Blang.true_ decode
