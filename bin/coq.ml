open Import

let doc =
  "Command group related to Coq."

let sub_commands_synopsis =
  Common.command_synopsis
    [ "coq top FILE -- ARGS"
    ]

let man =
  [ `Blocks sub_commands_synopsis
  ]

let info = Term.info ~doc ~man "coq"

let group =
  ( Term.Group.Group
      [ in_group Coqtop.command
      ]
  , info )
