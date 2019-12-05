open Core_kernel
include Timezone_intf
include Core_kernel_private.Time_zone

module type Extend_zone = Timezone_intf.Extend_zone

module Zone_cache = struct
  type z =
    { mutable full : bool
    ; basedir : string
    ; table : t String.Table.t
    }

  let the_one_and_only =
    { full = false
    ; basedir = Option.value (Sys.getenv_opt "TZDIR") ~default:"/usr/share/zoneinfo/"
    ; table = String.Table.create ()
    }
  ;;

  let find zone = Hashtbl.find the_one_and_only.table zone

  let find_or_load zonename =
    match find zonename with
    | Some z -> Some z
    | None ->
      if the_one_and_only.full
      then None
      else (
        try
          let filename = the_one_and_only.basedir ^ "/" ^ zonename in
          let zone = input_tz_file ~zonename ~filename in
          Hashtbl.set the_one_and_only.table ~key:zonename ~data:zone;
          Some zone
        with
        | _ -> None)
  ;;

  let traverse basedir ~f =
    let skip_prefixes = [ "Etc/GMT"; "right/"; "posix/" ] in
    let maxdepth = 10 in
    let basedir_len = String.length basedir + 1 in
    let rec dfs dir depth =
      if depth < 1
      then ()
      else
        Array.iter (Sys.readdir dir) ~f:(fun fn ->
          let fn = dir ^ "/" ^ fn in
          let relative_fn = String.drop_prefix fn basedir_len in
          match Sys.is_directory fn with
          | true ->
            if not
                 (List.exists skip_prefixes ~f:(fun prefix ->
                    String.is_prefix ~prefix relative_fn))
            then dfs fn (depth - 1)
          | false -> f relative_fn)
    in
    dfs basedir maxdepth
  ;;

  let init () =
    if not the_one_and_only.full
    then (
      traverse the_one_and_only.basedir ~f:(fun zone_name ->
        ignore (find_or_load zone_name : t option));
      the_one_and_only.full <- true)
  ;;

  let to_alist () = Hashtbl.to_alist the_one_and_only.table

  let initialized_zones t =
    List.sort ~compare:(fun a b -> String.ascending (fst a) (fst b)) (to_alist t)
  ;;

  let find_or_load_matching t1 =
    let file_size filename =
      let c = Stdio.In_channel.create filename in
      let l = Stdio.In_channel.length c in
      Stdio.In_channel.close c;
      l
    in
    let t1_file_size = Option.map (original_filename t1) ~f:file_size in
    with_return (fun r ->
      let return_if_matches zone_name =
        let filename =
          String.concat ~sep:"/" [ the_one_and_only.basedir; zone_name ]
        in
        let matches =
          try
            [%compare.equal: int64 option] t1_file_size (Some (file_size filename))
            && [%compare.equal: Md5.t option]
                 (digest t1)
                 Option.(join (map (find_or_load zone_name) ~f:digest))
          with
          | _ -> false
        in
        if matches then r.return (find_or_load zone_name) else ()
      in
      List.iter !likely_machine_zones ~f:return_if_matches;
      traverse the_one_and_only.basedir ~f:return_if_matches;
      None)
  ;;
end

let init = Zone_cache.init
let initialized_zones = Zone_cache.initialized_zones

let find zone =
  let zone =
    (* Some aliases for convenience *)
    match zone with
    (* case insensitivity *)
    | "utc" -> "UTC"
    | "gmt" -> "GMT"
    (* some aliases for common zones *)
    | "chi" -> "America/Chicago"
    | "nyc" -> "America/New_York"
    | "hkg" -> "Asia/Hong_Kong"
    | "lon" | "ldn" -> "Europe/London"
    | "tyo" -> "Asia/Tokyo"
    (* catchall *)
    | _ -> zone
  in
  Zone_cache.find_or_load zone
;;

let find_exn zone =
  match find zone with
  | None -> Error.raise_s [%message "unknown zone" (zone : string)]
  | Some z -> z
;;

let local =
  (* Load [TZ] immediately so that subsequent modifications to the environment cannot
     alter the result of [force local]. *)
  let local_zone_name = Sys.getenv_opt "TZ" in
  let load () =
    match local_zone_name with
    | Some zone_name -> find_exn zone_name
    | None ->
      let localtime_t =
        input_tz_file ~zonename:"/etc/localtime" ~filename:"/etc/localtime"
      in
      (* Load the matching zone file from the real zone cache so that we can serialize it
         properly. The file loaded from /etc/localtime won't have a name we can use on the
         other side to find the right zone. *)
      (match Zone_cache.find_or_load_matching localtime_t with
       | Some t -> t
       | None -> localtime_t)
  in
  Lazy.from_fun load
;;

module Stable = struct
  include Core_kernel_private.Time_zone.Stable

  module V1 = struct
    type nonrec t = t

    let t_of_sexp sexp =
      match sexp with
      | Sexp.Atom "Local" -> Lazy.force local
      | Sexp.Atom name ->
        ((* This special handling is needed because the offset directionality of the
            zone files in /usr/share/zoneinfo for GMT<offset> files is the reverse of
            what is generally expected.  That is, GMT+5 is what most people would call
            GMT-5. *)
          try
            if String.is_prefix name ~prefix:"GMT-"
            || String.is_prefix name ~prefix:"GMT+"
            || String.is_prefix name ~prefix:"UTC-"
            || String.is_prefix name ~prefix:"UTC+"
            || String.equal name "GMT"
            || String.equal name "UTC"
            then (
              let offset =
                if String.equal name "GMT" || String.equal name "UTC"
                then 0
                else (
                  let base =
                    Int.of_string (String.sub name ~pos:4 ~len:(String.length name - 4))
                  in
                  match name.[3] with
                  | '-' -> -1 * base
                  | '+' -> base
                  | _ -> assert false)
              in
              of_utc_offset ~hours:offset)
            else find_exn name
          with
          | exc ->
            of_sexp_error (sprintf "Timezone.t_of_sexp: %s" (Exn.to_string exc)) sexp)
      | _ -> of_sexp_error "Timezone.t_of_sexp: expected atom" sexp
    ;;

    let sexp_of_t t =
      let name = name t in
      if String.equal name "/etc/localtime"
      then failwith "the local time zone cannot be serialized";
      Sexp.Atom name
    ;;

    include Sexpable.Stable.To_stringable.V1 (struct
        type nonrec t = t [@@deriving sexp]
      end)

    (* The correctness of these relies on not exposing raw loading/creation functions to
       the outside world that would allow the construction of two Zone's with the same
       name and different transitions. *)
    let compare t1 t2 = String.compare (to_string t1) (to_string t2)
    let hash_fold_t state t = String.hash_fold_t state (to_string t)
    let hash = Ppx_hash_lib.Std.Hash.of_fold hash_fold_t

    include (
      Binable.Stable.Of_binable.V1 [@alert "-legacy"]
        (String)
        (struct
          type nonrec t = t

          let to_binable t =
            let name = name t in
            if String.equal name "/etc/localtime"
            then failwith "the local time zone cannot be serialized";
            name
          ;;

          let of_binable s = t_of_sexp (Sexp.Atom s)
        end) :
        Binable.S with type t := t)
  end
end

include Identifiable.Make (struct
    let module_name = "Timezone"

    include Stable.V1

    let of_string = of_string
    let to_string = to_string
  end)

module Private = struct
  module Zone_cache = Zone_cache
end
