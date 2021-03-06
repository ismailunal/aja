defmodule A do
  @moduledoc ~S"""
  Convenience macros to work with Aja's data structures.

  Use `import A` to import everything, or import only the macros you need.
  """

  @wildcard quote do: _

  @doc ~S"""
  A sigil to build [IO data](https://hexdocs.pm/elixir/IO.html#module-io-data) and avoid string concatenation.

  Use `import A` to use it, or `import A, only: [sigil_i: 2]`.

  This sigil provides a faster version of string interpolation which:
  - will build a list with all chunks instead of concatenating them as a string
  - uses `A.IO.to_iodata/1` on interpolated values instead of `to_string/1`, which:
    * will keep lists untouched, without any validation or transformation
    * will cast anything else using `to_string/1`

  Works with both [IO data](https://hexdocs.pm/elixir/IO.html#module-io-data) and
  [Chardata](https://hexdocs.pm/elixir/IO.html?#module-chardata).
  See their respective documentation for more information.

  ## Examples

      iex> ~i"atom: #{:foo}, charlist: #{'abc'}, number: #{12 + 2.35}\n"
      ["atom: ", "foo", ", charlist: ", 'abc', ", number: ", "14.35", 10]
      iex> ~i"abc#{['def' | "ghi"]}"
      ["abc", ['def' | "ghi"]]
      iex> ~i"Giorno Giovanna"
      "Giorno Giovanna"

    IO data can often be used as is without ever generating the corresponding string.
    If needed however, IO data can be cast as a string using `IO.iodata_to_binary/1`,
    and chardata using `List.to_string/1`. In most cases, both should be the same:

      iex> IO.iodata_to_binary(~i"atom: #{:foo}, charlist: #{'abc'}, number: #{12 + 2.35}\n")
      "atom: foo, charlist: abc, number: 14.35\n"
      iex> List.to_string(~i"abc#{['def' | "ghi"]}")
      "abcdefghi"

    Those are the exact same values returned by a regular string interpolation, without
    the `~i` sigil:

      iex> "atom: #{:foo}, charlist: #{'abc'}, number: #{12 + 2.35}\n"
      "atom: foo, charlist: abc, number: 14.35\n"
      iex> "abc#{['def' | "ghi"]}"
      "abcdefghi"

  """
  defmacro sigil_i(term, modifiers)

  defmacro sigil_i({:<<>>, _, [piece]}, []) when is_binary(piece) do
    Macro.unescape_string(piece)
  end

  defmacro sigil_i({:<<>>, _line, pieces}, []) do
    Enum.map(pieces, &sigil_i_piece/1)
  end

  defp sigil_i_piece({:"::", _, [{{:., _, _}, _, [expr]}, {:binary, _, _}]}) do
    quote do
      A.IO.to_iodata(unquote(expr))
    end
  end

  defp sigil_i_piece(piece) when is_binary(piece) do
    case Macro.unescape_string(piece) do
      <<char>> -> char
      binary -> binary
    end
  end

  @doc ~S"""
  Convenience macro to work with `A.ExRange`s (exclusive ranges).

  Use `import A` to use it, or `import A, only: [~>: 2]`.

  ## Examples

      iex> 1 ~> 5
      1 ~> 5
      iex> start ~> stop = 0 ~> 10
      iex> {start, stop}
      {0, 10}
      iex> for i <- 0 ~> 5, do: "id_#{i}"
      ["id_0", "id_1", "id_2", "id_3", "id_4"]

  """
  defmacro start ~> stop do
    case __CALLER__.context do
      nil ->
        quote do
          A.ExRange.new(unquote(start), unquote(stop))
        end

      _ ->
        quote do
          %A.ExRange{start: unquote(start), stop: unquote(stop)}
        end
    end
  end

  @doc ~S"""
  Convenience macro to create or pattern match on `A.OrdMap`s.

  Use `import A` to use it, or `import A, only: [ord: 1]`.

  ## Creation examples

      iex> ord(%{"一" => 1, "二" => 2, "三" => 3})
      #A<ord(%{"一" => 1, "二" => 2, "三" => 3})>
      iex> ord(%{a: "Ant", b: "Bat", c: "Cat"})
      #A<ord(%{a: "Ant", b: "Bat", c: "Cat"})>

  ## Pattern matching examples

      iex> ord(%{b: bat}) = ord(%{a: "Ant", b: "Bat", c: "Cat"})
      #A<ord(%{a: "Ant", b: "Bat", c: "Cat"})>
      iex> bat
      "Bat"

  ## Replace existing keys examples

      iex> ordered = ord(%{a: "Ant", b: "Bat", c: "Cat"})
      iex> ord(%{ordered | b: "Buffalo"})
      #A<ord(%{a: "Ant", b: "Buffalo", c: "Cat"})>
      iex> ord(%{ordered | z: "Zebra"})
      ** (KeyError) key :z not found in: #A<ord(%{a: "Ant", b: "Bat", c: "Cat"})>

  """
  defmacro ord({:%{}, _context, [{:|, _context2, [ordered, key_values]}]} = call) do
    unless Enum.all?(key_values, fn key_value -> match?({_, _}, key_value) end) do
      raise_ord_argument_error(call)
    end

    quote do
      A.OrdMap.replace_many!(unquote(ordered), unquote(key_values))
    end
  end

  defmacro ord({:%{}, context, key_value_pairs}) do
    case __CALLER__.context do
      nil ->
        quote do
          A.OrdMap.new(unquote(key_value_pairs))
        end

      :match ->
        match_map = to_match_map(key_value_pairs, context)

        quote do
          %A.OrdMap{map: unquote(match_map)}
        end

      :guard ->
        raise ArgumentError, "`A.ord/1` cannot be used in guards"
    end
  end

  defmacro ord(call) do
    raise_ord_argument_error(call)
  end

  defp raise_ord_argument_error(call) do
    raise ArgumentError, ~s"""
    Incorrect use of `A.ord/1`:
      ord(#{Macro.to_string(call)}).

    To create a new ordered map:
      ord_map = ord(%{b: "Bat", a: "Ant", c: "Cat"})

    To pattern-match:
      ord(%{a: ant}) = ord_map

    To replace an-existing key:
      ord(%{ord_map | b: "Buffalo"})
    """
  end

  defp to_match_map(key_value_pairs, context) do
    wildcard_pairs =
      for {key, value} <- key_value_pairs do
        {key,
         quote do
           {unquote(@wildcard), unquote(@wildcard), unquote(value)}
         end}
      end

    {:%{}, context, wildcard_pairs}
  end

  @doc """
  Convenience macro to create or pattern match on `A.Vector`s.

  It can only work with known-size vectors.

  ## Examples

      iex> import A
      iex> vec([1, 2, 3])
      #A<vec([1, 2, 3])>
      iex> vec([1, 2, var, _, _, _]) = A.Vector.new(1..6)
      #A<vec([1, 2, 3, 4, 5, 6])>
      iex> var
      3
      iex> vec([_, _, _]) = A.Vector.new(1..6)
      ** (MatchError) no match of right hand side value: #A<vec([1, 2, 3, 4, 5, 6])>

  It also supports ranges with **constant** values:

      iex> vec(0..4) = A.Vector.new(0..4)
      #A<vec([0, 1, 2, 3, 4])>
      iex> vec(0~>8)
      #A<vec([0, 1, 2, 3, 4, 5, 6, 7])>

  Variable lists or dynamic ranges cannot be passed:

      vec(my_list)  # invalid
      vec(1..n)  # invalid

  ## Explanation

  The `vec/1` macro generates the AST at compile time instead of building the vector
  at runtime. This can speedup the instanciation of vectors of known size.

      iex> import A
      iex> quote do vec([1, foo, _]) end |> Macro.expand(__ENV__) |> Macro.to_string()
      "%A.Vector{internal: {3, {1, foo, _, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}}}"

  """
  defmacro vec(list) when is_list(list) do
    ast_from_list(list)
  end

  defmacro vec({:.., _, [first, last]}) when is_integer(first) and is_integer(last) do
    first..last
    |> Enum.to_list()
    |> ast_from_list()
  end

  defmacro vec({:~>, _, [first, last]}) when is_integer(first) and is_integer(last) do
    first
    ~> last
    |> Enum.to_list()
    |> ast_from_list()
  end

  defp ast_from_list(list) do
    internal_ast = A.Vector.Raw.from_list_ast(list)

    quote do
      %A.Vector{internal: unquote(internal_ast)}
    end
  end

  defmacro vec({:_, _, _}) do
    quote do
      %A.Vector{internal: _}
    end
  end

  defmacro vec(call) do
    raise ArgumentError, ~s"""
    Incorrect use of `A.vec/1`:
      vec(#{Macro.to_string(call)}).

    To create a new vector from a fixed-sized list:
      vector = vec([:foo, 4, a + b])

    To create a new vector from a constant range:
      vector = vec(1..100)

    ! Variables cannot be used as lists or inside the range declaration !
      vec(my_list)  # invalid
      vec(1..n)  # invalid

    To pattern-match:
      vec([1, 2, x, _]) = vector
      vec([]) = empty_vector
      vec(_) = vector
    """
  end
end
