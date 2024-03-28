"""
Created in June, 2022 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
by team
[toolips](https://github.com/orgs/ChifiSource/teams/toolips)
This software is MIT-licensed.
### ToolipsSession
**Extension for:**
- [Toolips](https://github.com/ChifiSource/Toolips.jl) \
This module provides the capability to make web-pages interactive by simply
adding the Session extension to your ServerTemplate before starting. There are
also methods contained for modifying Servables.
##### Module Composition
- [**ToolipsSession**](https://github.com/ChifiSource/ToolipsSession.jl)
"""
module ToolipsSession
using Toolips
import Toolips: Servable, AbstractComponent, AbstractComponentModifier, style!, next!
import Toolips: AbstractRoute, kill!, AbstractConnection, script, write!, route!, on_start
import Base: setindex!, getindex, push!, iterate
using Dates
# using WebSockets: serve, writeguarded, readguarded, @wslog, open, HTTP, Response, ServerWS
include("Modifier.jl")

#==
Hello, welcome to the Session source. Here is an overview of the organization
that might help you out:
------------------
- ToolipsSession.jl
--- linker
--- Session extension
--- kill!
--- clear!
--- on
--- KeyMap
--- bind!
--- script interface
--- rpc
------------------
- Modifier.jl
--- ComponentModifiers
--- Modifier functions
------------------
==#

function document_linker(c::Connection)
    s::String = getpost(c)
    ip::String = getip(c)
    reftag::UnitRange{Int64} = findfirst("â•ƒCM", s)
    reftagend = findnext("â•ƒ", s, maximum(reftag))
    ref_r::UnitRange{Int64} = maximum(reftag) + 1:minimum(reftagend) - 1
    ref::String = s[ref_r]
    s = replace(s, "â•ƒCM" => "", "â•ƒ" => "")
    cm = ComponentModifier(s)
    c[:Session].events[ip][ref](cm)
    f(cm)
    write!(c, " ", cm)
    cm = nothing
    nothing::Nothing
end
#== WIP socket server
abstract type SocketServer <: Toolips.ServerTemplate end

function start!(mod::Module = server_cli(Main.ARGS), from::Type{SocketServer}; ip::IP4 = ip4_cli(Main.ARGS), 
    router_threads::Int64 = 1, threads::Int64 = 1)
    IP = Sockets.InetAddr(parse(IPAddr, ip.ip), ip.port)
    server::Sockets.TCPServer = Sockets.listen(IP)
    mod.server = server
    routefunc::Function, pm::ProcessManager = generate_router(mod, router_threads)
    if router_threads == 1
        w = pm["$mod router"]
        serve_router = @async HTTP.listen(routefunc, ip.ip, ip.port, server = server)
        w.task = serve_router
        w.active = true
        return(pm)::ProcessManager
    end
end

begin
    function handler(req)
        println("someone landed")
        open("ws://127.0.0.1:8000") do ws_client
            
        end
    end
    function wshandler(ws_server)
        println("websockethandled")
        writeguarded(ws_server, "Hello")
        readguarded(ws_server)
    end
    serverWS = ServerWS(handler, wshandler)
    servetask = @async with_logger(WebSocketLogger()) do
        serve(serverWS, port = 8000)
        "Task ended"
    end
end
==#

abstract type AbstractEvent <: Servable end

mutable struct Event <: AbstractEvent
    f::Function
    name::String
end

mutable struct Session <: Toolips.AbstractExtension
    active_routes::Vector{String}
    events::Dict{String, Vector{Event}}
    iptable::Dict{String, Dates.DateTime}
    peers::Dict{String, Vector{String}}
    gc::Int64
    function Session(active_routes::Vector{String} = ["/"])
        events = Dict{String, Dict{String, Function}}()
        peers::Dict{String, Vector{String}} = Dict{String, Dict{String, Vector{String}}}()
        iptable = Dict{String, Dates.DateTime}()
        new([:connection, :func, :routing], f, active_routes, events,
        readonly, iptable, peers, 0)
    end
end

on_start(ext::Session, data::Dict{Symbol, Any}, routes::Vector{<:AbstractRoute}) = begin
    if ~(:Session in c.data)
        push!(c.data, :Session => e)
    end
end

