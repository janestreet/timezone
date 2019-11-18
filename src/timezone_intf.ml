open Core_kernel

module type Extend_zone = sig
  type t

  include Identifiable.S with type t := t

  (** [find name] looks up a [t] by its name and returns it.  This also accepts some
      aliases, including:

      - chi -> America/Chicago
      - nyc -> America/New_York
      - hkg -> Asia/Hong_Kong
      - lon -> Europe/London
      - tyo -> Asia/Tokyo *)
  val find : string -> t option

  val find_exn : string -> t

  (** [local] is the machine's local timezone, as determined from the [TZ]
      environment variable or the [/etc/localtime] file.  It is computed from
      the state of the process environment and on-disk tzdata database at
      some unspecified moment prior to its first use, so its value may be
      unpredictable if that state changes during program operation. Arguably,
      changing the timezone of a running program is a problematic operation
      anyway -- most people write code assuming the clock doesn't suddenly
      jump several hours without warning.

      Note that any function using this timezone can throw an exception if
      the [TZ] environment variable is misconfigured or if the appropriate
      timezone files can't be found because of the way the box is configured.
      We don't sprinkle [_exn] all over all the names in this module because
      such misconfiguration is quite rare. *)
  val local : t Lazy.t

  (** [initialized_zones ()] returns a sorted list of time zone names that have
      been loaded from disk thus far. *)
  val initialized_zones : unit -> (string * t) list

  (** {3 Low-level functions}

      The functions below are lower level and should be used more rarely. *)

  (** [init ()] pre-load all available time zones from disk, this function has no effect if
      it is called multiple times.  Time zones will otherwise be loaded at need from the
      disk on the first call to find/find_exn. *)
  val init : unit -> unit
end

module type Timezone = sig
  module type Extend_zone = Extend_zone

  include Core_kernel_private.Time_zone.S with type t = Time.Zone.t
  include Extend_zone with type t := t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, compare, hash, sexp]
    end

    include Core_kernel_private.Time_zone.S_stable with type t := t
  end

  (**/**)

  (*_ See the Jane Street Style Guide for an explanation of [Private] submodules:

    https://opensource.janestreet.com/standards/#private-submodules *)
  module Private : sig
    module Zone_cache : sig
      type z =
        { mutable full : bool
        ; basedir : string
        ; table : Time.Zone.t String.Table.t
        }

      val the_one_and_only : z
      val init : unit -> unit
      val find : string -> t option
    end
  end
end
