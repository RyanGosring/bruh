open Import
open Dune_lang.Decoder

module Ext = struct
  type t = string

  let exe = ".bc.js"
  let wasm_exe = ".bc.wasm.js"
  let wasm = ".bc.wasm"
  let cmo = ".cmo.js"
  let cma = ".cma.js"
  let runtime = ".bc.runtime.js"
end

let field_oslu name = Ordered_set_lang.Unexpanded.field name

module Flags = struct
  type 'flags t =
    { build_runtime : 'flags
    ; compile : 'flags
    ; link : 'flags
    }

  module Spec = struct
    type nonrec t = Ordered_set_lang.Unexpanded.t t
  end

  let build_runtime t = t.build_runtime
  let compile t = t.compile
  let link t = t.link

  let decode =
    let+ build_runtime = field_oslu "build_runtime_flags"
    and+ compile = field_oslu "flags"
    and+ link = field_oslu "link_flags" in
    { build_runtime; compile; link }
  ;;

  let empty = { build_runtime = []; compile = []; link = [] }

  let default ~profile =
    if Profile.is_dev profile
    then
      { build_runtime = [ "--pretty"; "--source-map-inline" ]
      ; compile = [ "--pretty"; "--source-map-inline" ]
      ; link = [ "--source-map-inline" ]
      }
    else empty
  ;;

  let map ~f { build_runtime; compile; link } =
    { build_runtime = f build_runtime; compile = f compile; link = f link }
  ;;

  let standard =
    { build_runtime = Ordered_set_lang.Unexpanded.standard
    ; compile = Ordered_set_lang.Unexpanded.standard
    ; link = Ordered_set_lang.Unexpanded.standard
    }
  ;;

  let equal eq { build_runtime; compile; link } x =
    eq build_runtime x.build_runtime && eq compile x.compile && eq link x.link
  ;;

  let make ~spec ~default ~eval =
    let module Proj = struct
      type proj = { proj : 'a. 'a t -> 'a }
    end
    in
    let f { Proj.proj } = eval (proj spec) ~standard:(proj default) in
    let build_runtime = f { proj = build_runtime }
    and compile = f { proj = compile }
    and link = f { proj = link } in
    { build_runtime; compile; link }
  ;;

  let dump t =
    let open Action_builder.O in
    let+ build_runtime = t.build_runtime
    and+ compile = t.compile
    and+ link = t.link in
    List.map
      ~f:Dune_lang.Encoder.(pair string (list string))
      [ "js_of_ocaml_flags", compile
      ; "js_of_ocaml_build_runtime_flags", build_runtime
      ; "js_of_ocaml_link_flags", link
      ]
  ;;
end

module In_buildable = struct
  type t =
    { flags : Ordered_set_lang.Unexpanded.t Flags.t
    ; javascript_files : string list
    ; wasm_files : string list
    }

  let decode =
    let* syntax_version = Dune_lang.Syntax.get_exn Stanza.syntax in
    if syntax_version < (3, 0)
    then
      fields
        (let+ flags = Ordered_set_lang.Unexpanded.field "flags"
         and+ javascript_files = field "javascript_files" (repeat string) ~default:[] in
         { flags =
             { build_runtime = Ordered_set_lang.Unexpanded.standard
             ; compile = flags
             ; link = flags (* we set link as well to preserve the old semantic *)
             }
         ; javascript_files
         ; wasm_files = []
         })
    else
      fields
        (let+ flags = Flags.decode
         and+ javascript_files = field "javascript_files" (repeat string) ~default:[]
         and+ wasm_files =
           field
             "wasm_files"
             (Dune_lang.Syntax.since Stanza.syntax (3, 11) >>> repeat string)
             ~default:[]
         in
         { flags; javascript_files; wasm_files })
  ;;

  let default = { flags = Flags.standard; javascript_files = []; wasm_files = [] }
end

module In_context = struct
  type t =
    { flags : Ordered_set_lang.Unexpanded.t Flags.t
    ; javascript_files : Path.Build.t list
    ; wasm_files : Path.Build.t list
    }

  let make ~(dir : Path.Build.t) (x : In_buildable.t) =
    { flags = x.flags
    ; javascript_files =
        List.map ~f:(fun name -> Path.Build.relative dir name) x.javascript_files
    ; wasm_files = List.map ~f:(fun name -> Path.Build.relative dir name) x.wasm_files
    }
  ;;

  let default = { flags = Flags.standard; javascript_files = []; wasm_files = [] }
end

module Compilation_mode = struct
  type t =
    | Whole_program
    | Separate_compilation

  let decode = enum [ "whole_program", Whole_program; "separate", Separate_compilation ]

  let equal x y =
    match x, y with
    | Separate_compilation, Separate_compilation -> true
    | Whole_program, Whole_program -> true
    | Separate_compilation, _ -> false
    | Whole_program, _ -> false
  ;;
end

module Target = struct
  type t =
    | JS
    | Wasm

  module Set = struct
    type t =
      { js : bool
      ; wasm : bool
      }

    let decode =
      map
        (repeat1 (enum [ "js", JS; "wasm", Wasm ]))
        ~f:(fun l ->
          List.fold_left
            ~f:(fun t target ->
              match target with
              | JS -> { t with js = true }
              | Wasm -> { t with wasm = true })
            ~init:{ js = false; wasm = false }
            l)
    ;;

    let equal x y = x.js = y.js && x.wasm = y.wasm

    let to_list x =
      let l = if x.wasm then [ Wasm ] else [] in
      if x.js then JS :: l else l
    ;;
  end
end

module Env = struct
  type 'a t =
    { compilation_mode : Compilation_mode.t option
    ; targets : Target.Set.t option
    ; runtest_alias : Alias.Name.t option
    ; flags : 'a Flags.t
    }

  let decode =
    fields
    @@ let+ compilation_mode = field_o "compilation_mode" Compilation_mode.decode
       and+ targets =
         field_o
           "targets"
           (Dune_lang.Syntax.since Stanza.syntax (3, 11) >>> Target.Set.decode)
       and+ runtest_alias = field_o "runtest_alias" Dune_lang.Alias.decode
       and+ flags = Flags.decode in
       Option.iter ~f:Alias.register_as_standard runtest_alias;
       { compilation_mode; targets; runtest_alias; flags }
  ;;

  let equal { compilation_mode; targets; runtest_alias; flags } t =
    Option.equal Compilation_mode.equal compilation_mode t.compilation_mode
    && Option.equal Target.Set.equal targets t.targets
    && Option.equal Alias.Name.equal runtest_alias t.runtest_alias
    && Flags.equal Ordered_set_lang.Unexpanded.equal flags t.flags
  ;;

  let map ~f { compilation_mode; targets; runtest_alias; flags } =
    { compilation_mode; targets; runtest_alias; flags = Flags.map ~f flags }
  ;;

  let empty =
    { compilation_mode = None
    ; targets = None
    ; runtest_alias = None
    ; flags = Flags.standard
    }
  ;;

  let default ~profile =
    { compilation_mode = None
    ; targets = None
    ; runtest_alias = None
    ; flags = Flags.default ~profile
    }
  ;;
end
