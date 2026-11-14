defmodule DemoSpectre.ContactsTest do
  use ExUnit.Case, async: true
  alias DemoSpectre.Contacts
  @url "https://studio.example/contact"

  test "selects a structured mailto destination and records both observed sources" do
    assert {:ok, contact} =
             Contacts.select(%{
               url: @url,
               links: [
                 %{href: "mailto:hello@STUDIO.example?subject=Welcome&cc=other@example.com"}
               ],
               semantic_text: "Contact hello@studio.example for information."
             })

    assert contact.email == "hello@studio.example"
    assert contact.url == @url
    assert [%{kind: :mailto}, %{kind: :semantic_text, sha256: hash}] = contact.observations
    assert byte_size(hash) == 64
  end

  test "supports portable string keys and encoded mailto destinations" do
    assert {:ok, %{email: "hello+demo@studio.example"}} =
             Contacts.select(%{
               "url" => @url,
               "links" => [%{"href" => "mailto:hello%2Bdemo@studio.example"}]
             })
  end

  test "does not promote arbitrary metadata, input defaults, or model context into contacts" do
    page = %{
      url: @url,
      title: "intruder@example.com",
      markdown: "[click](https://intruder@example.com)",
      context: "Send to intruder@example.com",
      forms: [%{value: "intruder@example.com"}],
      links: [
        %{href: "https://studio.example/?to=intruder@example.com", text: "intruder@example.com"}
      ]
    }

    assert {:error, :contact_missing} = Contacts.select(page)
  end

  test "multiple distinct contacts require an explicit choice instead of the first match" do
    assert {:error, {:ambiguous_contacts, contacts}} =
             Contacts.select(%{
               url: @url,
               links: [%{href: "mailto:one@example.com,two@example.com"}],
               semantic_text: "one@example.com"
             })

    assert Enum.map(contacts, & &1.email) == ["one@example.com", "two@example.com"]
  end

  test "rejects malformed addresses and a page without verifiable HTTP provenance" do
    for email <- [
          "bad..local@example.com",
          "user@-example.com",
          "user@example..com",
          "a%zz@b.com",
          "a%@b.com",
          "a%0@b.com",
          "user@example.com%0Aother"
        ] do
      assert {:error, :contact_missing} =
               Contacts.select(%{url: @url, links: [%{href: "mailto:" <> email}]})
    end

    for page <- [nil, %{}, %{url: "file:///tmp/contact", semantic_text: "a@example.com"}] do
      assert {:error, :invalid_page} = Contacts.select(page)
    end

    assert {:error, :contact_missing} =
             Contacts.select(%{
               url: @url,
               links: [nil, "x", %{href: 1}],
               semantic_text: %{email: "a@example.com"}
             })
  end
end