function route!(c::Connection, e::Session)
    if get_route(c) in e.active_routes
        e.gc += 1
        if e.gc == 40
            
        elseif e.gc == 90
            GC.gc()
        end
        iptable[getip(c)] = now()
        if get_method(c) == "POST "
            document_linker(c)
            return(false)::Bool
        elseif ~(getip(c) in keys(e.iptable))
            T = typeof(e).parameters[1]
            push!(e.events, getip(c) => Vector{Event}())
        end
        durstr = string(transition_duration, "s")
        write!(c, """<script>
        const parser = new DOMParser();
        function sendpage(ref) {
        var bodyHtml = document.getElementsByTagName('body')[0].innerHTML;
        sendinfo('╃CM' + ref + '╃' + bodyHtml);
        }
        function sendinfo(txt) {
        let xhr = new XMLHttpRequest();
        xhr.open("POST", "/modifier/linker");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onload = () => eval(xhr.responseText);
        xhr.send(txt);
        }
        </script>
        <style type="text/css">
        #div {
        -webkit-transition: $durstr $transition;
        -moz-transition: $durstr $transition;
        -o-transition: $durstr $transition;
        transition: $durstr $transition;
        }
        </style>
        """)
    end
end

function register!(f::Function, s::Session, name::String)
    push!(s.events[getip(c)], Event(f, name))
end

register!(f::Function, c::AbstractConnection, args ...) = register!(f, c[:Session], args ...)

getindex(m::Session, s::AbstractString) = m.events[s]

setindex!(m::Session, d::Any, s::AbstractString) = m.events[s] = d

"""
**Session Interface**
### kill!(c::Connection, event::AbstractString) -> _
------------------
Removes a given event call from a connection's Session.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        set_text!(cm, myp, "not so wow")
    end
    write!(c, myp)
end
```
"""
function kill!(c::Connection, event::String)
    delete!(c[:Session][getip(c)], event)
end

"""
**Session Interface**
### kill!(c::Connection)
------------------
Kills a Connection's saved events.
#### example
```
using Toolips
using ToolipsSession

route("/") do c::Connection
    on(c, "load") do cm::ComponentModifier
        alert!(cm, "this text will never appear.")
    end
    println(length(keys(c[:Session].iptable)))
    kill!(c)
    println(length(keys(c[:Session].iptable)))
end
```
"""
function kill!(c::AbstractConnection)
    delete!(c[:Session].iptable, getip(c))
    delete!(c[:Session].events, getip(c))
end

function clear!(c::AbstractConnection)
    c[:Session].events[getip(c)] = Vector{AbstractEvent}()
end

"""

"""
function on(f::Function, c::Connection, event::AbstractString,
    readonly::Vector{String} = Vector{String}(); mark::String = "none")
    ref = gen_ref()
    ip::String = getip(c)
    write!(c,
        "<script>document.addEventListener('$event', sendpage('$ref'));</script>")
    if ip in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], ref => f)
    else
        c[:Session][getip(c)] = Dict(ref => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$ref"] = readonly
    end
    if mark != "none"
        if getip(c) * mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[getip(c) * mark], ref)
        else
            push!(c[:Session].readonly, getip(c) * mark => [ref])
        end
    end
end

"""
**Interface**
### on(f::Function, c::Connection, s::AbstractComponent, event::AbstractString, readonly::Vector{String} = Vector{String})
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, myp, "click")
        if cm[myp][:text] == "wow"
            c[:Logger].log("wow.")
        end
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, s::AbstractComponent,
     event::AbstractString, readonly::Vector{String} = Vector{String}(); mark::String = "none")
    name::String = s.name
    ip::String = string(getip(c))
    s["on$event"] = "sendpage('$event$name');"
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][ip], "$event$name" => f)
    else
        c[:Session].events[ip] = Dict("$event$name" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$event$name"] = readonly
    end
    if mark != "none"
        if getip(c) * mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[getip(c) * mark], "$event$name")
        else
            push!(c[:Session].readonly, getip(c) * mark => ["$event$name"])
        end
    end
end

"""
**Session Interface**
### on(f::Function, cm::ComponentModifier, comp::Component{<:Any}, event::String)
------------------
Binds a client-side event to `component` **inside of a callback**.
#### example
```
function home(c::Connection)

end
```
"""
function on(f::Function, cm::ComponentModifier, comp::Component{<:Any}, event::String)
    name = comp.name
    cl = ClientModifier(); f(cl)
    push!(cm.changes, """setTimeout(function (event) {
        document.getElementById('$name').addEventListener('$event',
        function (e) {
            $(join(cl.changes))
        });
        }, 1000);""")
end

"""
**Session Interface**
### on(f::Function, c::Connection, cm::ComponentModifier, event::AbstractString, readonly::Vector{String} = Vector{String}())
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
    readonly will provide certain names to be read into the ComponentModifier.
    This can help to improve Session's performance, as it will need to parse
    less Components. The ComponentModifier version can be done while in a callback.
    Remember: AbstractComponentModifiers mean callbacks, Connections mean initial requests.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        on(c, cm, "click") do cm::ComponentModifier
            set_text!(cm, myp, "not so wow")
        end
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, cm::AbstractComponentModifier, event::AbstractString,
    readonly::Vector{String} = Vector{String}(); mark::String = "none")
    ip::String = getip(c)
    push!(cm.changes, """setTimeout(function () {
    document.addEventListener('$event', function () {sendpage('$event');});}, 1000);""")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], "$event" => f)
    else
        c[:Session][getip(c)] = Dict("$event" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$event"] = readonly
    end
    if mark != "none"
        if getip(c) * mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[getip(c) * mark], event)
        else
            push!(c[:Session].readonly, getip(c) * mark => [event])
        end
    end
