/*--------------------------------------------------------------------------------------------------------------------------------------
	<Author			:-> Steve Oliai
	<Start Date		:-> 10/01/2021
	<Requirement Desc	:-> To mimic pagination in a more efficient way for large data sets from the DB to support stateless applications

----------------------------------------------------------------------------------------------------------------------------------------
-- History:
-- Modified Date		Modified by		Reason Of Changes
----------------------------------------------------------------------------------------------------------------------------------------
12-21-2021              Steve Oliai     Added a Sort Option
12-24-2021              Steve Oliai     Added no data found exception handler
--------------------------------------------------------------------------------------------------------------------------------------*/
--table for logging/resuming report

create table acct15m.report_settings (
    reportid number GENERATED ALWAYS as IDENTITY(START with 1 INCREMENT by 1),
    reportname varchar2(128),
    dayinterval number,
    modifiedon date default sysdate,
    forcesetting char(1) default 'N',
    primary key (reportid)
);

create table acct15m.report_instance (
    reportinstanceid number GENERATED ALWAYS as IDENTITY(START with 1 INCREMENT by 1),,
    reportid number, 
    sessionid varchar2(128),
    reportname varchar2(128),
    reportconditions varchar2(2000),
    columnlist varchar2(1000),
    numrows number,
    numrecsinrpt number,
    pageno  number,
    datefrom date,
    dateto date,
    pagedatefrom date,
    pagedateto date,
    pkid number,
    dayinterval number,
    sort varchar2(4);
    createdon date default sysdate,
    primary key (reportinstanceid)
);


--table for logging/resuming report

create table acct15m.report_scroll (
    reportscrollid number GENERATED ALWAYS as IDENTITY(START with 1 INCREMENT by 1),
    reportinstanceid number,
    sessionid varchar2(128),
    reportname varchar2(128),
    pageno  number,
    numrows number,
    datefrom date,
    dateto date,
    pagedatefrom date,
    pagedateto date,
    pkid number,
    dayinterval number,
    createdon date default sysdate,
    primary key (reportscrollid)
);

--create index report_scroll_check on acct15m.report_scroll(upper(sessionid), upper(reportname));




create or replace procedure  acct15m.REPORT_PAGINATOR(t_reportname varchar2, t_collist VARCHAR2, t_reportconditions varchar2, t_pkcolname varchar2, t_datecolname varchar2, t_sessionid IN VARCHAR2, t_numrows IN NUMBER, t_dtfrom IN DATE, t_dtto IN DATE, t_pageno_in IN NUMBER, t_sort IN VARCHAR2, t_hasmore OUT CHAR, t_rec_output OUT SYS_REFCURSOR)
AS
t_check NUMBER;
t_checkrpt NUMBER;
t_checkforce NUMBER;
t_checkpagecount NUMBER;
t_lastrunto DATE;
t_newrunfrom DATE;
t_newrunto DATE;
t_pagerunto DATE;
t_pagerunfrom DATE;
t_pageno NUMBER;
t_dayinterval NUMBER;
t_rptdayrange NUMBER;
t_numrecsinrpt NUMBER;
t_maxid NUMBER;
t_pkid NUMBER;
t_newpkid NUMBER;
t_rec_check_sqlstmt VARCHAR2(2000);
t_get_param_sqlstmt VARCHAR2(2000);
t_sqlstmt VARCHAR2(2000);
t_rundate DATE := SYS_EXTRACT_UTC(SYSTIMESTAMP);
t_reportinstanceid NUMBER;

