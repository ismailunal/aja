defmodule A.ListTest do
  use ExUnit.Case, async: true

  doctest A.List

  test "A.List.repeatedly/2" do
    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    assert [] = A.List.repeatedly(fun, 0)
    assert [1, 2, 3, 4, 5] = A.List.repeatedly(fun, 5)
    assert [6, 7, 8, 9, 10, 11, 12, 13, 14, 15] = A.List.repeatedly(fun, 10)

    assert_raise FunctionClauseError, fn -> A.List.repeatedly(fun, -1) end
  end
end