end

"""
**Session Interface**
### on(f::Function, c::Connection, cm::ComponentModifier, event::AbstractString, readonly::Vector{String} = Vector{String}())
------------------
Creates a new event for the current IP in a session. Performs the function on
    the event. The function should take a ComponentModifier as an argument.
    readonly will provide certain names to be read into the ComponentModifier.
    This can help to improve Session's performance, as it will need to parse
    less Components. The ComponentModifier version can be done while in a callback.
    Remember: AbstractComponentModifiers mean callbacks, Connections mean initial requests.
#### example
```
route("/") do c::Connection
    myp = p("hello", text = "wow")
    on(c, "load") do cm::ComponentModifier
        on(c, cm, "click") do cm::ComponentModifier
            set_text!(cm, myp, "not so wow")
        end
    end
    write!(c, myp)
end
```
"""
function on(f::Function, c::Connection, cm::AbstractComponentModifier, comp::Component{<:Any},
     event::AbstractString, readonly::Vector{String} = Vector{String}();
     mark::String = "none")
     name::String = comp.name
     ip::String = getip(c)
     push!(cm.changes, """setTimeout(function () {
     document.getElementById('$name').addEventListener('$event',
     function () {sendpage('$name$event');});
     }, 1000);""")
     if getip(c) in keys(c[:Session].iptable)
         push!(c[:Session][getip(c)], "$name$event" => f)
     else
         c[:Session][getip(c)] = Dict("$name$event" => f)
     end
     if length(readonly) > 0
         c[:Session].readonly["$ip$name$event"] = readonly
     end
     if mark != "none"
        if getip(c) * mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[getip(c) * mark], "$name$event")
        else
            push!(c[:Session].readonly, getip(c) * mark => ["$name$event"])
        end
    end
end

#==
bind!
==#
"""
### abstract type InputMap
Input maps are bound using the `bind` function and allow for multiple inputs to
be registered into a `Connection` at once. Notable example from this module is `keymap`
##### Consistencies
- bound to `bind!(f::Function, ip::InputMap, args ...)`
- bound to `bind!(c::Connection, ip::InputMap)`
"""
abstract type InputMap end
function button_select(c::Connection, name::String, buttons::Vector{<:Servable},
    unselected::Vector{Pair{String, String}} = ["background-color" => "blue",
     "border-width" => 0px],
    selected::Vector{Pair{String, String}} = ["background-color" => "green",
     "border-width" => 2px])
    selector_window = div(name, value = first(buttons)[:text])
    document.getElementById("xyz").style = "";
    [begin
    style!(butt, unselected)
    on(c, butt, "click") do cm
        [style!(cm, but, unselected) for but in buttons]
        cm[selector_window] = "value" => butt[:text]
        style!(cm, butt, selected)
    end
    end for butt in buttons]
    selector_window[:children] = Vector{Servable}(buttons)
    selector_window::Component{:div}
end

abstract type InputMap end

mutable struct SwipeMap <: InputMap
    bindings::Dict{String, Function}
    SwipeMap() = new(Dict{String, Function}())
end

function bind(f::Function, c::Connection, sm::SwipeMap, swipe::String)
    swipes = ["left", "right", "up", "down"]
    if ~(swipe in swipes)
        throw(
        "Swipe is not a proper direction, please use up, down, left, or right!")
    end
    sm.bindings[swipe] = f
end

