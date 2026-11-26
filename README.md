# Deploy and Host LearnHouse on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/lms?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=learnhouse)

LearnHouse is an open-source learning platform (LMS) for publishing online courses. Courses are built from chapters and activities: rich pages written in a collaborative block editor, videos, documents, and assignments with grading. Learners sign up, follow their progress and earn certificates. Around the courses come communities with discussions, podcasts, learning paths, user groups and roles, and a branded home page for your school. This template runs LearnHouse 1.4.5 on Railway with Postgres (with pgvector), Redis, course files on a persistent volume, and your organization and first admin set up on boot.

## About Hosting LearnHouse

Deploy, wait for the green check (the first boot creates the database, which takes about a minute), and open the Railway domain. Sign in with `LEARNHOUSE_INITIAL_ADMIN_EMAIL` (set it to your email before deploying) and the generated `LEARNHOUSE_INITIAL_ADMIN_PASSWORD`, both on the LearnHouse service's Variables tab. Change the password in your account settings afterwards; the variables are only used on the first boot. Then open the dashboard to rename your organization, add a logo and create your first course.

**Who can sign up:** anyone can create a learner account from the sign-up page, which is what a public course site wants. For a private academy, switch the organization to invite-only in the dashboard's member settings and send invite links.

**Your data:** courses, users and progress are in the Postgres service. Uploaded videos, images, documents and other course files are on the LearnHouse volume at `/data/content`. Redeploys, restarts and upgrades keep both. Grow the volume in the service's settings if you host many videos.

**Custom domain:** add it under the LearnHouse service's Settings > Networking (port 80), set `LEARNHOUSE_DOMAIN=learn.example.com`, and redeploy. Every URL the app uses (links, sign-in, live editing, CORS) follows that one variable.

**Email:** sign-up confirmations and password resets need an email provider. Set `LEARNHOUSE_EMAIL_PROVIDER=smtp` with `LEARNHOUSE_SMTP_HOST`, `LEARNHOUSE_SMTP_PORT`, `LEARNHOUSE_SMTP_USERNAME`, `LEARNHOUSE_SMTP_PASSWORD` and `LEARNHOUSE_SYSTEM_EMAIL_ADDRESS`, or `LEARNHOUSE_RESEND_API_KEY` for Resend.

**AI features:** course and quiz generation and the learning assistant need `LEARNHOUSE_IS_AI_ENABLED=true` and an API key (`LEARNHOUSE_GEMINI_API_KEY`, or `LEARNHOUSE_AI_PROVIDER` with `LEARNHOUSE_AI_API_KEY`). They are off by default.

## Common Use Cases

- Selling or sharing online courses from your own branded school site
- Employee onboarding and internal training with progress tracking and certificates
- University or bootcamp courses with assignments and grading
- A community-driven learning hub with discussions and podcasts
- Collaborative course writing, with several authors editing the same page live

## Dependencies for LearnHouse Hosting

- Postgres with pgvector (included)
- Redis (included)

### Deployment Dependencies

- [LearnHouse on GitHub](https://github.com/learnhouse/learnhouse)
- [LearnHouse documentation](https://docs.learnhouse.app)
- [Template source](https://github.com/two-workspaces/learnhouse)

### Implementation Details

- **Services:** LearnHouse (nginx in front of the Next.js web app, the Python API and the live collaboration server), Postgres 16 with pgvector, and Redis 8 with append-only persistence, all on Railway's private network. Database migrations run on every start.
- **One domain variable:** the web app needs about a dozen URL settings (API, backend, cookies, CORS, CSRF, collaboration WebSocket). The template derives them all from `LEARNHOUSE_DOMAIN`. Any of them set as a variable still wins.
- **Security:** CORS and CSRF are scoped to your domain; upstream's default pattern accepts any site. Secure cookies over HTTPS, and generated secrets for sign-in tokens, web sessions and the collaboration server. If one is emptied, a replacement is generated once and kept on the volume, outside the folder LearnHouse serves files from, so the API never refuses to start for a missing secret.
- **Memory:** LearnHouse needs a 1 GB memory limit (Railway's Free plan stops at 0.5 GB): the API, web app and collaboration server idle at about 550 MB together. On a smaller limit the service shows a page saying so instead of being stopped in a loop. Railway also counts the kernel's cache of files read from the volume as the service's memory; the template drops that cache for course files every 15 minutes, so watching videos doesn't inflate the bill.
- **Processes:** the web app, API and collaboration server run under a small supervisor that restarts any of them if it stops, with their logs going straight to Railway's deploy logs.
- **Image:** upstream's official `ghcr.io/learnhouse/app:1.4.5`, pinned, plus a small entrypoint.

## Why Deploy LearnHouse on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying LearnHouse on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
