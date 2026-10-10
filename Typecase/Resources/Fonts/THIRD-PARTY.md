# Bundled fonts

`TypecaseFallback.otf` and `TypecaseFallbackUpper.otf` are subsets of **GNU Unifont** (https://unifoundry.com/unifont/),
reduced to the characters that the macOS system fonts cannot draw and that Unifont really has a design for (its
placeholder boxes for newer characters are left out). They are used only as a last-resort fallback, drawn
faintly on a yellow box so they are not mistaken for a real design.

Unifont is copyright its authors (Roman Czyborra, Paul Hardy and others). It is distributed under the GNU GPL
version 2 or later with the GNU Font Embedding Exception, and alternatively under the SIL Open Font License 1.1.
Check the exact terms of the version you ship before submitting to the App Store, and include the licence text
you choose in the app's acknowledgements.

Rebuild with `Tools/make-fallback-font/make_fallback_font.py`.