function bind(c::Connection, sm::SwipeMap,
    readonly::Vector{String} = Vector{String}())
    swipes = keys
    swipes = ["left", "right", "up", "down"]
    newswipes = Dict([begin
        if swipe in keys(sm.bindings)
            ref = ToolipsSession.gen_ref()
            if getip(c) in keys(c[:Session].iptable)
                push!(c[:Session][getip(c)], "$ref" => sm.bindings[swipe])
            else
                c[:Session][getip(c)] = Dict("$ref" => sm.bindings[swipe])
            end
            if length(readonly) > 0
                c[:Session].readonly["$ip$ref"] = readonly
            end
            swipe => "sendpage('$ref');"
        else
            swipe => ""
        end
    end for swipe in swipes])
    sc::Component{:script} = script("swipemap", text = """
    document.addEventListener('touchstart', handleTouchStart, false);
document.addEventListener('touchmove', handleTouchMove, false);

var xDown = null;
var yDown = null;

function getTouches(evt) {
  return evt.touches ||             // browser API
         evt.originalEvent.touches; // jQuery
}

function handleTouchStart(evt) {
    const firstTouch = getTouches(evt)[0];
    xDown = firstTouch.clientX;
    yDown = firstTouch.clientY;
};

function handleTouchMove(evt) {
    if ( ! xDown || ! yDown ) {
        return;
    }

    var xUp = evt.touches[0].clientX;
    var yUp = evt.touches[0].clientY;

    var xDiff = xDown - xUp;
    var yDiff = yDown - yUp;

    if ( Math.abs( xDiff ) > Math.abs( yDiff ) ) {/*most significant*/
        if ( xDiff > 0 ) {
            $(newswipes["left"])
        } else {

            $(newswipes["right"])
        }
    } else {
        if ( yDiff > 0 ) {
            $(newswipes["up"])
        } else {
            $(newswipes["down"])
        }
    }
    /* reset values */
    xDown = null;
    yDown = null;
};

""")
    write!(c, sc)
end

"""
### KeyMap
- keys::Dict{String, Pair{Tuple, Function}}

The `KeyMap` allows one to `bind!` more than one key press with incredible ease.
##### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
------------------
##### constructors
- KeyMap()
"""
mutable struct KeyMap <: InputMap
    keys::Dict{String, Pair{Tuple, Function}}
    prevents::Vector{String}
    KeyMap() = new(Dict{String, Pair{Tuple, Function}}(), Vector{String}())
end

"""
**Session**
### bind!(f::Function, km::KeyMap, key::String, event::Symbol ...)
------------------
binds the `key` with the event keys (:ctrl, :shift, :alt) to `f` in `km`.
#### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
"""
function bind(f::Function, km::KeyMap, key::String, event::Symbol ...; prevent_default::Bool = true)
    if prevent_default == true
        push!(km.prevents, key * join([string(ev) for ev in event]))
    end
    if key in keys(km.keys)
        l = length(findall(k -> k == key, collect(keys(km.keys))))
        km.keys["$key;$l"] = event => f
        return
    end
    km.keys[key] = event => f
end

function bind(f::Function, km::KeyMap, vs::Vector{String}; prevent_default::Bool = true)
    if length(vs) > 1
        event = Tuple(vs[2:length(vs)])
    else
        event = Tuple()
    end
    key = vs[1]
    if prevent_default == true
        push!(km.prevents, key * join([string(ev) for ev in event]))
    end
    if key in keys(km.keys)
        l = length(findall(k -> k == key, collect(keys(km.keys))))
        key ="$key;$l"
    end
    km.keys[key] = event => f
end

"""
**Session**
### bind!(c::Connection, cm::ComponentModifier, km::KeyMap, readonly::Vector{String} = Vector{String}; on = :down)
------------------
Binds the `KeyMap` `km` to the `Connection` in a `ComponentModifier` callback.
#### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
"""
function bind(c::Connection, km::KeyMap,
    readonly::Vector{String} = Vector{String}(); on::Symbol = :down, prevent_default::Bool = true, mark::String = "none")
    firsbind = first(km.keys)
    ip::String = getip(c)
    first_line = """setTimeout(function () {
    document.addEventListener('key$on', function(event) { if (1 == 2) {}"""
    for binding in km.keys
        default::String = ""
        key = binding[1]
        if contains(key, ";")
            key = split(key, ";")[1]
        end
        if key * join([string(bin) for bin in binding[2][1]]) in km.prevents
            default = "event.preventDefault();"
        end
        eventstr::String = join([" event.$(event)Key && " for event in binding[2][1]])
        ref = gen_ref()
        first_line = first_line * """ elseif ($eventstr event.key == "$(binding[1])") {$default
                sendpage('$ref');
        }"""
        if ip in keys(c[:Session].iptable)
            push!(c[:Session][ip], ref => binding[2][2])
        else
            c[:Session][ip] = Dict(ref => binding[2][2])
        end
        if length(readonly) > 0
            c[:Session].readonly[getip(c) * ref] = readonly
        end
        if mark != "none"
            if getip(c) * mark in keys(c[:Session].readonly)
                push!(c[:Session].readonly[getip(c) * mark], ref)
            else
                push!(c[:Session].readonly, getip(c) * mark => [ref])
            end
        end
    end
    first_line = first_line * "});}, 1000);"
    scr = script(gen_ref(), text = first_line)
    write!(c, scr)
