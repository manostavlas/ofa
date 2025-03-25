# Initialization

Reports the procedure to set up the OFA :

1. Upload the latest OFA package and do some clean up and adaptation
2. Azure project and repository configuration

## OFA Package Adaptation

Upload the the latest OFA package and do some clean up, adapt the package build :

1. Set vars

    ``` bash
      export WKDIR='/home/aie/work/git-evx/it-software/ofa'
      export OFAVER='20220923.13.40.24'
    ```

2. Get ofa package [ofa-OFAVER.tar](https://almbinaryrepo.corp.ubp.ch:443/artifactory/ubp-applications-prd/ubp_ofa/ofa/ofa-[RELEASE].tar)

3. Prepare working dir

    ``` bash
      cd $WKDIR
      mkdir -p build ofa/local/base ofa/stuff ofa/local/oracle ofa/local/sybase ofa/local/mongo
    ```

4. Extract it in the git working copy

    ``` bash
    tar -xf /depot/ofa-$OFAVER.tar
    tar -xf ofa.ofaadm.$OFAVER.tgz -C ofa/stuff
    tar -xf ofa.base.$OFAVER.tgz -C ofa/local/base
    tar -xf ofa.oracle.$OFAVER.tgz -C ofa/local/oracle
    tar -xf ofa.sybase.$OFAVER.tgz -C ofa/local/sybase
    tar -xf ofa.mongo.$OFAVER.tgz -C ofa/local/mongo
    rm -f *.tgz
    ```

5. Clean up

    1. Remove package (will be moved in Artifactory)

        ``` bash
        # SQLC
        rm -rf ofa/local/oracle/sqlcl

        # Auto upgrade
        rm ofa/local/oracle/bin/autoupgrade_newest.jar
        ```

    2. Clean up in `ofa/stuff` : unused or temporary

        ``` bash

        # Unused
        rm -f ofa/stuff/bin/install_ofa_master.sh
        rm -f ofa/stuff/bin/bundle_ofa*
        rm -f ofa/stuff/bin/create.ofa.rpm.file.sh
        rm -f ofa/stuff/bin/deploy_ofa*
        rm -f ofa/stuff/bin/load.ofa*

        # Unused
        rm -rf ofa/stuff/doc/ofa/LICENCE
        rm -f ofa/stuff/doc/ofa/VERSION/*

        # Temporary ?
        rm ofa/stuff/etc/deploy_ofa/deploy_ofa.custom
        rm ofa/stuff/etc/deploy_ofa/deploy_ofa.defaults.orig
        rm ofa/stuff/etc/deploy_ofa/deploy_ofa.lxvgvagrdprd01p
        rm ofa/stuff/etc/deploy_ofa/deploy_ofa.oragridlx

        # Keys to be put in playbook vault
        rm -rf ofa/stuff/etc/ofa/.ofa_s

        # Old ?
        rm -rf ofa/stuff/etc/ofa/dry3_custom
        rm -rf ofa/stuff/etc/ofa/dry3_SITE.SAMPLE

        # Temporary ?
        rm -f ofa/stuff/etc/ofa/0fa_load.rc.asg

        # Temporary ?
        rm -rf ofa/stuff/etc/ofaadm/
        rm -f ofa/stuff/etc/ofaadm/ofaadm_settings.defaults.new
        rm -f ofa/stuff/etc/ofaadm/ofaadm_settings.lxsgvabmcprd11s
        rm -f ofa/stuff/etc/ofaadm/ofaadm_settings.lxsgvabmcprd12s
        rm -f ofa/stuff/etc/ofaadm/ofaadm_settings.lxvgvagrdprd02p
        rm -f ofa/stuff/etc/ofaadm/ofaadm_settings.oragridlx
        rm -f ofa/stuff/etc/ofaadm/ofa_reflist.graft.orig
        rm -f ofa/stuff/etc/ofaadm/Ofatab.lxvgvagrdprd02p
        rm -f ofa/stuff/etc/ofaadm/Ofatab.lxvgvagrdprd02p.070318
        rm -f ofa/stuff/etc/ofaadm/Ofatab.lxvgvagrdprd02p.190529
        rm -f ofa/stuff/etc/ofaadm/Ofatab.lxvgvagrdprd02p.20141218
        rm -f ofa/stuff/etc/ofaadm/Ofatab.lxvgvagrdprd02p.oracle.ev
        rm -f ofa/stuff/etc/ofaadm/Ofatab.lxvgvagrdprd02p.orig
        rm -f ofa/stuff/etc/ofaadm/Ofatab.oragridlx

        # Should be in ofa/local/sybase/fct/sybase/sybase_functions.defaults
        rm -rf ofa/stuff/fct/sybase

        rm ofa/stuff/install/Install_DB_rc.sh
        rm ofa/stuff/install/InstallOFA.sh
        rm ofa/stuff/install/ofa_bash_profile.new
        rm ofa/stuff/install/ofa_bash_profile.old

        # Temporary ?
        rm -rf ofa/stuff/script
        ```

    3. Clean up in `ofa/local/base` : unused or temporary

        ``` bash

        # Links to be build in archive only
        #
        #  cd ofa/local/base/etc/ofa_step
        # ? ofa_step.puttar_noveri.rc -> ofa_step.putfiles.rc
        # ? ofa_step.puttar.rc -> ofa_step.putfiles.rc
        #
        rm ofa/local/base/etc/ofa_step/ofa_step.puttar_noveri.rc
        cp -p ofa/local/base/etc/ofa_step/ofa_step.putfiles.rc ofa/local/base/etc/ofa_step/ofa_step.puttar_noveri.rc
        rm ofa/local/base/etc/ofa_step/ofa_step.puttar.rc
        cp -p ofa/local/base/etc/ofa_step/ofa_step.putfiles.rc ofa/local/base/etc/ofa_step/ofa_step.puttar.rc

        # Links to be build in archive only
        #
        rm ofa/local/base/doc/ofa
        rm ofa/local/base/fct/ofa
        rm ofa/local/base/etc/ofa
        rm ofa/local/base/sql/ofa

        # Temporary ?
        rm -rf ofa/local/base/script/tmp
        rm -rf ofa/local/base/script/work
        ```

    4. Clean up in `ofa/local/mongo` : unused or temporary

        ``` bash

        # Links to be build in archive only
        rm ofa/local/mongo/fct/ofa
        rm ofa/local/mongo/etc/ofa
        ```

    5. Clean up in `ofa/local/oracle` : unused or temporary

        ``` bash

        # Links to be destroy
        #
        #  cd ofa/local/oracle/etc/oracle
        # ? oracle_settings.INSTANCE.SAMPLE -> oracle_settings.DBNAME.SAMPLE
        #
        rm ofa/local/oracle/etc/oracle/oracle_settings.INSTANCE.SAMPLE
        cp -p ofa/local/oracle/etc/oracle/oracle_settings.DBNAME.SAMPLE ofa/local/oracle/etc/oracle/oracle_settings.INSTANCE.SAMPLE

        # Links to be build in archive only
        #
        rm ofa/local/oracle/doc/ofa
        rm ofa/local/oracle/fct/ofa
        rm ofa/local/oracle/etc/ofa
        rm ofa/local/oracle/sql/ofa

        # Temporary ?
        rm -f ofa/local/oracle/bin/CreOraUser.sh.new
        ```

    6. Clean up in `ofa/local/sybase` : unused or temporary

        ``` bash

        # Links to be build in archive only
        #
        rm ofa/local/sybase/doc/ofa
        rm ofa/local/sybase/fct/ofa
        rm ofa/local/sybase/etc/ofa
        rm ofa/local/sybase/sql/ofa

        # Temporary ?
        rm -f ofa/local/sybase/etc/sybase/rsybtab.old
        rm -f ofa/local/sybase/script/migration/¨
        rm -f ofa/local/sybase/script/migration/*.out
        ```

## Azure Configuration

Configure Azure for OFA package build :

1. Create variables to be used by the pipeline
   1. Go to Pipelines -> Library  and create Variable group : __ofa_artifactory__ with the following variables :
      * `ofa_artifact_url` : https://almbinaryrepo.corp.ubp.ch
      * `ofa_artifact_repo` : ubp-applications-ev0
      * `ofa_artifact_group_id` : ubp.ofa
      * `ofa_artifact_id_pre` : ofa
      * `ofa_artifactory_user` : sa_ubp_ofa-alm_evz
      * `ofa_artifactory_password` : see CyberArk
   1. Go to Pipelines -> Library  and create Variable group : __ofa_product_`<product>`__ with the following variables :
      * `ofa_product` : `<product>`
      * `ofa_major_minor_version` : `X.Y`

2. Configure branch policy
   1. Go to Repos -> Branches
   2. Hit vertical `...` of `master` branch, and select _Branch policies_
      1. Enable _Require a mininum number of reviewers_
         1. set _Minimum number of reviewers_ to __1__
         2. check _Allow requestors to approve their own changes_
         3. check _When new changes are pused_, select _Reset all code reviewer votes_
      2. Build Validation
         1. hit _+_ button _Add build policy_
         2. set _Build pipeline_ to `ofa_<product>`
         3. set _Path filter_ to `/ofa/stuff/*;/ofa/local/base/*;/ofa/local/<product>/*`
3. Project settings
   1. Grant pipeline execution to push tag on branch
      1. Go to Repos -> Repositories
      2. Select `ofa` repository
      3. Hit _Permissions_ tab
      4. Search _Project Collection Build Service (IT Software)_
      5. Set _Contribute_ to __Allow__
   2. Artifactory service connection
      1. Go to Pipelines -> Service connections
      2. Hit _Create service connection_
      3. Select _Artifactory_, hit _Next_
      4. _New Artifactory service connection_
         1. select _Basic Authentication_
         2. set _Server URL_ to https://almbinaryrepo.corp.ubp.ch
         3. set _Username_ to __sa_ubp_ofa_alm_evz__
         4. set _Password_ accordinately
         5. set _Service connection name_ to __Artifactory_DBA__
         6. hit _Verify and save_
4. Environments creation
   1. Go to Pipelines -> Environments
   2. Hit _Create environment_
   3. _New environment_
      1. set _Name_ to __EV0__
      2. hit _Create_
   4. Go back to Environments
      1. hit _New environment_
      2. set _Name_ to __EVX__
      3. hit _Create_
   5. Go back to Environments
      1. hit _New environment_
      2. set _Name_ to __PRD__
      3. hit _Create_
      4. hit vertical `...` and select _Approvals and checks_, hit _+_
      5. select _Approvals_, hit _Next_
      6. set _Approvers_ to __[DBA]\UBP Admin__, hit _Save_