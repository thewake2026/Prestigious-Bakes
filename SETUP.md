# Prestigious Bakes: setup

The site already works without any setup: it shows the starter menu and sends orders to WhatsApp (07046243952).
To switch on saved orders, order tracking and the admin page, do these steps once.

1. **Supabase:** create a free project at supabase.com.
2. **Database:** SQL Editor > paste all of `setup.sql` > Run.
3. **Logins:** Authentication > Users > Add user. Create one for you and one for the owner (email and password).
4. **Admins:** SQL Editor, run (with the real emails):
   `insert into admins values ('you@email.com','dev'), ('owner@email.com','owner');`
5. **Keys:** Project Settings > API. Copy the Project URL and the **anon public** key into `config.js`. Never use the service_role key.
6. **Deploy:** upload this whole folder to a new GitHub repo, then import it in Vercel (or turn on GitHub Pages).
7. **Admin page:** open `/admin.html`, log in, go to **Payment** and add the account number. Add real prices in **Menu**.

Using the admin: the owner can add photos and items, set prices, update order status, and mark orders paid. The Developer tab (only for you) manages who can log in.

## Notifications (do after the steps above)

1. **Keys:** on your laptop run `npx web-push generate-vapid-keys`. Put the **public** key in `config.js` (`VAPID_PUBLIC`). Keep the private key for step 3.
2. **Database:** Database > Extensions > enable `pg_net` and `pg_cron`. Open `setup-notifications.sql`, replace the project URL and the secret (make up a long random one) in the `insert into private_config` line, then run it.
3. **Function:** Edge Functions > Create function named `notify`, paste `notify-function.ts`, and turn **Verify JWT off**. Add these secrets: `VAPID_PUBLIC`, `VAPID_PRIVATE`, `VAPID_EMAIL` (your email), `PB_SECRET` (the same secret as step 2).
4. **Turn on alerts:** open `/admin.html` on the installed app, tap **Alerts**, and allow notifications. Do the same on the owner's phone.
5. **Test:** place an order from the site, then change its status in the admin.

On iPhone, notifications only work after Add to Home Screen. Admin tabs: **Leads** (people who signed up or left items in the cart, with a WhatsApp button) and **Notify** (send a message to all customers).
