(** A type of values with an associative operation and an identity element, for
    example, integers with addition and zero. *)
module type Basic = sig
  type t

  (** Must be the identity of [combine]:

      - combine empty t = t
      - combine t empty = t *)
  val empty : t

  (** Must be associative:

      - combine a (combine b c) = combine (combine a b) c *)
  val combine : t -> t -> t
end

(** This module type extends the basic definition of a monoid by adding a
    convenient operator synonym [( @ ) = combine], as well as derived functions
    [reduce], [map_reduce] and [times]. *)
module type Monoid = sig
  include Basic

  module O : sig
    (** An operator alias for [combine]. *)
    val ( @ ) : t -> t -> t
  end

  val reduce : t list -> t

  val map_reduce : f:('a -> t) -> 'a list -> t

  (** Combine a given value with itself [n] times, assuming [n >= 0]. This is a
      generalisation of multiplication and exponentiation.

      - times t ~n:0 = empty
      - times t ~n:1 = t
      - times t ~n   = times t ~n:(n-1) @ t

      Complexity: O(log n). *)
  val times : t -> n:int -> t
end
