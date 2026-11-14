defmodule DemoSpectre.Contacts do
  @moduledoc """
  Extracts observed contacts from Lens' structured page projection.

  Only mailto destinations and semantic page text contribute candidates. Model
  context, form values, arbitrary metadata and inspected Elixir terms do not.
  An observation proves presence on the page, not recipient authority: ambiguous
  pages stop the demo and the selected contact still requires GAM consent.
  """

  @email ~r/\A[A-Za-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z/
  @text_email ~r/(?<![A-Za-z0-9.!#$%&'*+\/=?^_`{|}~@-])[A-Za-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?![A-Za-z0-9@-])/
  @type contact :: %{email: String.t(), url: String.t(), observations: [map()]}

  @doc "Selects one observed contact or reports missing/ambiguous page contacts."
  @spec select(map()) ::
          {:ok, contact()}
          | {:error, :contact_missing | :invalid_page | {:ambiguous_contacts, [contact()]}}
  def select(page) when is_map(page) do
    with url when is_binary(url) <- field(page, :url),
         %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) <-
           URI.parse(url) do
      contacts =
        (link_observations(field(page, :links)) ++ text_observations(field(page, :semantic_text)))
        |> Enum.group_by(& &1.email, & &1.source)
        |> Enum.map(fn {email, observations} ->
          %{email: email, url: url, observations: Enum.uniq(observations)}
        end)
        |> Enum.sort_by(& &1.email)

      case contacts do
        [] -> {:error, :contact_missing}
        [contact] -> {:ok, contact}
        contacts -> {:error, {:ambiguous_contacts, contacts}}
      end
    else
      _ -> {:error, :invalid_page}
    end
  end

  def select(_), do: {:error, :invalid_page}

  @spec link_observations(term()) :: [map()]
  defp link_observations(links) when is_list(links) do
    Enum.flat_map(links, fn link ->
      case field(link, :href) do
        href when is_binary(href) -> mailto_observations(href)
        _ -> []
      end
    end)
  end

  defp link_observations(_), do: []

  @spec mailto_observations(String.t()) :: [map()]
  defp mailto_observations(href) do
    case URI.parse(href) do
      %URI{scheme: scheme, path: path} when scheme in ["mailto", "MAILTO"] and is_binary(path) ->
        if Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, path) do
          []
        else
          path
          |> URI.decode()
          |> String.split(",", trim: true)
          |> Enum.flat_map(&observation(&1, %{kind: :mailto, href: "mailto:" <> path}))
        end

      _ ->
        []
    end
  rescue
    ArgumentError -> []
  end

  @spec text_observations(term()) :: [map()]
  defp text_observations(text) when is_binary(text) do
    source = %{
      kind: :semantic_text,
      sha256: Base.encode16(:crypto.hash(:sha256, text), case: :lower)
    }

    @text_email |> Regex.scan(text) |> Enum.flat_map(fn [email] -> observation(email, source) end)
  end

  defp text_observations(_), do: []

  @spec observation(String.t(), map()) :: [map()]
  defp observation(email, source) do
    email = String.trim(email)

    if byte_size(email) <= 254 and Regex.match?(@email, email) do
      [local, domain] = String.split(email, "@")
      labels = String.split(domain, ".")

      if byte_size(local) <= 64 and not String.starts_with?(local, ".") and
           not String.ends_with?(local, ".") and not String.contains?(local, "..") and
           Enum.all?(
             labels,
             &(byte_size(&1) in 1..63 and not String.starts_with?(&1, "-") and
                 not String.ends_with?(&1, "-"))
           ) do
        [%{email: local <> "@" <> String.downcase(domain), source: source}]
      else
        []
      end
    else
      []
    end
  end

  @spec field(term(), atom()) :: term()
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil
end
