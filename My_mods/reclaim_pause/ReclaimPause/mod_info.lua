name = "Reclaim Pause"
version = 36
copyright = "2026 ExtraMassBlocker"
description = "Puts your reclaiming engineers on hold when your mass storage is nearly full (70% by default) and releases them again when you start spending mass (65%). Engineers keep their orders, so on release they carry on from where they stopped. Using the 'UI mod tools' mod, you can change every threshold. Created with AI and may contain errors."
author = "ExtraMassBlocker, Puffskein"
url = ""
-- The uid identifies one version of the mod, so every version needs a new one. The name
-- stays: by it the FAF client finds the mod to update.
uid = "22cf9e27-281f-4409-9d26-ce1fc6259b14"
exclusive = false
ui_only = true
-- Makes the 'UI mod tools' mod load modules/options.lua. Without UMT the mod runs on its
-- defaults.
__umt = true