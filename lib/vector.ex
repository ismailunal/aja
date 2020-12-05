defmodule A.Vector do
  @moduledoc """
  A Clojure-like persistent vector with efficient appends and random access.

  [Persistent vectors](https://hypirion.com/musings/understanding-persistent-vector-pt-1)
  are an efficient alternative to lists.
  Many operations for `A.Vector` run in effective constant time (length, random access, appends...),
  unlike linked lists for which most operations run in linear time.
  Functions that need to go through the whole collection like `map/2` or `foldl/3` are as often fast as
  their list equivalents, or sometimes even slightly faster.

  Vectors also use less memory than lists for "big" collections (see the [Memory usage section](#module-memory-usage)).

  Make sure to read the [Efficiency guide section](#module-efficiency-guide) to get the best performance
  out of vectors.

  Erlang's [`:array`](http://erlang.org/doc/man/array.html) module offer similar functionalities.
  However `A.Vector`:
  - is a better Elixir citizen: pipe-friendliness, `Access` behaviour, `Enum` / `Inspect` / `Collectable` protocols
  - should have higher performance in most use cases, especially "loops" like `map/2` / `to_list/1` / `foldl/3`
  - supports negative indexing (e.g. `-1` corresponds to the last element)
  - optionally implements the `Jason.Encoder` protocol if `Jason` is installed

  Note: most of the design is inspired by
  [this series of blog posts](https://hypirion.com/musings/understanding-persistent-vector-pt-1),
  but a branching factor of `16 = 2 ^ 4` has been picked instead of `32 = 2 ^ 5`.
  This choice was made following performance benchmarking that showed better overall performance
  for this particular implementation.

  ## Examples

      iex> vector = A.Vector.new(1..10)
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])>
      iex> A.Vector.append(vector, :foo)
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, :foo])>
      iex> vector[3]
      4
      iex> A.Vector.replace_at(vector, -1, :bar)
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8, 9, :bar])>
      iex> 3 in vector
      true

  ## Access behaviour

  `A.Vector` implements the `Access` behaviour.

      iex> vector = A.Vector.new(1..10)
      iex> vector[3]
      4
      iex> put_in(vector[5], :foo)
      #A<vec([1, 2, 3, 4, 5, :foo, 7, 8, 9, 10])>
      iex> {9, updated} = pop_in(vector[8]); updated
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8, 10])>

  ## Convenience [`vec/1`](`A.vec/1`) macro

  The `A.Vector` module can be used without any macro.
  The `A.vec/1` macro does however provide some syntactic sugar to make
  it more convenient to work with vectors of known size, namely:
  - construct new vectors of known size faster, by generating the AST at compile time
  - pattern match on elements for vectors of known size

  Examples:

      iex> import A
      iex> vec([1, 2, 3])
      #A<vec([1, 2, 3])>
      iex> vec([1, 2, var, _, _, _]) = A.Vector.new(1..6); var
      3

  ## Pattern-matching and opaque type

  An `A.Vector` is represented internally using the `%A.Vector{}` struct. This struct
  can be used whenever there's a need to pattern match on something being an `A.Vector`:
      iex> match?(%A.Vector{}, A.Vector.new())
      true

  Note, however, than `A.Vector` is an [opaque type](https://hexdocs.pm/elixir/typespecs.html#user-defined-types):
  its struct internal fields must not be accessed directly.

  As discussed in the previous section, [`vec/1`](`A.vec/1`) makes it
  possible to pattern match on size and elements as well as checking the type.

  ## Memory usage

  Vectors have a small overhead over lists for smaller collections, but are using
  far less memory for bigger collections:

      iex> memory_for = fn n -> [Enum.to_list(1..n), A.Vector.new(1..n)] |> Enum.map(&:erts_debug.size/1) end
      iex> memory_for.(1)
      [2, 28]
      iex> memory_for.(10)
      [20, 28]
      iex> memory_for.(100)
      [200, 150]
      iex> memory_for.(10_000)
      [20000, 11370]

  If you need to work with vectors containing mostly the same value,
  `A.Vector.duplicate/2` should be highly efficient both in time and
  memory, since it minimizes the number of actual copies and reuses the
  same nested structures under the hood:

      iex> A.Vector.duplicate(0, 1_000) |> :erts_debug.size()
      133
      iex> A.Vector.duplicate(0, 1_000) |> :erts_debug.flat_size()  # when shared over processes / ETS
      1170


  ## Efficiency guide

  If you are using vectors and not lists, chances are that you care about
  performance. Here are a couple notes about how to use vectors in an optimal
  way. Most functions from this module are highly efficient, those that are not
  will indicate it in their documentation.

  But remember the golden rule: in case of doubt, always benchmark.

  ### Avoid prepending

  Appending is very efficient, but prepending is highly inefficient since the
  whole array needs to be reconstructed.

  **DON'T**

      A.Vector.prepend(vector, :foo)

  **DO**

      [:foo | list]  # use lists
      A.Vector.append(vector, :foo)

  ### Avoid deletions

  This implementation of persistent vectors has many advantages, but it does
  not support efficient deletion, with the exception of the last element that
  can be popped very efficiently (`A.Vector.pop_last/1`, `A.Vector.delete_last/1`).

  Deletion functionality is still provided through functions like `A.Vector.pop_at/3`
  and `A.Vector.delete_at/2` for the sake of completion, but please note that they
  are highly inefficient and their usage is strongly discouraged.

  If you need to be able to pop arbitrary indexes, chances are you should consider
  an alternative data structure.
  Another possibility could be to use sparse arrays, defining `nil` as a deleted value
  (but then the indexing and size won't reflect this).

  **DON'T**

      A.Vector.pop_at(vector, 3)
      A.Vector.delete_at(vector, 3)
      pop_in(vector[3])

  **DO**

      A.Vector.pop_last(vector)
      A.Vector.delete_last(vector)
      A.Vector.replace_at(vector, 3, nil)

  ### Successive appends

  If you need to append all elements of an enumerable, it is more efficient to use
  `A.Vector.append_many/2` than successive calls to `A.Vector.append/2`.

  **DON'T**

      Enum.reduce(enumerable, vector, fn val, acc -> A.Vector.append(acc, val) end)
      Enum.into(enumerable, vector)

  **DO**

      A.Vector.append_many(vector, enumerable)

  ### Prefer `A.Vector` to `Enum` for vectors

  Many functions provided in this module are very efficient and should be
  used over `Enum` functions whenever possible, even if `A.Vector` implements
  the `Enumerable` and `Collectable` protocols for convienience.

  **DON'T**

      Enum.sum(vector)
      Enum.to_list(vector)
      Enum.reduce(vector, [], fun)
      Enum.into(enumerable, %A.Vector.new())
      Enum.into(enumerable, vector)

  **DO**

      A.Vector.sum(vector)
      A.Vector.to_list(vector)
      A.Vector.foldl(vector, [], fun)
      A.Vector.new(enumerable)
      A.Vector.append_many(vector, enumerable)

  `for` comprehensions are actually using `Enumerable` as well, so
  the same advice holds.

  **DON'T**

      for value <- vector do
        do_stuff()
      end

  **DO**

      for value <- A.Vector.to_list(vector) do
        do_stuff()
      end

  Not all `Enum` functions have been mirrored in `A.Vector`, but
  you can try either to:
  - use `A.Vector.foldl/3` or `A.Vector.foldr/3` to implement it
    (the latter is better to build lists)
  - call `A.Vector.to_list/1` before using `Enum`

  Also, it is worth noting that several `A.Vector` functions return vectors,
  not lists like their `Enum` counterpart:

      iex> vector = A.Vector.new(1..10)
      iex> A.Vector.map(vector, & (&1 * 7))
      #A<vec([7, 14, 21, 28, 35, 42, 49, 56, 63, 70])>
      iex> A.Vector.reverse(vector)
      #A<vec([10, 9, 8, 7, 6, 5, 4, 3, 2, 1])>

  ### Additional notes

  * If you need to work with vectors containing mostly the same value,
    use `A.Vector.duplicate/2` (more details in the [Memory usage section](#module-memory-usage)).

  * If you work with functions returning vectors of known size, you can use
    the `A.vec/1` macro to defer the generation of the AST for the internal
    structure to compile time instead of runtime.

        A.Vector.new([a, 1, 2, 3, 4])  # structure created at runtime
        vec([a, 1, 2, 3, 4])  # structure AST defined at compile time

  """

  alias A.Vector.{EmptyError, IndexError, Raw}

  @behaviour Access

  @type index :: non_neg_integer
  @type value :: term

  @opaque t(value) :: %__MODULE__{internal: Raw.t(value)}
  @enforce_keys [:internal]
  defstruct [:internal]

  @type t :: t(value)

  @doc """
  Returns the number of elements in `vector`.

  Runs in constant time.

  ## Examples

      iex> A.Vector.new(10_000..20_000) |> A.Vector.size()
      10001
      iex> A.Vector.new() |> A.Vector.size()
      0

  """
  @spec size(t()) :: non_neg_integer
  def size(%__MODULE__{internal: internal}) do
    Raw.size(internal)
  end

  @doc """
  Returns a new empty vector.

  ## Examples

      iex> A.Vector.new()
      #A<vec([])>

  """
  @compile {:inline, new: 0}
  @spec new :: t()
  def new() do
    %__MODULE__{internal: unquote(Raw.from_list([]))}
  end

  @doc """
  Creates a vector from an `enumerable`.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(10..25)
      #A<vec([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])>

  """
  @spec new(Enumerable.t()) :: t()
  def new(%__MODULE__{} = vector) do
    vector
  end

  def new(enumerable) do
    %__MODULE__{
      internal: Raw.new(enumerable)
    }
  end

  @doc """
  Creates a vector from an `enumerable` via the given `transform` function.

  ## Examples

      iex> A.Vector.new(1..10, &(&1 * &1))
      #A<vec([1, 4, 9, 16, 25, 36, 49, 64, 81, 100])>

  """
  @spec new(Enumerable.t(), (v1 -> v2)) :: t(v2) when v1: value, v2: value
  def new(enumerable, fun) when is_function(fun, 1) do
    case enumerable do
      %__MODULE__{} ->
        map(enumerable, fun)

      _ ->
        %__MODULE__{
          internal: Raw.new(enumerable, fun)
        }
    end
  end

  @doc """
  Duplicates the given element `n` times in a vector.

  `n` is an integer greater than or equal to `0`.
  If `n` is `0`, an empty list is returned.

  Runs in linear time, but is very fast and memory efficient (see [Memory usage](#module-memory-usage)).

  ## Examples

      iex> A.Vector.duplicate(nil, 10)
      #A<vec([nil, nil, nil, nil, nil, nil, nil, nil, nil, nil])>
      iex> A.Vector.duplicate(:foo, 0)
      #A<vec([])>

  """
  @spec duplicate(val, non_neg_integer) :: t(val) when val: value
  def duplicate(value, n) when is_integer(n) and n >= 0 do
    # TODO can still improve!
    %__MODULE__{
      internal: Raw.duplicate(value, n)
    }
  end

  @doc """
  Populates a vector of size `n` by calling `generator_fun` repeatedly.

  ## Examples

      # Although not necessary, let's seed the random algorithm
      iex> :rand.seed(:exsplus, {1, 2, 3})
      iex> A.Vector.repeatedly(&:rand.uniform/0, 3)
      #A<vec([0.40502929729990744, 0.45336720247823126, 0.04094511692041057])>

  """
  def repeatedly(generator_fun, n)
      when is_function(generator_fun, 0) and is_integer(n) and n >= 0 do
    %__MODULE__{
      internal: A.List.repeatedly(generator_fun, n) |> Raw.from_list()
    }
  end

  @doc """
  Appends a `value` at the end of a `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new() |> A.Vector.append(:foo)
      #A<vec([:foo])>
      iex> A.Vector.new(1..5) |> A.Vector.append(:foo)
      #A<vec([1, 2, 3, 4, 5, :foo])>

  """
  @spec append(t(val), val) :: t(val) when val: value
  def append(%__MODULE__{internal: internal}, value) do
    %__MODULE__{
      internal: Raw.append(internal, value)
    }
  end

  @doc """
  Appends all values from an `enumerable` at the end of a `vector`.

  Runs in effective linear time in respect with the length of `enumerable`,
  disregarding the size of the `vector`.

  ## Examples

      iex> A.Vector.new(1..5) |> A.Vector.append_many(10..15)
      #A<vec([1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15])>
      iex> A.Vector.new() |> A.Vector.append_many(10..15)
      #A<vec([10, 11, 12, 13, 14, 15])>

  """
  @spec append_many(t(val), Enumerable.t()) :: t(val) when val: value
  def append_many(%__MODULE__{internal: internal}, enumerable) do
    list = A.FastEnum.to_list(enumerable)

    %__MODULE__{
      internal: Raw.append_many(internal, list)
    }
  end

  @doc """
  (Inefficient) Prepends `value` at the beginning of the `vector`.

  Runs in linear time because the whole vector needs to be reconstructuded,
  and should be avoided.

  ## Examples

      iex> A.Vector.new() |> A.Vector.prepend(:foo)
      #A<vec([:foo])>
      iex> A.Vector.new(1..5) |> A.Vector.prepend(:foo)
      #A<vec([:foo, 1, 2, 3, 4, 5])>

  """
  @spec prepend(t(val), val) :: t(val) when val: value
  def prepend(%__MODULE__{internal: internal}, value) do
    %__MODULE__{
      internal: Raw.prepend(internal, value)
    }
  end

  @doc """
  Returns the first element in the `vector` or `default` if `vector` is empty.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..10_000) |> A.Vector.first()
      1
      iex> A.Vector.new() |> A.Vector.first()
      nil

  """
  @spec first(t(val), default) :: val | default when val: value, default: term
  def first(vector, default \\ nil)

  def first(%__MODULE__{internal: internal}, default) do
    Raw.first(internal, default)
  end

  @doc """
  Returns the last element in the `vector` or `default` if `vector` is empty.

  Runs in constant time (actual, not effective).

  ## Examples

      iex> A.Vector.new(1..10_000) |> A.Vector.last()
      10_000
      iex> A.Vector.new() |> A.Vector.last()
      nil

  """
  @spec last(t(val), default) :: val | default when val: value, default: term
  def last(vector, default \\ nil)

  def last(%__MODULE__{internal: internal}, default) do
    Raw.last(internal, default)
  end

  @doc """
  Finds the element at the given `index` (zero-based), and returns it in a ok-entry.
  If the `index` does not exist, returns `:error`.

  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..1_000) |> A.Vector.fetch(555)
      {:ok, 556}
      iex> A.Vector.new(1..1_000) |> A.Vector.fetch(1_000)
      :error
      iex> A.Vector.new(1..1_000) |> A.Vector.fetch(-1)
      {:ok, 1000}

  """
  @impl Access
  @spec fetch(t(val), index) :: {:ok, val} | :error when val: value
  def fetch(vector, index)

  def fetch(%__MODULE__{internal: internal}, index) when is_integer(index) do
    Raw.fetch_any(internal, index)
  end

  @doc """
  Finds the element at the given `index` (zero-based).

  Returns `default` if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..1_000) |> A.Vector.at(555)
      556
      iex> A.Vector.new(1..1_000) |> A.Vector.at(1_000)
      nil

  """
  @spec at(t(val), index, default) :: val | default when val: value, default: term
  def at(vector, index, default \\ nil)

  def at(%__MODULE__{internal: internal}, index, default) when is_integer(index) do
    case Raw.fetch_any(internal, index) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Finds the element at the given `index` (zero-based).

  Raises an `A.Vector.IndexError` if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..1_000) |> A.Vector.at!(555)
      556
      iex> A.Vector.new(1..1_000) |> A.Vector.at!(-10)
      991
      iex> A.Vector.new(1..1_000) |> A.Vector.at!(1_000)
      ** (A.Vector.IndexError) out of bound index: 1000 not in -1000..999

  """
  @spec at(t(val), index) :: val when val: value
  def at!(vector, index)

  def at!(%__MODULE__{internal: internal}, index) when is_integer(index) do
    case Raw.fetch_any(internal, index) do
      {:ok, value} -> value
      :error -> raise IndexError, index: index, size: Raw.size(internal)
    end
  end

  @doc """
  Returns a copy of `vector` with a replaced `value` at the specified `index`.

  Returns the `vector` untouched if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..8) |> A.Vector.replace_at(5, :foo)
      #A<vec([1, 2, 3, 4, 5, :foo, 7, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.replace_at(8, :foo)
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.replace_at(-2, :foo)
      #A<vec([1, 2, 3, 4, 5, 6, :foo, 8])>

  """
  @spec replace_at(t(val), index, val) :: t(val) when val: value
  def replace_at(%__MODULE__{internal: internal} = vector, index, value) when is_integer(index) do
    case Raw.replace_any(internal, index, value) do
      {:ok, updated} -> %__MODULE__{internal: updated}
      :error -> vector
    end
  end

  @doc """
  Returns a copy of `vector` with a replaced `value` at the specified `index`.

  Raises an `A.Vector.IndexError` if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..8) |> A.Vector.replace_at!(5, :foo)
      #A<vec([1, 2, 3, 4, 5, :foo, 7, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.replace_at!(-2, :foo)
      #A<vec([1, 2, 3, 4, 5, 6, :foo, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.replace_at!(8, :foo)
      ** (A.Vector.IndexError) out of bound index: 8 not in -8..7

  """
  @spec replace_at!(t(val), index, val) :: t(val) when val: value
  def replace_at!(%__MODULE__{internal: internal}, index, value)
      when is_integer(index) do
    case Raw.replace_any(internal, index, value) do
      {:ok, updated} -> %__MODULE__{internal: updated}
      :error -> raise IndexError, index: index, size: Raw.size(internal)
    end
  end

  @doc """
  Returns a copy of `vector` with an updated value at the specified `index`.

  Returns the `vector` untouched if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..8) |> A.Vector.update_at(2, &(&1 * 1000))
      #A<vec([1, 2, 3000, 4, 5, 6, 7, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.update_at(8, &(&1 * 1000))
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.update_at(-1, &(&1 * 1000))
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8000])>

  """
  @spec update_at(t(val), index, (val -> val)) :: t(val) when val: value
  def update_at(%__MODULE__{internal: internal} = vector, index, fun)
      when is_integer(index) and is_function(fun) do
    case Raw.update_any(internal, index, fun) do
      {:ok, updated} -> %__MODULE__{internal: updated}
      :error -> vector
    end
  end

  @doc """
  Returns a copy of `vector` with an updated value at the specified `index`.

  Raises an `A.Vector.IndexError` if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in effective constant time.

  ## Examples

      iex> A.Vector.new(1..8) |> A.Vector.update_at!(2, &(&1 * 1000))
      #A<vec([1, 2, 3000, 4, 5, 6, 7, 8])>
      iex> A.Vector.new(1..8) |> A.Vector.update_at!(-1, &(&1 * 1000))
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8000])>
      iex> A.Vector.new(1..8) |> A.Vector.update_at!(-9, &(&1 * 1000))
      ** (A.Vector.IndexError) out of bound index: -9 not in -8..7

  """
  @spec update_at!(t(val), index, (val -> val)) :: t(val) when val: value
  def update_at!(%__MODULE__{internal: internal}, index, fun)
      when is_integer(index) and is_function(fun) do
    case Raw.update_any(internal, index, fun) do
      {:ok, updated} -> %__MODULE__{internal: updated}
      :error -> raise IndexError, index: index, size: Raw.size(internal)
    end
  end

  @doc """
  Removes the last value from the `vector` and returns both the value and the updated vector.

  Leaves the `vector` untouched if empty.

  Runs in effective constant time.

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> {8, updated} = A.Vector.pop_last(vector); updated
      #A<vec([1, 2, 3, 4, 5, 6, 7])>
      iex> {nil, updated} = A.Vector.pop_last(A.Vector.new()); updated
      #A<vec([])>

  """
  @spec pop_last(t(val), default) :: {val | default, t(val)} when val: value, default: term
  def pop_last(vector, default \\ nil)

  def pop_last(%__MODULE__{internal: internal} = vector, default) do
    case Raw.pop_last(internal) do
      {value, new_internal} -> {value, %__MODULE__{internal: new_internal}}
      :error -> {default, vector}
    end
  end

  @doc """
  Removes the last value from the `vector` and returns both the value and the updated vector.

  Raises an `A.Vector.EmptyError` if empty.

  Runs in effective constant time.

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> {8, updated} = A.Vector.pop_last!(vector); updated
      #A<vec([1, 2, 3, 4, 5, 6, 7])>
      iex> {nil, updated} = A.Vector.pop_last!(A.Vector.new()); updated
      ** (A.Vector.EmptyError) empty vector error

  """
  @spec pop_last!(t(val)) :: {val, t(val)} when val: value
  def pop_last!(vector)

  def pop_last!(%__MODULE__{internal: internal}) do
    case Raw.pop_last(internal) do
      {value, new_internal} -> {value, %__MODULE__{internal: new_internal}}
      :error -> raise EmptyError
    end
  end

  @doc """
  Removes the last value from the `vector` and returns the updated vector.

  Leaves the `vector` untouched if empty.

  Runs in effective constant time.

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> A.Vector.delete_last(vector)
      #A<vec([1, 2, 3, 4, 5, 6, 7])>
      iex> A.Vector.delete_last(A.Vector.new())
      #A<vec([])>

  """
  @spec delete_last(t(val)) :: t(val) when val: value
  def delete_last(vector)

  def delete_last(%__MODULE__{internal: internal} = vector) do
    case Raw.pop_last(internal) do
      {_value, new_internal} -> %__MODULE__{internal: new_internal}
      :error -> vector
    end
  end

  @doc """
  Removes the last value from the `vector` and returns the updated vector.

  Raises an `A.Vector.EmptyError` if empty.

  Runs in effective constant time.

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> A.Vector.delete_last!(vector)
      #A<vec([1, 2, 3, 4, 5, 6, 7])>
      iex> A.Vector.delete_last!(A.Vector.new())
      ** (A.Vector.EmptyError) empty vector error

  """
  @spec delete_last!(t(val)) :: t(val) when val: value
  def delete_last!(vector)

  def delete_last!(%__MODULE__{internal: internal}) do
    case Raw.pop_last(internal) do
      {_value, new_internal} -> %__MODULE__{internal: new_internal}
      :error -> raise EmptyError
    end
  end

  @doc """
  (Inefficient) Returns and removes the value at the specified `index` in the `vector`.

  Returns the `vector` untouched if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in linear time. Its usage is discouraged, see the
  [Efficiency guide](#module-efficiency-guide).

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> {5, updated} = A.Vector.pop_at(vector, 4); updated
      #A<vec([1, 2, 3, 4, 6, 7, 8])>
      iex> {nil, updated} = A.Vector.pop_at(vector, -9); updated
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8])>

  """
  @spec pop_at(t(val), index, default) :: {val | default, t(val)} when val: value, default: term
  def pop_at(vector, index, default \\ nil)

  def pop_at(%__MODULE__{internal: internal} = vector, index, default) when is_integer(index) do
    case Raw.pop_any(internal, index) do
      {value, new_internal} -> {value, %__MODULE__{internal: new_internal}}
      :error -> {default, vector}
    end
  end

  @doc """
  (Inefficient) Returns and removes the value at the specified `index` in the `vector`.

  Raises an `A.Vector.IndexError` if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in linear time. Its usage is discouraged, see the
  [Efficiency guide](#module-efficiency-guide).

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> {5, updated} = A.Vector.pop_at!(vector, 4); updated
      #A<vec([1, 2, 3, 4, 6, 7, 8])>
      iex> A.Vector.pop_at!(vector, -9)
      ** (A.Vector.IndexError) out of bound index: -9 not in -8..7

  """
  @spec pop_at!(t(val), index) :: {val, t(val)} when val: value
  def pop_at!(vector, index)

  def pop_at!(%__MODULE__{internal: internal}, index) when is_integer(index) do
    case Raw.pop_any(internal, index) do
      {value, new_internal} -> {value, %__MODULE__{internal: new_internal}}
      :error -> raise IndexError, index: index, size: Raw.size(internal)
    end
  end

  @doc false
  @impl Access
  @spec pop(t(val), index) :: {val | nil, t(val)} when val: value
  defdelegate pop(vector, key), to: __MODULE__, as: :pop_at

  @doc """
  (Inefficient) Returns a copy of `vector` without the value at the specified `index`.

  Returns the `vector` untouched if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in linear time. Its usage is discouraged, see the
  [Efficiency guide](#module-efficiency-guide).

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> A.Vector.delete_at(vector, 4)
      #A<vec([1, 2, 3, 4, 6, 7, 8])>
      iex> A.Vector.delete_at(vector, -9)
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8])>

  """
  @spec delete_at(t(val), index) :: t(val) when val: value
  def delete_at(%__MODULE__{internal: internal} = vector, index) when is_integer(index) do
    case Raw.delete_any(internal, index) do
      {:ok, new_internal} -> %__MODULE__{internal: new_internal}
      :error -> vector
    end
  end

  @doc """
  (Inefficient) Returns a copy of `vector` without the value at the specified `index`.

  Raises an `A.Vector.IndexError` if `index` is out of bounds.
  Supports negative indexing from the end of the `vector`.

  Runs in linear time. Its usage is discouraged, see the
  [Efficiency guide](#module-efficiency-guide).

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> A.Vector.delete_at!(vector, 4)
      #A<vec([1, 2, 3, 4, 6, 7, 8])>
      iex> A.Vector.delete_at!(vector, -9)
      ** (A.Vector.IndexError) out of bound index: -9 not in -8..7

  """
  @spec delete_at!(t(val), index) :: t(val) when val: value
  def delete_at!(vector, index)

  def delete_at!(%__MODULE__{internal: internal}, index) when is_integer(index) do
    case Raw.delete_any(internal, index) do
      {:ok, new_internal} -> %__MODULE__{internal: new_internal}
      :error -> raise IndexError, index: index, size: Raw.size(internal)
    end
  end

  @doc """
  Gets the value from key and updates it, all in one pass.

  See `Access.get_and_update/3` for more details.

  ## Examples

      iex> vector = A.Vector.new(1..8)
      iex> {6, updated} = A.Vector.get_and_update(vector, 5, fn current_value ->
      ...>   {current_value, current_value && current_value * 100}
      ...> end); updated
      #A<vec([1, 2, 3, 4, 5, 600, 7, 8])>
      iex> {nil, updated} = A.Vector.get_and_update(vector, 8, fn current_value ->
      ...>   {current_value, current_value && current_value * 100}
      ...> end); updated
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8])>
      iex> {4, updated} = A.Vector.get_and_update(vector, 3, fn _ -> :pop end); updated
      #A<vec([1, 2, 3, 5, 6, 7, 8])>
      iex> {nil, updated} = A.Vector.get_and_update(vector, 8, fn _ -> :pop end); updated
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8])>

  """
  @impl Access
  @spec get_and_update(t(v), index, (v -> {returned, v} | :pop)) :: {returned, t(v)}
        when v: value, returned: term
  def get_and_update(%__MODULE__{internal: internal}, index, fun)
      when is_integer(index) and is_function(fun, 1) do
    {returned, new_internal} = Raw.get_and_update_any(internal, index, fun)
    {returned, %__MODULE__{internal: new_internal}}
  end

  @doc """
  Converts the `vector` to a list.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(10..25) |> A.Vector.to_list()
      [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
      iex> A.Vector.new() |> A.Vector.to_list()
      []

  """
  @spec to_list(t(val)) :: [val] when val: value
  def to_list(%__MODULE__{internal: internal}) do
    Raw.to_list(internal)
  end

  @doc """
  Returns a new vector where each element is the result of invoking `fun`
  on each corresponding element of `vector`.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..10) |> A.Vector.map(&(&1 * &1))
      #A<vec([1, 4, 9, 16, 25, 36, 49, 64, 81, 100])>

  """
  @spec map(t(v1), (v1 -> v2)) :: t(v2) when v1: value, v2: value
  def map(%__MODULE__{internal: internal}, fun) when is_function(fun, 1) do
    %__MODULE__{
      internal: Raw.map(internal, fun)
    }
  end

  @doc """
  Filters the `vector`, i.e. return a new vector containing only elements
  for which `fun` returns a truthy (neither `false` nor `nil`) value.

  Runs in linear time.

  ## Examples

      iex> vector = A.Vector.new(1..100)
      iex> A.Vector.filter(vector, fn i -> rem(i, 13) == 0 end)
      #A<vec([13, 26, 39, 52, 65, 78, 91])>

  """
  @spec filter(t(val), (val -> boolean)) :: t(val) when val: value
  def filter(%__MODULE__{internal: internal}, fun) when is_function(fun, 1) do
    %__MODULE__{
      internal: Raw.filter(internal, fun)
    }
  end

  @doc """
  Filters the `vector`, i.e. return a new vector containing only elements
  for which `fun` returns a falsy (either `false` or `nil`) value.

  Runs in linear time.

  ## Examples

      iex> vector = A.Vector.new(1..12)
      iex> A.Vector.reject(vector, fn i -> rem(i, 3) == 0 end)
      #A<vec([1, 2, 4, 5, 7, 8, 10, 11])>

  """
  @spec reject(t(val), (val -> boolean)) :: t(val) when val: value
  def reject(%__MODULE__{internal: internal}, fun) when is_function(fun, 1) do
    %__MODULE__{
      internal: Raw.reject(internal, fun)
    }
  end

  @doc """
  Sorts the `vector` in the same way as `Enum.sort/1`.

  ## Examples

      iex> A.Vector.new(9..1) |> A.Vector.sort()
      #A<vec([1, 2, 3, 4, 5, 6, 7, 8, 9])>

  """
  @spec sort(t(val)) :: t(val) when val: value
  def sort(%__MODULE__{internal: internal}) do
    new_internal =
      internal
      |> Raw.to_list()
      |> Enum.sort()
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Sorts the `vector` in the same way as `Enum.sort/2`.

  See `Enum.sort/2` documentation for detailled usage.

  ## Examples

      iex> A.Vector.new(1..9) |> A.Vector.sort(:desc)
      #A<vec([9, 8, 7, 6, 5, 4, 3, 2, 1])>

  """
  @spec sort(
          t(val),
          (val, val -> boolean)
          | :asc
          | :desc
          | module
          | {:asc | :desc, module}
        ) :: t(val)
        when val: value
  def sort(%__MODULE__{internal: internal}, fun) do
    new_internal =
      internal
      |> Raw.to_list()
      |> Enum.sort(fun)
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Sorts the `vector` in the same way as `Enum.sort_by/3`.

  See `Enum.sort_by/3` documentation for detailled usage.

  ## Examples

      iex> vector = A.Vector.new(["some", "kind", "of", "monster"])
      iex> A.Vector.sort_by(vector, &byte_size/1)
      #A<vec(["of", "some", "kind", "monster"])>
      iex> A.Vector.sort_by(vector, &{byte_size(&1), String.first(&1)})
      #A<vec(["of", "kind", "some", "monster"])>

  """
  @spec sort_by(
          t(val),
          (val -> mapped_val),
          (val, val -> boolean)
          | :asc
          | :desc
          | module
          | {:asc | :desc, module}
        ) :: t(val)
        when val: value, mapped_val: value
  def sort_by(%__MODULE__{internal: internal}, mapper, sorter \\ &<=/2) do
    new_internal =
      internal
      |> Raw.to_list()
      |> Enum.sort_by(mapper, sorter)
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Returns a copy of the vector without any duplicated element.

  The first occurrence of each element is kept.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new([1, 1, 2, 1, 2, 3, 2]) |> A.Vector.uniq()
      #A<vec([1, 2, 3])>

  """
  @spec uniq(t(val)) :: t(val) when val: value
  def uniq(%__MODULE__{internal: internal}) do
    # TODO optimize
    new_internal =
      internal
      |> Raw.to_list()
      |> Enum.uniq()
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Returns a copy of the vector without elements for which the function `fun` returned duplicate elements.

  The first occurrence of each element is kept.

  Runs in linear time.

  ## Examples

      iex> vector = A.Vector.new([x: 1, y: 2, z: 1])
      #A<vec([x: 1, y: 2, z: 1])>
      iex> A.Vector.uniq_by(vector, fn {_x, y} -> y end)
      #A<vec([x: 1, y: 2])>

  """
  @spec uniq_by(t(val), (val -> term)) :: t(val) when val: value
  def uniq_by(%__MODULE__{internal: internal}, fun) when is_function(fun, 1) do
    new_internal =
      internal
      |> Raw.to_list()
      |> Enum.uniq_by(fun)
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Intersperses `separator` between each element of the `vector`.

  ## Examples

      iex> A.Vector.new(1..6) |> A.Vector.intersperse(nil)
      #A<vec([1, nil, 2, nil, 3, nil, 4, nil, 5, nil, 6])>

  """
  @spec intersperse(
          t(val),
          separator
        ) :: t(val | separator)
        when val: value, separator: value
  def intersperse(%__MODULE__{internal: internal}, separator) do
    new_internal =
      internal
      |> Raw.intersperse(separator)
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Maps and intersperses the `vector` in one pass.

  ## Examples

      iex> A.Vector.new(1..6) |> A.Vector.map_intersperse(nil, &(&1 * 10))
      #A<vec([10, nil, 20, nil, 30, nil, 40, nil, 50, nil, 60])>

  """
  @spec map_intersperse(
          t(val),
          separator,
          (val -> mapped_val)
        ) :: t(mapped_val | separator)
        when val: value, separator: value, mapped_val: value
  def map_intersperse(%__MODULE__{internal: internal}, separator, mapper)
      when is_function(mapper, 1) do
    new_internal =
      internal
      |> Raw.map_intersperse(separator, mapper)
      |> Raw.from_list()

    %__MODULE__{
      internal: new_internal
    }
  end

  @doc """
  Folds (reduces) the given `vector` from the left with the function `fun`.
  Requires an accumulator `acc`.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..10) |> A.Vector.foldl(0, &+/2)
      55
      iex> A.Vector.new(1..10) |> A.Vector.foldl([], & [&1 | &2])
      [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]

  """
  @spec foldl(t(val), acc, (val, acc -> acc)) :: acc when val: value, acc: term
  def foldl(%__MODULE__{internal: internal}, acc, fun) when is_function(fun, 2) do
    Raw.foldl(internal, acc, fun)
  end

  @doc """
  Folds (reduces) the given `vector` from the right with the function `fun`.
  Requires an accumulator `acc`.

  Unlike linked lists, this is as efficient as `foldl/3`. This can typically save a call
  to `Enum.reverse/1` on the result when building a list.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..10) |> A.Vector.foldr(0, &+/2)
      55
      iex> A.Vector.new(1..10) |> A.Vector.foldr([], & [&1 | &2])
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

  """
  @spec foldr(t(val), acc, (val, acc -> acc)) :: acc when val: value, acc: term
  def foldr(%__MODULE__{internal: internal}, acc, fun) when is_function(fun, 2) do
    Raw.foldr(internal, acc, fun)
  end

  @doc """
  Returns the sum of all elements in the `vector`.

  Raises `ArithmeticError` if `vector` contains a non-numeric value.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..10) |> A.Vector.sum()
      55
      iex> A.Vector.new() |> A.Vector.sum()
      0

  """
  @spec sum(t(num)) :: num when num: number
  def sum(%__MODULE__{internal: internal}) do
    Raw.sum(internal)
  end

  @doc """
  Joins the given `vector` into a string using `joiner` as a separator.

  If `joiner` is not passed at all, it defaults to an empty string.

  All elements in the `vector` must be convertible to a string, otherwise an error is raised.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..6) |> A.Vector.join()
      "123456"
      iex> A.Vector.new(1..6) |> A.Vector.join(" + ")
      "1 + 2 + 3 + 4 + 5 + 6"
      iex> A.Vector.new() |> A.Vector.join(" + ")
      ""

  """
  @spec join(t(val), String.t()) :: String.t() when val: String.Chars.t()
  def join(%__MODULE__{internal: internal}, joiner \\ "") when is_binary(joiner) do
    Raw.join_as_iodata(internal, joiner) |> IO.iodata_to_binary()
  end

  @doc """
  Maps and joins the given `vector` into a string using `joiner` as a separator.

  If `joiner` is not passed at all, it defaults to an empty string.

  `mapper` should only return values that are convertible to a string, otherwise an error is raised.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..6) |> A.Vector.map_join(fn x -> x * 10 end)
      "102030405060"
      iex> A.Vector.new(1..6) |> A.Vector.map_join(" + ", fn x -> x * 10 end)
      "10 + 20 + 30 + 40 + 50 + 60"
      iex> A.Vector.new() |> A.Vector.map_join(" + ", fn x -> x * 10 end)
      ""

  """
  @spec map_join(t(val), String.t(), (val -> String.Chars.t())) :: String.t()
        when val: value
  def map_join(%__MODULE__{internal: internal}, joiner \\ "", mapper)
      when is_binary(joiner) and is_function(mapper, 1) do
    Raw.map_intersperse(internal, joiner, fn element ->
      mapper.(element) |> to_string()
    end)
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns the maximal element in the `vector` according to Erlang's term ordering.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..10) |> A.Vector.max()
      10
      iex> A.Vector.new() |> A.Vector.max()
      ** (A.Vector.EmptyError) empty vector error

  """
  @spec max(t(val)) :: val when val: value
  def max(%__MODULE__{internal: internal}) do
    Raw.max(internal)
  end

  @doc """
  Returns the minimal element in the `vector` according to Erlang's term ordering.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..10) |> A.Vector.min()
      1
      iex> A.Vector.new() |> A.Vector.min()
      ** (A.Vector.EmptyError) empty vector error

  """
  @spec min(t(val)) :: val when val: value
  def min(%__MODULE__{internal: internal}) do
    # TODO mirror Enum API
    Raw.min(internal)
  end

  @doc """
  Returns `true` if at least one element in `enumerable` is truthy.

  Runs in linear time, but stops evaluating when finds the first truthy value.

  Iterates over the `enumerable`, and when it finds a truthy value
  (neither `false` nor `nil`), `true` is returned.
  In all other cases `false` is returned.

  ## Examples

      iex> A.Vector.new([false, false, true]) |> A.Vector.any?()
      true
      iex> A.Vector.new([false, nil]) |> A.Vector.any?()
      false
      iex> A.Vector.new() |> A.Vector.any?()
      false

  """
  @spec any?(t(val)) :: boolean when val: value
  def any?(%__MODULE__{internal: internal}) do
    Raw.any?(internal)
  end

  @doc """
  Returns `true` if `fun.(element)` is truthy for at least one element in `enumerable`.

  Runs in linear time, but stops evaluating when finds the first truthy value.

  Iterates over the `enumerable` and invokes `fun` on each element. When an invocation
  of `fun` returns a truthy value (neither `false` nor `nil`) iteration stops immediately
  and `true` is returned. In all other cases `false` is returned.

  ## Examples

      iex> vector = A.Vector.new(1..10)
      iex> A.Vector.any?(vector, fn i -> rem(i, 7) == 0 end)
      true
      iex> A.Vector.any?(vector, fn i -> rem(i, 13) == 0 end)
      false
      iex> A.Vector.new() |> A.Vector.any?(fn i -> rem(i, 7) == 0 end)
      false

  """
  @spec any?(t(val), (val -> as_boolean(term))) :: boolean when val: value
  def any?(%__MODULE__{internal: internal}, fun) when is_function(fun, 1) do
    Raw.any?(internal, fun)
  end

  @doc """
  Returns `true` if all elements in `enumerable` are truthy.

  Runs in linear time, but stops evaluating when finds the first falsy value.

  Iterates over the `enumerable`, and when it finds a falsy value (`false` or `nil`),
  `false` is returned. In all other cases `true` is returned.

  ## Examples

      iex> A.Vector.new([true, true, false]) |> A.Vector.all?()
      false
      iex> A.Vector.new([true, [], %{}, 5]) |> A.Vector.all?()
      true
      iex> A.Vector.new() |> A.Vector.all?()
      true

  """
  @spec all?(t(val)) :: boolean when val: value
  def all?(%__MODULE__{internal: internal}) do
    Raw.all?(internal)
  end

  @doc """
  Returns `true` if `fun.(element)` is truthy for all elements in `enumerable`.

  Runs in linear time, but stops evaluating when finds the first falsy value.

  Iterates over the `enumerable` and invokes `fun` on each element. When an invocation
  of `fun` returns a falsy value (`false` or `nil`) iteration stops immediately and
  `false` is returned. In all other cases `true` is returned.

  ## Examples

      iex> vector = A.Vector.new(1..10)
      iex> A.Vector.all?(vector, fn i -> rem(i, 13) != 0 end)
      true
      iex> A.Vector.all?(vector, fn i -> rem(i, 7) != 0 end)
      false
      iex> A.Vector.new() |> A.Vector.all?(fn i -> rem(i, 7) != 0 end)
      true

  """
  @spec all?(t(val), (val -> as_boolean(term))) :: boolean when val: value
  def all?(%__MODULE__{internal: internal}, fun) when is_function(fun, 1) do
    Raw.all?(internal, fun)
  end

  @doc """
  Returns the `vector` in reverse order.

  Runs in linear time.

  ## Examples

      iex> A.Vector.new(1..12) |> A.Vector.reverse()
      #A<vec([12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1])>

  """
  @spec reverse(t(val)) :: t(val) when val: value
  def reverse(%__MODULE__{internal: internal}) do
    internal
    |> Raw.to_reverse_list()
    |> new()
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(vector, opts) do
      opts = %Inspect.Opts{opts | charlists: :as_lists}
      concat(["#A<vec(", Inspect.List.inspect(A.Vector.to_list(vector), opts), ")>"])
    end
  end

  defimpl Enumerable do
    def count(vector) do
      {:ok, A.Vector.size(vector)}
    end

    def member?(%A.Vector{internal: internal}, value) do
      {:ok, Raw.member?(internal, value)}
    end

    def slice(%A.Vector{internal: internal}) do
      size = A.Vector.Raw.size(internal)

      {:ok, size, fn start, length -> slicing_fun(start, start + length, internal, []) end}
    end

    @compile {:inline, slicing_fun: 4}
    defp slicing_fun(start, start, _vector, acc), do: acc

    defp slicing_fun(start, i, vector, acc) do
      new_acc = [A.Vector.Raw.fetch_positive!(vector, i - 1) | acc]
      slicing_fun(start, i - 1, vector, new_acc)
    end

    def reduce(%A.Vector{internal: internal}, acc, fun) do
      internal
      |> A.Vector.Raw.to_list()
      |> Enumerable.List.reduce(acc, fun)
    end
  end

  defimpl Collectable do
    alias A.Vector.Raw

    def into(%A.Vector{internal: internal}) do
      {{[], internal}, &collector_fun/2}
    end

    @compile {:inline, collector_fun: 2}
    defp collector_fun({acc, internal}, {:cont, value}), do: {[value | acc], internal}

    defp collector_fun({acc, internal}, :done) do
      new_internal = Raw.append_many(internal, :lists.reverse(acc))
      %A.Vector{internal: new_internal}
    end

    defp collector_fun(_acc, :halt), do: :ok
  end

  if Code.ensure_loaded?(Jason.Encoder) do
    defimpl Jason.Encoder do
      def encode(vector, opts) do
        vector |> A.Vector.to_list() |> Jason.Encode.list(opts)
      end
    end
  end
end
