open Import
open Fiber.O

type t =
  { bindings: string String_map.t
  ; ocamlc: Path.t
  }

let bindings t = t.bindings

let ocamlc_config_cmd ocamlc =
  sprintf "%s -config" (Path.to_string ocamlc)

let sexp_of_t t =
  let open Sexp.To_sexp in
  string_map Sexp.atom_or_quoted_string t.bindings

let make ~ocamlc ~ocamlc_config_output:lines =
  List.map lines ~f:(fun line ->
    match String.index line ':' with
    | Some i ->
      (String.sub line ~pos:0 ~len:i,
       String.sub line ~pos:(i + 2) ~len:(String.length line - i - 2))
    | None ->
      die "unrecognized line in the output of `%s`: %s"
        (ocamlc_config_cmd ocamlc) line)
  |> String_map.of_list
  |> function
  | Ok bindings -> { bindings ; ocamlc }
  | Error (key, _, _) ->
    die "variable %S present twice in the output of `%s`"
      key (ocamlc_config_cmd ocamlc)

let read ~ocamlc ~env =
  Process.run_capture_lines ~env Strict (Path.to_string ocamlc) ["-config"]
  >>| fun lines ->
  make ~ocamlc ~ocamlc_config_output:lines

let ocaml_value t =
  let t = String_map.to_list t.bindings in
  let longest = String.longest_map t ~f:fst in
  List.map t ~f:(fun (k, v) -> sprintf "%-*S , %S" (longest + 2) k v)
  |> String.concat ~sep:"\n      ; "

let get_opt t var = String_map.find t.bindings var

let not_found t var =
  die "variable %S not found in the output of `%s`" var
    (ocamlc_config_cmd t.ocamlc)

let get t ?default ~parse var =
  match get_opt t var with
  | Some s -> parse s
  | None ->
    match default with
    | Some x -> x
    | None -> not_found t var

let get_bool ?default t var =
  match get_opt t var with
  | None -> begin
      match default with
      | Some x -> x
      | None -> not_found t var
    end
  | Some s ->
    match s with
    | "true"  -> true
    | "false" -> false
    | _ ->
      die
        "variable %S is neither 'true' neither 'false' in the output of `%s`"
        var (ocamlc_config_cmd t.ocamlc)

let get_strings t var =
  match get_opt t var with
  | None -> []
  | Some s -> String.extract_blank_separated_words s

let get_path t var = Path.absolute (get t var)

let stdlib_dir t = get_path t "standard_library"

let natdynlink_supported t =
  Path.exists (Path.relative (stdlib_dir t) "dynlink.cmxa")

let version_string t = get t "version"

let version t = Scanf.sscanf (version_string t) "%u.%u.%u" (fun a b c -> a, b, c)

let word_size t = get_opt t "word_size"

let split_prog s =
  match String.extract_blank_separated_words s with
  | []           -> (""  , []  )
  | prog :: args -> (prog, args)

type c_compiler_settings =
  { c_compiler      : string
  ; ocamlc_cflags   : string list
  ; ocamlopt_cflags : string list
  }

let c_compiler_settings t =
  match get_opt t "c_compiler" with
  | Some c_compiler -> (* >= 4.06 *)
    let c_compiler, args = split_prog c_compiler in
    { c_compiler
    ; ocamlc_cflags   = args @ get_strings t "ocamlc_cflags"
    ; ocamlopt_cflags = args @ get_strings t "ocamlopt_cflags"
    }
  | None ->
    let c_compiler, ocamlc_cflags =
      split_prog (get t "bytecomp_c_compiler")
    in
    let _, ocamlopt_cflags =
      split_prog (get t "native_c_compiler")
    in
    { c_compiler
    ; ocamlc_cflags
    ; ocamlopt_cflags
    }

let flambda t = get_bool t "flambda" ~default:false