end

"""
**Session**
### bind!(c::Connection, cm::ComponentModifier, km::KeyMap, readonly::Vector{String} = Vector{String}; on = :down)
------------------
Binds the `KeyMap` `km` to the `Connection` in a `ComponentModifier` callback.
#### example
```
r = route("/") do c::Connection
    km = KeyMap()
    bind!(km, "S", :ctrl) do cm::ComponentModifier
        alert!(cm, "saved!")
    end
    bind!(km, "C", :ctrl) do cm::ComponentModifier
        alert!(cm, "copied!")
    end
    bind!(c, km)
end
```
"""
function bind(c::Connection, cm::ComponentModifier, km::KeyMap,
    readonly::Vector{String} = Vector{String}(); on::Symbol = :down, prevent_default::Bool = true, mark::String = "none")
    firsbind = first(km.keys)
    ip::String = getip(c)
    first_line = """setTimeout(function () {
    document.addEventListener('key$on', function(event) { if (1 == 2) {}"""
    for binding in km.keys
        default::String = ""
        key = binding[1]
        if contains(key, ";")
            key = split(key, ";")[1]
        end
        if key * join([string(ev) for ev in binding[2][1]]) in km.prevents
            if binding[2] == km.prevents[binding[1]]
                default = "event.preventDefault();"
            end
        end
        eventstr::String = join([" event.$(event)Key && " for event in binding[2][1]])
        ref = gen_ref()
        first_line = first_line * """else if ($eventstr event.key == "$(binding[1])") {$default
                sendpage('$ref');
        }"""
        if ip in keys(c[:Session].iptable)
            push!(c[:Session][ip], ref => binding[2][2])
        else
            c[:Session][ip] = Dict(ref => binding[2][2])
        end
        if length(readonly) > 0
            c[:Session].readonly[getip(c) * ref] = readonly
        end
        if mark != "none"
            if getip(c) * mark in keys(c[:Session].readonly)
                push!(c[:Session].readonly[getip(c) * mark], ref)
            else
                push!(c[:Session].readonly, getip(c) * mark => [ref])
            end
        end
    end
    first_line = first_line * "});}, 1000);"
    push!(cm.changes, first_line)
end

"""
**Session**
### bind!(c::Connection, comp::Component, km::KeyMap, readonly::Vector{String} = Vector{String}; on = :down)
------------------
Binds the `KeyMap` `km` to the `comp`.
#### example
```

```
"""
function bind(c::Connection, cm::ComponentModifier, comp::Component{<:Any},
    km::KeyMap, readonly::Vector{String} = Vector{String}(); on::Symbol = :down,
    prevent_default::Bool = true, mark::String = "none")
    firsbind = first(km.keys)
    ip = getip(c)
    first_line = """
    setTimeout(function () {
    document.getElementById('$(comp.name)').addEventListener('key$on', function (event) { if (1 == 2) {}"""
    n = 1
    for binding in km.keys
        default::String = ""
        key = binding[1]
        if contains(key, ";")
            key = split(key, ";")[1]
        end
        if (key * join([string(ev) for ev in binding[2][1]])) in km.prevents
            default = "event.preventDefault();"
        end
        ref = gen_ref()
        eventstr::String = join([" event.$(event)Key && " for event in binding[2][1]])
        first_line = first_line * """ else if ($eventstr event.key == "$key") {$default
                sendpage('$(comp.name * key * ref)');
                }"""
        if ip in keys(c[:Session].iptable)
            push!(c[:Session][ip], comp.name * key * ref => binding[2][2])
        else
            c[:Session][ip] = Dict(comp.name * key * ref => binding[2][2])
        end
        if length(readonly) > 0
            c[:Session].readonly["$(getip(c))$(comp.name)$key$ref"] = readonly
        end
        if mark != "none"
            if getip(c) * mark in keys(c[:Session].readonly)
                push!(c[:Session].readonly[getip(c) * mark], "$(comp.name * key * ref)")
            else
                push!(c[:Session].readonly, getip(c) * mark => ["$(comp.name * key * ref)"])
            end
        end
    end
    first_line = first_line * "}.bind(event));}, 500);"
    push!(cm.changes, first_line)
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::AbstractConnection, key::String, readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------

