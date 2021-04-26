module Annot = struct
  type t = ..
end

exception E of User_message.t * Annot.t option

let prefix =
  Pp.seq (Pp.tag User_message.Style.Error (Pp.verbatim "Error")) (Pp.char ':')

let make ?loc ?hints paragraphs =
  User_message.make ?loc ?hints paragraphs ~prefix

let raise ?loc ?hints ?annot paragraphs =
  raise (E (make ?loc ?hints paragraphs, annot))

let () =
  Printexc.register_printer (function
    | E (t, _) -> Some (Format.asprintf "%a@?" Pp.to_fmt (User_message.pp t))
    | _ -> None)
