open! Stdune
open Import

type t =
  | Disabled
  | Enabled

val to_dyn : t -> Dyn.t

val field :
  since:Dune_lang.Syntax.Version.t -> t option Dune_lang.Decoder.fields_parser

val of_config : t option -> t
