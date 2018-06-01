defmodule Drab.Live do
  @moduledoc """
  Drab Module to provide a live access and update of assigns of the template, which is currently
  rendered and displayed in the browser.

  The idea is to reuse your Phoenix templates and let them live, to make a possibility to update
  assigns on the living page, from the Elixir, without re-rendering the whole html. But because
  Drab tries to update the smallest amount of the html, there are some limitations, for example,
  it when updating the nested block it does not know the local variables used before. Please check
  out `Drab.Live.EExEngine` for more detailed description.

  Use `peek/2` to get the assign value, and `poke/2` to modify it directly in the DOM tree.

  Drab.Live uses the modified EEx Engine (`Drab.Live.EExEngine`) to compile the template and
  indicate where assigns were rendered. To enable it, rename the template you want to go live
  from extension `.eex` to `.drab`. Then, add Drab Engine to the template engines in `config.exs`:

      config :phoenix, :template_engines,
        drab: Drab.Live.Engine

  ### Avoiding using Drab
  If there is no need to use Drab with some expression, you may mark it with `nodrab/1` function.
  Such expressions will be treated as a "normal" Phoenix expressions and will not be updatable
  by `poke/2`.

      <p>Chapter <%= nodrab(@chapter_no) %>.</p>

  Since Elixir 1.6, you may use the special marker "/", which does exactly the same as `nodrab`:

      <p>Chapter <%/ @chapter_no %>.</p>

  #### The `@conn` case
  The `@conn` assign is often used in Phoenix templates. Drab considers it read-only, you can not
  update it with `poke/2`. And, because it is often quite hudge, may significantly increase
  the number of data sent to and back from the browser. This is why by default Drab trims `@conn`,
  leaving only the essential fields, by default `:private => :phoenix_endpoint`.

  This behaviour is configuable with `:live_conn_pass_through`. For example, if you want to preseve
  the specific assigns in the conn struct, mark them as true in the config:

      config :drab, :live_conn_pass_through, %{
        assigns: %{
          users: true
        },
        private: %{
          phoenix_endpoint: true
        }
      }


  ### Shared Commanders
  When the event is triggered inside the Shared Commander, defined with `drab-commander` attribute,
  all the updates will be done only withing this region. For example:

      <div drab-commander="DrabTestApp.Shared1Commander">
        <div><%= @assign1 %></div>
        <button drab-click="button_clicked">Shared 1</button>
      </div>
      <div drab-commander="DrabTestApp.Shared1Commander">
        <div><%= @assign1 %></div>
        <button drab-click="button_clicked">Shared 2</button>
      </div>

      defhandler button_clicked(socket, sender) do
        poke socket, assign1: "changed"
      end

  This will update only the div with `@assign1` in the same `<div drab-commander>` as the button.

  Please notice it works also for `peek` - it will return the proper value, depends where the event
  is triggered.

  ### Caching
  Browser communication is the time consuming operation and depends on the network latency. Because
  of this, Drab caches the values of assigns in the current event handler process, so they don't
  have to be re-read from the browser on every `poke` or `peek` operation. The cache is per
  process and lasts only during the lifetime of the event handler.

  This, event handler process keeps all the assigns value until it ends. Please notice that
  the other process may update the assigns on the page in the same time, by using broadcasting
  functions, when your event handler is still running. If you want to re-read the assigns cache,
  run `clean_cache/0`.

  ### Partials
  Function `poke/2` and `peek/2` works on the default template - the one rendered with
  the Controller. In case there are some child templates, rendered inside the main one, you need
  to specify the template name as a second argument of `poke/3` and `peek/3` functions.

  In case the template is not under the current (main) view, use `poke/4` and `peek/4` to specify
  the external view name.

  Assigns are archored within their partials. Manipulation of the assign outside the template it
  lives will raise `ArgumentError`. *Partials are not hierachical*, eg. modifying the assign
  in the main partial will not update assigns in the child partials, even if they exist there.

  #### Rendering partial templates in a runtime
  There is a possibility add the partial to the DOM tree in a runtime, using `render_to_string/2`
  helper:

      poke socket, live_partial1: render_to_string("partial1.html", color: "#aaaabb")

  But remember that assigns are assigned to the partials, so after adding it to the page,
  manipulation must be done within the added partial:

      poke socket, "partial1.html", color: "red"

  ### Evaluating expressions
  When the assign change is poked back to the browser, Drab need to re-evaluate all the expressions
  from the template which contain the given assign. This expressions are stored with the pattern
  in the cache DETS file.

  Because the expression must be run in the Phoenix environments, Drab does some `import` and `use`
  before. For example, it does `use Phoenix.HTML` and `import Phoenix.View`. It also imports
  the following modules from your application:

      import YourApplication.Router.Helpers
      import YourApplication.ErrorHelpers
      import YourApplication.Gettext

  If you renamed any of those modules in your application, you must tell Drab where to find it
  by adding the following entry to the `config.exs` file:

      config :drab, live_helper_modules: [Router.Helpers, ErrorHelpers, Gettext]

  Notice that the application name is derived automatically. Please check `Drab.Config.get/1`
  for more information on Drab setup.

  ### Limitions
  Because Drab must interpret the template, inject it's ID etc, it assumes that the template HTML
  is valid. There are also some limits for defining properties. See `Drab.Live.EExEngine` for
  a full description.

  ### Update Behaviours
  There are different behaviours of `Drab.Live`, depends on where the expression with the updated
  assign lives. For example, if the expression defines tag attribute, like
  `<span class="<%= @class %>">`, we don't want to re-render the whole tag, as it might override
  changes you made with other Drab module, or even with Javascript. Because of this, Drab finds
  the tag and updates only the required attributes.

  #### Plain Text
  If the expression in the template is given in any tag body, Drab will try to find the sourrounding
  tag and mark it with the attribute called `drab-ampere`. The attribute value is a hash of the
  previous buffer and the expression itself.

  Consider the template, with assign `@chapter_no` with initial value of `1` (given in render
  function in the controller, as usual):

      <p>Chapter <%= @chapter_no %>.</p>

  which renders to:

      <p drab-ampere="someid">Chapter 1.</p>

  This `drab-ampere` attribute is injected automatically by `Drab.Live.EExEngine`. Updating the
  `@chapter_no` assign in the Drab Commander, by using `poke/2`:

      chapter = peek(socket, :chapter_no)     # get the current value of `@chapter_no`
      poke(socket, chapter_no: chapter + 1)   # push the new value to the browser

  will change the `innerHTML` of the `<p drab-ampere="someid">` to "Chapter 2." by executing
  the following JS on the browser:

      document.querySelector('[drab-ampere=someid]').innerHTML = "Chapter 2."

  This is possible because during the compile phase, Drab stores the `drab-ampere` and
  the corresponding pattern in the cache DETS file (located in `priv/`).

  #### Injecting `<span>`
  In case, when Drab can't find the parent tag, it injects `<span>` in the generated html. For
  example, template like:

      Chapter <%= @chapter_no %>.

  renders to:

      Chapter <span drab-ampere="someid">1</span>.

  #### Attributes
  When the expression is defining the attribute of the tag, the behaviour if different. Let's
  assume there is a template with following html, rendered in the Controller with value of
  `@button` set to string `"btn-danger"`.

      <button class="btn <%= @button %>">

  It renders to:

      <button drab-ampere="someid" class="btn btn-danger">

  Again, you can see injected `drab-ampere` attribute. This allows Drab to indicate where
  to update the attribute. Pushing the changes to the browser with:

      poke socket, button: "btn btn-info"

  will result with updated `class` attribute on the given tag. It is acomplished by running
  `node.setAttribute("class", "btn btn-info")` on the browser.

  Notice that the pattern where your expression lives is preserved: you may update only the partials
  of the attribute value string.

  ##### Updating `value` attribute for `<input>` and `<textarea>`
  There is a special case for `<input>` and `<textarea>`: when poking attribute of `value`, Drab
  updates the corresponding `value` property as well.

  #### Properties
  Nowadays we deal more with node properties than attributes. This is why `Drab.Live` introduces
  the special syntax. When using the `@` sign at the beginning of the attribute name, it will
  be treated as a property.

      <button @hidden=<%= @hidden %>>

  Updating `@hidden` in the Drab Commander with `poke/2` will change the value of the `hidden`
  property (without dollar sign!), by sending the update javascript: `node['hidden'] = false`.

  You may also dig deeper into the Node properties, using dot - like in JavaScript - to bind
  the expression with the specific property. The good example is to set up `.style`:

      <button @style.backgroundColor=<%= @color %>>

  Additionally, Drab sets up all the properties defined that way when the page loads. Thanks to
  this, you don't have to worry about the initial value.

  Notice that `@property=<%= expression %>` *is the only available syntax*, you can not use
  string pattern or give more than one expression. Property must be stronly bind to the expression.

  The expression binded with the property *must be encodable to JSON*, so, for example, tuples
  are not allowed here. Please refer to `Jason` for more information about encoding JS.

  #### Scripts
  When the assign we want to change is inside the `<script></script>` tag, Drab will re-evaluate
  the whole script after assigment change. Let's say you don't want to use
  `@property=<%=expression%>` syntax to define the object property. You may want to render
  the javascript:

      <script>
        document.querySelectorAll("button").hidden = <%= @buttons_state %>
      </script>

  If you render the template in the Controller with `@button_state` set to `false`, the initial html
  will look like:

      <script drab-ampere="someid">
        document.querySelectorAll("button").hidden = false
      </script>

  Again, Drab injects some ID to know where to find its victim. After you `poke/2` the new value
  of `@button_state`, Drab will re-render the whole script with a new value and will send
  a request to re-evaluate the script. Browser will run something like:
  `eval("document.querySelectorAll(\"button\").hidden = true")`.

  Please notice this behaviour is disabled by default for safety. To enable it, use the following
  in your `config.exs`:

      config :drab, enable_live_scripts: true
  """

  @type result :: Phoenix.Socket.t() | Drab.Core.result() | no_return

  import Drab.Core
  require IEx
  alias Drab.Live.{Partial, Ampere}
  use DrabModule

  @impl true
  def js_templates(), do: ["drab.live.js"]

  @impl true
  def transform_socket(socket, payload, _state) do
    socket =
      Phoenix.Socket.assign(
        socket,
        :__sender_drab_commander_id,
        payload["drab_commander_id"] || "document"
      )

    Phoenix.Socket.assign(
      socket,
      :__sender_drab_commander_amperes,
      payload["drab_commander_amperes"] || []
    )
  end

  @doc """
  Returns the current value of the assign from the current (main) partial.

      iex> peek(socket, :count)
      42
      iex> peek(socket, :nonexistent)
      ** (ArgumentError) Assign @nonexistent not found in Drab EEx template

  Notice that this is a value of the assign, and not the value of any node property or attribute.
  Assign gets its value only while rendering the page or via `poke`. After changing the value
  of node attribute or property on the client side, the assign value will remain the same.
  """
  @spec peek(Phoenix.Socket.t(), atom) :: term | no_return
  def peek(socket, assign), do: peek(socket, nil, nil, assign)

  @doc """
  Like `peek/2`, but takes partial name and returns assign from that specified partial.

  Partial is taken from the current view.

      iex> peek(socket, "users.html", :count)
      42
  """
  # TODO: think if it is needed to sign/encrypt
  @spec peek(Phoenix.Socket.t(), String.t(), atom) :: term | no_return
  def peek(socket, partial, assign), do: peek(socket, nil, partial, assign)

  @doc """
  Like `peek/2`, but takes a view and a partial name and returns assign from that specified
  view/partial.

      iex> peek(socket, MyApp.UserView, "users.html", :count)
      42
  """
  @spec peek(Phoenix.Socket.t(), atom | nil, String.t() | nil, atom | String.t()) ::
          term | no_return
  def peek(socket, view, partial, assign) when is_atom(assign) do
    view = view || Drab.get_view(socket)
    hash = if partial, do: Partial.hash_for_view_and_name(view, partial), else: index(socket)

    current_assigns = assign_data_for_partial(socket, hash, partial, :assigns)

    case current_assigns |> Map.fetch(assign) do
      {:ok, val} ->
        val

      :error ->
        raise_assign_not_found(
          assign,
          Map.keys(current_assigns)
        )
    end
  end

  def peek(socket, view, partial, assign) when is_binary(assign) do
    peek(socket, view, partial, String.to_existing_atom(assign))
  end

  @doc """
  Updates the current page in the browser with the new assign value.

  Works inside the main partial - the one rendered in the controller - only. Does not touch children
  partials, even if they contain the given assign.

  Raises `ArgumentError` when assign is not found within the partial.
  Returns untouched socket or tuple {:error, description} or {:timeout, description}

      iex> poke(socket, count: 42)
      %Phoenix.Socket{ ...
  """
  @spec poke(Phoenix.Socket.t(), Keyword.t()) :: result
  def poke(socket, assigns) do
    # do_poke(socket, nil, nil, assigns, &Drab.Core.exec_js/2)
    poke(socket, nil, nil, assigns)
  end

  @doc """
  Like `poke/2`, but limited only to the given partial name.

      iex> poke(socket, "user.html", name: "Bożywój")
      %Phoenix.Socket{ ...
  """
  @spec poke(Phoenix.Socket.t(), String.t() | nil, Keyword.t()) :: result
  def poke(socket, partial, assigns) do
    # do_poke(socket, nil, partial, assigns, &Drab.Core.exec_js/2)
    poke(socket, nil, partial, assigns)
  end

  @doc """
  Like `poke/3`, but searches for the partial within the given view.

      iex> poke(socket, MyApp.UserView, "user.html", name: "Bożywój")
      %Phoenix.Socket{ ...
  """
  @spec poke(Phoenix.Socket.t(), atom | nil, String.t() | nil, Keyword.t()) :: result
  def poke(socket, view, partial, assigns) do
    do_poke(socket, view, partial, assigns, &Drab.Core.exec_js/2)
  end

  @doc """
  Broadcasting version of `poke/2`.

  Please notice that broadcasting living assigns makes sense only for the pages, which was rendered
  with the same templates.

  Always returns socket.

      iex> broadcast_poke(socket, count: 42)
      %Phoenix.Socket{ ...
  """
  @spec broadcast_poke(Drab.Core.subject(), Keyword.t()) :: result
  def broadcast_poke(socket, assigns) do
    # do_poke(socket, nil, nil, assigns, &Drab.Core.broadcast_js/2)
    broadcast_poke(socket, nil, nil, assigns)
  end

  @doc """
  Like `broadcast_poke/2`, but limited only to the given partial name.

      iex> broadcast_poke(socket, "user.html", name: "Bożywój")
      %Phoenix.Socket{ ...
  """
  @spec broadcast_poke(Drab.Core.subject(), String.t() | nil, Keyword.t()) :: result
  def broadcast_poke(socket, partial, assigns) do
    # do_poke(socket, nil, partial, assigns, &Drab.Core.broadcast_js/2)
    broadcast_poke(socket, nil, partial, assigns)
  end

  @doc """
  Like `broadcast_poke/3`, but searches for the partial within the given view.

      iex> broadcast_poke(socket, MyApp.UserView, "user.html", name: "Bożywój")
      %Phoenix.Socket{ ...
  """
  @spec broadcast_poke(Drab.Core.subject(), atom | nil, String.t() | nil, Keyword.t()) :: result
  def broadcast_poke(socket, view, partial, assigns) do
    # if socket.assigns.__broadcast_topic =~ "same_path:" ||
    #    socket.assigns.__broadcast_topic =~ "action:" do
    do_poke(socket, view, partial, assigns, &Drab.Core.broadcast_js/2)
    #  else
    #   raise ArgumentError,
    #     message: """
    #     Broadcasting `poke` makes sense only with `:same_path` or `:same_action` options.

    #     You tried: `#{socket.assigns.__broadcast_topic}`
    #     """
    #  end
  end

  @spec do_poke(String.t(), atom, String.t(), Keyword.t(), function) :: result
  defp do_poke(socket, view, partial_name, assigns, function) do
    assigns = Enum.into(assigns, %{})
    partial = Partial.hash_for_view_and_name(view, partial_name)
    amperes_to_update = Partial.amperes_for_assigns(partial, Map.keys(assigns))
    html =
      view
      |> Phoenix.View.render_to_string(Partial.template_filename(view, partial), assigns)
      |> Floki.parse()

    update_javascripts =
      html
      |> update_javascripts(partial, amperes_to_update)
      |> Enum.sort_by(&has_amperes/1)
    assign_updates = assign_updates_js(assigns, partial, "document")
    all_javascripts = (assign_updates ++ update_javascripts) |> Enum.uniq()

    case function.(socket, all_javascripts |> Enum.join(";")) do
      {:ok, _} ->
        socket
      other ->
        other
    end
  end

  @spec do_poke(Drab.Core.subject(), atom | nil, String.t() | nil, Keyword.t(), function) ::
          result
  defp do_poke(socket, view, partial_name, assigns, function) do
    if Enum.member?(Keyword.keys(assigns), :conn) do
      raise ArgumentError,
        message: """
        assign @conn is read only.
        """
    end

    view = view || Drab.get_view(socket)

    partial =
      if partial_name, do: Partial.hash_for_view_and_name(view, partial_name), else: index(socket)

    current_assigns = assign_data_for_partial(socket, partial, partial_name, :assigns)

    current_assigns_keys = Map.keys(current_assigns)
    assigns_to_update = Enum.into(assigns, %{})
    assigns_to_update_keys = Map.keys(assigns_to_update)

    for as <- assigns_to_update_keys do
      unless Enum.find(current_assigns_keys, fn key -> key == as end) do
        raise_assign_not_found(as, current_assigns_keys)
      end
    end

    updated_assigns =
      current_assigns
      |> Enum.into([])
      |> Keyword.merge(assigns)

    amperes_to_update = Partial.amperes_for_assigns(partial, assigns_to_update_keys)

    # update only those which are in shared commander
    amperes_to_update =
      case socket.assigns[:__sender_drab_commander_amperes] do
        [] ->
          amperes_to_update

        sender_drab_commader_amperes ->
          intersection(amperes_to_update, sender_drab_commader_amperes)
      end

    shared_commander_id = drab_commander_id(socket)

    nodrab_assigns =
      socket |> assign_data_for_partial(partial, partial_name, :nodrab) |> Enum.into([])

    all_assigns = Keyword.merge(nodrab_assigns, updated_assigns)

    html =
      view
      |> Phoenix.View.render_to_string(Partial.template_filename(view, partial), all_assigns)
      |> Floki.parse()

    # TODO: this is a very naive way of sorting JS. Small goes first.
    update_javascripts =
      html
      |> update_javascripts(partial, amperes_to_update)
      |> Enum.sort_by(&has_amperes/1)

    assign_updates = assign_updates_js(assigns_to_update, partial, shared_commander_id)
    all_javascripts = (assign_updates ++ update_javascripts) |> Enum.uniq()

    # IO.inspect update_javascripts
    # IO.inspect(all_javascripts)

    case function.(socket, all_javascripts |> Enum.join(";")) do
      {:ok, _} ->
        update_assigns_cache(socket, assigns_to_update, partial, shared_commander_id)
        socket

      other ->
        other
    end
  end

  defp update_javascripts(html, partial, amperes_to_update) do
    for ampere <- amperes_to_update,
        %Ampere{gender: gender, tag: tag, attribute: prop_or_attr} <-
          Partial.partial(partial).amperes[ampere] do
      case gender do
        :html -> update_html_js(html, ampere, tag)
        :attr -> update_attr_js(html, ampere, prop_or_attr)
        :prop -> update_prop_js(html, ampere, prop_or_attr)
      end
    end
  end

  defp update_html_js(html, ampere, tag) do
    case Floki.find(html, "[drab-ampere='#{ampere}']") do
      [{_, _, value}] ->
        new_value = Floki.raw_html(value)

        case {tag, Drab.Config.get(:enable_live_scripts)} do
          {"script", false} ->
            nil

          {_, _} ->
            "Drab.update_tag(#{encode_js(tag)}, #{encode_js(ampere)}, #{encode_js(new_value)})"
        end

      _ ->
        nil
    end
  end

  defp update_attr_js(html, ampere, attr) do
    case Floki.attribute(html, "[drab-ampere='#{ampere}']", attr) do
      [new_value] ->
        "Drab.update_attribute(#{encode_js(ampere)}, #{encode_js(attr)}, #{encode_js(new_value)})"

      _ ->
        nil
    end
  end

  defp update_prop_js(html, ampere, prop) do
    case Floki.attribute(html, "[drab-ampere='#{ampere}']", "@#{String.downcase(prop)}") do
      [new_value] ->
        "Drab.update_property(#{encode_js(ampere)}, #{encode_js(prop)}, #{encode_js(new_value)})"

      _ ->
        nil
    end
  end

  @spec has_amperes(String.t() | nil) :: integer
  defp has_amperes(nil), do: 0

  defp has_amperes(string) do
    length(String.split(string, "drab-ampere")) - 1
  end

  @spec intersection(list, list) :: list
  defp intersection(list1, list2) do
    MapSet.intersection(MapSet.new(list1), MapSet.new(list2))
    |> MapSet.to_list()
  end

  @doc """
  Returns a list of the assigns for the main partial.

  Examples:

      iex> Drab.Live.assigns(socket)
      [:welcome_text]
  """
  @spec assigns(Phoenix.Socket.t()) :: list
  def assigns(socket) do
    assigns(socket, nil, nil)
  end

  @doc """
  Like `assigns/1` but will return the assigns for a given `partial` instead of the main partial.

  Examples:

      iex> assigns(socket, "user.html")
      [:name, :age, :email]
  """
  @spec assigns(Phoenix.Socket.t(), String.t() | nil) :: list
  def assigns(socket, partial) do
    assigns(socket, nil, partial)
  end

  @doc """
  Like `assigns/2`, but returns the assigns for a given combination of a `view` and a `partial`.

      iex> assigns(socket, MyApp.UserView, "user.html")
      [:name, :age, :email]
  """
  @spec assigns(Phoenix.Socket.t(), atom | nil, String.t() | nil) :: list
  def assigns(socket, view, partial) do
    view = view || Drab.get_view(socket)

    partial_hash =
      if partial, do: Partial.hash_for_view_and_name(view, partial), else: index(socket)

    Partial.all_assigns(partial_hash)
  end

  @doc """
  Cleans up the assigns cache for the current event handler process.

  Should be used when you want to re-read the assigns from the browser, for example when the other
  process could update the living assigns in the same time as current event handler runs.
  """
  @spec clean_cache() :: term
  def clean_cache() do
    Process.put(:__assigns_and_index, nil)
  end

  @spec assign_updates_js(map, String.t(), String.t()) :: [String.t()]
  # TODO: refactor
  defp assign_updates_js(assigns, partial, "document") do
    Enum.map(assigns, fn {k, v} ->
      "__drab.assigns[#{Drab.Core.encode_js(partial)}][#{Drab.Core.encode_js(k)}] = {document: '#{
        Drab.Live.Crypto.encode64(v)
      }'}"
    end)
  end

  defp assign_updates_js(assigns, partial, shared_commander_id) do
    Enum.map(assigns, fn {k, v} ->
      "__drab.assigns[#{Drab.Core.encode_js(partial)}][#{Drab.Core.encode_js(k)}][#{
        Drab.Core.encode_js(shared_commander_id)
      }] = '#{Drab.Live.Crypto.encode64(v)}'"
    end)
  end

  @spec drab_commander_id(Phoenix.Socket.t()) :: String.t()
  defp drab_commander_id(socket) do
    socket.assigns[:__sender_drab_commander_id] || "document"
  end

  @spec assign_data_for_partial(
          Phoenix.Socket.t(),
          String.t() | atom,
          String.t() | atom,
          atom
        ) :: map | no_return
  defp assign_data_for_partial(socket, partial, partial_name, assigns_type) do
    assigns =
      case socket
           |> ampere_assigns(assigns_type)
           |> Map.fetch(partial) do
        {:ok, val} ->
          val

        :error ->
          raise_partial_not_found(partial_name)
      end

    assigns =
      for {k, v} <- assigns, into: %{} do
        {
          k,
          case v[drab_commander_id(socket)] do
            # global value
            nil ->
              v["document"]

            x ->
              x
          end
        }
      end

    assigns
    |> Enum.map(&apply_conn_merge/1)
    |> Enum.into(%{})
  end

  defp apply_conn_merge({:conn, v}), do: {:conn, Drab.Live.Assign.merge(%Plug.Conn{}, v)}
  defp apply_conn_merge(other), do: other

  @spec ampere_assigns(Phoenix.Socket.t(), atom) :: map
  defp ampere_assigns(socket, assigns_type) do
    assigns_and_index(socket)[assigns_type]
  end

  @spec index(Phoenix.Socket.t()) :: String.t()
  defp index(socket) do
    assigns_and_index(socket)[:index]
  end

  @spec assigns_and_index(Phoenix.Socket.t()) :: map
  defp assigns_and_index(socket) do
    case {Process.get(:__drab_event_handler_or_callback), Process.get(:__assigns_and_index)} do
      {true, nil} ->
        decrypted = decrypted_from_browser(socket)
        Process.put(:__assigns_and_index, decrypted)
        decrypted

      {true, value} ->
        value

      # the other case (it is test or IEx session)
      {_, _} ->
        decrypted_from_browser(socket)
    end
  end

  @spec update_assigns_cache(Phoenix.Socket.t(), map, String.t(), String.t()) :: term() | nil
  defp update_assigns_cache(socket, assigns_to_update, partial_hash, shared_commander_id) do
    cache = assigns_and_index(socket)

    updated_assigns =
      for {assign_name, assign_value} <- assigns_to_update, into: %{} do
        {assign_name, %{shared_commander_id => assign_value}}
      end

    cached_assigns = cache[:assigns]
    cache_for_partial = cached_assigns[partial_hash]
    updated_assigns_for_partial = Map.merge(cache_for_partial, updated_assigns)
    updated_assigns_cache = Map.put(cached_assigns, partial_hash, updated_assigns_for_partial)
    Process.put(:__assigns_and_index, %{cache | assigns: updated_assigns_cache})
  end

  defp decrypted_from_browser(socket) do
    {:ok, ret} =
      exec_js(socket, "({assigns: __drab.assigns, nodrab: __drab.nodrab, index: __drab.index})")

    %{
      :assigns => decrypted_assigns(ret["assigns"]),
      :nodrab => decrypted_assigns(ret["nodrab"]),
      :index => ret["index"]
    }
  end

  @spec decrypted_assigns(map) :: map
  defp decrypted_assigns(assigns) do
    for {partial, partial_assigns} <- assigns, into: %{} do
      {partial,
       for {assign_name, assign_values} <- partial_assigns, into: %{} do
         {
           String.to_existing_atom(assign_name),
           for {shared_commander_id, assign_value} <- assign_values, into: %{} do
             {shared_commander_id, Drab.Live.Crypto.decode64(assign_value)}
           end
         }
       end}
    end
  end

  @spec raise_assign_not_found(atom, list) :: no_return
  defp raise_assign_not_found(assign, current_keys) do
    raise ArgumentError,
      message: """
      assign @#{assign} not found in Drab EEx template.

      Please make sure all proper assigns have been set. If this
      is a child template, ensure assigns are given explicitly by
      the parent template as they are not automatically forwarded.

      Available assigns:
      #{inspect(current_keys)}
      """
  end

  @spec raise_partial_not_found(String.t() | nil) :: no_return
  def raise_partial_not_found(path) do
    raise ArgumentError,
      message: """
      template `#{path || "main"}` not found.

      Please make sure this partial exists and has been compiled
      by Drab (has *.drab extension).

      If you want to poke assign to the partial which belong to
      the other view, you need to specify the view name in `poke/4`.
      """
  end
end
