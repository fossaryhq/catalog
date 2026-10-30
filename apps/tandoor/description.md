# Tandoor

Tandoor is a household recipe library with ingredients, preparation steps, photographs, cookbooks, a meal calendar and shared shopping lists. It suits families who want to plan meals and reuse a common collection on their own server. It replaces parts of Paprika Recipe Manager, Recipe Keeper and AnyList; it does not bundle their paid apps or cloud services. Compared with Mealie, it offers another approach to recipe organization, meal planning and shopping, with a different license.

**Tandoor is source-available, not OSI-approved open source.** Its license is GNU AGPL v3 with the Commons Clause selling restriction. Personal and internal use are allowed, but the license does not grant the right to sell the software or services whose value derives substantially from it, including hosting and related consulting/support. Review the [actual license](https://github.com/TandoorRecipes/recipes/blob/2.7.2/LICENSE.md) before offering a service. The recipe files use MIT; the logo's upstream notice and license are preserved in `assets/NOTICE` and `assets/LICENSE`.

This recipe uses the official Tandoor 2.7.2 image, PostgreSQL 18.6 and an Alpine 3.22.2 initialization/archive helper. The application includes Nginx and Gunicorn and runs as UID/GID 65534; initialization prepares only the media/static volume roots. The database and media are persistent, while static assets are regenerated from the pinned image at startup. External AI providers, storage integrations, social identity providers and SMTP are not configured.

The web interface supports English and Russian. The [official related-project directory](https://docs.tandoor.dev/contribute/related/) lists the third-party **kitshn** client for Android and iOS; it is not installed or tested here. There is no desktop client in this recipe. Untare is listed upstream as discontinued and is not the recommended mobile option.

Local username/password login uses the browser authentication API. Bundled django-allauth providers support OIDC and SAML, and a reverse-proxy user-header mode exists; the recipe leaves all three disabled. No embedded second factor is enabled in this build. Use a properly configured identity provider if you need MFA, and never enable remote-user authentication behind a proxy that accepts an identity header from a visitor.

<!-- coverage:security-assessment -->
The security assessment records warnings. The first visitor to `/setup/` can create the owner, so bootstrap through loopback or an SSH tunnel before opening the proxy or LAN access. Ordinary signup is explicitly disabled. Permit trusted accounts, restrict server-side import access to sensitive internal services, protect the volumes and encrypt off-server backups.

Uploaded images are served by Nginx without per-file authorization. Marking a recipe private protects the recipe API, but does not make a known image URL private. Do not store sensitive photographs. Recipes, household membership, meal plans and integration credentials live in PostgreSQL and backups; the media archive and `.env` are equally sensitive.

Upstream 2.7.2 has a [known setup redirect bug (#4907)](https://github.com/TandoorRecipes/recipes/issues/4907): revisiting `/setup/` after the owner exists returns HTTP 500. Use `/account/login/` for ordinary access. The recipe does not patch upstream authentication or treat that error as a successful protection check; the smoke test checks the actual closed-signup configuration instead.

The amd64 recovery scenario creates an owner through the native CSRF form, signs in, stores a private recipe with an ingredient, instructions, keyword and uploaded image, deletes all three volumes and verifies restored data and the stored image hash. arm64, meal-plan timing, shopping synchronization, URL imports, identity providers, mail, AI and mobile clients remain untested. Five CRITICAL package findings across the pinned images remain visible in the security snapshot.

Allow at least 1 CPU, 1 GiB RAM and 5 GiB disk; 2 GiB RAM gives more room for PostgreSQL and two Gunicorn workers. These are deployment estimates, not a load-test guarantee. Home and VPS deployment are supported after safe bootstrap; the reliable level remains partial because external monitoring, resource limits and backup scheduling are operator tasks.

Sources: [Docker installation](https://docs.tandoor.dev/install/docker/), [configuration](https://docs.tandoor.dev/system/configuration/), [authentication](https://docs.tandoor.dev/features/authentication/), [SAML provider](https://docs.allauth.org/en/latest/socialaccount/providers/saml.html), and [2.7.2 release notes](https://github.com/TandoorRecipes/recipes/releases/tag/2.7.2).
