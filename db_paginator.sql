--table for logging/resuming report

create table report_settings (
    reportid number GENERATED ALWAYS as IDENTITY(START with 1 INCREMENT by 1),
    reportname varchar2(128),
    dayinterval number,
    modifiedon date default sysdate,
    forcesetting char(1) default 'N',
    primary key (reportid)
);

create table report_instance (
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

create table report_scroll (
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

--create index report_scroll_check on report_scroll(upper(sessionid), upper(reportname));




create or replace procedure  REPORT_PAGINATOR(t_reportname varchar2, t_collist VARCHAR2, t_reportconditions varchar2, t_pkcolname varchar2, t_datecolname varchar2, t_sessionid IN VARCHAR2, t_numrows IN NUMBER, t_dtfrom IN DATE, t_dtto IN DATE, t_pageno_in IN NUMBER, t_sort IN VARCHAR2, t_hasmore OUT CHAR, t_rec_output OUT SYS_REFCURSOR)
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
        select count(*) into t_checkforce from report_settings where upper(reportname) = upper(t_reportname) and forcesetting = 'Y';
        if t_checkforce = 1 then 
            select dayinterval into t_dayinterval from report_settings where upper(reportname) = upper(t_reportname) and forcesetting = 'Y' order by modifiedon desc fetch first 1 rows only;
            --could add logic here to select a recent interval if one exists to avoid extra work below    
        end if;
        --need to find out if this report has been run in the last hour
        select nvl(max(reportinstanceid), 0) into t_reportinstanceid from report_instance where upper(sessionid) = upper(t_sessionid) and upper(reportname) = upper(t_reportname) and upper(columnlist) = upper(t_collist) and upper(reportconditions) = upper(t_reportconditions) and upper(sort) = upper(t_sort) and datefrom = t_dtfrom and dateto = t_dtto and createdon > sysdate - (1/24);
        if t_reportinstanceid = 0 then --this is the first run
            t_newrunfrom := t_dtfrom;
            t_newrunto := t_dtto;
            t_pkid := 0;
            t_pageno := 1;

            --prepare a statement to check for total records in report
            t_rec_check_sqlstmt := 'select count(*), max('||t_pkcolname||') + 1 from '||t_reportname||' where '||t_reportconditions||' and '||t_datecolname||' >= :2 and '||t_datecolname||' <= :3 ';
            execute immediate t_rec_check_sqlstmt into t_numrecsinrpt, t_maxid using t_dtfrom, t_dtto;
            if t_numrecsinrpt > 0 then  --only go through this if there is data
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
            end if;    
        else 
            -- get the last page generated for the report
            -- get values from the last run to pass to the ref cursor
            if upper(t_sort) = 'ASC' then
                select pageno, pagedateto, pkid, dayinterval, numrecsinrpt into t_pageno, t_newrunfrom, t_pkid, t_dayinterval, t_numrecsinrpt from report_instance where reportinstanceid = t_reportinstanceid order by createdon desc fetch first 1 rows only;
                t_pageno := t_pageno + 1; --adding one here for insert below            
                t_newrunto := t_newrunfrom + t_dayinterval;
            else
                select pageno, pagedatefrom, pkid, dayinterval, numrecsinrpt into t_pageno, t_newrunto, t_pkid, t_dayinterval, t_numrecsinrpt from report_instance where reportinstanceid = t_reportinstanceid order by createdon desc fetch first 1 rows only;
                t_pageno := t_pageno + 1; --adding one here for insert below
                t_newrunfrom := t_newrunto - t_dayinterval; 
            end if;     
        end if;

        --make sure we don't go passed date range
        if t_newrunto > t_dtto then 
            t_newrunto := t_dtto;
        end if;
        if t_numrecsinrpt > 0 then  --only go through this if there is data
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
            select nvl(max(reportid), 0) into t_checkrpt from report_settings where upper(reportname) = upper(t_reportname);
            if t_checkrpt = 0 then
                insert into report_settings (reportname, dayinterval) values (t_reportname, t_dayinterval);
            end if;

            --insert our settings/info
            if t_pageno = 1 then --insert the instance record
                insert into report_instance(sessionid, reportname, reportconditions, columnlist, pageno, numrows, numrecsinrpt, datefrom, dateto, pagedatefrom, pagedateto, pkid, dayinterval, sort)
                    values (t_sessionid, t_reportname, t_reportconditions, t_collist, t_pageno, t_numrows, t_numrecsinrpt, t_dtfrom, t_dtto, t_pagerunfrom, t_pagerunto, t_newpkid, t_dayinterval, t_sort);
                select nvl(max(reportinstanceid), 0) into t_reportinstanceid from report_instance;    
            else --update the existing row        
                update report_instance set pageno = t_pageno, pagedatefrom = t_pagerunfrom, pagedateto = t_pagerunto, pkid = t_newpkid where reportinstanceid = t_reportinstanceid;
            end if;
            insert into report_scroll(sessionid, reportinstanceid, reportname, pageno, numrows, datefrom, dateto, pagedatefrom, pagedateto, pkid, dayinterval)
                values (t_sessionid, t_reportinstanceid, t_reportname, t_pageno, t_numrows, t_dtfrom, t_dtto, t_pagerunfrom, t_pagerunto, t_newpkid, t_dayinterval);
        end if;
    else  -- they want a specific page that is already generated
        select pagedatefrom, pagedateto into t_newrunfrom, t_newrunto from report_scroll where pageno = t_pageno_in and upper(sessionid) = upper(t_sessionid) and upper(reportname) = upper(t_reportname) and datefrom = t_dtfrom and dateto = t_dtto and createdon > sysdate - (1/24);
        --need the PKID from the previous page
        select nvl(max(pkid),0) into t_pkid from report_scroll where pageno < t_pageno_in and upper(sessionid) = upper(t_sessionid) and upper(reportname) = upper(t_reportname) and datefrom = t_dtfrom and dateto = t_dtto and createdon > sysdate - (1/24);
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
