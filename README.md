# Ship It

An invite-only site for a small group of game devs to get better at focusing and finishing games.

- **Quests**: Scope Slayer cuts a game idea down to a few core features, which become a quest board. Only 3 quests can be in progress at once.
- **Focus runs**: 10, 25 or 50 minute timers that give XP. Strict mode ends the run if you leave the tab for more than 15 seconds.
- **XP, levels and streaks**: a streak counts days you showed up, with 2 shields a month.
- **Devlog**: one-line daily posts.
- **Party**: everyone's progress, who's focusing right now, a group goal and high-fives.
- **Ship Wall**: every finished game.
- **Admin**: invite links, roles, announcements, challenges and the group goal.

It's a static site (`index.html` + `config.js`) hosted on GitHub Pages, with Supabase for accounts and data.

## Setup (about 5 minutes)

1. Create a free project at [supabase.com](https://supabase.com).
2. In the project, open **SQL Editor → New query**, paste all of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**.
3. Open **Authentication → Sign In / Providers → Email** and turn **Confirm email** off, then save. (Optional: if you keep it on, set **Authentication → URL Configuration → Site URL** to the site's address so confirmation links come back here.)
4. Open **Project Settings → API** (or the **Connect** button). Copy the **Project URL** and the **anon / publishable** key into [`config.js`](config.js).
5. Open the site and click **Join**. The first person to join becomes the admin and needs no invite code.

## Inviting friends

Admin tab → **Create invite link** → send the link. Each link works once. Friends make an account with their email and a password.

## Safety notes

- The anon key in `config.js` is public by design. Row Level Security in `schema.sql` keeps each person's board private, stops members from changing anyone else's data, and limits invites, roles and settings to admins.
- Never put the `service_role` key in this repo.
