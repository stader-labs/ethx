# ethx

```shell
npx hardhat help
npx hardhat test
GAS_REPORT=true
npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.ts
```

# Repository Conventions

### Types

- fix: Commits that fixes a bug
- feat: Commits that adds a new feature
- refactor: Commits that rewrite/restructure your code, however does not change any behaviour
- docs: Commits that affect documentation only
- chore: Miscellaneous commits e.g. modifying .gitignore

### Branches

#### Naming

```
{type}/{description-separated-by-dashes}
e.g. 'fix/add-natspec-comments'
```

- Branch names must be descriptive of what is being worked on
- Branch names must include the type of work being done
- The description portion must be in present tense
- Once the branch has been merged via PR it must be closed

#### Commits

```
{type}: {description}
e.g. 'docs: add conventions to Readme.md'
```

- Commit names must include a general description of the change
- The description portion must be in present tense
- Commits must have a type associated

#### Pull Requests

```
{linked jira issue} {description of the change}
e.g. 'ES-68 Add repository conventions to documentation'
```

- Pull Requests names should indicate a linked Jira Issue when possible
- PR names must include a description
- PR name description must be in present tense
- A brief description of what's being changed should be added to the PR
- A PR must include two reviewers
- A PR must only be merged after it has been approved by reviewers
