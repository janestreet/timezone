Timezone for OCaml
===================================

Timezone handles parsing timezone data and create [Timezone.t] that
can later be used to manipulate time in
[core](https://github.com/janestreet/core) (using [Time] and [Time_ns]
modules).

Timezone is currently only able to read the Timezone Database
provided by [IANA](https://www.iana.org/time-zones). It should work
out of the box on Linux and macOS.

## Where are the timezone data located ?

The location of the timezone files can be set using the environment
variable `TZDIR`. If not set, [Timezone] will fallback to
`/usr/share/zoneinfo/`.

## What is the local timezone ?

The local timezone can be set using the environment variable `TZ`. If
not set, [Timezone] will fallback to `/etc/localtime`.
In a JavaScript context, we automatically set the environment variable
`TZ` to `Intl.DateTimeFormat().resolvedOptions().timeZone`.

## Compatibility with JavaScript.

The [Timezone] library can be used when constructing JavaScript applications with
[Js_of_ocaml](https://github.com/ocsigen/js_of_ocaml/).

In the past, web browsers needed to be provided with a copy of the timezone database, but
this is no longer required.

------

Please report bugs and feature requests on
[GitHub](https://github.com/janestreet/timezone).

You can find all of Jane Street's open-source libraries on
[GitHub](https://github.com/janestreet).

Documentation can be found
[here](https://ocaml.janestreet.com/ocaml-core/latest/doc/timezone/index.html).