BEGIN

    if t_pageno_in is null then -- not lookng for a prebuilt page
        select count(*) into t_checkforce from acct15m.report_settings where upper(reportname) = upper(t_reportname) and forcesetting = 'Y';
        if t_checkforce = 1 then 
            select dayinterval into t_dayinterval from acct15m.report_settings where upper(reportname) = upper(t_reportname) and forcesetting = 'Y' order by modifiedon desc fetch first 1 rows only;
            --could add logic here to select a recent interval if one exists to avoid extra work below    
        end if;
        --need to find out if this report has been run in the last hour
        select nvl(max(reportinstanceid), 0) into t_reportinstanceid from acct15m.report_instance where upper(sessionid) = upper(t_sessionid) and upper(reportname) = upper(t_reportname) and upper(columnlist) = upper(t_collist) and upper(reportconditions) = upper(t_reportconditions) and upper(sort) = upper(t_sort) and datefrom = t_dtfrom and dateto = t_dtto and createdon > sysdate - (1/24);
        if t_reportinstanceid = 0 then --this is the first run
            t_newrunfrom := t_dtfrom;
            t_newrunto := t_dtto;
            t_pkid := 0;
            t_pageno := 1;

            --prepare a statement to check for total records in report
            t_rec_check_sqlstmt := 'select count(*), max('||t_pkcolname||') + 1 from '||t_reportname||' where '||t_reportconditions||' and '||t_datecolname||' >= :2 and '||t_datecolname||' <= :3 ';
            execute immediate t_rec_check_sqlstmt into t_numrecsinrpt, t_maxid using t_dtfrom, t_dtto;

            if upper(t_sort) = 'DESC' then  --need to go in reverse order
                t_pkid := t_maxid;
            end if;

            if t_dayinterval is null then
                --find a suitable day interval
                t_rptdayrange := round(t_dtto - t_dtfrom);
                if t_rptdayrange > 7 then  --process in batches


                    if t_numrecsinrpt < 10000 then  --if total count < 10000
                        t_dayinterval := t_dtto - t_dtfrom;  --pass the whole range
                    elsif t_numrecsinrpt/t_rptdayrange <= t_numrows and t_numrecsinrpt > 10000  then --if daily average is less than number to display per page and total count > 10000
                        t_dayinterval := 7;
                    else  --it's greater than 10000 and  daily average is greater than number to display per page
                        t_dayinterval := 1;
                    end if;
                else 
                    t_dayinterval := t_dtto - t_dtfrom;  --pass the whole range    
                end if;
                if upper(t_sort) = 'ASC' then
                    t_newrunto := t_newrunfrom + t_dayinterval;
                else
                    t_newrunfrom := t_newrunto - t_dayinterval; -- descending order by default
                end if;    
            else
                if upper(t_sort) = 'ASC' then
                    t_newrunto := t_newrunfrom + t_dayinterval; --use predefined interval
                else
                    t_newrunfrom := t_newrunto - t_dayinterval; -- descending order by default
                end if; 
            end if;    
        else 
            -- get the last page generated for the report
            -- get values from the last run to pass to the ref cursor
            if upper(t_sort) = 'ASC' then
                select pageno, pagedateto, pkid, dayinterval, numrecsinrpt into t_pageno, t_newrunfrom, t_pkid, t_dayinterval, t_numrecsinrpt from acct15m.report_instance where reportinstanceid = t_reportinstanceid order by createdon desc fetch first 1 rows only;
                t_pageno := t_pageno + 1; --adding one here for insert below            
                t_newrunto := t_newrunfrom + t_dayinterval;
            else
                select pageno, pagedatefrom, pkid, dayinterval, numrecsinrpt into t_pageno, t_newrunto, t_pkid, t_dayinterval, t_numrecsinrpt from acct15m.report_instance where reportinstanceid = t_reportinstanceid order by createdon desc fetch first 1 rows only;
                t_pageno := t_pageno + 1; --adding one here for insert below
                t_newrunfrom := t_newrunto - t_dayinterval; 
            end if;     
        end if;

        --make sure we don't go passed date range
        if t_newrunto > t_dtto then 
            t_newrunto := t_dtto;
        end if;

        --make sure we are getting the specified number of rows to display per page
        t_checkpagecount := 0;
        --prepare a statement to check for total records in page
        if upper(t_sort) = 'ASC' then
            t_rec_check_sqlstmt := 'select count(*) from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' > :2 and '||t_datecolname||' <= :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' > :5))';
            execute immediate t_rec_check_sqlstmt into t_checkpagecount using t_newrunfrom , t_newrunto, t_newrunfrom, t_pkid;
        else
            t_rec_check_sqlstmt := 'select count(*) from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' >= :2 and '||t_datecolname||' < :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' < :5))';
            execute immediate t_rec_check_sqlstmt into t_checkpagecount using t_newrunfrom , t_newrunto, t_newrunto, t_pkid;
        end if;

        if upper(t_sort) = 'ASC' then
            WHILE t_checkpagecount < t_numrows and t_newrunto < t_dtto LOOP  --if less than number to display add the interval and we have not met the date range
                t_newrunto := t_newrunto + t_dayinterval;
                if t_newrunto > t_dtto then
                    t_newrunto := t_dtto;
                end if;
                -- get a new count with the new range
                t_rec_check_sqlstmt := 'select count(*) from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' > :2 and '||t_datecolname||' <= :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' > :5))';
                execute immediate t_rec_check_sqlstmt into t_checkpagecount using t_newrunfrom , t_newrunto, t_newrunfrom, t_pkid;

            END LOOP;

        else
            --if descending sort order
            WHILE t_checkpagecount < t_numrows and t_newrunfrom > t_dtfrom LOOP  --if less than number to display add the interval and we have not met the date range
                t_newrunfrom := t_newrunfrom - t_dayinterval;
                if t_newrunfrom < t_dtfrom then
                    t_newrunfrom := t_dtfrom;
                end if;
                -- get a new count with the new range
                t_rec_check_sqlstmt := 'select count(*) from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' >= :2 and '||t_datecolname||' < :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' < :5))';
                execute immediate t_rec_check_sqlstmt into t_checkpagecount using t_newrunfrom , t_newrunto, t_newrunto, t_pkid;

            END LOOP;

        end if;    

        --need to get new data for insert into report_scroll
        if upper(t_sort) = 'ASC' then
            t_get_param_sqlstmt := 'select '||t_datecolname||', '||t_pkcolname||' from (select '||t_datecolname||', '||t_pkcolname||' from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' > :2 and '||t_datecolname||' <= :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' > :5)) order by '||t_datecolname||', '||t_pkcolname||' fetch first :6 rows only) order by '||t_datecolname||' desc, '||t_pkcolname||' desc  fetch first 1 rows only';
            execute immediate t_get_param_sqlstmt into t_pagerunto, t_newpkid using t_newrunfrom , t_newrunto, t_newrunfrom, t_pkid, t_numrows;
            t_pagerunfrom := t_newrunfrom;
        else
            t_get_param_sqlstmt := 'select '||t_datecolname||', '||t_pkcolname||' from (select '||t_datecolname||', '||t_pkcolname||' from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' >= :2 and '||t_datecolname||' < :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' < :5)) order by '||t_datecolname||' desc, '||t_pkcolname||' desc fetch first :6 rows only) order by '||t_datecolname||' , '||t_pkcolname||' fetch first 1 rows only';
            execute immediate t_get_param_sqlstmt into t_pagerunfrom, t_newpkid using t_newrunfrom , t_newrunto, t_newrunto, t_pkid, t_numrows;
            t_pagerunto := t_newrunto;
        end if;


        --check if we have a report entry w/o forced params
        select nvl(max(reportid), 0) into t_checkrpt from acct15m.report_settings where upper(reportname) = upper(t_reportname);
        if t_checkrpt = 0 then
            insert into acct15m.report_settings (reportname, dayinterval) values (t_reportname, t_dayinterval);
        end if;

        --insert our settings/info
        if t_pageno = 1 then --insert the instance record
            insert into acct15m.report_instance(sessionid, reportname, reportconditions, columnlist, pageno, numrows, numrecsinrpt, datefrom, dateto, pagedatefrom, pagedateto, pkid, dayinterval, sort)
                values (t_sessionid, t_reportname, t_reportconditions, t_collist, t_pageno, t_numrows, t_numrecsinrpt, t_dtfrom, t_dtto, t_pagerunfrom, t_pagerunto, t_newpkid, t_dayinterval, t_sort);
            select nvl(max(reportinstanceid), 0) into t_reportinstanceid from acct15m.report_instance;    
        else --update the existing row        
            update acct15m.report_instance set pageno = t_pageno, pagedatefrom = t_pagerunfrom, pagedateto = t_pagerunto, pkid = t_newpkid where reportinstanceid = t_reportinstanceid;
        end if;
        insert into acct15m.report_scroll(sessionid, reportinstanceid, reportname, pageno, numrows, datefrom, dateto, pagedatefrom, pagedateto, pkid, dayinterval)
            values (t_sessionid, t_reportinstanceid, t_reportname, t_pageno, t_numrows, t_dtfrom, t_dtto, t_pagerunfrom, t_pagerunto, t_newpkid, t_dayinterval);

    else  -- they want a specific page that is already generated
        select pagedatefrom, pagedateto into t_newrunfrom, t_newrunto from acct15m.report_scroll where pageno = t_pageno_in and upper(sessionid) = upper(t_sessionid) and upper(reportname) = upper(t_reportname) and datefrom = t_dtfrom and dateto = t_dtto and createdon > sysdate - (1/24);
        --need the PKID from the previous page
        select nvl(max(pkid),0) into t_pkid from acct15m.report_scroll where pageno < t_pageno_in and upper(sessionid) = upper(t_sessionid) and upper(reportname) = upper(t_reportname) and datefrom = t_dtfrom and dateto = t_dtto and createdon > sysdate - (1/24);
    end if;
    --set indicator to inform if more records in report
    if (t_pageno * t_numrows) >= t_numrecsinrpt then
        t_hasmore := 'N';
    else
        t_hasmore := 'Y';
    end if;
    --build the SQL
    if upper(t_sort) = 'ASC' then
        t_sqlstmt := 'select '||t_collist||' from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' > :2 and '||t_datecolname||' <= :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' > :5)) order by '||t_datecolname||', '||t_pkcolname||' fetch first :6 rows only';
        OPEN T_REC_OUTPUT FOR t_sqlstmt USING t_newrunfrom , t_newrunto, t_newrunfrom, t_pkid, t_numrows;
    else
        t_sqlstmt := 'select '||t_collist||' from '||t_reportname||' where '||t_reportconditions||' and (('||t_datecolname||' >= :2 and '||t_datecolname||' < :3) or ('||t_datecolname||' = :4 and '||t_pkcolname||' < :5)) order by '||t_datecolname||' desc, '||t_pkcolname||' desc fetch first :6 rows only';
        OPEN T_REC_OUTPUT FOR t_sqlstmt USING t_newrunfrom , t_newrunto, t_newrunto, t_pkid, t_numrows;
    end if;    

    exception when no_data_found then
        t_hasmore := 'N';

