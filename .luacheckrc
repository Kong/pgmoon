-- Luacheck configuration for pgmoon.
--
-- Every *.lua file under pgmoon/ (and pgmoon.lua) is a build artifact compiled
-- from its *.moon source by the MoonScript compiler (`moonc`); see the Makefile.
-- That generated Lua is never hand-edited, so we relax the warnings that only
-- flag stylistic patterns inherent to moonc's output rather than real defects.
-- Hand-written Lua (specs, tooling) is still checked normally.

std = "max"

read_globals = {
  "ngx",
}

local generated = {
  ignore = {
    "211", -- unused local variable / function
    "212", -- unused argument (moonc keeps full signatures, e.g. `self`)
    "213", -- unused loop variable
    "231", -- local variable is set but never accessed
    "241", -- local variable is mutated but never accessed
    "311", -- value assigned to a local variable is unused
    "312", -- value of an argument is unused
    "411", -- redefining a local variable
    "412", -- redefining an argument
    "421", -- shadowing a local variable
    "431", -- shadowing an upvalue
    "432", -- shadowing an upvalue argument
    "511", -- unreachable code
    "512", -- loop can be executed at most once
    "531", -- unbalanced assignment: too many values on the right
    "532", -- unbalanced assignment: too few values on the right
    "542", -- empty if branch
    "631", -- line is too long
  },
}

files["pgmoon.lua"] = generated
files["pgmoon/**/*.lua"] = generated
