module Fetch = Fetch
module Checksum = Checksum
module Source = Source
module Lock_dir = Lock_dir
module Opam_file = Opam_file
module Opam_repo = Opam_repo
module Opam_solver = Opam_solver
module OpamUrl = OpamUrl0
module Package_variable = Package_variable
module Package_dependency = Package_dependency
module Rev_store = Rev_store
module Solver_env = Solver_env
module Solver_stats = Solver_stats
module Substs = Substs
module Sys_poll = Sys_poll
module Version_preference = Version_preference
module Package_version = Package_version
module Pkg_workspace = Workspace
module Local_package = Local_package
module Package_universe = Package_universe
module Variable_value = Variable_value
module Resolved_package = Resolved_package

module Private = struct
  (* only exposed for tests *)
  module Git_config_parser = Git_config_parser
end