END;

/


create view acct15m.acct_trans_vw1 as            
SELECT A.ACC_ID as ACC_ID, A.ACC_NUMBER AS ACC_NUMBER, A.ACC_NAME AS ACC_NAME,T.BANK_ID AS BANK_ID, NULL AS RES_ID, NULL AS RES_CURRENCY_CODE, T.TX_CODE AS TX_CODE, NULL AS RES_AMOUNT, NULL AS RES_DATE, NULL AS RES_EXPIRE_DATE, T.TEXT AS TEXT, NULL AS MATCH_REF, NULL AS STATUS, NULL AS ORIGINAL_AMOUNT, NULL AS RES_REG_TIMESTAMP, NULL AS RES_CODE, T.TX_ID AS TX_ID, T.CURRENCY_CODE AS CURRENCY_CODE, T.AMOUNT AS AMOUNT, T.BOOK_DATE AS BOOK_DATE, T.DEBCRED_IND AS DEBCRED_IND, T.ORG_CURRENCY_CODE ORG_CURRENCY_CODE, T.EXCH_RATE AS EXCH_RATE, T.ORG_CUR_AMOUNT AS ORG_CUR_AMOUNT, T."DOMAIN" AS "DOMAIN", T.FAMILY AS FAMILY, T.SUB_FAMILY AS SUB_FAMILY, T.ETOE_REF AS ETOE_REF, T.PAYM_REF AS PAYM_REF, T.EXTERNAL_REF AS EXTERNAL_REF, T.ADD_REF AS ADD_REF, T.ADDITIONAL_ENTRY_INFO AS ADDITIONAL_ENTRY_INFO, T.INITIATOR AS INITIATOR, T.TX_CODE_TEXT AS TX_CODE_TEXT, T.VALUE_DATE AS VALUE_DATE, T.TRAN_PAYM_AMT_TEXT AS TRAN_PAYM_AMT_TEXT, T.REG_TIMESTAMP AS REG_TIMESTAMP, T.RESERVATION_ID AS RESERVATION_ID, T.EXCEP_CONTRA_TRANS AS EXCEP_CONTRA_TRANS, T.SENT_FROM_EXCEPTION AS SENT_FROM_EXCEPTION, T.ERROR_CODE AS ERROR_CODE, T.ERROR_ACCOUNT_REF AS ERROR_ACCOUNT_REF, T.MOVED_TO_ACCOUNT AS MOVED_TO_ACCOUNT, T.MOVED_TO_DATE AS MOVED_TO_DATE, T.RMTINF_USTRD AS RMTINF_USTRD, T.ACCT_REF AS ACCT_REF_IN_TX, T.VRA_NUM AS VRA_NUMBER, T.COND_FUNC_ID AS COND_FUNC_ID, T.COND_CODE AS COND_CODE
			FROM acct15m.ACCOUNT A, acct15m.TRANSACTION T
			WHERE
			A.ACC_ID = T.ACC_ID;
            

