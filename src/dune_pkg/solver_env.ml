open Import

module Variable = struct
  module Flag = struct
    module T = struct
      type t =
        [ `With_test
        | `With_doc
        ]

      let to_string = function
        | `With_test -> "with-test"
        | `With_doc -> "with-doc"
      ;;

      let compare a b = String.compare (to_string a) (to_string b)
      let equal a b = Ordering.is_eq (compare a b)
      let to_dyn t = Dyn.variant (to_string t) []
      let all = [ `With_test; `With_doc ]
    end

    include T

    let of_string_opt s = List.find all ~f:(fun t -> String.equal s (to_string t))

    module Set = struct
      include Set.Of_map (T) (Map.Make (T))

      let all : t = of_list all

      let of_ordered_set ordered_set =
        Dune_lang.Ordered_set_lang.eval
          ordered_set
          ~parse:(fun ~loc string ->
            match of_string_opt string with
            | Some flag -> flag
            | None ->
              User_error.raise
                ~loc
                [ Pp.textf "No such flag: %s" (String.maybe_quoted string)
                ; Pp.textf
                    "Valid flags: %s"
                    (String.enumerate_and
                       (List.map T.all ~f:(fun v -> String.maybe_quoted @@ to_string v)))
                ])
          ~eq:T.equal
          ~standard:T.all
        |> of_list
      ;;

      let decode =
        let open Decoder in
        let+ ordered_set = Dune_lang.Ordered_set_lang.decode in
        of_ordered_set ordered_set
      ;;

      let encode t =
        Dune_sexp.List
          (to_list t
           |> List.map ~f:(fun flag ->
             (* Note that flags are quoted to make the output a valid Ordered
                Set Language expression so that [encode] and [decode] can round
                trip. Technically only the first flag needs to be quoted to
                form a valid OSL expression but all are quoted for
                consistency.*)
             Dune_sexp.Quoted_string (to_string flag)))
      ;;

      let pp t =
        to_list all
        |> Pp.enumerate ~f:(fun flag -> Pp.textf "%s = %b" (to_string flag) (mem t flag))
      ;;
    end
  end

  module Sys = struct
    module T = struct
      type t =
        [ `Arch
        | `Os
        | `Os_version
        | `Os_distribution
        | `Os_family
        ]

      let to_string = function
        | `Arch -> "arch"
        | `Os -> "os"
        | `Os_version -> "os-version"
        | `Os_distribution -> "os-distribution"
        | `Os_family -> "os-family"
      ;;

      let compare a b = String.compare (to_string a) (to_string b)
      let to_dyn t = Dyn.string (to_string t)
      let all = [ `Arch; `Os; `Os_version; `Os_distribution; `Os_family ]
    end

    include T

    let of_string_opt s = List.find all ~f:(fun t -> String.equal s (to_string t))

    let decode =
      let open Decoder in
      let+ loc, name = located string in
      match of_string_opt name with
      | Some t -> t
      | None ->
        User_error.raise
          ~loc
          [ Pp.textf "No such sys variable: %s" (String.maybe_quoted name)
          ; Pp.textf
              "Valid variables: %s"
              (String.enumerate_and
                 (List.map T.all ~f:(fun v -> String.maybe_quoted @@ to_string v)))
          ]
    ;;

    module Map = Map.Make (T)

    module Bindings = struct
      type t = string Map.t

      let empty = Map.empty
      let to_dyn = Map.to_dyn Dyn.string
      let equal = Map.equal ~equal:String.equal
      let set = Map.set
      let get = Map.find

      let decode =
        let open Decoder in
        let+ loc, bindings = located (repeat (pair decode string)) in
        match Map.of_list bindings with
        | Ok t -> t
        | Error (duplicate_key, a, b) ->
          User_error.raise
            ~loc
            [ Pp.textf
                "Duplicate entries for sys variable %s (%s, %s)"
                (String.maybe_quoted (to_string duplicate_key))
                (String.maybe_quoted a)
                (String.maybe_quoted b)
            ]
      ;;

      let encode t =
        let open Encoder in
        Map.to_list_map t ~f:(fun key value ->
          Dune_sexp.List [ to_string key |> string; string value ])
      ;;

      let extend t t' = Map.superpose t' t

      let pp t =
        Pp.enumerate all ~f:(fun variable ->
          match Map.find t variable with
          | Some value ->
            Pp.textf "%s = %s" (to_string variable) (String.maybe_quoted value)
          | None -> Pp.textf "%s (unset)" (to_string variable))
      ;;
    end
  end

  module Const = struct
    type t = [ `Opam_version ]

    let to_string = function
      | `Opam_version -> "opam-version"
    ;;

    let all = [ `Opam_version ]
    let of_string_opt s = List.find all ~f:(fun t -> String.equal s (to_string t))

    module Fields = struct
      let opam_version = "opam_version"
    end

    module Values = struct
      let opam_version = OpamVersion.to_string OpamVersion.current
    end

    module Bindings = struct
      type t = { opam_version : string }

      let to_dyn { opam_version } =
        Dyn.(record [ Fields.opam_version, string opam_version ])
      ;;

      let equal { opam_version } t = String.equal opam_version t.opam_version

      let get { opam_version } = function
        | `Opam_version -> opam_version
      ;;

      let pp { opam_version } =
        Pp.enumerate
          [ `Opam_version, opam_version ]
          ~f:(fun (variable, value) -> Pp.textf "%s = %s" (to_string variable) value)
      ;;

      let value =
        let open Values in
        { opam_version }
      ;;

      (* Tests that each field matches the constant value for that field. This
         is included so that [encode] and [decode] can round trip. *)
      let decode =
        let open Decoder in
        let+ loc, opam_version =
          fields
          @@ located
          @@ field Fields.opam_version ~default:Values.opam_version string
        in
        (* Make sure that the value we parsed is the constant value for this
           field. Otherwise it's an error. This prevents unexpected constant
           values from being set due to users manually changing the encoded
           solver environment and then decoding it. *)
        if not (String.equal opam_version Values.opam_version)
        then
          User_error.raise
            ~loc
            [ Pp.textf
                "Field %S must have value %S (found %S)"
                Fields.opam_version
                Values.opam_version
                opam_version
            ];
        value
      ;;

      let encode { opam_version } =
        let open Encoder in
        [ Dune_sexp.List [ string Fields.opam_version; string opam_version ] ]
      ;;
    end
  end

  type t =
    | Flag of Flag.t
    | Sys of Sys.t
    | Const of Const.t

  let of_string_opt string =
    match Flag.of_string_opt string with
    | Some flag -> Some (Flag flag)
    | None ->
      (match Sys.of_string_opt string with
       | Some sys -> Some (Sys sys)
       | None -> Const.of_string_opt string |> Option.map ~f:(fun const -> Const const))
  ;;
