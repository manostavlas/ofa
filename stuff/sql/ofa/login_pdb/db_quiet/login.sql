SET ECHO OFF
SET TERM OFF
SET FEEDBACK OFF
SET LINES 200
SET TRIMSPO ON
SET DEFINE ON
SET VERIFY OFF
SET HEAD OFF
SET PAGES 0
SET TIME OFF
SET TIMING OFF

-- Set PDB name
column pdb_name for a12 noprint new_value pdb_name
select PDB pdb_name from v$services where PDB not like '%ROOT%';
alter session set container=&pdb_name;

ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY/MM/DD HH24:MI:SS';
SET TERM ON
