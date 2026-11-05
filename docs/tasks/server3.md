# SERVER agent — iteration 3 (port 7471)
Owns: server/**, shared-luau/**, docs/ACTIONS.md, docs/PROTOCOL.md, docs/LOCALE_KEYS.md (+ server/locale).
Implement the "Server contract" and `listMyCompanies` from docs/STORY.md: story state + migration, repair orders
economy (spawn cadence, devices/faults/parts, rewards scaled by score, parts as resources repair_screen/repair_battery/repair_port in Purchasing with prices),
step tracking hooked into existing actions, storyEvent whitelist, storySkip (owner only), clock pause until chapter 4,
investor top-up at chapter 4, createCompany storyMode flag, notify keys (story.*) for localization, story/repairs sections replicated.
Publish docs/ACTIONS.md "Story & repairs" EARLY (other agents depend on it) with exact step ids per chapter.
Tests: e2e full story run (both players in co-op can complete steps; chapter order; skip; old save migration = done;
quick start unchanged; clock paused then running), repair rewards capped. Keep run.py + soak green.
