# Draggable draw-mode toolbar

## Request

> can we make the drawing tools to be draggable/movable as well?
>
> the drag should be part of the new tag btw

## Decisions

- Release: keep published v0.5.2 (notch fix) as-is; ship drag as v0.5.3 only after Erick tests and approves.
- Scope: draw mode only; editor window toolbar stays fixed.
- Grab area: grip handle on left edge of the bar, plus the bar's empty background.
- Limits: bar stays fully on screen and below the notch safe area.
- Memory: none; bar starts top center every draw session.
- Extras: open-hand cursor over grab areas, closed-hand while dragging. No double-click reset.
- Plan file deleted in the last task's commit.

## Tasks

- [x] Drag the bar by a left grip handle or its empty background; buttons, slider, color well, and text field still work normally. Check: test drags the bar via grip and background and asserts it moved; test that clicking a tool button still selects the tool.
- [x] Clamp the bar fully inside the screen and below `safeAreaInsets.top`. Check: test drags far past every edge and asserts the bar frame stays within bounds minus the notch inset.
- [x] Open-hand cursor over grip and background, closed-hand while dragging. Check: test asserts cursor rects/cursor on grip; `make build` and `make test` pass.
- [ ] Hand off for manual test: `make bundle`, Erick tests draw mode drag on his Mac (mom's Mac if possible) and approves. Delete this plan file. Check: Erick's explicit approval; no tag or release until then.
