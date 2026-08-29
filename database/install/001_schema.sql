WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing synthetic POC schema...
@@../01_schema.sql
PROMPT Synthetic POC schema installed.
