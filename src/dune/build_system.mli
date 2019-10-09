(** Build rules *)

open! Stdune
open! Import

(** {1 Setup} *)

(** {2 Creation} *)

type caching =
  | Disabled
  | Enabled of Dune_manager.Client.t
  | Check of Dune_manager.Client.t

(** Initializes the build system. This must be called first. *)
val init :
     contexts:Context.t list
  -> ?caching:caching
  -> sandboxing_preference:Sandbox_mode.t list
  -> unit

val reset : unit -> unit

module Subdir_set : sig
  type t =
    | All
    | These of String.Set.t

  val empty : t

  val union : t -> t -> t

  val union_all : t list -> t

  val mem : t -> string -> bool
end

type extra_sub_directories_to_keep = Subdir_set.t

module Context_or_install : sig
  type t =
    | Install of string
    | Context of string

  val to_dyn : t -> Dyn.t
end

(** Set the rule generators callback. There must be one callback per build
    context name.

    Each callback is used to generate the rules for a given directory in the
    corresponding build context. It receives the directory for which to
    generate the rules and the split part of the path after the build context.
    It must return an additional list of sub-directories to keep. This is in
    addition to the ones that are present in the source tree and the ones that
    already contain rules.

    It is expected that [f] only generate rules whose targets are descendant of
    [dir].

    [init] can generate rules in any directory, so it's always called. *)
val set_rule_generators :
     init:(unit -> unit)
  -> gen_rules:
       (   Context_or_install.t
        -> (dir:Path.Build.t -> string list -> extra_sub_directories_to_keep)
           option)
  -> unit

(** All other functions in this section must be called inside the rule
    generator callback. *)

(** {2 Primitive for rule generations} *)

(** [prefix_rules t prefix ~f] Runs [f] and adds [prefix] as a dependency to
    all the rules generated by [f] *)
val prefix_rules : unit Build.t -> f:(unit -> 'a) -> 'a

(** [eval_pred t [glob]] returns the list of files in [File_selector.dir glob]
    that matches [File_selector.predicate glob]. The list of files includes the
    list of targets. *)
val eval_pred : File_selector.t -> Path.Set.t

(** Returns the set of targets in the given directory. *)
val targets_of : dir:Path.t -> Path.Set.t

(** Load the rules for this directory. *)
val load_dir : dir:Path.t -> unit

(** Sets the package assignment *)
val set_packages : (Path.Build.t -> Package.Name.Set.t) -> unit

(** Assuming [files] is the list of files in [_build/install] that belong to
    package [pkg], [package_deps t pkg files] is the set of direct package
    dependencies of [package]. *)
val package_deps : Package.Name.t -> Path.Set.t -> Package.Name.Set.t Build.t

(** {2 Aliases} *)

module Alias : sig
  type t = Alias.t

  (** Alias for all the files in [_build/install] that belong to this package *)
  val package_install : context:Context.t -> pkg:Package.Name.t -> t

  (** [dep t = Build.path (stamp_file t)] *)
  val dep : t -> unit Build.t

  (** Implements [@@alias] on the command line *)
  val dep_multi_contexts :
    dir:Path.Source.t -> name:string -> contexts:string list -> unit Build.t

  (** Implements [(alias_rec ...)] in dependency specification *)
  val dep_rec : t -> loc:Loc.t -> unit Build.t

  (** Implements [@alias] on the command line *)
  val dep_rec_multi_contexts :
    dir:Path.Source.t -> name:string -> contexts:string list -> unit Build.t
end

(** {1 Building} *)

(** All the functions in this section must be called outside the rule generator
    callback. *)

(** Do the actual build *)
val do_build : request:'a Build.t -> 'a Fiber.t

(** {2 Other queries} *)

val is_target : Path.t -> bool

(** Return all the library dependencies (as written by the user) needed to
    build this request, by context name *)
val all_lib_deps :
     request:unit Build.t
  -> Lib_deps_info.t Path.Source.Map.t String.Map.t Fiber.t

(** List of all buildable targets *)
val all_targets : unit -> Path.Build.Set.t

(** Return the set of files that were created in the source tree and needs to
    be deleted *)
val files_in_source_tree_to_delete : unit -> Path.Set.t

(** {2 Build rules} *)

(** A fully built rule *)
module Rule : sig
  module Id : sig
    type t

    val to_int : t -> int

    val compare : t -> t -> Ordering.t
  end

  type t =
    { id : Id.t
    ; dir : Path.Build.t
    ; deps : Dep.Set.t
    ; targets : Path.Build.Set.t
    ; context : Context.t option
    ; action : Action.t
    }
end

(** Return the list of rules used to build the given targets. If [recursive] is
    [true], return all the rules needed to build the given targets and their
    transitive dependencies. *)
val evaluate_rules :
  recursive:bool -> request:unit Build.t -> Rule.t list Fiber.t

val get_memory : unit -> caching
