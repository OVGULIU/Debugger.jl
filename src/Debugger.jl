module Debugger

using Markdown
using Base.Meta: isexpr
using REPL
using REPL.LineEdit

using JuliaInterpreter: JuliaInterpreter, JuliaStackFrame, @lookup, Compiled, JuliaProgramCounter, JuliaFrameCode,
      finish!, enter_call_expr, step_expr!

# TODO: Work on better API in JuliaInterpreter and rewrite Debugger.jl to use it
# These are undocumented functions used by Debugger.jl from JuliaInterpreter
using JuliaInterpreter: _make_stack, pc_expr,isassign, getlhs, do_assignment!, maybe_next_call!, is_call, _step_expr!, next_call!,  moduleof,
                        iswrappercall, next_line!, location


include("DebuggerFramework.jl")
using .DebuggerFramework
using .DebuggerFramework: FileLocInfo, BufferLocInfo, Suppressed

export @enter

const SEARCH_PATH = []
function __init__()
    append!(SEARCH_PATH,[joinpath(Sys.BINDIR,"../share/julia/base/"),
            joinpath(Sys.BINDIR,"../include/")])
    return nothing
end

include("commands.jl")

const all_commands = ("q", "s", "si", "finish", "bt", "nc", "n", "se")

function DebuggerFramework.language_specific_prompt(state, frame::JuliaStackFrame)
    if haskey(state.language_modes, :julia)
        return state.language_modes[:julia]
    end
    julia_prompt = LineEdit.Prompt(DebuggerFramework.promptname(state.level, "julia");
        # Copy colors from the prompt object
        prompt_prefix = state.repl.prompt_color,
        prompt_suffix = (state.repl.envcolors ? Base.input_color : state.repl.input_color),
        complete = REPL.REPLCompletionProvider(),
        on_enter = REPL.return_callback)
    julia_prompt.hist = state.main_mode.hist
    julia_prompt.hist.mode_mapping[:julia] = julia_prompt

    julia_prompt.on_done = (s,buf,ok)->begin
        if !ok
            LineEdit.transition(s, :abort)
            return false
        end
        xbuf = copy(buf)
        command = String(take!(buf))
        @static if VERSION >= v"1.2.0-DEV.253"
            response = DebuggerFramework.eval_code(state, command)
            val, iserr = response
            REPL.print_response(state.repl, response, true, true)
        else
            ok, result = DebuggerFramework.eval_code(state, command)
            REPL.print_response(state.repl, ok ? result : result[1], ok ? nothing : result[2], true, true)
        end
        println(state.repl.t)

        if !ok
            # Convenience hack. We'll see if this is more useful or annoying
            for c in all_commands
                !startswith(command, c) && continue
                LineEdit.transition(s, state.main_mode)
                LineEdit.state(s, state.main_mode).input_buffer = xbuf
                break
            end
        end
        LineEdit.reset_state(s)
    end
    julia_prompt.keymap_dict = LineEdit.keymap([REPL.mode_keymap(state.main_mode);state.standard_keymap])
    state.language_modes[:julia] = julia_prompt
    return julia_prompt
end

function DebuggerFramework.debug(meth::Method, args...)
    stack = [enter_call(meth, args...)]
    DebuggerFramework.RunDebugger(stack)
end

macro enter(arg)
    quote
        let stack = $(_make_stack(__module__,arg))
            DebuggerFramework.RunDebugger(stack)
        end
    end
end
end # module