DECLARE
  T_REPORTNAME VARCHAR2(200);
  T_COLLIST VARCHAR2(200);
  T_REPORTCONDITIONS VARCHAR2(200);
  T_PKCOLNAME VARCHAR2(200);
  T_DATECOLNAME VARCHAR2(200);
  T_SESSIONID VARCHAR2(200);
  T_NUMROWS NUMBER;
  T_DTFROM DATE;
  T_DTTO DATE;
  T_PAGENO_IN NUMBER;
  T_SORT VARCHAR2(200);
  T_HASMORE CHAR(200);
  T_REC_OUTPUT SYS_REFCURSOR;
BEGIN
  T_REPORTNAME := 'acct15m.acct_trans_vw1';
  T_COLLIST := 'ACC_ID, ACC_NUMBER, ACC_NAME, BANK_ID, TX_CODE, BOOK_DATE, TX_ID';
  T_REPORTCONDITIONS := 'ACC_ID =1934863';
  T_PKCOLNAME := 'TX_ID';
  T_DATECOLNAME := 'BOOK_DATE';
  T_SESSIONID := '3';
  T_NUMROWS := 15;
  T_DTFROM := to_date('2021-07-12','yyyy-MM-dd');
  T_DTTO := to_date('2021-10-12','yyyy-MM-dd');
  T_PAGENO_IN := NULL;
  T_SORT := 'DESC';

  ACCT15M.REPORT_PAGINATOR(
    T_REPORTNAME => T_REPORTNAME,
    T_COLLIST => T_COLLIST,
    T_REPORTCONDITIONS => T_REPORTCONDITIONS,
    T_PKCOLNAME => T_PKCOLNAME,
    T_DATECOLNAME => T_DATECOLNAME,
    T_SESSIONID => T_SESSIONID,
    T_NUMROWS => T_NUMROWS,
    T_DTFROM => T_DTFROM,
    T_DTTO => T_DTTO,
    T_PAGENO_IN => T_PAGENO_IN,
    T_SORT => T_SORT,
    T_HASMORE => T_HASMORE,
    T_REC_OUTPUT => T_REC_OUTPUT
  );
  /* Legacy output: 
DBMS_OUTPUT.PUT_LINE('T_HASMORE = ' || T_HASMORE);
*/ 
  :T_HASMORE := T_HASMORE;
  /* Legacy output: 
DBMS_OUTPUT.PUT_LINE('T_REC_OUTPUT = ' || T_REC_OUTPUT);
*/ 
  :T_REC_OUTPUT := T_REC_OUTPUT; --<-- Cursor
--rollback; 
END;
