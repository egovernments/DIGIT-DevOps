# Kargo Promotions - Access and Use

<sub>[Kargo Promotions](README.md) - Access and Use</sub>

This is the day-to-day job: log in, assemble Freight, promote a release.

## Log in

Open the control plane, for example `https://kargo-latest.digit.org`.

- **GitHub SSO** - the normal path. Kargo trusts GitHub organization teams. You see and act on a project only if you are in a team the project grants access to.
- **Local admin** - a break-glass account held by the platform team, used for setup and recovery, not daily work.

### Who can do what

Access is granted per project in the project config `teams:` list. A team maps to a GitHub org team, and a role sets what it can do.

```yaml
teams:
  - name: kargo-crest
    role: admin                 # create Freight + promote
    groups: [digitnxt:kargo-crest]
  - name: kargo-studio
    role: admin
    groups: [egovernments:kargo-studio]
```

- The control plane can trust more than one GitHub org at once. Group names are `<org>:<team-slug>`, so `crest` access can come from a team in one org and `studio` access from a team in another.
- A user-owned GitHub OAuth app is third-party to each org. An org with OAuth-app access restrictions must approve the app before its private team membership can be read, or logins from that org see no teams.
- `admin` on a project can assemble Freight and promote within that project. Use a `viewer`-style team where people only need to watch.

## Assemble Freight

Freight is assembled deliberately (`freightCreationPolicy: Manual`):

1. Open the project, open the service's Warehouse.
2. Choose **one image tag** and **one chart version**.
3. Create the Freight.

Points that bite:

- **Choose the tag deliberately.** Build dates can be identical across tags, so "newest" ordering can be meaningless.
- **App image and migration image share the tag.** For `dbMigration: true` services, both `<service>` and `<service>-db` must exist for that tag.
- **The chart version must stay published** for as long as any environment uses it.
- **Freight is per service.** Releasing five services means five Freight.

## Promote

1. Select the Freight.
2. Promote it to the target stage.

What a promotion does:

1. Clones the stage's branch.
2. Writes the Freight's versions into the stage's env file (`envFileWrite: merge` - missing keys are created, everything else is left untouched).
3. Commits `kargo: promote <service> to <env>` and pushes.

The keys written:

| Key | Value | When |
|---|---|---|
| `<service>.chart-version` | Chart version from the Freight | `chart:` set |
| `<service>.image.tag` | Image tag | Service has an image |
| `<service>.initContainers.dbMigration.image.tag` | Same tag | `dbMigration: true` |

These keys are owned by Kargo; all other env-file content is written by pull request.

### How the commit reaches the branch

Promotion commits are pushed straight to the environment branch. Where the branch is protected, the push uses a GitHub App whose identity is allowed to bypass the protection rule; without that, protected-branch pushes fail. See [maintenance.md](maintenance.md#promotion-pushes-and-branch-protection).

## After promoting

Argo CD on the environment's cluster picks the commit up within about a minute and rolls the change out. Confirm it there:

- The service's Application reaches Synced and Healthy (see [Argo CD access-and-use](<../5. Argo CD/access-and-use.md>)).
- In a promotion chain, promote to the next stage only after the current one is healthy, and in order.

## Roll back

Promote the previous Freight to the same stage. Kargo writes the older versions back and Argo CD rolls the workload back. A roll back is just another promotion.
