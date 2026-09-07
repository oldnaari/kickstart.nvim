;; extends
;;
;; Give GitHub-style callouts a colour of their own in the raw view.
;;
;; Without this, treesitter parses `[!NOTE]` as an ordinary shortcut link and it
;; is highlighted exactly like `[a real link]` -- so in insert, replace and visual
;; modes every callout reads as a green underlined link regardless of its type.
;; render-markdown replaces the whole thing with `󰋽 Note` in normalish modes, so
;; the problem is invisible until you start editing.
;;
;; The `@markup.callout.*` groups are defined in lua/custom/markdown_theme.lua,
;; paired with the RenderMarkdown* groups used by the `callout` config in
;; init.lua so both modes agree on the colour.
;;
;; `;; extends` above is load-bearing: without it this file REPLACES the upstream
;; markdown_inline highlights instead of adding to them. Being an `after/` query,
;; it is applied last, so these captures win over the `@markup.link.label` the
;; upstream query assigns to the same node.

((shortcut_link
  (link_text) @markup.callout.note)
  (#any-of? @markup.callout.note "!NOTE" "!IMPORTANT"))

((shortcut_link
  (link_text) @markup.callout.tip)
  (#eq? @markup.callout.tip "!TIP"))

((shortcut_link
  (link_text) @markup.callout.warning)
  (#eq? @markup.callout.warning "!WARNING"))

((shortcut_link
  (link_text) @markup.callout.danger)
  (#any-of? @markup.callout.danger "!DANGER" "!CAUTION"))
