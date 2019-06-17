open Stdune

type t =
  { obj_dir : Path.Build.t Obj_dir.t
  ; modules : Module.t list
  ; top_sorted_modules : (unit, Module.t list) Build.t
  ; ext_obj : string
  }

let make_exe ~obj_dir ~modules ~top_sorted_modules ~ext_obj =
  let modules = Module.Name_map.impl_only modules in
  { obj_dir
  ; modules
  ; top_sorted_modules
  ; ext_obj
  }

let make_lib ~obj_dir ~modules ~top_sorted_modules ~ext_obj =
  { obj_dir
  ; modules
  ; top_sorted_modules
  ; ext_obj
  }

let unsorted_objects_and_cms t ~mode =
  let kind = Mode.cm_kind mode in
  let cm_files = Obj_dir.Module.L.cm_files t.obj_dir t.modules ~kind in
  match mode with
  | Byte -> cm_files
  | Native ->
    Obj_dir.Module.L.o_files t.obj_dir t.modules ~ext_obj:t.ext_obj
    |> List.rev_append cm_files

let top_sorted_cms t ~mode =
  let kind = Mode.cm_kind mode in
  let open Build.O in
  t.top_sorted_modules
  >>^ Obj_dir.Module.L.cm_files t.obj_dir ~kind
