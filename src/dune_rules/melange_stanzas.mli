open Import

(** Stanza to produce JavaScript targets from Melange libraries *)
module Emit : sig
  type t =
    { loc : Loc.t
    ; target : string
    ; module_system : Melange.Module_system.t
    ; entries : Ordered_set_lang.t
    ; libraries : Lib_dep.t list
    ; package : Package.t option
    ; preprocess : Preprocess.With_instrumentation.t Preprocess.Per_module.t
    ; preprocessor_deps : Dep_conf.t list
    ; flags : Ocaml_flags.Spec.t
    }

  val decode : t Dune_lang.Decoder.t
end