Binds a key event to a `Component`.
#### example
```

```
"""
function bind(f::Function, c::AbstractConnection, comp::Component{<:Any},
    key::String, eventkeys::Symbol ...; readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, mark::String = "none")
    cm::Modifier = ClientModifier()
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    write!(c, """<script>
    setTimeout(function () {
    document.getElementById('$(comp.name)').addEventListener('key$on', function(event) {
        if ($eventstr event.key == "$(key)") {
        sendpage('$(comp.name * key)');
        }
});}, 1000)</script>
    """)
    ip::String = getip(c)
    if ip in keys(c[:Session].iptable)
        push!(c[:Session][ip], comp.name * key => f)
    else
        c[:Session][ip] = Dict(comp.name * key => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$key"] = readonly
    end
    if mark != "none"
        if mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[mark], comp.name * key)
        else
            push!(c[:Session].readonly, mark => [comp.name * key])
        end
    end
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::AbstractConnection, key::String, readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------
Binds a key event to a `Connection`.
#### example
```

```
"""
function bind(f::Function, c::AbstractConnection, key::String, eventkeys::Symbol ...;
    readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, prevent_default::Bool = true, mark::String = "none")
    cm::Modifier = ClientModifier()
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    ref = gen_ref()
    write!(c, """<script>
    setTimeout(function () {
document.addEventListener('key$on', function(event) {
    if ($eventstr event.key == "$(key)") {
    sendpage('$ref');
    }
});}, 1000);</script>
    """)
    ip::String = getip(c)
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][ip], ref => f)
    else
        c[:Session][ip] = Dict(ref => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ref"] = readonly
    end
    if mark != "none"
        if mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[mark], ref)
        else
            push!(c[:Session].readonly, mark => [ref])
        end
    end
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::Connection, cm::AbstractComponentModifier, key::String, eventkeys::Symbol ...; readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------
Binds a key event to a `Connection` in a `ComponentModifier` callback.
#### example
```

```
"""
function bind(f::Function, c::Connection, cm::AbstractComponentModifier, key::String,
    eventkeys::Symbol ...; readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, mark::String = "none")
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
    ref = gen_ref()
    push!(cm.changes, """
    setTimeout(function () {
    document.addEventListener('key$on', (event) => {
            if ($eventstr event.key == "$(key)") {
            sendpage('$ref');
            }
            });}, 1000);""")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], ref => f)
    else
        c[:Session][getip(c)] = Dict(ref => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$ref"] = readonly
    end
    if mark != "none"
        if mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[mark], ref)
        else
            push!(c[:Session].readonly, mark => [ref])
        end
    end
end

"""
**Session Interface** 0.3
### bind!(f::Function, c::Connection, cm::AbstractComponentModifier, comp::Component{<:Any}, key::String, eventkeys::Symbol ...; readonly::Vector{String} = [];
    on::Symbol = :down, client::Bool == false)  -> _
------------------
Binds a key event to a `Component` in a `ComponentModifier` callback.
#### example
```

```
"""
function bind(f::Function, c::Connection, cm::AbstractComponentModifier, comp::Component{<:Any},
    key::String, eventkeys::Symbol ...; readonly::Vector{String} = Vector{String}(),
    on::Symbol = :down, mark::String = "none")
    name::String = comp.name
    eventstr::String = join([begin " event.$(event)Key && "
                            end for event in eventkeys])
push!(cm.changes, """setTimeout(function () {
document.getElementById('$(name)').onkeydown = function(event){
        if ($eventstr event.key == '$(key)') {
        sendpage('$(name * key)')
        }
        }}, 1000);""")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], "$name$key" => f)
    else
        c[:Session][getip(c)] = Dict("$name$key" => f)
    end
    if length(readonly) > 0
        c[:Session].readonly["$ip$name$event"] = readonly
    end
    if mark != "none"
        if mark in keys(c[:Session].readonly)
            push!(c[:Session].readonly[mark], ref)
        else
            push!(c[:Session].readonly, mark => [ref])
        end
    end
end

#==
script!
==#
"""

