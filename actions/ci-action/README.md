# QCP Pipeline CI for Github Actions

You can use this in your Github actions workflows to run QCP Pipeline CI steps.

## Example usage

```yaml
name: Pipeline CI

on:
  push:  # Run on pushes to all branches

concurrency: # It's recommended to set concurrency limits so that only 1 build per branch happens at once
  group: ${{ github.ref_name }}
  cancel-in-progress: false  # Let the current build keep running

jobs:
  pipeline-ci:
    runs-on: self-hosted
    steps:
    - name: checkout repository
      uses: actions/checkout@v2

    # Set up your environment here

    - name: Pipeline CI
      uses: qantas-cloud/c031-pipeline/actions/ci-action@master
```
