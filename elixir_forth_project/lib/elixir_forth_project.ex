defmodule Forth do
  @opaque evaluator :: any

  @valid_operators ["+", "*", "/", "-", "drop", "dup", "swap", "over"]

  @doc """
  Create a new evaluator.
  """
  @spec new() :: evaluator
  def new() do
    table = :ets.new(:stack, [:set, :public])
    :ets.insert(table, {"stack", []})

    custom = :ets.new(:custom, [:set, :public])

    result = :ets.insert(custom, [
      {"+", "+"},
      {"-", "-"},
      {"*", "*"},
      {"/", "/"},
      {"drop", "drop"},
      {"dup", "dup"},
      {"swap", "swap"},
      {"over", "over"}
    ])

    {table, custom}
  end

  @doc """
  Evaluate an input string, updating the evaluator state.
  """
  @spec eval(evaluator, String.t()) :: evaluator
  def eval(ev = {table, custom}, ":" <> string) do

    [command, to_eval] = String.split(string, ";")

    stored = string
    |>String.downcase()
    |>String.trim(" ;")
    |>String.split(" ", parts: 2, trim: true)
    |>then(fn [x, y] -> check_value(x, y, custom) end)

    if to_eval != "" do
      eval(ev, to_eval)
    else
      ev
    end
  end
  def eval(ev = {table, custom}, s) do

    [{_, stack}] = :ets.lookup(table, "stack")

    split_string = s
          |>String.replace(~r/[^( -~)(€)]/," ", global: true)
          |>String.downcase()
          |>String.split()
          |>Enum.map(fn x -> if Integer.parse(x) == :error, do: get_operator(x, custom), else: String.to_integer(x) end)
          |>List.flatten()
          |>then(fn x -> stack ++ x end)
          |>Enum.reverse()
          |>operate(custom)
          |>Enum.reverse()
          |>then(fn x -> :ets.insert(table, {"stack", x}) end)

    ev
  end

  defp check_value(x, y, ev) do
    if Integer.parse(x) == :error do
      :ets.insert(ev, {x, get_operator_custom(y, ev)})
    else
      raise Forth.InvalidWord
    end
  end

  defp check_operator(y) do
    if length(y)==0 do
      raise Forth.UnknownWord
    else
      y
    end
  end

  defp get_operator(x, ev) do
    x
    |>then(fn y -> :ets.lookup(ev, y) end)
    |>then(fn y -> check_operator(y) end)
    |>Enum.at(0)
    |>elem(1)
    |>String.split()
    |>Enum.map(fn y -> if Integer.parse(y) == :error, do: y, else: String.to_integer(y) end)
  end

  defp get_operator_custom(x, ev) do
    x
    |>String.split()
    |>Enum.map(fn y -> if Integer.parse(y) == :error, do: :ets.lookup(ev, y), else: {"int", y} end)
    |>List.flatten()
    |>Enum.map(fn {x, y} -> y end)
    |>Enum.join(" ")
  end

  defp operate([ "+" | tail ], ev) when length(tail) < 2 do
    raise Forth.StackUnderflow
  end
  defp operate(["+" | [op1 | tail] ], ev) do
    [value | eval_tail] = operate(tail, ev)
    [ op1 + value | eval_tail]
  end

  defp operate([ "-" | tail ], ev) when length(tail) < 2 do
    raise Forth.StackUnderflow
  end
  defp operate([ "-" | [op1 | tail]  ], ev) do
    [value | eval_tail] = operate(tail, ev)
    [ value - op1 | eval_tail]
  end

  defp operate([ "*" | tail ], ev) when length(tail) < 2 do
    raise Forth.StackUnderflow
  end
  defp operate([ "*" | [op1 | tail] ], ev) do
    [value | eval_tail] = operate(tail, ev)
    [ op1 * value | eval_tail ]
  end

  defp operate([ "/" | tail ], ev) when length(tail) < 2 do
    raise Forth.StackUnderflow
  end
  defp operate([ "/" | [op1 | tail] ], ev) do
    [value | eval_tail] = operate(tail, ev)
    if op1 == 0, do: raise Forth.DivisionByZero
    [ div(value, op1) | eval_tail ]
  end

  defp operate([ "dup" | tail ], ev) when length(tail) < 1 do
    raise Forth.StackUnderflow
  end
  defp operate([ "dup" | [op1 | []] ], ev) do
    [ op1, op1]
  end
  defp operate([ "dup" | tail ], ev) do
    [value | eval_tail] = operate(tail, ev)

    [ value, value | eval_tail ]
  end

  defp operate([ "drop" | tail ], ev) when length(tail) < 1 do
    raise Forth.StackUnderflow
  end
  defp operate([ "drop" | [op1 | []] ], ev) do
    []
  end

  defp operate([ "drop" | tail ], ev) do
    [_value | eval_tail] = operate(tail, ev)
    eval_tail
  end

  defp operate([ "swap" | tail ], ev) when length(tail) < 2 do
    raise Forth.StackUnderflow
  end
  defp operate([ "swap" | [op1 | tail] ], ev) do
    if length(tail) == 1 do
      [ Enum.at(tail,0), op1 ]
    else
      [value | eval_tail] = operate(tail, ev)
      [ value, op1 | eval_tail]
    end
  end

  defp operate([ "over" | tail ], ev) when length(tail) < 2 do
    raise Forth.StackUnderflow
  end
  defp operate([ "over" | [op1 | tail] ], ev) do
    if length(tail) == 1 do
      [ Enum.at(tail,0), op1, Enum.at(tail,0) ]
    else
      [value1, value2 | eval_tail] = operate([op1 | tail], ev)
      [ value2, value1, value2 | eval_tail]
    end
  end

  defp operate(value, ev), do: value

  defp operate([value | tail], ev) when is_integer(value) do
    [value, operate(tail, ev)]
  end

  defp operate([value | tail], ev) do
    value
    |>get_operator(ev)
    |>List.flatten()
    |>then(fn x -> operate([x | tail], ev) end)
  end



  @doc """
  Return the current stack as a string with the element on top of the stack
  being the rightmost element in the string.
  """
  @spec format_stack(evaluator) :: String.t()
  def format_stack(ev = {table, custom}) do
    [{_, stack}] = :ets.lookup(table, "stack")
    Enum.join(stack, " ")
  end

  defmodule StackUnderflow do
    defexception []
    def message(_), do: "stack underflow"
  end

  defmodule InvalidWord do
    defexception word: nil
    def message(e), do: "invalid word: #{inspect(e.word)}"
  end

  defmodule UnknownWord do
    defexception word: nil
    def message(e), do: "unknown word: #{inspect(e.word)}"
  end

  defmodule DivisionByZero do
    defexception []
    def message(_), do: "division by zero"
  end
end
