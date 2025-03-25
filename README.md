# DBA - OFA Artifact

Manage OFA artifat:

* Build artifact by product (oracle, sybase and mongo)
* Publish artifact to Artifactory for EV0 environment
* Promote artifact to EVX and PRD environments

## Status

| OFA Product  | Deployment Status |
|--|--|
| Oracle  | [![Build Status](https://tfs-prd.corp.ubp.ch/IT%20Software/DBA/_apis/build/status/ofa_oracle?branchName=master)](https://tfs-prd.corp.ubp.ch/IT%20Software/DBA/_build/latest?definitionId=24&branchName=master)  |
| Sybase  | [![Build Status](https://tfs-prd.corp.ubp.ch/IT%20Software/DBA/_apis/build/status/ofa_sybase?branchName=master)](https://tfs-prd.corp.ubp.ch/IT%20Software/DBA/_build/latest?definitionId=26&branchName=master) |
| Mongo   | [![Build Status](https://tfs-prd.corp.ubp.ch/IT%20Software/DBA/_apis/build/status/ofa_mongo?branchName=master)](https://tfs-prd.corp.ubp.ch/IT%20Software/DBA/_build/latest?definitionId=25&branchName=master) |

## Deployment

### General

For each product (oracle, sybase or mongo), the main deployment steps are :

1. Build OFA artifact
   1. Checkout the OFA code source branch from `ofa` git repository
   2. Search the latest OFA artifact version `<x>.<y>.<z>` in Artifactory under `ubp-applications-ev0/ubp.ofa/ofa_<product>`
   3. Calculate the next OFA artifact version :
      * `<x>.<y>.<z+1>-beta` when source branch is __not__ `master`
      * `<x>.<y>.<z+1>-RC` when triggered by a Pull Request
      * `<x>.<y>.<z+1>` when source branch is `master`
   4. Create the new archive file ([Archive Creation](#archive-creation))
   5. Publish the built artifact on Azure
   6. If branch is `master`, add a tag `ofa_<product>-<version>` on it

2. Publish OFA artifact to Artifactory -- only if source branch is `master` __or__ triggered by a Pull Request
   1. Download build artifact from Azure (created at 1.5)
   2. Upload artifact to Artifactory in `ubp-applications-ev0/ubp.ofa/ofa_<product>` repository (UBP Applications __EV0__)
   3. Publish build information in Artifactory
   4. Check artifact for security vulnerabilities (Xray scan)
   5. Discard old builds (max 10) in Artifactory

3. Promote OFA artifact to EVX -- only if source branch is `master`
   1. Promote artifact from EV0 (step 2) to EVX `ubp-applications-evx/ubp.ofa/ofa_<product>` repository (UBP Applications __EVX__)

4. Promote OFA artifact to Production -- only if source branch is `master`
   1. Approve the promotion
   2. Promote artifact from EVX (step 3) to PRD `ubp-applications-prd/ubp.ofa/ofa_<product>` repository (UBP Applications __PRD__)

### Triggers

The build process for a given product is triggered in the following cases:

* A Pull Request has been requested and a change has been made in the paths :
  * `ofa/stuff/*`
  * `ofa/local/base/*`
  * `ofa/local/<product>/*`
* A merge on `master` branch has been requested and a change has been made in the paths :
  * `ofa/stuff/*`
  * `ofa/local/base/*`
  * `ofa/local/<product>/*`

### Archive Creation

The archive creation is common to all products :

1. Create directory `ofa/stuff/doc/ofa/VERSION` and write :
   1. date time in `OFA.lastchck`
   2. new version to `OFA.version.tag`
   3. hostname to `OFA.hostname`$
   4. build to `OFA.version`
   5. nothing to `OFA.changed_files`, `OFA.md5.stamp`, `OFA.changed_files.log`
2. Bundle ofaadm
   1. List files in `ofa/stuff` excluding ones that match step 2
   2. Add obtained files in the product archive in `stuff`
3. Bundle base
   1. List files in `ofa/local/base` excluding ones that match step 2
   2. Add obtained files in the product archive in `local/<product>`
4. Bundle product
   1. List files in `ofa/local/<product>` excluding ones that match step 2
   2. Add obtained files in the product archive in `local/<product>`
5. Create logs diretory in the product archive `local/<product>/logs`
6. Create symbolic links :
   * `local/dba` -> `<product>`
   * `local/ofa` -> `../stuff`
   * `local/oracle/doc/ofa` -> `../../ofa/doc/ofa`
   * `local/oracle/etc/ofa` -> `../../ofa/etc/ofa`
   * `local/oracle/fct/ofa` -> `../../ofa/fct/ofa`
   * `local/oracle/sql/ofa` -> `../../ofa/sql/ofa`
7. Set directories and files permissions :
   1. All directories to 0770 (`drwxrwx---`)
   2. All files to 0660 (`-rw-rw----`)
   3. Files to 0770 (`-rwxrwx---`) matching the paths :
      * `*/script/*`
      * `*/bin/*`
8. Create the artifcact `ofa_<product>-<new version>.tar.gz`