end

type t =
  { flags : Variable.Flag.Set.t
  ; sys : Variable.Sys.Bindings.t
  ; const : Variable.Const.Bindings.t
  ; repos : Workspace.Repository.Name.t list
  }

module Fields = struct
  let flags = "flags"
  let sys = "sys"
  let const = "const"
  let repos = "repositories"
end

let default =
  { flags = Variable.Flag.Set.all
  ; sys = Variable.Sys.Bindings.empty
  ; const = Variable.Const.Bindings.value
  ; repos = [ Workspace.Repository.Name.of_string "default" ]
  }
;;

let repos_of_ordered_set ordered_set =
  Dune_lang.Ordered_set_lang.eval
    ordered_set
    ~parse:(fun ~loc string -> Workspace.Repository.Name.parse_string_exn (loc, string))
    ~eq:Workspace.Repository.Name.equal
    ~standard:default.repos
;;

let decode =
  let open Decoder in
  fields
  @@ let+ flags = field Fields.flags ~default:default.flags Variable.Flag.Set.decode
     and+ sys = field Fields.sys ~default:default.sys Variable.Sys.Bindings.decode
     and+ repos = Dune_lang.Ordered_set_lang.field Fields.repos
     and+ const =
       field Fields.const ~default:default.const Variable.Const.Bindings.decode
     in
     let repos = repos_of_ordered_set repos in
     { flags; sys; const; repos }
;;

let encode { flags; sys; const; repos } =
  let open Encoder in
  [ [ string Fields.flags; Variable.Flag.Set.encode flags ]
  ; string Fields.sys :: Variable.Sys.Bindings.encode sys
  ; string Fields.const :: Variable.Const.Bindings.encode const
  ; string Fields.repos :: List.map repos ~f:Workspace.Repository.Name.encode
  ]
  |> List.map ~f:(fun x -> Dune_sexp.List x)
;;

let to_dyn { flags; sys; const; repos } =
  Dyn.record
    [ Fields.flags, Variable.Flag.Set.to_dyn flags
    ; Fields.sys, Variable.Sys.Bindings.to_dyn sys
    ; Fields.const, Variable.Const.Bindings.to_dyn const
    ; Fields.repos, Dyn.list Workspace.Repository.Name.to_dyn repos
    ]
;;

let equal { flags; sys; const; repos } t =
  Variable.Flag.Set.equal flags t.flags
  && Variable.Sys.Bindings.equal sys t.sys
  && Variable.Const.Bindings.equal const t.const
  && List.equal Workspace.Repository.Name.equal repos t.repos
;;

let sys { sys; _ } = sys
let set_sys t sys = { t with sys }
let clear_flags t = { t with flags = Variable.Flag.Set.empty }
let repos { repos; _ } = repos

let pp =
  let pp_section heading pp_section =
    (* The hbox is to prevent long values in [pp_section] from causing the heading to wrap. *)
    let pp_heading = Pp.hbox (Pp.text heading) in
    Pp.concat ~sep:Pp.newline [ pp_heading; pp_section ]
  in
  fun { flags; sys; const; repos } ->
    Pp.enumerate
      ~f:Fun.id
      [ pp_section "Flags" (Variable.Flag.Set.pp flags)
      ; pp_section "System Environment Variables" (Variable.Sys.Bindings.pp sys)
      ; pp_section "Constants" (Variable.Const.Bindings.pp const)
      ; pp_section
          "Repositories"
          (Pp.chain repos ~f:(fun r -> Workspace.Repository.Name.pp r))
      ]
;;

module Variable_value = struct
  type t =
    | Bool of bool
    | String of string
    | Unset_sys
end

let get t variable =
  match (variable : Variable.t) with
  | Flag flag -> Variable_value.Bool (Variable.Flag.Set.mem t.flags flag)
  | Const const -> String (Variable.Const.Bindings.get t.const const)
  | Sys sys ->
    (match Variable.Sys.Bindings.get t.sys sys with
     | Some value -> String value
     | None -> Unset_sys)
;;
