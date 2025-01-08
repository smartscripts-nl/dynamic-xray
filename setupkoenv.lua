-- set search path for 'require()'
-- #((extensions system: add frontend/extensions to package paths))
package.path =
    "common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;frontend/extensions/?.lua;" ..
    package.path

-- [...]
