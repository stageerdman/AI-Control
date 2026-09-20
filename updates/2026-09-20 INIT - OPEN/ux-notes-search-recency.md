# Search & Recency/Ordering — UX Notes

## 1. Search field placement and scope
Persistent search field pinned at the top of the window, always visible — like Finder, Mail, Xcode's file navigator. No Cmd+F overlay: this is the primary navigation surface for a tool opened many times a day, and hiding search behind a shortcut adds a step to the single most common action after "look at the list." Native `NSSearchField` styling, standard placeholder ("Search").

Filters on **name + description** only. Not chat transcript content. Description is short, curated, human-written text meant to identify the project — it belongs in the same search as the name. Full-text search across session logs is a fundamentally different, heavier feature (different data source, different mental model — "find that conversation" vs. "find that project") and doesn't belong in this phase or this field.

## 2. Hierarchy during search
Flatten. Search results are a flat list of matching projects and organizers-that-themselves-match; nested browsing structure disappears while a query is active. An organizer whose name/description doesn't match but contains a matching child project appears too, but only as a lightweight anchor for its matches, not expanded to show its full, unfiltered contents.

Reasoning: browsing hierarchy exists for when you don't know exactly what you want. Searching means you already know the name and want the fastest path to it — nesting toggles and nonmatching siblings are friction at that moment. Collapse-to-flat also avoids the visually confusing state of "organizer expanded, but half its children are greyed out because they don't match."

## 3. Recency display
Relative time ("2h ago", "Yesterday", "Mar 3"), never a raw timestamp as the primary label. Exact time on hover (tooltip) is fine — it's free and native — but not printed in the row by default.

This is a single-user daily tool, not a shared log where "who did what when, precisely" matters for accountability. The row's recency exists to answer one glanceable question — "was I just in this, or has it been a while" — and relative phrasing answers that faster than parsing a clock time. Exact timestamps read as database output, not a personal tool; wrong tone here.

## 4. Sort for zero-history items — pushing back on the placeholder
The placeholder ("below chatted items, then alphabetical") gets the *grouping* right but the wrong secondary sort. Alphabetical is an arbitrary key that has nothing to do with why the list is ordered by recency in the first place — it's borrowed from a different UI paradigm (file browsers) and breaks the list's one organizing principle at exactly the point where a user is most likely to be hunting for "that thing I just created."

**Recommendation:** within the no-chat-history group, sort by filesystem modification time (folder mtime), descending — same direction as the chatted group above it. This costs nothing extra (already reading the filesystem to detect projects/organizers), and a project you just scaffolded or `git clone`d minutes ago is far more likely to be what you're looking for than one sitting untouched for a year, even though neither has a chat yet. It keeps "recency" as the single mental model for the entire list instead of switching rules partway down. Alphabetical only wins if the user is scanning for a known name by eye — but that's what search is for (see §1); it shouldn't be the default sort's job.

## 5. Live re-sort while the app is open
Yes — instant live re-sort is correct and is the whole point of the feature. If you start a session with a project, it must jump to the top without a refresh or reopen.

The jump should be an animated reorder, not a silent teleport — but restrained: a short (~0.2s), ease-out position interpolation using SwiftUI's default `List` move transition, nothing more. The reason isn't decoration, it's continuity: if a row you're looking at vanishes and reappears elsewhere instantly, you lose track of it and have to re-scan the list. A brief animated move lets your eye follow it. No flash, highlight color, or bounce — that crosses from "helps you track state" into "look at me," which this app should avoid everywhere.
