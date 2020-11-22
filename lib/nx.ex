defmodule Nx do
  @moduledoc """
  Numerical Elixir.

  A collection of functions and data types to work
  with Numerical Elixir.
  """

  defmodule Tensor do
    defstruct [:data, :type, :shape]
  end

  # A macro that allows us to writes all possibles match types
  # in the most efficient format. This is done by looking at @0,
  # @1, etc and replacing them by currently matched type at the
  # given position. In other words, this:
  #
  #    combine_types [input_type, output_type] do
  #      for <<seg::@0 <- data>>, into: <<>>, do: <<seg+right::@1>>
  #    end
  #
  # Is compiled into:
  #
  #    for <<seg::float-size(...) <- data>>, into: <<>>, do: <<seg+right::float-size(...)>>
  #
  # for all possible valid types between input and input types.
  # @0 mataches to `input_type`, @1 to `output_type`, and so on.
  #
  # In particular, note that a rolled out case such as:
  #
  #     for <<seg::size(size)-signed-integer <- data>>, into: <<>> do
  #       <<seg+number::signed-integer-size(size)>>
  #     end
  #
  # is twice as fast and uses twice less memory than:
  #
  #     for <<seg::size(size)-signed-integer <- data>>, into: <<>> do
  #       case output_type do
  #         {:s, size} ->
  #           <<seg+number::signed-integer-size(size)>>
  #         {:f, size} ->
  #           <<seg+number::float-size(size)>>
  #         {:u, size} ->
  #           <<seg+number::unsigned-integer-size(size)>>
  #       end
  #     end
  #
  defmacrop match_types([_ | _] = args, do: block) do
    sizes = Macro.generate_arguments(length(args), __MODULE__)
    matches = match_types(sizes)

    clauses =
      Enum.flat_map(matches, fn match ->
        block =
          Macro.prewalk(block, fn
            {:@, _, [pos]} when is_integer(pos) ->
              {type, size} = Enum.fetch!(match, pos)
              quote do: size(unquote(size))-unquote(type_to_bin_modifier(type))

            other ->
              other
          end)

        quote do
          {unquote_splicing(match)} -> unquote(block)
        end
      end)

    quote do
      case {unquote_splicing(args)}, do: unquote(clauses)
    end
  end

  @all_types [:s, :f, :u]

  defp match_types([h | t]) do
    for type <- @all_types, t <- match_types(t) do
      [{type, h} | t]
    end
  end

  defp match_types([]), do: [[]]

  defp type_to_bin_modifier(:s), do: quote(do: signed-integer)
  defp type_to_bin_modifier(:u), do: quote(do: unsigned-integer)
  defp type_to_bin_modifier(:f), do: quote(do: float)

  @doc """
  Builds a tensor.

  The argument is either a number or a boolean, which means the tensor is
  a scalar (zero-dimentions), a list of those (the tensor is a vector) or
  a list of n-lists of those, leading to n-dimensional tensors.

  ## Examples

  A number or a boolean returns a tensor of zero dimensions:

      iex> t = Nx.tensor(0)
      iex> Nx.to_bitstring(t)
      <<0::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {}

      iex> t = Nx.tensor(true)
      iex> Nx.to_bitstring(t)
      <<1::1>>
      iex> Nx.type(t)
      {:u, 1}
      iex> Nx.shape(t)
      {}

  Giving a list returns a vector (an one-dimensional tensor):

      iex> t = Nx.tensor([1, 2, 3])
      iex> Nx.to_bitstring(t)
      <<1::64, 2::64, 3::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {3}

      iex> t = Nx.tensor([1.2, 2.3, 3.4, 4.5])
      iex> Nx.to_bitstring(t)
      <<1.2::64-float, 2.3::64-float, 3.4::64-float, 4.5::64-float>>
      iex> Nx.type(t)
      {:f, 64}
      iex> Nx.shape(t)
      {4}

  The type can be explicitly given. Integers and floats
  bigger than the given size overlap:

      iex> t = Nx.tensor([300, 301, 302], type: {:s, 8})
      iex> Nx.to_bitstring(t)
      <<44::8, 45::8, 46::8>>
      iex> Nx.type(t)
      {:s, 8}

      iex> t = Nx.tensor([1.2, 2.3, 3.4], type: {:f, 32})
      iex> Nx.to_bitstring(t)
      <<1.2::32-float, 2.3::32-float, 3.4::32-float>>
      iex> Nx.type(t)
      {:f, 32}

  An empty list defaults to floats:

      iex> t = Nx.tensor([])
      iex> Nx.to_bitstring(t)
      <<>>
      iex> Nx.type(t)
      {:f, 64}

  Mixed types get the highest precision type:

      iex> t = Nx.tensor([true, 2, 3.0])
      iex> Nx.to_bitstring(t)
      <<1.0::float-64, 2.0::float-64, 3::float-64>>
      iex> Nx.type(t)
      {:f, 64}

  Multi-dimensional tensors are also possible:

      iex> t = Nx.tensor([[1, 2, 3], [4, 5, 6]])
      iex> Nx.to_bitstring(t)
      <<1::64, 2::64, 3::64, 4::64, 5::64, 6::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {2, 3}

      iex> t = Nx.tensor([[1, 2], [3, 4], [5, 6]])
      iex> Nx.to_bitstring(t)
      <<1::64, 2::64, 3::64, 4::64, 5::64, 6::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {3, 2}

      iex> t = Nx.tensor([[[1, 2], [3, 4], [5, 6]], [[-1, -2], [-3, -4], [-5, -6]]])
      iex> Nx.to_bitstring(t)
      <<1::64, 2::64, 3::64, 4::64, 5::64, 6::64, -1::64, -2::64, -3::64, -4::64, -5::64, -6::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {2, 3, 2}

  ## Options

    * `:type` - sets the type of the tensor. If one is not given,
      one is automatically inferred based on the input. See `Nx.Type`
      and `Nx.Type.infer/1` for information.

  """
  def tensor(arg, opts \\ []) do
    type = opts[:type] || Nx.Type.infer(arg)
    Nx.Type.validate!(type)
    {dimensions, data} = flatten(arg, type)
    %Tensor{shape: dimensions, type: type, data: data}
  end

  defp flatten(list, type) when is_list(list) do
    {dimensions, acc} = flatten_list(list, type, [], [])

    {dimensions |> Enum.reverse() |> List.to_tuple(),
     acc |> Enum.reverse() |> :erlang.list_to_bitstring()}
  end

  defp flatten(other, type), do: {{}, scalar_to_binary(other, type)}

  defp flatten_list([], _type, dimensions, acc) do
    {[0 | dimensions], acc}
  end

  defp flatten_list([head | rest], type, parent_dimensions, acc) when is_list(head) do
    {child_dimensions, acc} = flatten_list(head, type, [], acc)

    {n, acc} =
      Enum.reduce(rest, {1, acc}, fn list, {count, acc} ->
        case flatten_list(list, type, [], acc) do
          {^child_dimensions, acc} ->
            {count + 1, acc}

          {other_dimensions, _acc} ->
            raise ArgumentError,
                  "cannot build tensor because lists have different shapes, got " <>
                    inspect(List.to_tuple(child_dimensions)) <>
                    " at position 0 and " <>
                    inspect(List.to_tuple(other_dimensions)) <> " at position #{count + 1}"
        end
      end)

    {child_dimensions ++ [n | parent_dimensions], acc}
  end

  defp flatten_list(list, type, dimensions, acc) do
    {[length(list) | dimensions], Enum.reduce(list, acc, &[scalar_to_binary(&1, type) | &2])}
  end

  defp scalar_to_binary(true, type), do: scalar_to_binary(1, type)
  defp scalar_to_binary(false, type), do: scalar_to_binary(0, type)
  defp scalar_to_binary(value, type), do: match_types([type], do: <<value::@0>>)

  @doc """
  Returns the type of the tensor.

  See `Nx.Type` for more information.
  """
  def type(%Tensor{type: type}), do: type

  @doc """
  Returns the shape of the tensor as a tuple.

  The size of this tuple gives the rank of the tensor.
  """
  def shape(%Tensor{shape: shape}), do: shape

  @doc """
  Returns the rank of a tensor.
  """
  def rank(%Tensor{shape: shape}), do: tuple_size(shape)

  @doc """
  Returns the underlying tensor as a bitstring.

  The bitstring is returned as is (which is row-major).
  """
  def to_bitstring(%Tensor{data: data}), do: data

  @doc """
  Adds two tensors together.

  If a scalar is given, they are kept as scalars.
  If a tensor and a scalar are given, it adds the
  scalar to all entries in the tensor.

  ## Examples

  ### Adding scalars

      iex> Nx.add(1, 2)
      3
      iex> Nx.add(1, 2.2)
      3.2

  ### Adding a scalar to a tensor

      iex> t = Nx.add(Nx.tensor([1, 2, 3]), 1)
      iex> Nx.to_bitstring(t)
      <<2::64, 3::64, 4::64>>

  Given a float scalar converts the tensor to a float:

      iex> t = Nx.add(Nx.tensor([1, 2, 3]), 1.0)
      iex> Nx.to_bitstring(t)
      <<2.0::float-64, 3.0::float-64, 4.0::float-64>>

      iex> t = Nx.add(Nx.tensor([1.0, 2.0, 3.0]), 1)
      iex> Nx.to_bitstring(t)
      <<2.0::float-64, 3.0::float-64, 4.0::float-64>>

      iex> t = Nx.add(Nx.tensor([1.0, 2.0, 3.0], type: {:f, 32}), 1)
      iex> Nx.to_bitstring(t)
      <<2.0::float-32, 3.0::float-32, 4.0::float-32>>

  The size of the tensor will grow if the scalar is bigger than
  the tensor size. But, if smaller, it overflows:

      iex> t = Nx.add(Nx.tensor([true, false, true]), 1)
      iex> Nx.to_bitstring(t)
      <<0::1, 1::1, 0::1>>

      iex> t = Nx.add(Nx.tensor([true, false, true]), 10)
      iex> Nx.to_bitstring(t)
      <<11::8, 10::8, 11::8>>

  Unsigned tensors become signed and double their size if a
  negative number is given:

      iex> t = Nx.add(Nx.tensor([0, 1, 2], type: {:u, 8}), -1)
      iex> Nx.to_bitstring(t)
      <<-1::16, 0::16, 1::16>>

  """
  def add(left, right)

  def add(left, right) when is_number(left) and is_number(right), do: :erlang.+(left, right)

  def add(%Tensor{data: data, type: input_type} = left, right) when is_number(right) do
    output_type = Nx.Type.merge_scalar(input_type, right)

    data =
      # match_types is a macro, see its definition at the top of this module.
      match_types [input_type, output_type] do
        for <<seg::@0 <- data>>, into: <<>>, do: <<seg+right::@1>>
      end

    %{left | data: data, type: output_type}
  end
end