"""
function script!(f::Function, c::Connection, name::String,
    readonly::Vector{String} = Vector{String}(); time::Integer = 500,
    type::String = "Interval", mark = "none")
    if getip(c) in keys(c[:Session].iptable)
        push!(c[:Session][getip(c)], name => f)
    else
        c[:Session][getip(c)] = Dict(name => f)
    end
    obsscript = script(name, text = """
    set$(type)(function () { sendpage('$name'); }, $time);
   """)
   if length(readonly) > 0
       c[:Session].readonly["$(getip(c))$name"] = readonly
   end
   if mark != "none"
    if mark in keys(c[:Session].readonly)
        push!(c[:Session].readonly[mark], ref)
    else
        push!(c[:Session].readonly, mark => [ref])
    end
end
   write!(c, obsscript)
end

function script(f::Function, s::String = gen_ref())
    cl = ClientModifier(s)
    f(cl)
    script(cl.name, text = funccl(cl))
end

script(cl::ClientModifier) = begin
    script(cl.name, text = join(cl.changes))
end

#==
rpc
==#

"""
**Session Interface**
### open_rpc!(c::Connection, name::String = getip(c); tickrate::Int64 = 500)
------------------
Creates a new rpc session inside of ToolipsSession. Other clients can then join and
have the same `ComponentModifier` functions run.
#### example
```

```
"""
function open_rpc!(c::Connection, name::String = getip(c); tickrate::Int64 = 500)
    push!(c[:Session].peers,
     name => Dict{String, Vector{String}}(getip(c) => Vector{String}()))
    script!(c, getip(c) * "rpc", ["none"], time = tickrate) do cm::ComponentModifier
        push!(cm.changes, join(c[:Session].peers[name][getip(c)]))
        c[:Session].peers[name][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### open_rpc!(c::Connection, name::String = getip(c); tickrate::Int64 = 500)
------------------
Creates a new rpc session inside of ToolipsSession. Other clients can then join and
have the same `ComponentModifier` functions run.
#### example
```

```
"""
function open_rpc!(c::Connection, cm::ComponentModifier, 
    name::String = gen_ref(); tickrate::Int64 = 500)
    push!(c[:Session].peers,
     name => Dict{String, Vector{String}}(getip(c) => Vector{String}()))
    script!(c, cm, name, time = tickrate, ["none"]) do cm::ComponentModifier
        push!(cm.changes, join(c[:Session].peers[name][getip(c)]))
        c[:Session].peers[name][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### open_rpc!(f::Function, c::Connection, name::String; tickrate::Int64 = 500)
------------------
Does the same thing as `open_rpc!(::Connection, ::String; tickrate::Int64)`,
but also runs `f` on each tick.
#### example
```

```
"""
function open_rpc!(f::Function, c::Connection, name::String; tickrate::Int64 = 500)
    push!(c[:Session].peers,
     name => Dict{String, Vector{String}}(getip(c) => Vector{String}()))
    script!(c, name, ["none"], time = tickrate) do cm::ComponentModifier
        f(cm)
        push!(cm.changes, join(c[:Session].peers[name][getip(c)]))
        c[:Session].peers[name][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### close_rpc!(c::Connection)
------------------
Removes the current RPC session from `c`.
#### example
```

```
"""
function close_rpc!(c::Connection)
    delete!(c[:Session].peers, getip(c))
end

"""
**Session Interface**
### join_rpc!(c::Connection, host::String; tickrate::Int64 = 500)
------------------
Joins an rpc session by name.
#### example
```

```
"""
function join_rpc!(c::Connection, host::String; tickrate::Int64 = 500)
    push!(c[:Session].peers[host], getip(c) => Vector{String}())
    script!(c, getip(c) * "rpc", ["none"], time = tickrate) do cm::ComponentModifier
        push!(cm.changes, join(c[:Session].peers[host][getip(c)]))
        c[:Session].peers[host][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### join_rpc!(c::Connection, host::String; tickrate::Int64 = 500)
------------------
Joins an rpc session by name.
#### example
```

```
"""
function join_rpc!(c::Connection, cm::ComponentModifier, host::String; tickrate::Int64 = 500)
    push!(c[:Session].peers[host], getip(c) => Vector{String}())
    script!(c, cm, gen_ref(), ["none"], time = tickrate) do cm::ComponentModifier
        push!(cm.changes, join(c[:Session].peers[host][getip(c)]))
        c[:Session].peers[host][getip(c)] = Vector{String}()
    end
end

"""
**Session Interface**
### join_rpc!(f::Function, c::Connection, host::String; tickrate::Int64 = 500)
------------------
Joins an rpc session by name, runs `f` on each tick.
#### example
```

```
"""
function join_rpc!(f::Function, c::Connection, host::String; tickrate::Int64 = 500)
    push!(c[:Session].peers[host], getip(c) => Vector{String}())
    script!(c, cm, getip(c) * "rpc", ["none"], time = tickrate) do cm::ComponentModifier
        f(cm)
        location::String = find_client(c)
        push!(cm.changes, join(c[:Session].peers[location][getip(c)]))
        c[:Session].peers[location][getip(c)] = Vector{String}()
    end
    f(cm)
end

"""
**Session Interface**
### find_client(c::Connection)
------------------
Finds the RPC session name of this client.
#### example
```

```
"""
function find_client(c::Connection)
    clientlocation = findfirst(x -> getip(c) in keys(x), c[:Session].peers)
    clientlocation::String
end

"""
**Session Interface**
### rpc!(c::Connection, cm::ComponentModifier)
------------------
Does an rpc for all other connection clients, also clears `ComponentModifier` changes.
 You can use this interchangeably with local function calls by calling `rpc!` first
then calling your regular `ComponentModifier` functions.
#### example
```

```
"""
function rpc!(c::Connection, cm::ComponentModifier)
    mods::String = find_client(c)
    [push!(mod, join(cm.changes)) for mod in values(c[:Session].peers[mods])]
    deleteat!(cm.changes, 1:length(cm.changes))
end

"""
**Session Interface**
### rpc!(f::Function, c::Connection)
------------------
Does RPC with a new `ComponentModifier` and will rpc everything inside of `f`.
#### example
```
rpc!(c) do cm::ComponentModifier

end
```
"""
function rpc!(f::Function, c::Connection)
    cm = ComponentModifier("")
    f(cm)
    mods::String = find_client(c)
    for mod in values(c[:Session].peers[mods])
        push!(mod, join(cm.changes))
    end
end

function call!(c::Connection, cm::ComponentModifier)
    mods::String = find_client(c)
    [if mod[1] != getip(c); push!(mod[2], join(cm.changes)); end for mod in c[:Session].peers[mods]]
    deleteat!(cm.changes, 1:length(cm.changes))
end

function call!(f::Function, c::Connection)
    cm = ComponentModifier("")
    f(cm)
    mods::String = find_client(c)
    for mod in c[:Session].peers[mods]
        if mod[1] != getip(c)
            push!(mod[2], join(cm.changes))
        end
    end
end


"""
**Session Interface**
### disconnect_rpc!(c::Connection)
------------------
Removes the client from the current rpc session.
#### example
```

```
"""
function disconnect_rpc!(c::Connection)
    mods::String = find_client(c)
    delete!(c[:Session].peers[mods], getip(c))
end

"""
**Session Interface**
### is_host(c::Connection) -> ::Bool
------------------
Checks if the current `Connection` is hosting an rpc session.
#### example
```

```
"""
is_host(c::Connection) = getip(c) in keys(c[:Session].peers)

"""
**Session Interface**
### is_client(c::Connection, s::String) -> ::Bool
------------------
Checks if the client is in the `s` RPC session..
#### example
```

```
"""
is_client(c::Connection, s::String) = getip(c) in keys(c[:Session].peers[s])

"""
**Session Interface**
### is_dead(c::Connection) -> ::Bool
------------------
Checks if the current `Connection` is still connected to `Session`
#### example
```

```
"""
is_dead(c::Connection) = getip(c) in keys(c[:Session].iptable)

export Session, on, bind!, script!, script, ComponentModifier, ClientModifier
export KeyMap
export playanim!, alert!, redirect!, modify!, move!, remove!, set_text!
export update!, insert_child!, append_first!, animate!, pauseanim!, next!
export set_children!, get_text, style!, free_redirects!, confirm_redirects!, store!
export scroll_by!, scroll_to!, focus!, set_selection!, blur!
export rpc!, disconnect_rpc!, find_client, join_rpc!, close_rpc!, open_rpc!
export join_rpc!, is_client, is_dead, is_host, call!
end # module
