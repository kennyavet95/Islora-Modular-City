# Islora · Top Players on Supabase

The Top Players screen runs on fake players (`MockLeaderboardService`) until
Supabase is configured. The swap touches no UI code.

## Switching to Supabase

1. Create a Supabase project.
2. Run `migrations/20261123000000_leaderboard.sql`: either paste it into the SQL
   Editor or run `supabase db push` with the CLI.
3. Enable **pg_cron** and schedule the weekly season close. The exact
   `cron.schedule(...)` call is in the comment above `lb_close_season` in the
   migration.
4. In `Blockora/Core/Leaderboard/LeaderboardService.swift`, fill in
   `SupabaseConfig.projectURL` and `SupabaseConfig.anonKey` (Dashboard → Project
   Settings → API). `LeaderboardServiceFactory` then picks
   `SupabaseLeaderboardService` automatically.

## How the pieces fit

```
top-players.html  ──Islora.call(method)──▶  TopPlayersBridge  ──▶  LeaderboardService
   (UI only)        ◀──IsloraBridge.resolve──    (native)              ├─ MockLeaderboardService
                                                                       └─ SupabaseLeaderboardService ──▶ RPCs
```

- The page never talks to Supabase directly. Everything goes through the native
  bridge, so the same HTML works with both services.
- Each `LeaderboardService` method maps to one RPC: `register_player`,
  `submit_stats`, `get_leaderboard`, `get_league`, `get_faction_war`,
  `join_faction`, `get_player`, `get_gift_status`, `send_gift`, `claim_gifts`.
- Tables have RLS turned on and no policies. The anon key can only call the RPCs.
- On the wire, keys are snake_case and timestamps are epoch milliseconds.
- Identity: on first launch the app generates a UUID, a device token and a
  "Builder nnnn" name. If that name is taken, `register_player` hands back a free
  one (4 digits, then 5). The identity is kept in UserDefaults, outside the save
  file, so "Reset Game" keeps the public name.
- Stats are submitted on app launch, when the app goes to the background, and
  when Top Players opens.

## Game rules

The SQL and the mock implement the same rules. The constants live in
`LeaderboardModels.swift`.

| Rule | Value |
|---|---|
| Season | ISO week, UTC (`2026-W48`), closes Monday 00:00 UTC |
| League group | 30 players in the same tier |
| League score | XP earned this season |
| Promotion / demotion | top 5 / bottom 5 (no demotion in groups under 10) |
| Tiers | bronze → silver → gold → platinum → diamond |
| Factions | coast, highland, delta; one pick per season; score = sum of members' weekly XP |
| Gifts | 1 per day; recipient gets +2 blocks, sender gets +1 back when it's claimed |
| Inspire | copies one building from another player's city into your Codex as a Blueprint |

## Not done yet

- **Supabase Realtime**: the page polls every 30 s. To get live pushes, subscribe
  natively to `lb_league_members` and forward changes to the page as an event.
