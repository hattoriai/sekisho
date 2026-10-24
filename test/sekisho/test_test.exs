defmodule Sekisho.TestTest do
  use SekishoTest.DataCase, async: true
  use Sekisho.Test, permissions: SekishoTest.Permissions

  test "the assertions, and why they fail" do
    ana = user!()
    post = insert!(%Post{title: "mine", author_id: ana.id})
    other = insert!(%Post{title: "other", published: true})

    assert_allowed(scope(ana), :update, post)
    refute_allowed(scope(ana), :update, other)
    assert_allowed(scope(ana), :create, Post)
    assert_where_allowed(Post, scope(ana), :read, [post, other])

    error =
      assert_raise ExUnit.AssertionError, fn -> assert_allowed(scope(ana), :update, other) end

    assert error.message =~ "expected to be allowed :update"
    assert error.message =~ "not allowed :update on SekishoTest.Post #{other.id}"

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_where_allowed(Post, scope(ana), :update, [other])
      end

    assert error.message =~ "missing [#{other.id}], unexpected [#{post.id}]"
  end
end
